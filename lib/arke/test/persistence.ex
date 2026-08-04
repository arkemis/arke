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

defmodule Arke.Test.Persistence do
  @moduledoc """
  In-memory implementation of the arke persistence contract, for test suites.

  Arke core performs no I/O of its own; a persistence layer is injected through
  config. This one keeps units in ETS instead of a database, so
  `QueryManager.get_by/1` and friends round-trip what was created and
  validations that query (uniqueness, duplicate ids) actually work.

      # config/test.exs
      config :arke,
        persistence: %{
          arke_postgres: %{
            create: &Arke.Test.Persistence.create/2,
            update: &Arke.Test.Persistence.update/2,
            update_key: &Arke.Test.Persistence.update_key/2,
            delete: &Arke.Test.Persistence.delete/2,
            execute_query: &Arke.Test.Persistence.execute/2,
            get_parameters: &Arke.Test.Persistence.get_parameters/0,
            create_project: &Arke.Test.Persistence.create_project/1,
            delete_project: &Arke.Test.Persistence.delete_project/1
          }
        }

  Call `setup/0` once from `test_helper.exs`, before any test runs, so the
  table is owned by a process that outlives them. `Arke.Test.Sandbox.restore/0`
  empties it between tests.
  """

  alias Arke.Core.Unit
  alias Arke.Test.Persistence.Query

  @table :arke_test_persistence

  @doc """
  Creates the backing table. Idempotent.
  """
  @spec setup() :: :ok
  def setup do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
      _ -> @table
    end

    :ok
  end

  @doc """
  Drops every stored unit.
  """
  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  @spec create(atom(), Unit.t()) :: {:ok, Unit.t()}
  def create(project, %Unit{} = unit) do
    unit = unit |> put_id() |> put_project(project)
    :ets.insert(@table, {key(project, unit), unit})
    {:ok, unit}
  end

  @spec update(atom(), Unit.t()) :: {:ok, Unit.t()}
  def update(project, %Unit{} = unit) do
    unit = put_project(unit, project)
    :ets.insert(@table, {key(project, unit), unit})
    {:ok, unit}
  end

  @doc """
  Mirrors the adapter's `update_key/2`, which takes the current unit rather
  than a project so the old row can be replaced when the id changes.
  """
  @spec update_key(Unit.t(), Unit.t()) :: {:ok, Unit.t()}
  def update_key(%Unit{} = current_unit, %Unit{} = new_unit) do
    project = project_of(current_unit)
    :ets.delete(@table, key(project, current_unit))
    create(project, new_unit)
  end

  @doc """
  Mirrors the repo's `insert_all/3`; sends the call to the caller for `assert_received`.
  """
  @spec insert_all(String.t(), [keyword()], keyword()) :: {non_neg_integer(), nil}
  def insert_all(table, rows, opts) do
    send(self(), {:insert_all, table, rows, opts})
    {length(rows), nil}
  end

  @spec delete(atom(), Unit.t()) :: {:ok, nil}
  def delete(project, %Unit{} = unit) do
    :ets.delete(@table, key(project, unit))
    {:ok, nil}
  end

  @spec execute(Arke.Core.Query.t(), atom()) :: any()
  def execute(query, :all), do: run(query)
  def execute(query, :one), do: query |> run() |> List.first()
  def execute(query, :raw), do: run(query)
  def execute(query, :count), do: query |> run() |> length()
  def execute(query, :pseudo_query), do: query

  @spec get_parameters() :: []
  def get_parameters, do: []

  @spec create_project(Unit.t()) :: :ok
  def create_project(%{arke_id: :arke_project, id: _id}), do: :ok

  @spec delete_project(Unit.t()) :: :ok
  def delete_project(%{arke_id: :arke_project, id: id}) do
    :ets.match_delete(@table, {{id, :_}, :_})
    :ok
  end

  defp run(query) do
    project = Map.get(query, :project)
    units = :ets.select(@table, [{{{:"$1", :_}, :"$2"}, [{:==, :"$1", project}], [:"$2"]}])
    Query.run(units, query)
  end

  defp key(project, %Unit{id: id}), do: {project, id}

  defp put_id(%Unit{id: nil} = unit), do: %{unit | id: Unit.generate_id()}
  defp put_id(unit), do: unit

  defp put_project(%Unit{metadata: metadata} = unit, project),
    do: Unit.update(unit, metadata: Map.put(metadata || %{}, :project, project))

  defp project_of(%Unit{metadata: %{project: project}}), do: project
  defp project_of(_unit), do: :arke_system
end
