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

defmodule Arke.QueryManager do
  @moduledoc """
  Module to manage the CRUD operations to create the below elements and also manage the query to get the elements from db.

  ## `arke`
    - Parameter => `Arke.Core.Parameter`
    - Arke => `Arke.Core.Arke`
    - Unit => `Arke.Core.Unit`
    - Group => `Arke.Core.Group`

  ## `operators`
    - eq => equal => `=`
    - contains => contains a value (Case sensitive) =>  `LIKE %word%`
    - icontains => contains a value (Not case sensitive) => `LIKE %word%`
    - startswith => starts with the given value (Case sensitive) => `LIKE %word`
    - istartswith => starts with the given value (Not case sensitive) => `LIKE %word`
    - endswith => ends with the given value (Case sensitive) => `LIKE word%`
    - iendswith => ends with the given value (Not case sensitive) => `LIKE word%`
    - lte => less than or equal => `<=`
    - lt => less than => `<`
    - gt => greater than => `>`
    - gte => greater than or equal => `>=`
    - in =>  value is in a collection => `IN`

  """
  require Logger

  alias Arke.Boundary.{ArkeManager, ParameterManager, GroupManager}
  alias Arke.Validator
  alias Arke.LinkManager
  alias Arke.Hook
  alias Arke.Hook.{Deferred, Pipeline}
  alias Arke.Utils.DatetimeHandler, as: DatetimeHandler
  alias Arke.Errors.ArkeError
  alias Arke.Utils.ErrorGenerator, as: Error
  alias Arke.Core.{Arke, Unit, Query}

  @persistence Application.compile_env(:arke, :persistence)

  @type func_return() :: {:ok, Unit.t()} | Error.t()
  @type operator() ::
          :eq
          | :contains
          | :icontains
          | :startswith
          | :istartswith
          | :endswith
          | :iendswith
          | :lte
          | :lt
          | :gt
          | :gte
          | :in
          | :isnull

  @doc """
  Create a new query

  ## Parameter
    - opts => %{map} || [keyword: value] || key1: value1, key2: value2 => map containing the project and the arke where to apply the query

  ## Example
      iex> Arke.QueryManager.query(project: :public)
  """
  @spec query(list()) :: Query.t()
  def query(opts) do
    project = Keyword.get(opts, :project)
    arke = get_arke(Keyword.get(opts, :arke), project)
    distinct = Keyword.get(opts, :distinct, nil)
    _query = Query.new(arke, project, distinct)
  end

  @doc """
  Create a new topology query

  ## Parameter
    - query => refer to `query/1`
    - unit => %{arke_struct} => struct of the unit used as reference for the query
    - opts => [keyword: value] => KeywordList containing the link conditions
    - depth => int => max depth of the topoplogy
    - direction => :atom => :child/:parent => the direction of the link. From parent to child or viceversa
    - connection_type => string => name of the connection where to search

  ## Example

      iex> Arke.QueryManager.query(project: :public)
      ...> unit = QueryManager.get_by([project: :arke_system, id: "test"])
      ...> QueryManager.link(query, unit)

  ## Return
      %Arke.Core.Query{}
  """

  @spec link(Query.t(), unit :: Unit.t(), opts :: list()) :: Query.t()
  def link(query, unit, opts \\ []) do
    direction = Keyword.get(opts, :direction, :child)
    depth = Keyword.get(opts, :depth, 500)
    type = Keyword.get(opts, :type, nil)

    query
    |> Query.add_link_filter(unit, parse_link_depth(depth), parse_link_direction(direction), type)
  end

  defp parse_link_depth(depth) when is_binary(depth), do: String.to_integer(depth)
  defp parse_link_depth(depth) when is_integer(depth), do: depth

  # TODO exception if depth is not an integer
  defp parse_link_depth(_depth), do: 500

  defp parse_link_direction(direction) when is_binary(direction),
    do: String.to_existing_atom(direction)

  defp parse_link_direction(direction), do: direction

  @doc """
  Runs `fun` inside a database transaction.

  Every `Arke.QueryManager` write performed inside `fun` joins the
  transaction; their `after_commit` hooks defer to the outermost commit.
  Returning `{:error, reason}` from `fun` rolls everything back and returns
  `{:error, reason}`; `{:ok, value}` commits and returns `{:ok, value}`.

  ## Options
    - `timeout:` => transaction timeout in ms, passed to the adapter

  ## Example
      iex> Arke.QueryManager.transaction(:my_project, fn ->
      ...>   with {:ok, a} <- QueryManager.create(...),
      ...>        {:ok, b} <- QueryManager.update(...),
      ...>        do: {:ok, {a, b}}
      ...> end, timeout: 600_000)
  """
  @spec transaction(project :: atom(), fun :: (-> any()), opts :: keyword()) ::
          {:ok, any()} | {:error, any()}
  def transaction(project, fun, opts \\ [])

  def transaction(_project, fun, opts) do
    transaction_fn = @persistence[:arke_postgres][:transaction] || fn f, _opts -> f.() end

    Deferred.begin()

    result = settle_on_abort(fn -> transaction_fn.(fun, opts) end)

    Deferred.finish()

    case result do
      {:error, errors} = error ->
        Deferred.rollback(errors)
        error

      other ->
        Deferred.commit()
        other
    end
  end

  @doc """
  Function to create an element

  ## Parameters
    - project => :atom =>  identify the `Arke.Core.Project`
    - arke => {arke_struct} =>  identify the struct of the element we want to create
    - args => [list] =>  list of key: value we want to assign to the {arke_struct} above

  ## Example
      iex> string = ArkeManager.get(:string, :default)
      ...> Arke.QueryManager.create(:default, string, [id: "name", label: "Nome"])

  ## Returns
      {:ok, %Arke.Core.Unit{}}


  """
  @spec create(project :: atom(), arke :: Arke.t(), args :: list()) :: func_return()
  def create(project, arke, args) do
    persistence_fn = @persistence[:arke_postgres][:create]

    with %Unit{} = unit <- Unit.load(arke, args, :create),
         {:ok, unit} <- Validator.validate(unit, :create, project) do
      %Hook{op: :create, arke: arke, project: project, unit: unit}
      |> execute_write(fn unit -> persistence_fn.(project, unit) end, %{})
    end
  end

  defp handle_link_parameters_unit(%{id: :arke_link} = _, unit), do: {:ok, unit}
  defp handle_link_parameters_unit(%{id: :parameter_value} = _, unit), do: {:ok, unit}

  defp handle_link_parameters_unit(
         %{data: _parameters} = arke,
         %{metadata: %{project: project}} = unit
       ) do
    {errors, link_units} =
      Enum.filter(ArkeManager.get_parameters(arke), fn p -> p.arke_id == :link end)
      |> Enum.reduce({[], []}, fn p, {errors, link_units} ->
        arke = ArkeManager.get(String.to_existing_atom(p.data.arke_or_group_id), project)

        case handle_create_on_link_parameters_unit(
               project,
               unit,
               p,
               arke,
               Unit.get_value(unit, p.id)
             ) do
          {:ok, parameter, %Unit{} = link_unit} -> {errors, [{parameter, link_unit} | link_units]}
          {:ok, _parameter, _link_unit} -> {errors, link_units}
          {:error, e} -> {[e | errors], link_units}
        end
      end)

    case length(errors) > 0 do
      true ->
        {:error, errors}

      false ->
        args =
          Enum.reduce(link_units, %{}, fn {p, u}, args ->
            Map.put(args, p.id, Atom.to_string(u.id))
          end)

        {:ok, Unit.update(unit, args)}
    end
  end

  defp handle_create_on_link_parameters_unit(_project, _unit, parameter, _arke, value)
       when is_nil(value),
       do: {:ok, parameter, value}

  defp handle_create_on_link_parameters_unit(_project, _unit, parameter, _arke, value)
       when is_binary(value),
       do: {:ok, parameter, value}

  defp handle_create_on_link_parameters_unit(project, unit, parameter, arke, value)
       when is_map(value) do
    value = Map.put(value, :runtime_data, %{link: unit, link_parameter: parameter})

    case create(project, arke, value) do
      {:ok, unit} -> {:ok, parameter, unit}
      {:error, error} -> {:error, error}
    end
  end

  defp handle_create_on_link_parameters_unit(_, _, parameter, _, value),
    do: {:ok, parameter, value}

  defp execute_write(%Hook{arke: arke} = hook, persist, old_data) do
    result =
      with {:ok, hook} <- Pipeline.run(:before_transaction, hook, sources(arke)) do
        in_transaction(arke, fn ->
          with {:ok, hook} <- Pipeline.run(:before_write, hook, arke_sources(arke)),
               {:ok, hook} <- Pipeline.run(:before_write, hook, group_sources(arke)),
               {:ok, unit} <- handle_link_parameters_unit(arke, hook.unit),
               {:ok, unit} <- persist.(unit),
               {:ok, hook} <-
                 Pipeline.run(:after_write, %{hook | unit: unit}, arke_sources(arke)),
               {:ok, unit} <- handle_link_parameters(hook.unit, old_data),
               {:ok, hook} <-
                 Pipeline.run(:after_write, %{hook | unit: unit}, group_sources(arke)),
               do: {:ok, hook}
        end)
      end

    finish_write(result, hook, arke, fn final -> {:ok, final.unit} end)
  end

  defp finish_write(result, hook, arke, on_success) do
    case result do
      {:ok, %Hook{} = final} ->
        Deferred.on_commit(fn -> Pipeline.run_isolated(:after_commit, final, sources(arke)) end)

        # This write is durable but an enclosing transaction can still abort
        # it, and only that outer frame knows: queue the compensator too.
        Deferred.on_rollback(fn error ->
          Pipeline.run_isolated(:after_rollback, %{final | error: error}, sources(arke))
        end)

        Deferred.commit()
        on_success.(final)

      {:error, errors} ->
        Pipeline.run_isolated(:after_rollback, %{hook | error: errors}, sources(arke))
        Deferred.rollback(errors)
        {:error, errors}
    end
  end

  defp in_transaction(arke, fun) do
    if Map.get(arke.metadata || %{}, :transaction, true) == false do
      fun.()
    else
      transaction_fn = @persistence[:arke_postgres][:transaction] || fn f, _opts -> f.() end
      Deferred.begin()

      result = settle_on_abort(fn -> transaction_fn.(fun, []) end)

      Deferred.finish()
      result
    end
  end

  # A raise/throw/exit skips `finish_write`, so the queues would outlive the
  # transaction that filled them and fire against the next successful write.
  defp settle_on_abort(fun) do
    fun.()
  catch
    kind, reason ->
      Deferred.finish()
      Deferred.rollback(reason)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end

  defp sources(arke), do: arke_sources(arke) ++ group_sources(arke)

  defp arke_sources(%{__module__: module}), do: [{module, nil}]

  defp group_sources(arke),
    do: Enum.map(GroupManager.get_groups_by_arke(arke), fn group -> {group.__module__, group} end)

  @doc """
  Function to update an element

  ## Parameters
    - project => :atom =>  identify the `Arke.Core.Project`
    - unit => %{arke_struct} =>  unit to update
    - args => [list]  => list of key: value to update

  ## Example
      iex> name = QueryManager.get_by(id: "name")
      ...> QueryManager.update(:default, name, [max_length: 20])

  ## Returns
      {:ok,  %Arke.Core.Unit{} }
      {:error, [msg]}

  """
  @spec update(Unit.t(), args :: list()) :: func_return()
  def update(%{arke_id: arke_id, metadata: %{project: project}, data: data} = current_unit, args) do
    persistence_fn = @persistence[:arke_postgres][:update]
    arke = ArkeManager.get(arke_id, project)

    with %Unit{} = unit <- Unit.update(current_unit, args),
         {:ok, unit} <- update_at_on_update(unit),
         {:ok, unit} <- Validator.validate(unit, :update, project) do
      %Hook{op: :update, arke: arke, project: project, unit: unit, old_unit: current_unit}
      |> execute_write(fn unit -> persistence_fn.(project, unit) end, data)
    end
  end

  def update_key(
        %{arke_id: arke_id, metadata: %{project: project}, data: data} = current_unit,
        args
      ) do
    persistence_fn = @persistence[:arke_postgres][:update_key]
    arke = ArkeManager.get(arke_id, project)

    with %Unit{} = unit <- Unit.update(current_unit, args),
         {:ok, unit} <- update_at_on_update(unit),
         {:ok, unit} <- Validator.validate(unit, :update, project) do
      %Hook{op: :update, arke: arke, project: project, unit: unit, old_unit: current_unit}
      |> execute_write(fn unit -> persistence_fn.(current_unit, unit) end, data)
    end
  end

  defp update_at_on_update(unit) do
    updated_at = DatetimeHandler.now(:datetime)
    {:ok, Unit.update(unit, updated_at: updated_at)}
  end

  @doc """
  Function to delete a given unit
  ## Parameters
    - project => :atom =>  identify the `Arke.Core.Project`
    - unit => %{arke_struct} => the unit to delete
  ## Example
      iex> element = Arke.QueryManager.get_by(id: "name")
      ...> Arke.QueryManager.delete(element)

  ## Returns
      {:ok, _}

  """
  @spec delete(project :: atom(), Unit.t()) :: {:ok, any()}
  def delete(project, %{arke_id: arke_id} = unit) do
    arke = ArkeManager.get(arke_id, project)
    persistence_fn = @persistence[:arke_postgres][:delete]
    hook = %Hook{op: :delete, arke: arke, project: project, unit: unit}

    result =
      with {:ok, hook} <- Pipeline.run(:before_transaction, hook, sources(arke)) do
        in_transaction(arke, fn ->
          with {:ok, hook} <- Pipeline.run(:before_write, hook, arke_sources(arke)),
               {:ok, hook} <- Pipeline.run(:before_write, hook, group_sources(arke)),
               {:ok, nil} <- persistence_fn.(project, hook.unit),
               {:ok, hook} <- Pipeline.run(:after_write, hook, group_sources(arke)),
               {:ok, hook} <- Pipeline.run(:after_write, hook, arke_sources(arke)),
               do: {:ok, hook}
        end)
      end

    finish_write(result, hook, arke, fn _final -> {:ok, nil} end)
  end

  @doc """
  Function to get a single element identified by the opts. Use `Arke.QueryManager.filter_by` if more than one element is returned
  ## Parameters
    - opts => %{map} || [keyword: value] || key1: value1, key2: value2 => identify the element to get

  ## Example
      iex> Arke.QueryManager.get_by(id: "name")
  """
  @spec get_by(opts :: list()) :: Unit.t() | nil
  def get_by(opts \\ []), do: basic_query(opts) |> one

  @doc """
  Function to get all the element which match the given criteria
  ## Parameters
    - opts => %{map} || [keyword: value] || key1: value1, key2: value2 => identify the element to get
    - operator => :atom => refer to [operators](#module-operators)

  ## Example
      iex> Arke.QueryManager.filter_by(id: "name")

  ## Return
      [ Arke.Core.Unit{}, ...]
  """
  @spec filter_by(opts :: list()) :: [Unit.t()] | []
  def filter_by(opts \\ []), do: basic_query(opts) |> all
  defp basic_query(opts) when is_map(opts), do: Map.to_list(opts) |> basic_query

  defp basic_query(opts) do
    {project, opts} = Keyword.pop!(opts, :project)
    {arke, opts} = Keyword.pop(opts, :arke, nil)
    {distinct, opts} = Keyword.pop(opts, :distinct, nil)
    {lock, opts} = Keyword.pop(opts, :lock, false)

    if lock and Deferred.depth() == 0,
      do: raise(ArgumentError, "lock: is only valid inside a transaction")

    arke = get_arke(arke, project)

    query(project: project, arke: arke, distinct: distinct)
    |> Query.set_lock(lock)
    |> where(opts)
  end

  defp get_arke(nil, _), do: nil

  defp get_arke(arke, project) when is_binary(arke),
    do: String.to_existing_atom(arke) |> get_arke(project)

  defp get_arke(arke, project) when is_atom(arke) do
    case ArkeManager.get(arke, project) do
      nil ->
        {:error, msg} = Error.create(:query, "arke not found")
        raise ArkeError, message: msg, type: :not_found

      arke ->
        arke
    end
  end

  defp get_arke(arke, _), do: arke

  defp get_group(group, project) when is_binary(group),
    do: String.to_existing_atom(group) |> get_group(project)

  defp get_group(group, project) when is_atom(group), do: GroupManager.get(group, project)
  defp get_group(group, _), do: group

  @doc """
  Add an `:and` logic to a query

  ## Parameter
    - query => refer to `query/1`
    - negate => boolean => used to figure out whether the condition is to be denied
    - filters => refer to `condition/3 | conditions/1`

  ## Example
      iex> query = QueryManager.query(arke: nil, project: :arke_system)
      ...> query = QueryManager.and_(query, false, QueryManager.conditions(parameter__eq: "value"))

  ## Return
      %Arke.Core.Query{}
  """
  @spec and_(query :: Query.t(), negate :: boolean(), filters :: list()) :: Query.t()
  def and_(query, negate, filters) when is_list(filters),
    do: Query.add_filter(query, :and, negate, parse_base_filters(query, filters))

  def and_(_query, _negate, _filters), do: raise("filters must be a list")

  @doc """
  Add an `:or` logic to a query

  ## Parameter
    - query => refer to `query/1`
    - negate => boolean => used to figure out whether the condition is to be denied
    - filters => refer to `condition/3 | conditions/1`

  ## Example
      iex> query = QueryManager.query(arke: nil, project: :arke_system)
      ...> query = QueryManager.or_(query, false, QueryManager.conditions(parameter__eq: "value"))

  ## Return
      %Arke.Core.Query{}
  """
  @spec or_(query :: Query.t(), negate :: boolean(), filters :: list()) :: Query.t()
  def or_(query, negate, filters) when is_list(filters),
    do: Query.add_filter(query, :or, negate, parse_base_filters(query, filters))

  def or_(_query, _negate, _filters), do: raise("filters must be a list")

  defp parse_base_filters(query, filters) do
    Enum.reduce(filters, [], fn
      %Query.Filter{} = filter, new_filters ->
        [filter | new_filters]

      f, new_filters ->
        parameter = get_parameter(query, f.parameter)
        [Query.new_base_filter(parameter, f.operator, f.value, f.negate, f.path) | new_filters]
    end)
  end

  @doc """
  Create a `Arke.Core.Query.BaseFilter`

  ## Parameters
    - parameter => :atom | %Arke.Core.Arke{} => the parameter where to check the condition
    - operator => :atom => refer to [operators](#module-operators)
    - value => string | boolean | nil => the value the parameter and operator must check
    - negate => boolean => used to figure out whether the condition is to be denied

  ## Example
      iex> QueryManager.condition(:string, :eq, "test")

  ## Return
      %Arke.Core.Query.BaseFilter{}
  """
  @spec condition(
          parameter :: Arke.t() | atom(),
          negate :: boolean(),
          value :: String.t() | boolean() | nil,
          negate :: boolean(),
          path :: [Arke.t()]
        ) :: Query.BaseFilter.t()
  def condition(parameter, operator, value, negate \\ false, path \\ []),
    do: Query.new_base_filter(parameter, operator, value, negate, path)

  @doc """
  Create a list of `Arke.Core.Query.BaseFilter`

  ## Parameter
    - opts => %{map} || [keyword: value] || key1: value1, key2: value2 => the condtions used to create the BaseFilters

  ## Example
      iex>  QueryManager.conditions(parameter__eq: "test", string__contains: "t")

  ## Return
      [ %Arke.Core.Query.BaseFilter{}, ...]
  """
  @spec conditions(opts :: list()) :: [Query.BaseFilter.t()]
  def conditions(opts \\ []) do
    Enum.reduce(opts, [], fn {key, value}, filters ->
      {parameter, operator} = get_parameter_operator(nil, String.split(Atom.to_string(key), "__"))
      [condition(parameter, operator, value) | filters]
    end)
  end

  @doc """
  Create query with specific options

  ##  Parameters
    - query => refer to `query/1`
    - opts => %{map} || [keyword: value] || key1: value1, key2: value2 => keyword list containing the filter to apply

  ## Example
      iex> query = Arke.QueryManager.query()
      ...> QueryManager.where(query, [id__contains: "me", id__contains: "n"])

  ## Return
      %Arke.Core.Query{ %Arke.Core.Query.Filter{ ... base_filters: %Arke.Core.Query.BaseFilter{ ... }}}

  """
  @spec where(query :: Query.t(), opts :: list()) :: Query.t()
  def where(query, opts \\ []) do
    Enum.reduce(opts, query, fn {key, value}, new_query ->
      {parameter, operator} =
        get_parameter_operator(query.arke, String.split(Atom.to_string(key), "__"))

      filter(new_query, parameter, operator, value)
    end)
  end

  @doc """
  Filter of the query

  ## Parameters
    - query => refer to `query/1`
    - filter => refer to `Arke.Core.Query.Filter`

  ## Example
      iex> query = Arke.QueryManager.Query.t
      ...> parameter = Arke.Boundary.ParameterManager.get(:id,:arke_system)
      ...> Arke.Core.Query.new_filter(parameter,:equal,"name",false)
      ...> Arke.Core.Query.filter(query, filter

  """
  @spec filter(query :: Query.t(), filter :: Query.Filter.t()) :: Query.t()
  def filter(query, filter), do: Query.add_filter(query, filter)

  @doc """
  Filter of the query

  ## Parameters
    - query => refer to `query/1`
    - parameter => %{arke_struct} => arke struct of the parameter
    - operator => :atom => refer to [operators](#module-operators)
    - value => string | boolean | nil => the value the parameter and operator must check
    - negate => boolean => used to figure out whether the condition is to be denied

  ## Example
      iex> query = Arke.QueryManager.query()
      ...> QueryManager.filter(query, Arke.Core.Query.new_filter(Arke.Boundary.ParameterManager.get(:id,:default),:equal,"name",false))

  ## Return
      %Arke.Core.Query{...}

  """
  @spec filter(
          query :: Query.t(),
          parameter :: Arke.t() | String.t() | atom(),
          operator :: operator(),
          value :: String.t() | boolean() | number(),
          negate :: boolean()
        ) :: Query.t()
  def filter(query, parameter, operator, value, negate \\ false),
    do: handle_filter(query, parameter, operator, value, negate)

  defp handle_filter(query, "group", :eq, value, negate),
    do: handle_filter(query, :group_id, :eq, value, negate)

  defp handle_filter(query, "group_id", :eq, value, negate),
    do: handle_filter(query, :group_id, :eq, value, negate)

  defp handle_filter(query, :group, :eq, value, negate),
    do: handle_filter(query, :group_id, :eq, value, negate)

  defp handle_filter(query, :group_id, :eq, value, negate) do
    %{id: _id} = group = get_group(value, query.project)

    arke_list =
      Enum.map(GroupManager.get_arke_list(group), fn a ->
        Atom.to_string(a.id)
      end)

    handle_filter_group(query, group, arke_list, negate)
  end

  # handles nested parameters (eg. link_parameter.parameter)
  defp handle_filter(query, parameter, operator, value, negate) when is_binary(parameter) do
    {parameter_id, path_ids} =
      parameter
      |> String.split(".")
      |> List.pop_at(-1)

    parameter = get_parameter(query, parameter_id)
    path = get_path_parameters(query, path_ids)
    Query.add_filter(query, parameter, operator, value, negate, path)
  end

  defp handle_filter(query, parameter, operator, value, negate) do
    Query.add_filter(query, get_parameter(query, parameter), operator, value, negate)
  end

  defp handle_filter_group(query, group, _arke_list, _negate) when is_nil(group), do: query

  defp handle_filter_group(query, _group, arke_list, negate),
    do: handle_filter(query, :arke_id, :in, arke_list, negate)

  @doc """
  Define a criteria to order the element returned from a query

  ## Parameter
    - query => refer to `query/1`
    - order => int => number of element to return

  ## Example
      iex> query = QueryManager.query()
      ...> parameter = Arke.Boundary.ParameterManager.get(:id,:default)
      ...> QueryManager.order(query, parameter, :asc)

  """
  @spec order(
          query :: Query.t(),
          parameter :: Arke.t() | String.t() | atom() | [Arke.t()] | [String.t()] | [atom()],
          direction :: atom()
        ) :: Query.t()

  def order(query, parameter, direction) when is_list(parameter) do
    [head | tail] = parameter

    parameters =
      [get_parameter(query, head)] ++ get_path_parameters(query, tail)

    Query.add_order(query, parameters, direction)
  end

  def order(query, parameter, direction),
    do: Query.add_order(query, get_parameter(query, parameter), direction)

  defp get_path_parameters(query, path),
    do: Enum.map(path, &get_parameter(%{query | arke: nil}, &1))

  @doc """
  Set the offset of the  query

  ## Parameter
    - query => refer to `query/1`
    - offset => int => offset of the query

  ## Example
      iex> query = QueryManager.query()
      ...> QueryManager.where(query, id: "name") |> QueryManager.offset(5)

  """
  @spec offset(query :: Query.t(), offset :: integer()) :: Query.t()
  def offset(query, offset), do: Query.set_offset(query, offset)

  @doc """
  Set the limit of the element to be returned from a query

  ## Parameter
    - query => refer to `query/1`
    - limit => int => number of element to return

  ## Example
      iex> query = QueryManager..query()
      ...> QueryManager.where(query, id: "name") |> QueryManager.limit(1)

  """
  @spec limit(query :: Query.t(), limit :: integer()) :: Query.t()
  def limit(query, limit), do: Query.set_limit(query, limit)

  def pagination(query, nil, limit), do: pagination(query, 0, limit)
  def pagination(query, offset, nil), do: pagination(query, offset, 100)

  def pagination(query, offset, limit) do
    tmp_query = %{query | orders: []}
    count = count(tmp_query)
    elements = query |> offset(offset) |> limit(limit) |> all
    {count, elements}
  end

  @doc """
  Return all the results from a query

  ## Parameter
    - query => refer to `query/1`
  """
  @spec all(query :: Query.t()) :: [Unit.t()] | []
  def all(query), do: execute_query(query, :all)

  @doc """
  Return the first result of a query

  ## Parameter
    - query => refer to `query/1`
  """
  @spec one(query :: Query.t()) :: Unit.t() | nil
  def one(query), do: execute_query(query, :one)

  @doc """
  Return the query as a string

  ## Parameter
    - query => refer to `query/1`
  """
  @spec raw(query :: Query.t()) :: String.t()
  def raw(query), do: execute_query(query, :raw)

  @doc """
  Return the count of the element returned from a query

  ## Parameter
    - query => refer to `query/1`
  """
  @spec count(query :: Query.t()) :: integer()
  def count(query), do: execute_query(query, :count)

  @doc """
  Return a string which represent the query itself

  ## Parameter
    - query => refer to `query/1`

  ## Example
      iex> query = QueryManager.query()
      ...> QueryManager.where(query, id: "name") |> QueryManager.pseudo_query

  ## Return
      #Ecto.Query<>
  """
  @spec pseudo_query(query :: Query.t()) :: Ecto.Query.t()
  def pseudo_query(query), do: execute_query(query, :pseudo_query)

  ######################################################################################################################
  # PRIVATE FUNCTIONS ##################################################################################################
  ######################################################################################################################

  defp execute_query(query, action) do
    query = handle_arke_filter(query)
    persistence_fn = @persistence[:arke_postgres][:execute_query]
    persistence_fn.(query, action)
  end

  defp handle_arke_filter(%{arke: nil} = query), do: query

  defp handle_arke_filter(%{arke: %{data: %{type: "arke"}, id: id}} = query),
    do: filter(query, :arke_id, :eq, id)

  defp handle_arke_filter(query), do: query

  defp get_parameter_operator(_arke, [key, operator]),
    do: {key, String.to_existing_atom(operator)}

  defp get_parameter_operator(_arke, [key]), do: {key, :eq}
  # TODO custom exception
  defp get_parameter_operator(_, _), do: nil

  defp get_parameter(%{arke: nil, project: project} = _query, %{id: id} = _parameter),
    do: ParameterManager.get(id, project)

  defp get_parameter(%{arke: nil, project: project} = _query, key),
    do: ParameterManager.get(key, project)

  defp get_parameter(%{arke: arke, project: project} = _query, key) do
    ArkeManager.get_parameter(arke, project, key)
  end

  # Definition units (arkes, groups, parameters) keep best-effort sync: their
  # link targets (base parameters, system arkes) live in :arke_system, not in
  # the project, so strictness would fail every definition create.
  defp handle_link_parameters(%{arke_id: arke_id, metadata: %{project: project}} = unit, old_data) do
    if definition_unit?(arke_id, project) do
      case do_handle_link_parameters(unit, old_data) do
        {:error, errors} ->
          Logger.debug("link sync failed for `#{unit.id}`: #{inspect(errors)}")
          {:ok, unit}

        ok ->
          ok
      end
    else
      do_handle_link_parameters(unit, old_data)
    end
  end

  defp definition_unit?(arke_id, _project) when arke_id in [:arke, :group], do: true

  defp definition_unit?(arke_id, project) do
    case ArkeManager.get(arke_id, project) do
      nil -> false
      arke -> Enum.any?(GroupManager.get_groups_by_arke(arke), &(&1.id == :parameter))
    end
  end

  defp do_handle_link_parameters(
         %{arke_id: arke_id, metadata: %{project: project}, data: new_data, id: _id} = unit,
         old_data
       ) do
    arke = ArkeManager.get(arke_id, project)

    Enum.filter(ArkeManager.get_parameters(arke), fn p -> p.arke_id == :link end)
    |> Enum.reduce_while({:ok, unit}, fn p, acc ->
      old_value = Map.get(old_data, p.id, nil)
      new_value = Map.get(new_data, p.id, nil)

      case handle_link_parameter(unit, p, old_value, new_value) do
        {:error, errors} -> {:halt, {:error, errors}}
        _ -> {:cont, acc}
      end
    end)
  end

  defp handle_link_parameter(_, nil, _, _), do: nil

  defp handle_link_parameter(unit, %{data: %{multiple: false}} = parameter, old_value, new_value) do
    with {:ok, _} <-
           link_result(
             update_parameter_link(
               unit,
               parameter,
               normalize_value(old_value),
               :delete,
               old_value == new_value
             )
           ),
         {:ok, _} <-
           link_result(
             update_parameter_link(
               unit,
               parameter,
               normalize_value(new_value),
               :add,
               old_value == new_value
             )
           ),
         do: {:ok, unit}
  end

  defp handle_link_parameter(unit, %{data: %{multiple: true}} = parameter, old_value, new_value) do
    # TODO make more efficient with bulk actions

    old_value = old_value || []
    new_value = new_value || []
    nodes_to_delete = Enum.map(old_value -- new_value, &normalize_value(&1))

    nodes_to_add = Enum.map(new_value -- old_value, &normalize_value(&1))

    with {:ok, _} <- update_parameter_links(unit, parameter, nodes_to_delete, :delete),
         {:ok, _} <- update_parameter_links(unit, parameter, nodes_to_add, :add),
         do: {:ok, unit}
  end

  defp update_parameter_links(unit, parameter, nodes, action) do
    Enum.reduce_while(nodes, {:ok, unit}, fn n, acc ->
      case link_result(update_parameter_link(unit, parameter, n, action, false)) do
        {:error, errors} -> {:halt, {:error, errors}}
        _ -> {:cont, acc}
      end
    end)
  end

  defp link_result({:error, errors}), do: {:error, errors}
  defp link_result(_), do: {:ok, nil}

  defp update_parameter_link(_, _, _, _, true), do: nil
  defp update_parameter_link(_, _, nil, _, _), do: nil

  defp update_parameter_link(
         %{metadata: %{project: project}} = unit,
         %{
           id: p_id,
           data: %{connection_type: connection_type, direction: "child"}
         } = _parameter,
         id_to_link,
         action,
         false
       ) do
    handle_update_parameter_link(
      project,
      Atom.to_string(unit.id),
      id_to_link,
      connection_type,
      p_id,
      action
    )
  end

  defp update_parameter_link(
         %{metadata: %{project: project}} = unit,
         %{
           id: p_id,
           data: %{connection_type: connection_type, direction: "parent"}
         } = _parameter,
         id_to_link,
         action,
         false
       ) do
    handle_update_parameter_link(
      project,
      id_to_link,
      Atom.to_string(unit.id),
      connection_type,
      p_id,
      action
    )
  end

  defp handle_update_parameter_link(project, from, to, connection_type, p_id, :add) do
    LinkManager.add_node(project, from, to, connection_type, %{parameter_id: Atom.to_string(p_id)})
  end

  defp handle_update_parameter_link(project, from, to, connection_type, p_id, :delete) do
    LinkManager.delete_node(project, from, to, connection_type, %{
      parameter_id: Atom.to_string(p_id)
    })
  end

  # Function to get only the parameter id from `handle_link_parameter`
  defp normalize_value(nil), do: nil

  defp normalize_value(%{id: id} = _value) do
    to_string(id)
  end

  defp normalize_value(value), do: to_string(value)
end
