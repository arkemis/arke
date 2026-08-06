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

defmodule Arke.Hook.AfterCommit do
  @moduledoc """
  Process-local `after_commit` queue.

  Entries queue while a transaction is open and flush after the OUTERMOST
  commit, in completion order. When no transaction is open, "outermost commit"
  degrades to "pipeline success" and `flush/0` runs the queue immediately, so
  arkes opted out of the transaction keep their `after_commit` slot.

  `begin/0`/`finish/0` bracket every transaction the write pipeline opens;
  `drop/0` empties the queue when the outermost transaction rolled back.
  """

  @depth {__MODULE__, :depth}
  @queue {__MODULE__, :queue}

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

  @spec enqueue((-> any())) :: :ok
  def enqueue(fun) do
    Process.put(@queue, [fun | Process.get(@queue, [])])
    :ok
  end

  @doc """
  Runs and empties the queue, oldest entry first — only when no transaction
  is open. Entries are expected to isolate their own failures
  (`Arke.Hook.Pipeline.run_isolated/3`).
  """
  @spec flush() :: :ok
  def flush() do
    if depth() == 0 do
      entries = Process.get(@queue, [])
      Process.delete(@queue)
      entries |> Enum.reverse() |> Enum.each(& &1.())
    end

    :ok
  end

  @spec drop() :: :ok
  def drop() do
    if depth() == 0, do: Process.delete(@queue)
    :ok
  end
end
