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

defmodule Arke.Boundary.GroupManager do
  @moduledoc false
  use Arke.Boundary.UnitManager
  alias Arke.Utils.ErrorGenerator, as: Error

  manager_id(:group)

  defp check_module(%{__module__: nil} = unit),
    do: Unit.update(unit, __module__: Arke.System.BaseGroup)

  defp check_module(unit), do: unit

  def before_create(%{id: id, data: data, metadata: unit_metadata} = unit, project) do
    unit = check_module(unit)
    {unit, project}
  end

  def get_arke_list(%{data: data, metadata: %{project: project}} = unit) do
    Enum.reduce(data.arke_list, [], fn %{id: arke_id, metadata: arke_metadata} = _,
                                       new_arke_list ->
      case init_arke(project, arke_id, arke_metadata) do
        {:error, msg} -> new_arke_list
        arke -> [arke | new_arke_list]
      end
    end)
  end

  def get_arke_list(_unit) do
    Error.create(:group, "invalid unit")
  end

  def get_arke(%{id: id} = unit, project, arke_id),
    do: get_arke(id, project, arke_id)

  def get_arke(%{id: id, metadata: %{project: project}} = unit, arke_id),
    do: get_arke(id, project, arke_id)

  def get_arke(unit_id, project, arke_id) when is_binary(arke_id),
    do: get_arke(unit_id, project, String.to_existing_atom(arke_id))

  def get_arke(unit_id, project, arke_id) when is_atom(arke_id) do
    case get(unit_id, project) do
      {:error, _msg} ->
        nil

      unit ->
        with %Unit{} = arke <-
               Enum.find(get_arke_list(unit), {:error, "arke id not found"}, fn f ->
                 f.id == arke_id
               end),
             do: arke,
             else: ({:error, msg} -> nil)
    end
  end

  def get_arke(unit_id, project, %Unit{} = parameter), do: parameter

  def get_groups_by_arke(%{id: id, metadata: %{project: project}} = arke),
    do: get_groups_by_arke(id, project)

  def get_groups_by_arke(arke_id, project) do
    group_keys = get_all(project)

    Enum.reduce(group_keys, [], fn {g, _}, groups ->
      group = get(g, project)

      if arke_id in Enum.map(group.data.arke_list, fn a -> a.id end) do
        [group | groups]
      else
        groups
      end
    end)
  end

  def get_parameters(group_id, project), do: get(group_id, project) |> get_parameters

  def get_parameters(%{id: id, metadata: %{project: project}} = group) do
    parameters =
      get_arke_list(group)
      |> get_group_parameters(project)
      |> init_parameters_by_ids(project)
  end

  defp get_group_parameters(arke_list, _project) do
    Enum.reduce(arke_list, [], fn arke, group_parameters ->
      check_group_parameters(group_parameters, Arke.Boundary.ArkeManager.get_parameters(arke))
    end)
  end

  defp init_parameters_by_ids(ids, project) do
    Enum.reduce(ids, [], fn id, parameters ->
      [Arke.Boundary.ParameterManager.get(id, project) | parameters]
    end)
  end

  defp check_group_parameters([], arke_parameters),
    do: Enum.map(arke_parameters, fn p -> p.id end)

  defp check_group_parameters(group_parameters, arke_parameters) do
    arke_ids = Enum.map(arke_parameters, fn p -> p.id end)
    group_parameters -- group_parameters -- arke_ids
  end

  defp link_init(project, :arke_list, child_id, metadata) do
    case init_arke(project, child_id, metadata) do
      {:error, msg} -> %{id: child_id, metadata: metadata}
      p -> p
    end
  end

  defp init_arke(project, id, metadata) do
    case Arke.Boundary.ArkeManager.get(id, project) do
      {:error, msg} ->
        {:error, msg}

      arke ->
        metadata = remove_project(metadata)
        Unit.update(arke, metadata)
    end
  end

  defp remove_project(metadata) when is_map(metadata) do
    {_, metadata} = Map.pop(metadata, :project, nil)
    metadata
  end

  defp remove_project(metadata) do
    {_, metadata} = Keyword.pop(metadata, :project, nil)
    metadata
  end
end
