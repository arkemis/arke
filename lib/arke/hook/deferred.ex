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

defmodule Arke.Hook.Deferred do
  @moduledoc """
  Process-local queues for the callbacks deferred to the transaction boundary.

  `after_commit` and `after_rollback` entries queue while a transaction is
  open and run after the OUTERMOST commit or rollback, so a write nested in a
  larger transaction gets its slot from the outcome that actually decided it.
  When no transaction is open, "outermost" degrades to "pipeline success or
  failure" and the entries run immediately, so arkes opted out of the
  transaction keep both slots.

  `begin/0`/`finish/0` bracket every transaction the write pipeline opens;
  whichever of `commit/0`/`rollback/1` fires empties both queues.
  """

  @depth {__MODULE__, :depth}
  @commit {__MODULE__, :commit}
  @rollback {__MODULE__, :rollback}

  @spec begin() :: :ok
  def begin() do
    Process.put(@depth, depth() + 1)
    :ok
  end

  @spec finish() :: :ok
  def finish() do
    Process.put(@depth, max(depth() - 1, 0))
    :ok
  end

  @spec depth() :: non_neg_integer()
  def depth(), do: Process.get(@depth, 0)

  @spec on_commit((-> any())) :: :ok
  def on_commit(fun), do: enqueue(@commit, fun)

  @spec on_rollback((any() -> any())) :: :ok
  def on_rollback(fun), do: enqueue(@rollback, fun)

  @doc """
  Runs the queued `after_commit` entries oldest first — only when no
  transaction is open. Entries are expected to isolate their own failures
  (`Arke.Hook.Pipeline.run_isolated/3`).
  """
  @spec commit() :: :ok
  def commit() do
    if depth() == 0, do: take(@commit) |> Enum.reverse() |> Enum.each(& &1.())
    :ok
  end

  @doc """
  Runs the queued `after_rollback` entries with the failure reason — only when
  no transaction is open. Compensators undo in reverse order of the writes
  that queued them, so the queue is drained newest first.
  """
  @spec rollback(any()) :: :ok
  def rollback(error) do
    if depth() == 0, do: take(@rollback) |> Enum.each(& &1.(error))
    :ok
  end

  defp enqueue(key, fun) do
    Process.put(key, [fun | Process.get(key, [])])
    :ok
  end

  defp take(key) do
    entries = Process.get(key, [])
    Process.delete(@commit)
    Process.delete(@rollback)
    entries
  end
end
