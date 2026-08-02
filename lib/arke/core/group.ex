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

  arke do
  end

  def on_create(arke, unit) do
    group = Unit.update(unit, arke_list: [])
    GroupManager.create(group)
    {:ok, unit}
  end

  def on_update(_, _old_unit, %{id: id, metadata: %{project: project}, data: data} = unit) do
    arke_list =
      Enum.reduce(data.arke_list, [], fn a, new_arke_list ->
        [handle_link_init(a, :arke_list) | new_arke_list]
      end)

    unit = Unit.update(unit, %{arke_list: arke_list})
    GroupManager.update(id, project, unit)
    {:ok, unit}
  end

  def handle_link_init(u, p) when is_binary(u),
    do: %{id: String.to_atom(u), metadata: %{"parameter_id" => Atom.to_string(p)}}

  def handle_link_init(u, p) when is_atom(u),
    do: %{id: u, metadata: %{"parameter_id" => Atom.to_string(p)}}

  def handle_link_init(u, _), do: u

  def on_delete(_, unit) do
    GroupManager.remove(unit)
    {:ok, unit}
  end
end
