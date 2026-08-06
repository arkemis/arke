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

defmodule Arke.Hook.Pipeline do
  @moduledoc """
  Executes the hook entries a module registered through `Arke.Hook.DSL`.

  A source is `{module, group}`: the arke module with `group: nil`, or a group
  module with its group unit. Entries run in registration order; `{:error, _}`
  halts the run. `run_isolated/3` is for post-outcome slots
  (`after_commit`/`after_rollback`): every entry runs under its own rescue,
  because after the outcome is fixed a raising entry must not fail the caller
  nor starve later entries.
  """

  require Logger

  alias Arke.Hook
  alias Arke.Utils.ErrorGenerator, as: Error

  @type source() :: {module() | nil, Arke.Core.Unit.t() | nil}

  @spec run(atom(), Hook.t(), [source()]) :: {:ok, Hook.t()} | {:error, any()}
  def run(slot, %Hook{} = hook, sources) do
    Enum.reduce_while(entries(slot, hook.op, sources), {:ok, hook}, fn
      {module, group, handler}, {:ok, acc} ->
        case invoke(module, handler, %{acc | group: group}) do
          {:ok, %Hook{} = new_hook} -> {:cont, {:ok, %{new_hook | group: nil}}}
          {:error, reason} -> {:halt, {:error, reason}}
          other -> {:halt, invalid_return(module, slot, other)}
        end
    end)
  end

  @spec run_isolated(atom(), Hook.t(), [source()]) :: :ok
  def run_isolated(slot, %Hook{} = hook, sources) do
    Enum.each(entries(slot, hook.op, sources), fn {module, group, handler} ->
      try do
        invoke(module, handler, %{hook | group: group})
      rescue
        e ->
          Logger.error(
            "#{slot} hook in #{inspect(module)} raised: #{Exception.message(e)}",
            crash_reason: {e, __STACKTRACE__}
          )

          :telemetry.execute([:arke, :hook, :exception], %{count: 1}, %{
            slot: slot,
            module: module,
            op: hook.op,
            reason: e
          })
      end
    end)
  end

  defp entries(slot, op, sources) do
    Enum.flat_map(sources, fn
      {nil, _group} ->
        []

      {module, group} ->
        if Code.ensure_loaded?(module) and function_exported?(module, :__arke_hooks__, 0) do
          for entry <- module.__arke_hooks__(),
              entry.slot == slot,
              entry.on == nil or op in entry.on,
              do: {module, group, entry.handler}
        else
          []
        end
    end)
  end

  defp invoke(module, {:local, name}, hook), do: module.__arke_hook_call__(name, hook)
  defp invoke(module, {:legacy, name}, hook), do: module.__arke_legacy__(name, hook)
  defp invoke(_module, fun, hook) when is_function(fun, 1), do: fun.(hook)

  defp invalid_return(module, slot, other) do
    Error.create(
      :hook,
      "#{slot} hook in #{inspect(module)} returned #{inspect(other)}; expected {:ok, hook} or {:error, reason}"
    )
  end
end
