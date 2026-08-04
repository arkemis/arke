# Copyright 2023 Arkemis S.r.l.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule Arke.Boundary.UnitManager do
  defmacro __using__(_) do
    quote do
      use GenServer
      require Logger
      alias Arke.Core.Unit
      alias Arke.Utils.ErrorGenerator, as: Error
      @compile {:parse_transform, :ms_transform}

      Module.register_attribute(__MODULE__, :manager_id, accumulate: false, persist: true)

      Module.register_attribute(__MODULE__, :arke_list, accumulate: true, persist: true)
      Module.register_attribute(__MODULE__, :group_list, accumulate: true, persist: false)

      import unquote(__MODULE__), only: [manager_id: 1]

      def arke_list(), do: Keyword.get(__MODULE__.__info__(:attributes), :arke_list, [])
      def group_list(), do: Keyword.get(__MODULE__.__info__(:attributes), :arke_list, [])

      def manager_id(),
        do: Keyword.get(__MODULE__.__info__(:attributes), :manager_id, []) |> List.first()

      # client
      def start_link(state \\ []) do
        GenServer.start_link(__MODULE__, state, name: __MODULE__)
      end

      # server
      @impl true
      def init(arg) do
        :ets.new(manager_id(), [:set, :named_table, :public, read_concurrency: true])
        # do not block the init
        {:ok, arg}
      end

      def get_all(project \\ :arke_system) do
        fun =
          :ets.fun2ms(fn {{unit_id, project_id}, _unit} when project_id == project ->
            {unit_id, project_id}
          end)

        :ets.select(manager_id(), fun)
      end

      def get(unit_id, _) when is_nil(unit_id), do: nil

      def get(unit_id, project) when is_binary(unit_id) do
        get(String.to_existing_atom(unit_id), project)
      rescue
        ArgumentError -> nil
      end

      def get(unit_id, project) do
        case :ets.lookup(manager_id(), {unit_id, project}) do
          [{_, unit}] ->
            unit

          [] ->
            case :ets.lookup(manager_id(), {unit_id, :arke_system}) do
              [{_, unit}] -> unit
              [] -> nil
            end
        end
      end

      def remove(%{id: id, metadata: %{project: project}} = unit), do: remove(id, project)

      def remove(unit_id, project) do
        case get(unit_id, project) do
          nil ->
            {:error, "#{unit_id} doesn't exist in project: #{project}"}

          _ ->
            :ets.delete(manager_id(), {unit_id, project})
            :ok
        end
      end

      def create(unit), do: create(unit, [])

      def create(%{id: id, metadata: %{project: project}} = unit, opts) when is_list(opts),
        do: create(unit, project, opts)

      def create(unit, project), do: create(unit, project, [])

      def create(unit, project, opts) do
        {manager, opts} = Keyword.pop(opts, :manager, __MODULE__)
        {unit, project} = before_create(unit, project)
        current_node_create = GenServer.call(manager, {:create, unit, project})
        call_nodes_manager(manager, :create, [unit, project])
        current_node_create
      end

      def before_create(unit, project), do: {unit, project}

      def update(%{id: id, metadata: %{project: project}} = unit, new_unit),
        do: update(id, project, new_unit)

      def update(unit_id, project, new_unit) do
        unit = get(unit_id, project)
        current_node_update = GenServer.call(__MODULE__, {:update, new_unit, project})
        call_nodes_manager(__MODULE__, :update, [new_unit, project])
        current_node_update
      end

      def call_func(%{id: id, metadata: %{project: project}} = unit, func, opts),
        do: call_func(id, project, func, opts)

      def call_func(unit_id, project, func, opts),
        do: get(unit_id, project) |> exec_call_func(func, opts)

      defp exec_call_func(unit, func, opts) when is_nil(unit),
        do: get(:arke, :arke_system) |> exec_call_func(func, opts)

      defp exec_call_func(%{__module__: module} = unit, func, opts) when is_nil(module),
        do: {:error, "No Module"}

      defp exec_call_func(
             %{id: id, metadata: %{project: project}, __module__: module} = unit,
             func,
             opts
           ) do
        try do
          apply(module, func, opts)
        rescue
          e ->
            IO.inspect(e)
            {:error, "Undefined function"}
        end
      end

      ####
      # Link
      ####
      def get_link(%{id: id, metadata: %{project: project}} = unit, parameter_id),
        do: get_link(id, project, parameter_id)

      def get_link(unit_id, project, parameter_id) do
        case get(unit_id, project) do
          nil -> {:error, "#{unit_id} doesn't exist in project: #{project}"}
          %{data: data} = unit -> Enum.map(Map.get(data, parameter_id, []), fn l -> l end)
        end
      end

      def add_link(unit, parameter_id, child_id, metadata)

      def add_link(
            %{id: id, metadata: %{project: project}} = unit,
            parameter_id,
            child_id,
            metadata
          ),
          do: add_link(id, project, parameter_id, child_id, metadata)

      def add_link(unit_id, project, parameter_id, child_id, metadata) do
        manager = __MODULE__

        case get(unit_id, project) do
          nil ->
            {:error, "#{unit_id} doesn't exist in project: #{project}"}

          unit ->
            current_node_update =
              GenServer.call(manager, {:add_link, unit, parameter_id, child_id, metadata})

            call_nodes_manager(manager, :add_link, [unit, parameter_id, child_id, metadata])
            current_node_update
        end
      end

      def remove_link(unit, parameter_id, child_id)

      def remove_link(%{id: id, metadata: %{project: project}} = unit, parameter_id, child_id),
        do: remove_link(id, project, parameter_id, child_id)

      def remove_link(unit_id, project, parameter_id, child_id) do
        manager = __MODULE__

        case get(unit_id, project) do
          nil ->
            {:error, "#{unit_id} doesn't exist in project: #{project}"}

          unit ->
            current_node_update =
              GenServer.call(manager, {:remove_link, unit, parameter_id, child_id})

            call_nodes_manager(manager, :remove_link, [unit, parameter_id, child_id])
            current_node_update
        end
      end

      ######
      ## HANDLE
      ######

      # Update Unit
      @impl true
      def handle_call({:create, %{metadata: metadata} = unit, project}, _from, state) do
        unit = Unit.update(unit, metadata: Map.put(metadata, :project, project))
        :ets.insert(manager_id(), {{unit.id, project}, unit})
        {:reply, unit, state}
      end

      # Update Unit
      @impl true
      def handle_call({:update, new_unit, project}, _from, state) do
        :ets.insert(manager_id(), {{new_unit.id, project}, new_unit})
        {:reply, new_unit, state}
      end

      # Call handle link

      # Add link
      @impl true
      def handle_call(
            {:add_link, %{data: data, metadata: %{project: project}} = unit, parameter_id,
             child_id, metadata},
            _from,
            state
          ) do
        opts =
          %{}
          |> Map.put(parameter_id, [
            link_init(project, parameter_id, child_id, metadata) | Map.get(data, parameter_id, [])
          ])

        unit = Unit.update(unit, opts)
        :ets.insert(manager_id(), {{unit.id, project}, unit})

        {:reply, unit, state}
      end

      defp link_init(project, parameter_id, child_id, metadata),
        do: %{id: child_id, metadata: metadata}

      # Update all nodes manager
      defp call_nodes_manager(manager, func_name, opts) do
        tuple_data =
          Enum.reduce(opts, {func_name}, fn opt, acc ->
            Tuple.insert_at(acc, tuple_size(acc), opt)
          end)

        {right_nodes, bad_nodes} =
          :rpc.multicall(Node.list(), GenServer, :call, [manager, tuple_data])

        if length(bad_nodes) > 0 do
          Enum.each(bad_nodes, fn unit ->
            Logger.warning("Something went wrong during multi node update for unit: `#{unit.id}`")
          end)
        end

        {right_nodes, bad_nodes}
      end

      # Remove link
      @impl true
      def handle_call(
            {:remove_link, %{data: data, metadata: %{project: project}} = unit, parameter_id,
             child_id},
            _from,
            state
          ) do
        opts =
          %{}
          |> Map.put(
            parameter_id,
            Enum.filter(Map.get(data, parameter_id, []), fn link -> link.id != child_id end)
          )

        unit = Unit.update(unit, opts)
        :ets.insert(manager_id(), {{unit.id, project}, unit})
        {:reply, unit, state}
      end

      @impl true
      def handle_info({:EXIT, _from, reason}, state) do
        Logger.warning("Tracking #{state.name} - Stopped with reason #{inspect(reason)}")
      end

      @impl true
      def terminate(reason, _s) do
        IO.inspect({self(), reason}, label: :terminate)
        :ok
      end

      defoverridable before_create: 2, link_init: 4
    end
  end

  defmacro manager_id(name) do
    quote do
      @manager_id unquote(name)
    end
  end
end
