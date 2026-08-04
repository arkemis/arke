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

defmodule Arke.Boundary.ArkeManager do
  @moduledoc """
  This module manage the gen servers for the element specified in `Arke.Core.Arke`
  """

  alias Arke.Utils.ErrorGenerator, as: Error
  use Arke.Boundary.UnitManager

  manager_id(:arke)
  # set_supervisor_name(:arke_supervisor)

  def before_create(%{id: _id, data: _data, metadata: _unit_metadata} = unit, project) do
    unit = check_module(unit)

    {unit, project}
  end

  def get_parameters(%{data: data, metadata: %{project: project}} = _unit) do
    Enum.reduce(data.parameters, [], fn %{
                                          id: parameter_id,
                                          metadata: parameter_metadata
                                        },
                                        new_parameters ->
      case init_parameter(project, parameter_id, parameter_metadata) do
        {:error, _msg} -> new_parameters
        parameter -> [parameter | new_parameters]
      end
    end)
  end

  def get_parameter(%{id: id} = _unit, project, parameter_id),
    do: get_parameter(id, project, parameter_id)

  def get_parameter(unit_id, project, parameter_id) when is_binary(parameter_id),
    do: get_parameter(unit_id, project, String.to_existing_atom(parameter_id))

  def get_parameter(unit_id, project, parameter_id) when is_atom(parameter_id) do
    case get(unit_id, project) do
      {:error, _msg} ->
        nil

      %{id: _id, data: data} ->
        with %{id: id, metadata: metadata} <-
               Enum.find(data.parameters, {:error, "parameter id not found"}, fn f ->
                 f.id == parameter_id
               end),
             %Unit{} = parameter <- init_parameter(project, id, metadata),
             do: parameter,
             else: ({:error, _msg} -> nil)
    end
  end

  def get_parameter(_unit_id, _project, %Unit{} = parameter), do: parameter

  def get_parameter(%{id: id, metadata: %{project: project}} = _unit, parameter_id),
    do: get_parameter(id, project, parameter_id)

  def update_parameter(unit_id, parameter_id, project, metadata) when is_binary(parameter_id),
    do: update_parameter(unit_id, String.to_existing_atom(parameter_id), project, metadata)

  def update_parameter(unit_id, parameter_id, project, metadata) do
    case get(unit_id, project) do
      nil ->
        Error.create(:unit, "unit #{unit_id} not found")

      {:error, msg} ->
        Error.create(:unit, msg)

      %{id: _id, data: data} = arke ->
        parameters =
          Enum.map(data.parameters, fn x ->
            if x.id == parameter_id, do: Map.put(x, :metadata, metadata), else: x
          end)

        new_unit = Unit.update(arke, parameters: parameters)
        update(unit_id, project, new_unit)
    end
  end

  defp check_module(%{__module__: nil} = unit),
    do: Unit.update(unit, __module__: Arke.System.Arke)

  defp check_module(unit), do: unit

  defp init_parameter(project, id, metadata) do
    case Arke.Boundary.ParameterManager.get(id, project) do
      nil ->
        Error.create(:parameter, "parameter #{id} not found")

      {:error, msg} ->
        Error.create(:parameter, msg)

      parameter ->
        _parameter = handle_init_p(id, parameter, metadata)
    end
  end

  defp handle_init_p(_id, nil, _metadata) do
    nil
  end

  defp handle_init_p(_id, parameter, override_data) do
    Map.update(parameter, :data, %{}, fn v ->
      Map.merge(v, override_data, fn _k, _pdata, ovdata -> ovdata end)
    end)
  end
end
