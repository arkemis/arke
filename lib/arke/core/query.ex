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

defmodule Arke.Core.Query do
  @moduledoc """
    Struct which defines a Query
  """

  defstruct ~w[project arke persistence distinct filters link orders offset limit]a
  @type t() :: %Arke.Core.Query{}

  defmodule LinkFilter do
    @moduledoc """
      Base struct of a LinkFilter:
      - unit => %Arke.Core.`{arke_struct}`{} => the `arke_struct` of the unit which we want to filter on. See `Arke.Struct`
      - depth => integer => how many results we want to have at max
      - direction => "child" | "parent" => the direction the query will use to search,
      - type => the name of the connection we want to look at \n
      It is used to define a common filter struct which will be applied on an arke_link Query
    """
    defstruct ~w[unit depth direction type]a
    @type t() :: %Arke.Core.Query.LinkFilter{}
  end

  defmodule Filter do
    @moduledoc """
      Base struct of a Filter:
      - logic => :and | :or => the logic of the filter
      - negate => boolean => used to figure out whether the condition is to be denied
      - base_filters (refer to `Arke.Core.Query.BaseFilter`).\n
      It is used to define a Filter which will be applied on a Query
    """
    defstruct ~w[logic negate base_filters]a
    @type t() :: %Arke.Core.Query.Filter{}
  end

  defmodule BaseFilter do
    @moduledoc """
      Base struct of a BaseFilter:
      - parameter => %Arke.Core.Parameter.`ParameterType` => refer to `Arke.Core.Parameter`
      - operator => refer to [operators](#module-operators)
      - value => any => the value that the query will search for
      - negate => boolean => used to figure out whether the condition is to be denied
      - path => [Arke.Core.Parameter.ParameterType] => the path of the parameter \n
      It is used to keep the same logic structure across all the Filter
    """

    defstruct ~w[parameter operator value negate path]a
    @type t() :: %Arke.Core.Query.BaseFilter{}

    @doc """
    Create a new BaseParameter

    ## Parameters
      - parameter => %Arke.Core.Parameter.`ParameterType` => refer to `Arke.Core.Parameter`
      - operator => refer to [operators](#module-operators)
      - value => any => the value that the query will search for
      - negate => boolean => used to figure out whether the condition is to be denied \n

    ## Example
        iex> filter = Arke.Core.Query.BaseFilter.new(parameter: "name", operator: "eq", value: "John", negate: false)
        ...> Arke.Core.Query.BaseFilter.new(person, :default)

    ## Return
        %Arke.Core.Query.BaseFilter{}

    """
    @spec new(
            parameter :: Arke.Core.Parameter.ParameterType,
            operator :: atom(),
            value :: any,
            negate :: boolean,
            path :: [Arke.Core.Parameter.ParameterType]
          ) :: Arke.Core.Query.BaseFilter.t()
    def new(parameter, operator, value, negate, path) do
      %__MODULE__{
        parameter: parameter,
        operator: operator,
        value: cast_value(parameter, value),
        negate: negate,
        path: path
      }
    end

    defp cast_value(%Arke.Core.Unit{arke_id: arke_id} = parameter, value) do
      case arke_id do
        :datetime ->
          Arke.Utils.DatetimeHandler.parse_datetime(value)
          |> case do
            {:ok, value} -> value
            _ -> raise ArgumentError, message: "Invalid datetime format"
          end

        _ ->
          value
      end
    end

    defp cast_value(parameter, value), do: value
  end

  defmodule Order do
    @moduledoc """
      Base struct Order:
      - parameter => %Arke.Core.Parameter.`ParameterType` => refer to `Arke.Core.Parameter`
      - direction => "child" | "parent" => the direction the query will use to search
      - path => [Arke.Core.Parameter.ParameterType] => the path of the parameter \n
      It is used to define the return order of a Query
    """
    defstruct ~w[parameter direction path]a
    @type t() :: %Arke.Core.Query.Order{}
  end

  @doc """
  Create a new Query

  ## Parameters
    - arke => %Arke.Core.`{arke_struct}`{} => the `arke_struct` of the unit which we want to filter on. See `Arke.Struct`
    - project => :atom =>  identify the `Arke.Core.Project`

  ## Example
      iex> person = Arke.Core.Arke.new(id: "person", label: "Person")
      ...> Arke.Core.Query.new(person, :default)

  ## Return
      %Arke.Core.Query{}

  """
  @spec new(arke :: %Arke.Core.Arke{}, project :: atom(), distinct :: atom()) ::
          Arke.Core.Query.t()
  def new(arke, project, distinct \\ nil),
    do: %__MODULE__{
      project: project,
      arke: arke,
      distinct: distinct,
      persistence: nil,
      filters: [],
      orders: [],
      offset: nil,
      limit: nil
    }

  @doc """
  Add a new link filter
  ## Parameters
    - query => refer to `new/1`
    - unit => %Arke.Core.`{arke_struct}`{} => the `arke_struct` of the unit which we want to filter on. See `Arke.Struct`
    - depth => integer => how many results we want to have at max
    - direction => "child" | "parent" => the direction the query will use to search
    - type => the name of the link we want to look at

  ## Example

      iex> person = Arke.Core.Arke.new(id: :person, label: "Person")
      ...> query = Arke.Core.Query.new(person, :arke_system)
      ...> Arke.Core.Query.add_link_filter(query, person, 0, "child", "link")

  ## Return
      %Arke.Core.Query{... link: %Arke.Core.Query.LinkFilter{} ... }
  """
  @spec add_link_filter(
          query :: Arke.Core.Query.t(),
          unit :: Arke.Core.Unit.t(),
          depth :: integer(),
          direction :: atom(),
          connection_type :: String.t()
        ) :: Arke.Core.Query.t()
  def add_link_filter(query, unit, depth, direction, type) do
    %{query | link: %LinkFilter{unit: unit, depth: depth, direction: direction, type: type}}
  end

  @doc """
  Add a filter to a query

  ## Parameters
    - query => refer to `new/1`
    - filter => refer to `Arke.Core.Query.BaseFilter`

  ## Example
      iex> person = Arke.Core.Arke.new(id: :person, label: "Person")
      ...> query = Arke.Core.Query.new(person, :arke_system)
      ...> parameter = Arke.Boundary.ParameterManager.get(:id,:arke_system)
      ...> filter = Arke.Core.Query.new_filter(parameter,:eq, "name", false)
      ...> Arke.Core.Query.add_filter(query, filter)

  ## Return
      %Arke.Core.Query{... filters: [ %Arke.Core.Query.Filter{} ] ... }
  """
  def add_filter(query, filter) do
    %{query | filters: [filter | query.filters]}
  end

  @doc """
  Add a filter to a query

  ## Parameters
    - query => refer to `new/1`
    - parameter
    - operator
    - value
    - negate

  ## Example
      iex> person = Arke.Core.Arke.new(id: :person, label: "Person")
      ...> query = Arke.Core.Query.new(person, :arke_system)
      ...> parameter = Arke.Boundary.ParameterManager.get(:id,:arke_system)
      ...> base_filter = Arke.Core.Query.new_base_filter(parameter, :eq, "name", false)
      ...> Arke.Core.Query.add_filter(query, :and, false, base_filter)

  ## Return
       %Arke.Core.Query{... filters: [ %Arke.Core.Query.Filter{} ] ... }
  """
  def add_filter(query, parameter, operator, value, negate, path \\ []) do
    %{query | filters: [new_filter(parameter, operator, value, negate, path) | query.filters]}
  end

  @doc """
  Add a filter to a query

  ## Parameters
    - query => refer to `new/1`
    - logic => :and | :or => the logic of the filter
    - negate => boolean => used to figure out whether the condition is to be denied
    - base_filters

  ## Example
      iex> person = Arke.new(id: :person, label: "Person")
      ...> query = Arke.Core.Query.new(person, :arke_system)
      ...> parameter = Arke.Core.ParameterManager.get(:id,:arke_system)
      ...> Arke.Core.Query.add_filter(query, parameter, :eq, "name", false)

  ## Return
       %Arke.Core.Query{... filters: [ %Arke.Core.Query.Filter{} ] ... }
  """
  def add_filter(query, logic, negate, base_filters) do
    %{query | filters: [new_filter(logic, negate, base_filters) | query.filters]}
  end

  @doc """
  Create a new filter
  ## Parameters
    - parameter => %Arke.Core.Parameter.`ParameterType` => refer to `Arke.Core.Parameter`
    - operator => refer to [operators](#module-operators)
    - value => any => the value that the query will search for
    - negate => boolean => used to figure out whether the condition is to be denied

  ## Example
      iex> parameter = Arke.Boundary.ParameterManager.get(:id,:arke_system)
      ...> Arke.Core.Query.new_filter(parameter,:eq, "name", false)

  ## Return
      %Arke.Core.Query.Filter{base_filters: [ %Arke.Core.Query.BaseFilter{} ]}
  """
  def new_filter(parameter, operator, value, negate, path \\ []) do
    %Filter{
      logic: :and,
      negate: false,
      base_filters: [new_base_filter(parameter, operator, value, negate, path)]
    }
  end

  @doc """
  Create a new filter
  ## Parameters
    - logic => :and | :or => the logic of the filter
    - negate => boolean => used to figure out whether the condition is to be denied
    - base_filters => refer to `Arke.Core.Query.BaseFilter`

  ## Example
      iex> base_filter = Arke.Core.Query.new_base_filter(parameter, :eq, "name", false)
      ...> Arke.Core.Query.new_filter(:and, false, base_filter)

  ## Return
      %Arke.Core.Query.Filter{base_filters: [ %Arke.Core.Query.BaseFilter{} ]}
  """
  def new_filter(logic, negate, base_filters) do
    %Filter{base_filters: parse_base_filters(base_filters), logic: logic, negate: negate}
  end

  @doc """
  Create a new base filter

  ## Parameters
    - parameter => %Arke.Core.Parameter.`ParameterType` => refer to `Arke.Core.Parameter`
    - operator => refer to [operators](#module-operators)
    - value => any => the value that the query will search for
    - negate => boolean => used to figure out whether the condition is to be denied

  ## Example
      iex> parameter = Arke.Boundary.ParameterManager.get(:id,:arke_system)
      ...> Arke.Core.Query.new_base_filter(parameter, :eq, "name", false)

  ## Return
      %Arke.Core.Query.BaseFilter{}

  """

  # TODO: standardize parameter
  #  if it is a string convert it to existing atom and get it from paramater manager
  #  if it is an atom get it from paramater manaager

  def new_base_filter(parameter, operator, value, negate, path \\ []) do
    BaseFilter.new(parameter, operator, value, negate, path)
  end

  defp parse_base_filters(base_filters) when is_list(base_filters), do: base_filters
  defp parse_base_filters(base_filters), do: [base_filters]

  @doc """
  Get the query result ordered by specific criteria

  ## Parameters
    - query => refer to refer to `new/1`
    - parameter => %Arke.Core.Parameter.`ParameterType` => refer to `Arke.Core.Parameter`
    - direction => "child" | "parent" => the direction the query will use to search

  ## Example
      iex> person = Arke.Core.Arke.new(id: "person", label: "Person")
      ...> query = Arke.Core.Query.new(person, :arke_system)
      ...> parameter = Arke.Boundary.ParameterManager.get(:id,:arke_system)
      ...> Arke.Core.Query.add_order(query, parameter, :asc)

  ## Return
      %Arke.Core.Query{ ... orders: [ %Arke.Core.Query.Order{} ] ... }
  """

  def add_order(query, parameter, direction) when is_list(parameter) do
    {parameter, path} = List.pop_at(parameter, -1)

    %{
      query
      | orders: [%Order{parameter: parameter, direction: direction, path: path} | query.orders]
    }
  end

  def add_order(query, parameter, direction) do
    %{
      query
      | orders: [%Order{parameter: parameter, direction: direction, path: []} | query.orders]
    }
  end

  @doc """
  Define the offset of the query

  ## Parameters
    - query => refer to `new/1`
    - offset => integer => define the offset of the query

  ## Example
      iex> person = Arke.Core.Arke.new(id: :person, label: "Person")
      ...> query = Arke.Core.Query.new(person, :arke_system)
      ...> Arke.Core.Query.set_offset(query, 5)

  ## Return
      %Arke.Core.Query{... offset: value ...}

  """

  def set_offset(query, nil), do: query

  def set_offset(query, offset) when is_binary(offset),
    do: %{query | offset: String.to_integer(offset)}

  def set_offset(query, offset) when is_integer(offset), do: %{query | offset: offset}
  # TODO Custom exception offset must be integer
  def set_offset(query, offset), do: nil

  @doc """
  Define the limit of the query

  ## Parameters
    - query => refer to `new/1`
    - limit => integer => set the results limit of the query

  ## Example
      iex> person = Arke.Core.Arke.new(id: :person, label: "Person")
      ...> query = Arke.Core.Query.new(person, :arke_system)
      ...> Arke.Core.Query.set_limit(query, 100)

  ## Return
      %Arke.Core.Query{... limit: value ...}
  """
  def set_limit(query, nil), do: query

  def set_limit(query, offset) when is_binary(offset),
    do: %{query | limit: String.to_integer(offset)}

  def set_limit(query, limit) when is_integer(limit), do: %{query | limit: limit}
  # TODO Custom exception limit must be integer
  def set_limit(query, limit), do: nil
end
