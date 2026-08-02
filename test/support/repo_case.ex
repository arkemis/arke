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

defmodule Arke.Test.RepoCase do
  @moduledoc """
  Case template for suites that run against the in-memory managers.

  Brings the usual aliases into scope and rolls manager and persistence state
  back after each test.

      # test/test_helper.exs
      ExUnit.start()

      Arke.Test.Persistence.setup()
      Arke.Test.Bootstrap.start(apps: [:arke, :my_app])
      Arke.Test.Sandbox.checkpoint()

      # test/my_test.exs
      defmodule MyTest do
        use Arke.Test.RepoCase
      end

  Cases are synchronous: the managers are process-independent ETS tables, so
  `async: true` would let concurrent tests see each other's units.
  """

  use ExUnit.CaseTemplate

  alias Arke.Boundary.ArkeManager

  using do
    quote do
      alias Arke.Boundary.{ArkeManager, ParameterManager, GroupManager}
      alias Arke.QueryManager
      alias Arke.Core.Unit
      alias Arke.LinkManager
      alias Arke.Core.Query
      alias Arke.StructManager
    end
  end

  setup_all do
    if is_nil(ArkeManager.get(:arke, :arke_system)) do
      raise """
      the arke registry is not loaded — ArkeManager.get(:arke, :arke_system) returned nil.

      Add this to test_helper.exs, before any test runs:

          Arke.Test.Persistence.setup()
          Arke.Test.Bootstrap.start()
          Arke.Test.Sandbox.checkpoint()
      """
    end

    :ok
  end

  setup do
    on_exit(&Arke.Test.Sandbox.restore/0)
    :ok
  end
end
