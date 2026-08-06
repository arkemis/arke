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

defmodule Arke.Core.Project do
  @moduledoc """
    Define a Project structure where more Arke will be grouped
        {arke_struct} = Project
  """

  use Arke.System
  alias Arke.Hook
  alias Arke.Utils.ErrorGenerator, as: Error

  @persistence Application.compile_env(:arke, :persistence)

  arke id: :arke_project do
  end

  after_write :create_schema, on: :create
  after_write :drop_schema, on: :delete

  defp create_schema(%Hook{unit: unit} = hook) do
    persistence_fn = @persistence[:arke_postgres][:create_project]

    case persistence_fn.(unit) do
      :error -> Error.create(:project, "cannot create project schema")
      _ -> {:ok, hook}
    end
  end

  defp drop_schema(%Hook{unit: unit} = hook) do
    persistence_fn = @persistence[:arke_postgres][:delete_project]
    persistence_fn.(unit)
    {:ok, hook}
  end
end
