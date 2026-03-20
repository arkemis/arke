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

defmodule Arke.StructManager do
  @moduledoc """
    Module that provides function for getting Arke and Unit structs.
    It also provides functions for encoding and decoding Units.
  """

  alias Arke.Boundary.GroupManager
  alias Arke.Boundary.ArkeManager
  alias Arke.QueryManager
  alias Arke.Utils.DatetimeHandler, as: DatetimeHandler
  alias Arke.Core.{Unit, Arke}

  @type parameter :: %{
          default: String.t() | boolean() | atom() | map() | list() | nil,
          helper_text: String.t() | nil,
          id: String.t(),
          label: String.t(),
          required: boolean() | nil,
          type: String.t(),
          key: String.t() | boolean() | atom() | map() | list() | nil
        }

  @doc """
  Function that encodes a Unit or list of Unit

  ## Parameters
    - unit => [%{arke_struct}] | %{arke_struct} => unit or list of units that we want to encode
    - type => :json => desired encode type

  ## Example
      iex> units = QueryManager.filter_by(arke_id: id)
      ...> StructManager.encode(units, type: :json)

  """
  @spec encode(unit :: Unit.t(), format :: atom()) :: %{
          key: String.t() | number() | boolean() | atom()
        }
  def encode(unit, opts \\ [])

  def encode(unit, opts) do
    type = Keyword.get(opts, :type, :json)
    load_links = Keyword.get(opts, :load_links, false)
    handle_encode(unit, type, load_links, opts)
  end

  def encode(unit, opts)
  defp handle_encode(u, type, load_links, opts \\ [])

  defp handle_encode([], _, _, _), do: []
  defp handle_encode(nil, _, _, _), do: nil

  defp handle_encode(units, type, load_links, opts) when is_list(units) do
    # TODO handle multiple project encode
    %{metadata: %{project: project}} = List.first(units, nil)

    link_units = handle_load_link(units, project, load_links, opts)
    opts = Keyword.put(opts, :link_units, link_units)

    Enum.map(units, fn u ->
      handle_encode(u, type, load_links, opts)
    end)
  end

  defp handle_encode(
         %{id: id, arke_id: arke_id, metadata: %{project: project}} = unit,
         type,
         load_links,
         opts
       ) do
    {link_units, opts} = Keyword.pop(opts, :link_units, nil)

    link_units =
      if link_units == nil,
        do: handle_load_link(unit, project, load_links, opts),
        else: link_units

    opts = Keyword.put(opts, :link_units, link_units)

    arke = ArkeManager.get(arke_id, project)

    base_data = %{
      id: Atom.to_string(id),
      arke_id: Atom.to_string(arke_id),
      inserted_at: DatetimeHandler.parse_datetime(unit.inserted_at, true),
      updated_at: DatetimeHandler.parse_datetime(unit.updated_at, true),
      # to remove project Map.delete(unit.metadata, :project)
      metadata: unit.metadata
    }

    {:ok, new_unit} = ArkeManager.call_func(arke, :before_struct_encode, [arke, unit])

    data = get_raw_data(new_unit) |> get_parsed_data(arke, opts) |> Map.merge(base_data)

    {:ok, data} = ArkeManager.call_func(arke, :on_struct_encode, [arke, new_unit, data, opts])

    # TODO figure out why in link units project key in metadata is a string
    Map.put(data, :metadata, Map.drop(data.metadata, [:project, "project"]))
  end

  defp handle_load_link(_, _, false, _opts), do: []

  defp handle_load_link(unit, project, true, opts) do
    get_link_id_list(unit)
    |> get_link_units(project, opts)
  end

  # TODO forced load_links as false for link units
  defp get_link_units([], _project, _opts), do: []

  defp get_link_units(id_list, project, opts) do
    QueryManager.filter_by(id__in: id_list, project: project)
    |> Enum.map(fn unit -> encode(unit, opts) end)
  end

  defp get_link_id_list(units) when is_list(units) do
    link_id_list =
      Enum.reduce(units, [], fn unit, acc ->
        acc ++ get_link_id_list(unit)
      end)
  end

  defp get_link_id_list(
         %{id: id, arke_id: arke_id, metadata: %{project: project}, data: data} = unit
       ) do
    arke = ArkeManager.get(arke_id, project)

    ArkeManager.get_parameters(arke)
    |> Enum.filter(fn param -> param.arke_id == :link end)
    |> Enum.reduce([], fn param, id_list ->
      link_id = Map.get(data, param.id, nil)
      updates_id_list(id_list, link_id)
    end)
  end

  defp updates_id_list(id_list, id) when is_nil(id), do: id_list
  defp updates_id_list(id_list, id) when is_list(id), do: id_list ++ id
  defp updates_id_list(id_list, id), do: [id | id_list]

  defp get_raw_data(%{link: nil} = unit), do: unit.data

  defp get_raw_data(%{link: link} = unit) do
    Map.put(unit.data, :link, link)
  end

  defp get_raw_data(unit), do: unit.data

  defp get_parsed_data(data, arke, opts \\ [])
  defp get_parsed_data(nil, arke, _), do: %{}
  defp get_parsed_data(data, arke, _) when data == %{}, do: %{}

  defp get_parsed_data(data, arke, opts) do
    data
    |> Enum.map(fn {k, v} -> validate_data(k, v, arke, opts) end)
    |> Enum.reduce(fn key, new_value ->
      Map.merge(key, new_value)
    end)
  end

  def encode(_unit, _format), do: raise("Must pass a valid unit")
  def validate_data(id, value, arke, opts \\ [])

  def validate_data(id, value, arke, opts) do
    param = ArkeManager.get_parameter(arke, id)
    new_value = parse_value(value, param, Enum.into(opts, %{}))
    %{id => new_value}
  end

  defp parse_value(value, param, _opts \\ [])

  defp parse_value(value, %{arke_id: :link} = _param, opts) do
    load_links = Map.get(opts, :load_links, false)

    Map.get(opts, :link_units, [])
    |> filter_link_units(value, load_links)
  end

  defp parse_value(value, %{data: %{values: nil}} = param, %{load_values: true} = opts) do
    opts = Map.delete(opts, :load_values)
    parse_value(value, param, opts)
  end

  defp parse_value(
         value,
         %{arke_id: param_type, data: %{multiple: false, values: values}} = param,
         %{load_values: true} = opts
       )
       when param_type in [:string, :float, :integer] and is_list(values) do
    Enum.find(values, fn map -> Map.get(map, :value, nil) == value end)
  end

  defp parse_value(
         value,
         %{arke_id: param_type, data: %{multiple: true, values: values}} = param,
         %{load_values: true} = opts
       )
       when param_type in [:string, :float, :integer] and is_list(values) and is_list(value) do
    Enum.reduce(value, [], fn v, new_value ->
      [Enum.find(values, fn map -> Map.get(map, :value, nil) == v end) | new_value]
    end)
  end

  defp parse_value(value, _param, _opts), do: value

  defp filter_link_units(link_units, map_list, false) when is_list(map_list) do
    Enum.map(map_list, fn map -> filter_link_units(link_units, map, false) end)
  end

  defp filter_link_units(_link_units, %{id: id, metadata: metadata} = unit, false)
       when is_atom(id),
       do: Atom.to_string(id)

  defp filter_link_units(_link_units, id, false), do: id

  defp filter_link_units(link_units, id_list, true) when is_list(id_list),
    do: Enum.filter(link_units, fn unit -> unit.id in id_list end)

  defp filter_link_units(link_units, id, true) do
    Enum.find(link_units, fn unit -> unit.id == id end)
  end

  @doc """
  Function that decodes data into a Unit or list of Unit

  ## Parameters
    - project => :atom =>  identify the `Arke.Core.Project`
    - arke_id => atom | string => arke id
    - json => %{key: value} => json data that we want to decode
    - type => :json => data input type

  ## Example
      iex> StructManager.decode(:arke, my_json_data, :json)
  """
  @spec decode(
          project :: atom(),
          arke_id :: atom(),
          json :: %{key: String.t() | number() | boolean() | atom()},
          format :: atom()
        ) :: Unit.t()
  def decode(project, arke_id, json, :json) when is_atom(arke_id) do
    ArkeManager.get(arke_id, project)
    |> Unit.load(json)
  end

  def decode(project, arke_id, json, :json) when is_binary(arke_id) do
    ArkeManager.get(String.to_existing_atom(arke_id), project)
    |> Unit.load(json)
  end

  def decode(_project, _arke_id, _json, _format), do: raise("Must pass valid data")

  defp handle_default_value(
         %{arke_id: :string, data: %{default_string: default_string}} = _,
         value
       )
       when is_nil(value),
       do: default_string

  defp handle_default_value(
         %{arke_id: :integer, data: %{default_integer: default_integer}} = _,
         value
       )
       when is_nil(value),
       do: default_integer

  defp handle_default_value(%{arke_id: :float, data: %{default_float: default_float}} = _, value)
       when is_nil(value),
       do: default_float

  defp handle_default_value(
         %{arke_id: :boolean, data: %{default_boolean: default_boolean}} = _,
         value
       )
       when is_nil(value),
       do: default_boolean

  defp handle_default_value(%{arke_id: :date, data: %{default_date: default_date}} = _, value)
       when is_nil(value),
       do: default_date

  defp handle_default_value(%{arke_id: :time, data: %{default_time: default_time}} = _, value)
       when is_nil(value),
       do: default_time

  defp handle_default_value(
         %{arke_id: :datetime, data: %{default_datetime: default_datetime}} = _,
         value
       )
       when is_nil(value),
       do: default_datetime

  defp handle_default_value(%{arke_id: :dict, data: %{default_dict: default_dict}} = _, value)
       when is_nil(value),
       do: default_dict

  defp handle_default_value(%{arke_id: :link, data: %{default_link: default_link}} = _, value)
       when is_nil(value),
       do: default_link

  defp handle_default_value(_, value), do: value

  @doc """
  Function that returns a Struct that describes an Arke or a Unit

  ## Parameters
    - unit => %Unit{} | %Arke{} => unit or arke struct

  ## Example
        iex> arke = ArkeManager.get(:test, :default)
        ...> StructManager.get_struct(arke)
  """
  @spec get_struct(arke :: Unit.t()) :: %{parameters: [parameter()], label: String.t()}
  def get_struct(%{arke_id: :arke, data: data} = arke) do
    struct = %{parameters: get_struct_parameters(arke, %{}), label: data.label}
    ArkeManager.call_func(arke, :after_get_struct, [arke, struct])
  end

  def get_struct(arke, %{data: data} = unit, opts) do
    struct = %{
      parameters: get_struct_parameters(arke, unit, opts),
      label: arke.data.label
    }

    ArkeManager.call_func(arke, :after_get_struct, [arke, unit, struct])
  end

  def get_struct(arke, %{data: data} = unit) do
    struct = %{
      parameters: get_struct_parameters(arke, unit, %{}),
      label: arke.data.label
    }

    ArkeManager.call_func(arke, :after_get_struct, [arke, unit, struct])
  end

  @spec get_struct(arke :: Unit.t(), opts :: list()) :: %{
          parameters: [parameter()],
          label: String.t()
        }
  def get_struct(%{arke_id: :arke, data: data} = arke, opts) do
    struct = %{
      parameters: get_struct_parameters(arke, opts),
      label: data.label
    }

    ArkeManager.call_func(arke, :after_get_struct, [arke, struct])
  end

  def get_struct(_), do: raise("Must pass a valid arke or unit")

  defp get_filtered_parameters(parameters, %{"exclude" => exclude}) do
    Enum.filter(parameters, fn p -> !(Atom.to_string(p.id) in exclude) end)
  end

  defp get_filtered_parameters(parameters, %{"include" => include}) do
    Enum.filter(parameters, fn p -> Atom.to_string(p.id) in include end)
  end

  defp get_filtered_parameters(parameters, _), do: parameters

  defp get_struct_parameters(%{metadata: %{project: project}} = arke, opts) do
    ArkeManager.get_parameters(arke)
    |> get_filtered_parameters(opts)
    |> Enum.reduce([], fn p, acc ->
      [base_parameter_struct(p) |> add_type_fields(project) | acc]
    end)
  end

  defp get_struct_parameters(%{metadata: %{project: project}} = arke, unit, opts) do
    ArkeManager.get_parameters(arke)
    |> get_filtered_parameters(opts)
    |> Enum.reduce([], fn p, acc ->
      [base_parameter_struct(p) |> add_type_fields(project) |> add_value(unit) | acc]
    end)
  end

  defp base_parameter_struct(%{id: id, arke_id: arke_id, data: data} = parameter) do
    {
      parameter,
      %{
        label: data.label,
        id: Atom.to_string(id),
        type: Atom.to_string(arke_id),
        required: data.required,
        helper_text: data.helper_text
      }
    }
  end

  defp add_value(%{id: "id"} = struct, %{id: id} = _), do: Map.merge(struct, %{value: id})

  defp add_value(%{id: "arke_id"} = struct, %{arke_id: arke_id} = _),
    do: Map.merge(struct, %{value: arke_id})

  defp add_value(%{id: "metadata"} = struct, %{metadata: metadata} = _),
    do: Map.merge(struct, %{value: Map.drop(metadata, [:project])})

  defp add_value(%{id: "inserted_at"} = struct, %{inserted_at: inserted_at} = _),
    do: Map.merge(struct, %{value: inserted_at})

  defp add_value(%{id: "updated_at"} = struct, %{updated_at: updated_at} = _),
    do: Map.merge(struct, %{value: updated_at})

  defp add_value(struct, %{data: data} = unit) do
    Map.merge(struct, %{
      value: Unit.get_value(data, String.to_existing_atom(struct.id))
    })
  end

  ######################################################################
  # STRING PARAMETER ###################################################
  ######################################################################

  defp add_type_fields({%{arke_id: :string, data: data} = parameter, base_data}, _project) do
    Map.merge(base_data, %{
      max_length: data.max_length,
      min_length: data.min_length,
      strip: data.strip,
      default: data.default_string,
      values: data.values,
      multiple: data.multiple
    })
  end

  ######################################################################
  # NUMBER PARAMETER ###################################################
  ######################################################################

  defp add_type_fields({%{arke_id: :integer, data: data} = _parameter, base_data}, _project) do
    Map.merge(base_data, %{
      max: data.max,
      min: data.min,
      default: data.default_integer,
      values: data.values,
      multiple: data.multiple
    })
  end

  defp add_type_fields({%{arke_id: :float, data: data} = _parameter, base_data}, _project) do
    Map.merge(base_data, %{
      max: data.max,
      min: data.min,
      default: data.default_float,
      values: data.values,
      multiple: data.multiple
    })
  end

  ######################################################################
  # BOOLEAN PARAMETER ##################################################
  ######################################################################

  defp add_type_fields({%{arke_id: :boolean, data: data} = parameter, base_data}, _project) do
    Map.merge(base_data, %{
      default: data.default_boolean
    })
  end

  ######################################################################
  # DICT PARAMETER #####################################################
  ######################################################################

  defp add_type_fields({%{arke_id: :dict, data: data} = parameter, base_data}, _project) do
    Map.merge(base_data, %{
      default: data.default_dict
    })
  end

  ######################################################################
  # LIST PARAMETER #####################################################
  ######################################################################

  defp add_type_fields({%{arke_id: :list, data: data} = parameter, base_data}, _project) do
    Map.merge(base_data, %{
      default: data.default_list
    })
  end

  ######################################################################
  # LINK PARAMETER #####################################################
  ######################################################################

  defp add_type_fields(
         {%{arke_id: :link, data: data} = _parameter, base_data},
         project
       ) do
    Map.merge(base_data, %{
      default: data.default_link,
      multiple: data.multiple,
      filter_keys: data.filter_keys,
      link_ref: encode(get_arke_or_group_id(data.arke_or_group_id, project), type: :json)
      # depth: data.depth,
      # connection_type: data.connection_type
    })
  end

  defp get_arke_or_group_id(nil, project), do: nil

  defp get_arke_or_group_id(arke_or_group_id, project) do
    case ArkeManager.get(arke_or_group_id, project) do
      {:error, _} ->
        case GroupManager.get(arke_or_group_id, project) do
          {:error, _} ->
            nil

          group ->
            group
        end

      nil ->
        case GroupManager.get(arke_or_group_id, project) do
          {:error, _} ->
            nil

          group ->
            group
        end

      arke ->
        put_in(arke.data.parameters, get_struct(arke).parameters)
    end
  end

  ######################################################################
  # DEFAULT PARAMETER ##################################################
  ######################################################################
  defp add_type_fields({p, base_data}, _project) do
    base_data
  end
end
