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

defmodule Arke.Validator do
  @moduledoc """
  This module provide validation before assign a certain value to an `{arke_struct}`
  """
  alias Arke.Boundary.{ArkeManager, ParameterManager}
  alias Arke.QueryManager, as: QueryManager
  alias Arke.Utils.ErrorGenerator, as: Error
  alias Arke.Utils.DatetimeHandler, as: DatetimeHandler
  alias Arke.Core.{Arke, Unit, Parameter}

  @type func_return() :: {:ok, Unit.t()} | Error.t()

  @doc """
  Function to check the given data based on the fields in the reference schema.

  ## Parameters
    - unit =>  => %Arke.Core.Unit{} => unit to add
    - persistence_fn => fun.() => function containng the action that will be performed on the Repo
    - project => :atom => identify the `Arke.Core.Project`

  ## Example
      iex> schema = Arke.Core.Arke.new
      ...> param = Arke.Core.Parameter.new(%{type: :string,opts: [id: :name]})
      ...> schema = Arke.Core.Arke.add_parameter(schema, param)
      ...> Arke.Validator.validate(%{arke: schema, data: %{name: "test"}})

  ## Return
      %{:ok,_}
      %{:error, [message]}

  """
  @spec validate(unit :: Unit.t(), peristence_fn :: (-> any()), project :: atom()) ::
          func_return()
  def validate(%{arke_id: arke_id} = unit, persistence_fn, project \\ :arke_system) do
    with {:ok, unit} <- check_duplicate_unit(unit, project, persistence_fn) do
      {%{data: data} = unit, errors} = before_validate(unit, project)
      %{data: _arke_data} = arke = ArkeManager.get(arke_id, project)

      unit_parameters =
        Enum.filter(ArkeManager.get_parameters(arke), fn %{data: %{persistence: persistence}} ->
          persistence == "arke_parameter"
        end)

      res =
        Enum.reduce(unit_parameters, {unit, errors}, fn p, {new_unit, errors} = _res ->
          {value, err} = validate_parameter(arke, p, Unit.get_value(data, p.id), project)
          {Unit.update(new_unit, [{p.id, value}]), errors ++ err}
        end)

      {new_unit, errors} = res
      filtered_errors = check_old_values(errors, data, new_unit.data, persistence_fn)

      get_result({new_unit, filtered_errors})
    else
      {:error, errors} -> get_result({unit, errors})
    end

    # TODO: handle after validate
  end

  defp before_validate(%{arke_id: arke_id} = unit, project) do
    arke = ArkeManager.get(arke_id, project)

    with {:ok, unit} <- ArkeManager.call_func(arke, :before_validate, [arke, unit]),
         do: {unit, []},
         else: ({:error, errors} -> {unit, errors})
  end

  defp check_duplicate_unit(%{id: unit_id} = unit, _project, :create) when is_nil(unit_id),
    do: {:ok, unit}

  defp check_duplicate_unit(%{id: unit_id} = unit, project, :create) do
    with nil <- QueryManager.get_by(%{:id => unit_id, :project => project}),
         do: {:ok, unit},
         else: (_ -> {:error, [{"You can not create Unit with same id", unit_id}]})
  end

  defp check_duplicate_unit(%{id: _unit_id} = unit, _project, _persistence_fn), do: {:ok, unit}

  defp check_old_values(errors, old_unit_data, new_unit_data, :update) do
    duplicate_list =
      Enum.filter(errors, fn {k, v} ->
        is_binary(k) and String.contains?(k, "duplicate") and is_atom(v)
      end)

    same_value =
      Enum.filter(duplicate_list, fn {_k, v} -> old_unit_data[v] == new_unit_data[v] end)

    :ordsets.subtract(errors, same_value)
  end

  defp check_old_values(errors, _old_unit_data, _new_unit_data, :create), do: errors

  defp get_result({_unit, errors} = _res) when is_list(errors) and length(errors) > 0,
    do: Error.create(:parameter_validation, errors)

  defp get_result({unit, _errors} = _res), do: {:ok, unit}

  @doc """
  Check if the value can be assigned to a given parameter in a specific schema struct.

  ## Parameters
    - schema_struct => %{arke_struct} => the element where to find and check the field
    - field => :atom => the id of the paramater
    - value => any => the value we want to assign to the above field
    - project => :atom => identify the `Arke.Core.Project`

  ## Example
        iex> Arke.Boundary.ArkeValidator.validate_field(schema_struct, :field_id, value_to_check)

  ## Returns
      {value,[]} if success
      {value,["parameter label", message ]} in case of error
  """
  @spec validate_parameter(
          arke :: Arke.t(),
          parameter :: Sring.t() | atom() | Parameter.parameter_struct(),
          value :: String.t() | number() | atom() | boolean() | map() | list(),
          project :: atom()
        ) :: func_return()
  def validate_parameter(arke, parameter, value, project \\ :arke_system)

  def validate_parameter(arke, parameter, value, project) when is_atom(parameter) do
    parameter = get_parameter(arke, parameter, project)
    check_parameter(parameter, value, project, arke)
  end

  def validate_parameter(arke, parameter, value, project) do
    check_parameter(parameter, value, project, arke)
  end

  defp get_parameter(nil, parameter_id, project),
    do: ParameterManager.get(parameter_id, project)

  defp get_parameter(arke, parameter_id, _project),
    do: ArkeManager.get_parameter(arke, parameter_id)

  defp check_parameter(parameter, value, project, arke) do
    value = get_default_value(parameter, value)
    value = parse_value(parameter, value)
    value = check_whitespace(parameter, value)
    value = check_lowercase(parameter, value)

    errors =
      []
      |> check_required_parameter(parameter, value)
      |> check_by_type(parameter, value)
      |> check_duplicate(parameter, value, project, arke)

    {value, errors}
  end

  def get_default_value(parameter, value) when is_nil(value), do: handle_default_value(parameter)
  def get_default_value(_parameter, value), do: value

  defp parse_value(%{arke_id: :integer, data: %{multiple: false} = _data} = _, value)
       when not is_integer(value) and not is_nil(value) do
    case Integer.parse(value) do
      :error -> value
      {v, _e} -> v
    end
  end

  defp parse_value(%{arke_id: :float, data: %{multiple: false} = _data} = _, value)
       when not is_number(value) and not is_nil(value) do
    case Float.parse(value) do
      :error -> value
      {v, _e} -> v
    end
  end

  defp parse_value(_p, value), do: value

  defp handle_default_value(%{arke_id: :string, data: %{default_string: default_string}} = _),
    do: default_string

  defp handle_default_value(%{arke_id: :integer, data: %{default_integer: default_integer}} = _),
    do: default_integer

  defp handle_default_value(%{arke_id: :float, data: %{default_float: default_float}} = _),
    do: default_float

  defp handle_default_value(%{arke_id: :boolean, data: %{default_boolean: default_boolean}} = _),
    do: default_boolean

  defp handle_default_value(%{arke_id: :date, data: %{default_date: default_date}} = _),
    do: default_date

  defp handle_default_value(%{arke_id: :time, data: %{default_time: default_time}} = _),
    do: default_time

  defp handle_default_value(
         %{arke_id: :datetime, data: %{default_datetime: default_datetime}} = _
       ),
       do: default_datetime

  defp handle_default_value(%{arke_id: :dict, data: %{default_dict: default_dict}} = _),
    do: default_dict

  defp handle_default_value(%{arke_id: :link, data: %{default_link: default_link}} = _),
    do: default_link

  defp handle_default_value(_), do: nil

  defp check_required_parameter(errors, %{id: id, data: %{required: true}} = _parameter, value)
       when is_nil(value),
       do: errors ++ [{id, "is required"}]

  defp check_required_parameter(errors, _parameter, _value), do: errors

  defp check_duplicate(
         errors,
         %{id: id, data: %{unique: true}} = _parameter,
         value,
         project,
         arke
       ) do
    with nil <- QueryManager.get_by(%{id => value, :project => project, :arke_id => arke.id}),
         do: errors,
         else: (_ -> errors ++ [{"duplicate values are not allowed for", id}])
  end

  defp check_duplicate(errors, _parameter, _value, _project, _arke), do: errors

  defp check_by_type(errors, _parameter, value) when is_nil(value), do: errors

  ######################################################################
  # STRING PARAMETER ###################################################
  ######################################################################

  defp check_by_type(errors, %{arke_id: :string} = parameter, value) when is_atom(value),
    do: check_by_type(errors, parameter, Atom.to_string(value))

  defp check_by_type(errors, %{arke_id: :string} = parameter, value)
       when is_binary(value) or is_atom(value) or is_list(value) do
    errors
    # also update the insert in arke postgres
    |> check_max_length(parameter, value)
    |> check_min_length(parameter, value)
    |> check_values(parameter, value)
    |> check_multiple(parameter, value)
  end

  defp check_by_type(errors, %{arke_id: :string} = parameter, _value),
    do: errors ++ [{parameter.data.label, "must be a string"}]

  # --- start Enum ---
  defp check_values(errors, %{data: %{values: nil}} = _parameter, _value), do: errors

  defp check_values(
         errors,
         %{arke_id: type, data: %{values: values, label: label, multiple: true}} = parameter,
         value
       )
       when is_list(value) do
    admitted_values = Enum.map(values, fn %{label: _l, value: v} -> v end)

    with true <- check_values_type(value, type) do
      with [] <- value -- admitted_values do
        errors
      else
        _ -> __enum_error_common__(errors, parameter)
      end
    else
      _ -> errors ++ [{value, "#{label} must be a list of #{to_string(type)}"}]
    end
  end

  defp check_values(errors, %{data: %{values: values}} = parameter, value) do
    case Enum.find(values, fn %{label: _l, value: v} -> v == value end) do
      nil -> __enum_error_common__(errors, parameter)
      _ -> errors
    end
  end

  defp check_values(
         errors,
         %{arke_id: type, data: %{multiple: true, values: _values, label: label}} = _parameter,
         value
       ),
       do: errors ++ [{value, "#{label} must be a list of #{type}}"}]

  defp check_values(errors, _parameter, _value), do: errors

  defp check_values_type(value, type) do
    condition =
      cond do
        type == :string -> fn v -> is_binary(v) end
        type == :integer -> fn v -> is_integer(v) end
        type == :float -> fn v -> is_number(v) end
      end

    Enum.all?(value, &condition.(&1))
  end

  # --- end Enum ---
  # --- start Multiple ---
  defp check_multiple(errors, %{id: id, data: %{multiple: false}} = _parameter, value)
       when is_list(value),
       do: errors ++ [{"multiple values are not allowed for", id}]

  defp check_multiple(errors, %{id: _id, data: %{multiple: true}} = parameter, value)
       when not is_list(value),
       do: check_multiple(errors, parameter, [value])

  defp check_multiple(
         errors,
         %{id: id, arke_id: type, data: %{multiple: true}} = _parameter,
         value
       ) do
    case check_values_type(value, type) do
      true ->
        errors

      false ->
        errors ++ [{"[#{Enum.join(value, ",")}]", "#{id} must be a list of #{type} "}]
    end
  end

  defp check_multiple(errors, _parameter, _value), do: errors
  # --- end Multiple ---

  defp check_whitespace(%{data: %{strip: true}} = _parameter, value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.trim()
    |> String.replace(~r/\s+/, "-")
    |> String.to_existing_atom()
  end

  defp check_whitespace(%{data: %{strip: true}} = _parameter, value) do
    value |> String.trim() |> String.replace(~r/\s+/, "-")
  end

  defp check_whitespace(_, value),
    do: value

  defp check_lowercase(%{data: %{lowercase: true}} = _parameter, value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.downcase()
    |> String.to_atom()
  end

  defp check_lowercase(%{data: %{lowercase: true}} = _parameter, value) do
    value |> String.downcase()
  end

  defp check_lowercase(_, value),
    do: value

  defp check_max_length(errors, %{data: %{max_length: max_length}} = _parameter, _)
       when is_nil(max_length),
       do: errors

  defp check_max_length(
         errors,
         %{data: %{label: label, max_length: max_length}} = _parameter,
         value
       ) do
    # todo: used to parse override in metadata which can be written as string
    max = parse_value(%{arke_id: :integer, data: %{multiple: false}}, max_length)

    if String.length(value) > max do
      errors ++ [{label, "max length is #{max_length}"}]
    else
      errors
    end
  end

  defp check_min_length(errors, %{data: %{min_length: min_length}} = _parameter, _)
       when is_nil(min_length),
       do: errors

  defp check_min_length(
         errors,
         %{data: %{label: label, min_length: min_length}} = _parameter,
         value
       ) do
    # todo: used to parse override in metadata which can be written as string
    min = parse_value(%{arke_id: :integer, data: %{multiple: false}}, min_length)

    if String.length(value) < min do
      errors ++ [{label, "min length is #{min_length}"}]
    else
      errors
    end
  end

  ######################################################################
  # NUMBER PARAMETER ###################################################
  ######################################################################

  defp check_by_type(errors, %{arke_id: :integer} = parameter, value)
       when is_integer(value) or is_list(value) do
    errors
    |> check_max(parameter, value)
    |> check_min(parameter, value)
    |> check_values(parameter, value)
    |> check_multiple(parameter, value)
  end

  defp check_by_type(errors, %{arke_id: :integer, data: %{label: label}} = _parameter, _value),
    do: errors ++ [{label, "must be an integer"}]

  defp check_by_type(errors, %{arke_id: :float} = parameter, value)
       when is_number(value) or is_list(value) do
    errors
    |> check_max(parameter, value)
    |> check_min(parameter, value)
    |> check_values(parameter, value)
    |> check_multiple(parameter, value)
  end

  defp check_by_type(errors, %{arke_id: :float, data: %{label: label}} = _parameter, _value),
    do: errors ++ [{label, "must be a float"}]

  defp check_by_type(_errors, %{arke_id: :dict} = _parameter, value) when is_map(value), do: []

  defp check_by_type(errors, %{arke_id: :dict, data: %{label: label}} = _parameter, _value),
    do: errors ++ [{label, "must be a map"}]

  defp check_by_type(_errors, %{arke_id: :list} = _parameter, value) when is_list(value), do: []

  defp check_by_type(errors, %{arke_id: :list, data: %{label: label}} = _parameter, _value),
    do: errors ++ [{label, "must be a list"}]

  defp check_max(errors, %{data: %{max: max}} = _parameter, _) when is_nil(max), do: errors

  defp check_max(errors, %{data: %{max: max, label: label}} = parameter, value) do
    parsed_max = parse_value(parameter, max)

    if value > parsed_max do
      errors ++ [{label, "max is #{max}"}]
    else
      errors
    end
  end

  defp check_min(errors, %{data: %{min: min}} = _parameter, _) when is_nil(min), do: errors

  defp check_min(errors, %{data: %{min: min, label: label}} = parameter, value) do
    parsed_min = parse_value(parameter, min)

    if value < parsed_min do
      errors ++ [{label, "min is #{min}"}]
    else
      errors
    end
  end

  # DATE
  defp check_by_type(errors, %{arke_id: :date} = parameter, value) do
    case DatetimeHandler.parse_date(value) do
      {:ok, _date} -> errors
      {:error, msg} -> errors ++ [{parameter.data.label, msg}]
    end
  end

  # TIME
  defp check_by_type(errors, %{arke_id: :time} = parameter, value) do
    case DatetimeHandler.parse_time(value) do
      {:ok, _date} -> errors
      {:error, msg} -> errors ++ [{parameter.data.label, msg}]
    end
  end

  # DATETIME
  defp check_by_type(errors, %{arke_id: :datetime} = parameter, value) do
    case DatetimeHandler.parse_datetime(value) do
      {:ok, _date} -> errors
      {:error, msg} -> errors ++ [{parameter.data.label, msg}]
    end
  end

  ######################################################################
  # BOOLEAN PARAMETER ##################################################
  ######################################################################

  defp check_by_type(errors, %{arke_id: :boolean} = _parameter, value)
       when is_boolean(value),
       do: errors

  defp check_by_type(errors, %{arke_id: :boolean} = parameter, _value),
    do: errors ++ [{parameter.data.label, "must be a boolean"}]

  ######################################################################
  # ARKE LINK PARAMETER ################################################
  ######################################################################

  # defp check_by_type(errors, %{arke_id: :arke_link} = parameter, value, project) when is_nil(value),
  #   do: check_by_type(errors, parameter, [], project)

  # defp check_by_type(errors, %{arke_id: :arke_link} = parameter, value, project) when is_list(value)
  #   units = QueryManager.filter_by(project: project, id__in: value)

  #   with nil <- QueryManager.filter_by(project: project, id__in: value),
  #   do: errors,
  #   else: (_ -> errors ++ [{"duplicate values are not allowed for", id}])

  # end

  defp check_by_type(errors, _, _), do: errors

  defp __enum_error_common__(errors, %{id: _id, data: %{values: nil}} = _parameter), do: errors
  defp __enum_error_common__(errors, %{id: _id, data: %{values: %{}}} = _parameter), do: errors
  defp __enum_error_common__(errors, %{id: _id, data: %{values: []}} = _parameter), do: errors

  defp __enum_error_common__(errors, %{id: id, data: %{values: values}} = _parameter) do
    errors ++
      [{"allowed values for #{id} are", Enum.map(values, fn %{label: _l, value: v} -> v end)}]
  end
end
