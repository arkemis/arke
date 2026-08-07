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

defmodule Arke.Hook.DSL do
  @moduledoc """
  Plug-style hook registration, available inside `use Arke.System` and
  `use Arke.System.Group` modules.

      before_write :check_cashback_limit, on: :create
      after_commit :send_status_email,    on: [:create, :update]
      after_write fn hook -> {:ok, hook} end

  Handlers are private arity-1 functions named by atom, or captures/anonymous
  functions for one-liners. Registration order is execution order; multiple
  hooks per slot are first-class. `on:` filters by operation
  (`:create` | `:update` | `:delete`); without it the hook runs on every op.

  At `@before_compile` the accumulated registrations become
  `__arke_hooks__/0` (the ordered entry list `Arke.Hook.Pipeline` reads) and
  `__arke_hook_call__/2` (the dispatcher that reaches private handlers).
  """

  @slots [:before_transaction, :before_write, :after_write, :after_commit, :after_rollback]
  @ops [:create, :update, :delete]

  for slot <- @slots do
    defmacro unquote(slot)(handler, opts \\ []) do
      Arke.Hook.DSL.__register__(unquote(slot), handler, opts)
    end
  end

  def __register__(slot, handler, opts) do
    handler_ast = Macro.escape(handler)

    quote do
      @arke_hooks {unquote(slot), unquote(handler_ast), unquote(opts)}
    end
  end

  defmacro __before_compile__(env) do
    hooks =
      env.module
      |> Module.get_attribute(:arke_hooks)
      |> Enum.reverse()
      |> Enum.map(fn {slot, handler, opts} -> {slot, handler, normalize_on(env, opts)} end)

    entries =
      Enum.map(hooks, fn {slot, handler, on} ->
        handler_repr =
          if is_atom(handler),
            do: quote(do: {:local, unquote(handler)}),
            else: handler

        quote do
          %{slot: unquote(slot), on: unquote(on), handler: unquote(handler_repr)}
        end
      end)

    dispatchers =
      for name <- hooks |> Enum.map(&elem(&1, 1)) |> Enum.filter(&is_atom/1) |> Enum.uniq() do
        quote do
          def __arke_hook_call__(unquote(name), hook), do: unquote(name)(hook)
        end
      end

    quote do
      def __arke_hooks__(), do: unquote(entries)
      unquote_splicing(dispatchers)
    end
  end

  defp normalize_on(_env, []), do: nil

  defp normalize_on(env, opts) do
    case Keyword.fetch(opts, :on) do
      :error ->
        nil

      {:ok, on} ->
        on = List.wrap(on)

        case Enum.reject(on, &(&1 in @ops)) do
          [] ->
            on

          bad ->
            raise CompileError, description: "invalid hook op #{inspect(bad)}", file: env.file
        end
    end
  end
end
