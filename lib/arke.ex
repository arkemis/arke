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

defmodule Arke do
  alias Arke.Core.Unit
  alias Arke.Boundary.{ArkeManager, GroupManager, ParameterManager}
  alias Arke.System.BaseParameter

  def init(), do: :ok

  defp get_module(data, type) do
    # get all the arke modules which has the arke macro defined
    # find the right module for the given data and return it
    arke_module_list =
      Enum.reduce(:application.loaded_applications(), [], fn {app, _, _}, arke_list ->
        {:ok, modules} = :application.get_key(app, :modules)

        function_name = get_module_fn(type)

        module_arke_list =
          Enum.reduce(modules, [], fn mod, mod_arke_list ->
            if Code.ensure_loaded?(mod) and :erlang.function_exported(mod, function_name, 0) and
                 apply(mod, function_name, []) != nil do
              [%{module: mod, arke_id: apply(mod, function_name, []).id} | mod_arke_list]
            else
              mod_arke_list
            end
          end)

        arke_list ++ module_arke_list
      end)

    Enum.find(arke_module_list, %{module: nil, arke_id: nil}, fn k ->
      if is_map(k) do
        to_string(k.arke_id) == to_string(Map.get(data, :id))
      end
    end)[:module]
  end

  defp get_module_fn("arke"), do: :arke_from_attr
  defp get_module_fn("group"), do: :group_from_attr

  def handle_manager(_data, _project, _arke_id, _error \\ [])

  def handle_manager([data | t], project, :parameter, error) do
    {type, updated_data} = Map.pop(data, :type)
    final_data = BaseParameter.check_enum(type, updated_data) |> Enum.into(%{})
    updated_error = start_manager(final_data, type, project, ParameterManager, nil)
    handle_manager(t, project, :parameter, updated_error ++ error)
  end

  def handle_manager([data | t], project, :arke, error) do
    {flatten_data, other} = Map.pop(data, :data, %{})

    updated_data =
      Map.merge(flatten_data, other)
      |> Map.put(:type, Map.get(data, :type, "arke"))
      |> Map.put_new(:active, true)

    final_data =
      Map.replace(updated_data, :parameters, parse_arke_parameter(updated_data, project))

    module = get_module(final_data, "arke")
    updated_error = start_manager(final_data, "arke", project, ArkeManager, module)
    handle_manager(t, project, :arke, updated_error ++ error)
  end

  def handle_manager([data | t], project, :group, error) do
    loaded_list =
      Enum.reduce(Map.get(data, :arke_list, []), [], fn arke, acc ->
        with %{id: id, metadata: _metadata} = link_data <- parse_group_member(arke),
             %Unit{} = _arke_unit <- ArkeManager.get(id, project) do
          [link_data | acc]
        else
          _ ->
            [
              %{
                context: :arke_list_group,
                message: "invalid arke in arke_list of: `#{data.id}` in `#{project}`"
              }
              | error
            ]
        end
      end)

    final_data = Map.put(data, :arke_list, loaded_list)
    module = get_module(final_data, "group")
    updated_error = start_manager(final_data, "group", project, GroupManager, module)

    handle_manager(t, project, :group, updated_error ++ error)
  end

  def handle_manager([], _project, _arke_id, error), do: error

  defp parse_group_member(member) when is_binary(member),
    do: %{id: String.to_atom(member), metadata: %{}}

  defp parse_group_member(member) when is_map(member) do
    case Map.get(member, :id) do
      nil -> {:error, "arke id not found"}
      id -> %{id: id, metadata: Map.get(member, :metadata, %{})}
    end
  end

  defp start_manager(_data, _type, _project, _manager, _module, _error \\ [])

  defp start_manager(data, type, project, manager, module, error) do
    case Map.pop(data, :id, nil) do
      {nil, _updated_data} ->
        [%{context: :manager, message: "key id not found"} | error]

      {id, updated_data} ->
        {metadata, updated_data} = Map.pop(updated_data, :metadata, %{project: project})

        case manager.create(
               Unit.new(
                 String.to_atom(id),
                 updated_data,
                 String.to_atom(type),
                 nil,
                 metadata,
                 nil,
                 nil,
                 module
               ),
               project
             ) do
          %Unit{} = _unit ->
            error

          _ ->
            [%{context: :manager, message: "cannot start manager for: `#{id}`"} | error]
        end
    end
  end

  defp parse_arke_parameter(data, project) do
    base_parameters(Map.get(data, :parameters, []), Map.get(data, :type, "arke"))
    |> Enum.reduce([], fn param, acc ->
      # controllare anche che il parameter manager torni qualcosa che esiste
      converted = Map.update(param, :id, "tbd", &String.to_atom(to_string(&1)))
      id = converted[:id]

      case ParameterManager.get(id, project) do
        %Unit{} = arke ->
          type = arke.arke_id

          final_data =
            Map.update(
              converted,
              :metadata,
              %{},
              &(BaseParameter.check_enum(type, &1)
                |> Enum.into(%{}))
            )
            |> Map.put(:arke, type)

          [final_data | acc]

        _ ->
          acc
      end
    end)
  end

  defp base_parameters(arke_parameters, "arke") do
    arke_parameters ++
      [
        %{id: "id", metadata: %{required: true, persistence: "table_column"}},
        %{id: "arke_id", metadata: %{required: false, persistence: "table_column"}},
        %{id: "metadata", metadata: %{required: false, persistence: "table_column"}},
        %{id: "inserted_at", metadata: %{required: false, persistence: "table_column"}},
        %{id: "updated_at", metadata: %{required: false, persistence: "table_column"}}
      ]
  end

  defp base_parameters(arke_parameters, _type), do: arke_parameters
end
