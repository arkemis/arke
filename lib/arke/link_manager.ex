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

defmodule Arke.LinkManager do
  @moduledoc false
  @record_fields [:id, :data, :metadata, :inserted_at, :updated_at]

  alias Arke.Boundary.ArkeManager
  alias Arke.Utils.ErrorGenerator, as: Error
  alias Arke.QueryManager
  alias Arke.Core.Unit

  def add_node(project, %Unit{} = parent, %Unit{} = child, type \\ "link", metadata \\ %{}) do
    arke_link = ArkeManager.get(:arke_link, project)

    case check_link(project, parent, child, type, arke_link) do
      {_, nil} ->
        QueryManager.create(project, arke_link,
          parent_id: Atom.to_string(parent.id),
          child_id: Atom.to_string(child.id),
          type: type,
          metadata: metadata
        )

      {:ok, _} ->
        Error.create(:link, "link already exists")
    end
  end

  def add_node(project, parent, child, type, metadata)
      when is_binary(parent) and is_binary(child) do
    with %Unit{} = unit_parent <- QueryManager.get_by(id: parent, project: project),
         %Unit{} = unit_child <- QueryManager.get_by(id: child, project: project) do
      add_node(project, unit_parent, unit_child, type, metadata)
    else
      _ -> Error.create(:link, "parent: `#{parent}` or child: `#{child}` not found")
    end
  end

  def add_node(_project, _parent, _child, _type, _metadata),
    do: Error.create(:link, "invalid parameters")

  def update_node(project, %Unit{} = parent, %Unit{} = child, type, metadata) do
    arke_link = ArkeManager.get(:arke_link, :arke_system)

    case check_link(project, parent, child, type, arke_link) do
      {:error, _} -> Error.create(:link, "link not found")
      {:ok, link} -> QueryManager.update(link, metadata: metadata, type: type)
    end
  end

  def update_node(project, parent, child, type, metadata)
      when is_binary(parent) and is_binary(child) do
    unit_parent = QueryManager.get_by(id: parent, project: project)
    unit_child = QueryManager.get_by(id: child, project: project)

    update_node(project, unit_parent, unit_child, type, metadata)
  end

  def update_node(_project, _parent, _child, _type, _metadata),
    do: Error.create(:link, "invalid parameters")

  def delete_node(project, %Unit{} = parent, %Unit{} = child, type, metadata \\ %{}) do
    arke_link = ArkeManager.get(:arke_link, :arke_system)

    case check_link(project, parent, child, type, arke_link) do
      {:error, _} -> Error.create(:link, "link not found")
      {:ok, link} -> QueryManager.delete(project, link)
    end
  end

  def delete_node(project, parent, child, type, metadata)
      when is_binary(parent) and is_binary(child) do
    unit_parent = QueryManager.get_by(id: parent, project: project)
    unit_child = QueryManager.get_by(id: child, project: project)

    delete_node(project, unit_parent, unit_child, type, metadata)
  end

  def delete_node(_project, _parent, _child, _type, _metadata),
    do: Error.create(:link, "invalid parameters")

  defp check_link(project, parent, child, type, arke_link) do
    with %Arke.Core.Unit{} = link <-
           Arke.QueryManager.query(project: project, arke: arke_link)
           |> Arke.QueryManager.filter(:parent_id, :eq, Atom.to_string(parent.id), false)
           |> Arke.QueryManager.filter(:child_id, :eq, Atom.to_string(child.id), false)
           |> Arke.QueryManager.filter(:type, :eq, type, false)
           |> Arke.QueryManager.one(),
         do: {:ok, link},
         else: (_ -> {:error, nil})
  end
end
