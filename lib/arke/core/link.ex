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
  alias Arke.Boundary.{ArkeManager, GroupManager}
  alias Arke.Hook

  arke id: :arke_link do
  end

  after_commit :sync_managers

  defp sync_managers(%Hook{unit: unit} = hook) do
    sync(hook.op, unit)
    {:ok, hook}
  end

  defp sync(:create, %{
         data: %{type: "parameter", parent_id: parent_id, child_id: child_id},
         metadata: %{project: project} = metadata
       }) do
    ArkeManager.add_link(
      String.to_existing_atom(parent_id),
      project,
      :parameters,
      String.to_existing_atom(child_id),
      metadata
    )
  end

  defp sync(:create, %{
         data: %{type: "group", parent_id: parent_id, child_id: child_id},
         metadata: %{project: project} = metadata
       }) do
    GroupManager.add_link(
      String.to_existing_atom(parent_id),
      project,
      :arke_list,
      String.to_existing_atom(child_id),
      metadata
    )
  end

  defp sync(:update, %{
         data: %{type: "parameter", parent_id: parent_id, child_id: child_id},
         metadata: %{project: project} = metadata
       }) do
    ArkeManager.update_parameter(parent_id, child_id, project, metadata)
  end

  defp sync(:delete, %{
         data: %{type: "parameter", parent_id: parent_id, child_id: child_id},
         metadata: %{project: project}
       }) do
    ArkeManager.remove_link(
      String.to_existing_atom(parent_id),
      project,
      :parameters,
      String.to_existing_atom(child_id)
    )
  end

  defp sync(:delete, %{
         data: %{type: "group", parent_id: parent_id, child_id: child_id},
         metadata: %{project: project}
       }) do
    GroupManager.remove_link(
      String.to_existing_atom(parent_id),
      project,
      :arke_list,
      String.to_existing_atom(child_id)
    )
  end

  defp sync(_op, _unit), do: :ok
end
