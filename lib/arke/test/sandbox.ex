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

defmodule Arke.Test.Sandbox do
  @moduledoc """
  Per-test isolation for the manager tables.

  The managers are ETS-backed and process-independent, so whatever a test
  registers stays visible to every later test — including in `:arke_system`,
  which tests write to as often as they write to their own project. Snapshot
  the bootstrapped state once, then roll back to it after each test:

      # test/test_helper.exs
      Arke.Test.Bootstrap.start()
      Arke.Test.Sandbox.checkpoint()

      # in your case template
      setup do
        on_exit(&Arke.Test.Sandbox.restore/0)
      end
  """

  alias Arke.Boundary.{ArkeManager, ParameterManager, GroupManager}

  @managers [ParameterManager, ArkeManager, GroupManager]

  @doc """
  Records the current contents of every manager as the state to roll back to.
  """
  @spec checkpoint() :: :ok
  def checkpoint do
    Enum.each(@managers, fn manager ->
      :persistent_term.put({__MODULE__, manager}, :ets.tab2list(manager.manager_id()))
    end)
  end

  @doc """
  Rolls every manager back to the last `checkpoint/0` and empties the
  in-memory persistence store.
  """
  @spec restore() :: :ok
  def restore do
    Arke.Test.Persistence.reset()

    Enum.each(@managers, fn manager ->
      case :persistent_term.get({__MODULE__, manager}, nil) do
        nil ->
          raise "no checkpoint recorded — call Arke.Test.Sandbox.checkpoint/0 in test_helper.exs"

        units ->
          table = manager.manager_id()
          :ets.delete_all_objects(table)
          :ets.insert(table, units)
      end
    end)
  end
end
