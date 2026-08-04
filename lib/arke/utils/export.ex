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

defmodule Arke.Utils.Export do
  alias Arke.QueryManager
  alias Arke.Boundary.ArkeManager

  def get_db_structure(project, opts \\ []) do
    data = get_data(project, opts)
    arke = prepare_arke(data.arke, data.arke_parameter)
    group = prepare_group(data.group)
    parameter = prepare_parameter(data.parameter)
    permission = prepare_permission(data.permission)
    %{arke: arke, group: group, parameter: parameter, link: permission}
  end

  def get_data(project, opts) do
    # if the opts doesn not include any flag then export all
    if not Enum.any?(Keyword.keys(opts), fn k -> k in [:arke, :parameter, :group] end) do
      get_all(project)
    else
      arke = get_arke(project, opts[:arke])
      arke_parameter = get_arke_parameter(project)
      parameter = get_parameter(project, opts[:parameter])
      group = get_group(project, opts[:group])
      permission = get_permission(project)

      %{
        arke: arke,
        parameter: parameter,
        group: group,
        permission: permission,
        arke_parameter: arke_parameter
      }
    end
  end

  defp get_arke(_project, nil), do: []
  defp get_arke(project, _), do: QueryManager.filter_by(project: project, arke_id: "arke")

  defp get_parameter(_project, nil), do: []

  defp get_parameter(project, _),
    do:
      QueryManager.filter_by(
        project: project,
        arke_id__in: Arke.Utils.DefaultData.get_parameters_id()
      )

  defp get_group(_project, nil), do: []
  defp get_group(project, _), do: QueryManager.filter_by(project: project, arke_id: "group")

  defp get_permission(project) do
    arke_link = ArkeManager.get(:arke_link, :arke_system)

    QueryManager.query(project: project, arke: arke_link.id)
    |> QueryManager.where(type: "permission")
    |> QueryManager.all()
  end

  defp get_arke_parameter(project) do
    arke_link = ArkeManager.get(:arke_link, :arke_system)

    QueryManager.query(project: project, arke: arke_link.id)
    |> QueryManager.where(type: "parameter")
    |> QueryManager.all()
  end

  defp get_all(project) do
    data =
      QueryManager.filter_by(project: project, arke_id__in: Arke.Utils.DefaultData.get_arke_id())

    p_list = Arke.Utils.DefaultData.get_parameters_id()

    _parsed_data =
      Enum.reduce(data, %{arke: [], group: [], parameter: []}, fn unit, acc ->
        parse_data(unit, to_string(unit.arke_id), p_list, acc)
      end)
      |> Map.put(:permission, get_permission(project))
      |> Map.put(:arke_parameter, get_arke_parameter(project))
  end

  defp parse_data(unit, "arke", _p_list, acc), do: %{acc | arke: acc.arke ++ [unit]}
  defp parse_data(unit, "group", _p_list, acc), do: %{acc | group: acc.group ++ [unit]}

  defp parse_data(unit, arke_id, p_list, acc) do
    if arke_id in p_list do
      %{acc | parameter: acc.parameter ++ [unit]}
    else
      acc
    end
  end

  # parse arke and make them usable for seed_project
  defp prepare_arke(data, arke_param_list) do
    Enum.map(data, fn arke ->
      parameters =
        Enum.filter(arke_param_list, fn p -> to_string(p.data.parent_id) == to_string(arke.id) end)
        |> Enum.map(fn p ->
          %{id: to_string(p.data.child_id), metadata: Map.delete(p.metadata, :project)}
        end)
        |> Enum.sort_by(&Map.fetch(&1, :id))

      %{id: to_string(arke.id), label: arke.data.label, parameters: parameters}
    end)
    |> Enum.sort_by(&Map.fetch(&1, :id))
  end

  defp prepare_group(data) do
    Enum.map(data, fn group ->
      ordered_arke = Enum.sort_by(group.data.arke_list, & &1)

      %{
        id: to_string(group.id),
        label: group.data.label,
        description: group.data.description,
        arke_list: ordered_arke
      }
    end)
    |> Enum.sort_by(&Map.fetch(&1, :id))
  end

  defp prepare_parameter(data),
    do:
      Enum.map(data, fn parameter ->
        Map.put(parameter.data, :id, to_string(parameter.id))
        |> Map.put(:type, to_string(parameter.arke_id))
      end)
      |> Enum.sort_by(&Map.fetch(&1, :id))

  defp prepare_permission(data),
    do:
      Enum.map(data, fn permission ->
        %{
          parent: permission.data.parent_id,
          child: permission.data.child_id,
          metadata: Map.delete(permission.metadata, :project),
          type: permission.data.type
        }
      end)
      |> Enum.sort_by(&Map.fetch(&1, :parent))
end
