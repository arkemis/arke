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

defmodule Arke.Boundary.FileManager do
  @moduledoc """
  Cache for signed URLs to avoid redundant signing requests.
  Stores only `signed_url` and `expiration` keyed by `{unit_id, project}`.
  Expired entries are purged every hour.
  """
  use GenServer
  require Logger

  @table :file_manager_cache
  @compile {:parse_transform, :ms_transform}
  @one_hour :timer.hours(1)

  def start_link(state \\ []) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def add(%{id: id, metadata: %{project: project}}, %{
        signed_url: signed_url,
        expiration: expiration
      }) do
    add(id, project, signed_url, expiration)
  end

  def add(unit_id, project, signed_url, expiration) do
    :ets.insert(@table, {{unit_id, project}, %{signed_url: signed_url, expiration: expiration}})
    :ok
  end

  def get(unit_id, project) when is_binary(unit_id) do
    get(String.to_existing_atom(unit_id), project)
  rescue
    ArgumentError -> nil
  end

  def get(unit_id, project) do
    case :ets.lookup(@table, {unit_id, project}) do
      [{_, entry}] -> entry
      [] -> nil
    end
  end

  def get_all(project) do
    fun = :ets.fun2ms(fn {{unit_id, ^project}, entry} -> {unit_id, entry} end)

    :ets.select(@table, fun)
    |> Enum.map(fn {unit_id, entry} -> Map.put(entry, :unit_id, unit_id) end)
  end

  def remove(%{id: id, metadata: %{project: project}}), do: remove(id, project)

  def remove(unit_id, project) do
    :ets.delete(@table, {unit_id, project})
    :ok
  end

  @impl true
  def init(state) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    schedule_cleanup()
    {:ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.os_time(:second)

    fun = :ets.fun2ms(fn {key, %{expiration: expiration}} when expiration < now -> key end)

    expired = :ets.select(@table, fun)

    Enum.each(expired, &:ets.delete(@table, &1))

    if length(expired) > 0 do
      Logger.debug("FileManager: purged #{length(expired)} expired entries")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, @one_hour)
end
