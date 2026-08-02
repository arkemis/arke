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

defmodule Arke.Core.Link do
  @moduledoc false

  use Arke.System
  alias Arke.LinkManager
  alias Arke.Boundary.{ArkeManager, GroupManager}

  arke id: :arke_link do
  end

  def on_create(
        _,
        %{
          data: %{type: "parameter", parent_id: parent_id, child_id: child_id},
          metadata: %{project: project} = metadata
        } = unit
      ) do
    ArkeManager.add_link(
      String.to_existing_atom(parent_id),
      project,
      :parameters,
      String.to_existing_atom(child_id),
      metadata
    )

    {:ok, unit}
  end

  def on_create(
        _,
        %{
          data: %{type: "group", parent_id: parent_id, child_id: child_id},
          metadata: %{project: project} = metadata
        } = unit
      ) do
    GroupManager.add_link(
      String.to_existing_atom(parent_id),
      project,
      :arke_list,
      String.to_existing_atom(child_id),
      metadata
    )

    {:ok, unit}
  end

  def on_create(
        _,
        %{
          data: %{type: type, parent_id: parent_id, child_id: child_id},
          metadata: %{project: project} = metadata
        } = unit
      ) do
    {:ok, unit}
  end

  def on_update(
        _,
        _old_unit,
        %{
          data: %{type: "parameter", parent_id: parent_id, child_id: child_id},
          metadata: %{project: project} = metadata
        } = unit
      ) do
    ArkeManager.update_parameter(parent_id, child_id, project, metadata)
    {:ok, unit}
  end

  def on_update(_, _old_unit, unit), do: {:ok, unit}

  def on_delete(
        _,
        %{
          data: %{type: "parameter", parent_id: parent_id, child_id: child_id},
          metadata: %{project: project} = metadata
        } = unit
      ) do
    ArkeManager.remove_link(
      String.to_existing_atom(parent_id),
      project,
      :parameters,
      String.to_existing_atom(child_id)
    )

    {:ok, unit}
  end

  def on_delete(
        _,
        %{
          data: %{type: "group", parent_id: parent_id, child_id: child_id},
          metadata: %{project: project} = metadata
        } = unit
      ) do
    GroupManager.remove_link(
      String.to_existing_atom(parent_id),
      project,
      :arke_list,
      String.to_existing_atom(child_id)
    )

    {:ok, unit}
  end

  def on_delete(
        _,
        %{
          data: %{type: type, parent_id: parent_id, child_id: child_id},
          metadata: %{project: project} = metadata
        } = unit
      ) do
    {:ok, unit}
  end
end
