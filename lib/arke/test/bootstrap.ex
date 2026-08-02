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

defmodule Arke.Test.Bootstrap do
  @moduledoc """
  Populates the Arke managers from registry files, in memory, without a database.

  In production the managers are filled by `ArkePostgres.init/0` from persisted
  rows, which `mix arke.seed_project` had seeded from the registry files. A test
  suite has neither step, so this module feeds the registry straight into
  `Arke.handle_manager/4`.

      # test/test_helper.exs
      ExUnit.start()
      Arke.Test.Bootstrap.start()

  Downstream packages layer their own registry on top of arke's:

      Arke.Test.Bootstrap.start(apps: [:arke, :arke_auth])

  Entries are loaded into `:arke_system` only. Manager lookups fall back to
  `:arke_system` when an id is missing from the requested project, so system
  arkes resolve from every project without being duplicated into each.

  Pair with `Arke.Test.Sandbox` to keep tests from leaking state into one
  another.
  """

  # Parameters before arkes before groups: `handle_manager/4` resolves an arke's
  # `parameters` through the ParameterManager, and a group's `arke_list` through
  # the ArkeManager.
  @load_order [:parameter, :arke, :group]

  @system_project :arke_system

  @doc """
  Loads the registry of `:apps` into the managers.

  ## Options

    * `:apps` — apps whose registry to load, layered in order. Defaults to
      `:arke` plus the current Mix project.
  """
  @spec start(keyword()) :: :ok
  def start(opts \\ []) do
    data = opts |> Keyword.get(:apps, default_apps()) |> read_registry()

    Enum.each(@load_order, fn key ->
      case Arke.handle_manager(Map.get(data, key, []), @system_project, key) do
        [] ->
          :ok

        errors ->
          raise "#{length(errors)} #{key} entries failed to load:\n" <>
                  Enum.map_join(errors, "\n", fn %{context: context, message: message} ->
                    "  * [#{context}] #{message}"
                  end)
      end
    end)
  end

  defp default_apps, do: Enum.uniq([:arke, Mix.Project.config()[:app]])

  # Same files and merge semantics as `mix arke.seed_project`, minus the database.
  # A later app extends entries declared by an earlier one.
  defp read_registry(apps) do
    apps
    |> Enum.flat_map(&files/1)
    |> Enum.reduce(%{}, fn file, acc ->
      json = file |> File.read!() |> Jason.decode!(keys: :atoms)

      Enum.reduce(@load_order, acc, fn key, acc ->
        Map.update(acc, key, Map.get(json, key, []), &(&1 ++ Map.get(json, key, [])))
      end)
    end)
    |> Map.new(fn {key, entries} -> {key, merge_by_id(entries)} end)
  end

  defp files(app) do
    case app_root(app) do
      nil -> []
      root -> Path.wildcard(Path.join(root, "lib/registry/{system,shared}/*.json"))
    end
  end

  defp app_root(app) do
    if app == Mix.Project.config()[:app],
      do: File.cwd!(),
      else: Mix.Project.deps_paths()[app]
  end

  defp merge_by_id(entries) do
    entries
    |> Enum.reduce(%{}, fn %{id: id} = entry, acc ->
      Map.update(acc, id, entry, &Map.merge(&1, entry))
    end)
    |> Map.values()
  end
end
