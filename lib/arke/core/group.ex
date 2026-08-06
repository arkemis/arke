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

defmodule Arke.Core.Group do
  @moduledoc """
    Defines the structure of a Group in which more than one Arke will be grouped
  """

  use Arke.System
  alias Arke.Boundary.GroupManager
  alias Arke.Core.Unit
  alias Arke.Hook

  arke do
  end

  after_write :normalize_arke_list, on: :update
  after_commit :sync_manager

  defp normalize_arke_list(%Hook{unit: %{data: data} = unit} = hook) do
    arke_list =
      Enum.reduce(data.arke_list, [], fn a, new_arke_list ->
        [handle_link_init(a, :arke_list) | new_arke_list]
      end)

    {:ok, %{hook | unit: Unit.update(unit, %{arke_list: arke_list})}}
  end

  defp sync_manager(%Hook{op: :create, unit: unit} = hook) do
    group = Unit.update(unit, arke_list: [])
    GroupManager.create(group)
    {:ok, hook}
  end

  defp sync_manager(%Hook{op: :update, unit: %{id: id, metadata: %{project: project}} = unit} = hook) do
    GroupManager.update(id, project, unit)
    {:ok, hook}
  end

  defp sync_manager(%Hook{op: :delete, unit: unit} = hook) do
    GroupManager.remove(unit)
    {:ok, hook}
  end

  def handle_link_init(u, p) when is_binary(u),
    do: %{id: String.to_atom(u), metadata: %{"parameter_id" => Atom.to_string(p)}}

  def handle_link_init(u, p) when is_atom(u),
    do: %{id: u, metadata: %{"parameter_id" => Atom.to_string(p)}}

  def handle_link_init(u, _), do: u
end
