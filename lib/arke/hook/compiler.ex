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

defmodule Arke.Hook.Compiler do
  @moduledoc """
  Compile-time backing of `Arke.Hook.DSL`.

  Runs as a `@before_compile` hook of `use Arke.System` and
  `use Arke.System.Group`. It turns the accumulated `@arke_hooks`
  registrations into `__arke_hooks__/0` (the ordered entry list the pipeline
  reads) and `__arke_hook_call__/2` (the dispatcher that reaches private
  handlers).

  It also implements the deprecation shim: old-style callback heads
  (`before_create/2`, `on_update/3`, `before_unit_create/2`, ...) are detected
  and auto-registered as pipeline entries that run OUTSIDE the transaction,
  keeping the autocommit-era semantics they were written against — `before_*`
  in the pre-transaction stage, `on_*` after the commit. Ordering and error
  propagation are preserved; only migrated hooks join the transaction. One
  warning per module points at the migration.
  """

  @ops [:create, :update, :delete]

  # Legacy hooks keep autocommit-era semantics, so they run OUTSIDE the
  # transaction: `before_*` in the pre-txn stage (same position, mutations
  # still reach the persist), `on_*` after the commit (the row is committed
  # and visible, as the hook was written to assume; an error is returned to
  # the caller but no longer rolls anything back — exactly the old contract).
  @arke_legacy [
    {:before_create, 2, :before_transaction, :create},
    {:before_update, 3, :before_transaction, :update},
    {:before_delete, 2, :before_transaction, :delete},
    {:on_create, 2, :legacy_after, :create},
    {:on_update, 3, :legacy_after, :update},
    {:on_delete, 2, :legacy_after, :delete}
  ]

  @group_legacy [
    {:before_unit_create, 2, :before_transaction, :create},
    {:before_unit_update, 2, :before_transaction, :update},
    {:before_unit_delete, 2, :before_transaction, :delete},
    {:on_unit_create, 2, :legacy_after, :create},
    {:on_unit_update, 2, :legacy_after, :update},
    {:on_unit_delete, 2, :legacy_after, :delete}
  ]

  # {old_name, new_name, arity, default_body_kind} — the new heads are only
  # emitted at before_compile so a user definition (or a legacy old-name head
  # to delegate to) can be detected first.
  @arke_renames [
    {:on_load, :after_load, 2, :first},
    {:on_validate, :after_validate, 2, :second},
    {:on_struct_encode, :after_struct_encode, 4, :third}
  ]

  defmacro __before_compile_arke__(env), do: compile(env, :arke)
  defmacro __before_compile_group__(env), do: compile(env, :group)

  defp compile(env, kind) do
    module = env.module
    legacy = detect_legacy(module, kind)

    {renames, rename_defaults} =
      if kind == :arke, do: detect_renames(module), else: {[], []}

    warn_legacy(env, legacy, renames, kind)

    dsl =
      module
      |> Module.get_attribute(:arke_hooks)
      |> Enum.reverse()
      |> Enum.map(fn {slot, handler, opts} -> {slot, handler, normalize_on(env, opts)} end)

    entries =
      Enum.map(legacy, fn {name, _arity, slot, op} ->
        quote do
          %{slot: unquote(slot), on: [unquote(op)], handler: {:legacy, unquote(name)}}
        end
      end) ++
        Enum.map(dsl, fn {slot, handler, on} ->
          handler_repr =
            if is_atom(handler),
              do: quote(do: {:local, unquote(handler)}),
              else: handler

          quote do
            %{slot: unquote(slot), on: unquote(on), handler: unquote(handler_repr)}
          end
        end)

    dispatchers =
      for name <- dsl |> Enum.map(&elem(&1, 1)) |> Enum.filter(&is_atom/1) |> Enum.uniq() do
        quote do
          def __arke_hook_call__(unquote(name), hook), do: unquote(name)(hook)
        end
      end

    quote do
      def __arke_hooks__(), do: unquote(entries)
      unquote_splicing(dispatchers)
      unquote_splicing(Enum.map(legacy, &legacy_wrapper/1))
      unquote_splicing(Enum.map(renames, &rename_delegation/1))
      unquote_splicing(Enum.map(rename_defaults, &rename_default/1))
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

  defp detect_legacy(module, kind) do
    table = if kind == :arke, do: @arke_legacy, else: @group_legacy
    Enum.filter(table, fn {name, arity, _, _} -> Module.defines?(module, {name, arity}) end)
  end

  defp detect_renames(module) do
    Enum.reduce(@arke_renames, {[], []}, fn {old, new, arity, _} = rename,
                                            {delegations, defaults} ->
      cond do
        Module.defines?(module, {new, arity}) -> {delegations, defaults}
        Module.defines?(module, {old, arity}) -> {[rename | delegations], defaults}
        true -> {delegations, [rename | defaults]}
      end
    end)
  end

  defp legacy_wrapper({name, 2, _slot, op}) do
    quote do
      def __arke_legacy__(unquote(name), hook) do
        unquote(__MODULE__).__legacy_result__(
          unquote(name)(hook.arke, hook.unit),
          hook,
          unquote(op)
        )
      end
    end
  end

  defp legacy_wrapper({name, 3, _slot, op}) do
    quote do
      def __arke_legacy__(unquote(name), hook) do
        unquote(__MODULE__).__legacy_result__(
          unquote(name)(hook.arke, hook.old_unit, hook.unit),
          hook,
          unquote(op)
        )
      end
    end
  end

  def __legacy_result__({:ok, %Arke.Core.Unit{} = unit}, hook, op) when op != :delete,
    do: {:ok, %{hook | unit: unit}}

  def __legacy_result__({:ok, _}, hook, _op), do: {:ok, hook}
  def __legacy_result__({:error, reason}, _hook, _op), do: {:error, reason}

  defp rename_delegation({old, new, 2, _}) do
    quote do
      def unquote(new)(a, b), do: unquote(old)(a, b)
    end
  end

  defp rename_delegation({old, new, 4, _}) do
    quote do
      def unquote(new)(a, b, c, d), do: unquote(old)(a, b, c, d)
    end
  end

  defp rename_default({_, new, 2, :first}) do
    quote do
      def unquote(new)(value, _), do: {:ok, value}
    end
  end

  defp rename_default({_, new, 2, :second}) do
    quote do
      def unquote(new)(_, value), do: {:ok, value}
    end
  end

  defp rename_default({_, new, 4, :third}) do
    quote do
      def unquote(new)(_, _, value, _), do: {:ok, value}
    end
  end

  defp warn_legacy(env, legacy, renames, kind) do
    heads =
      Enum.map(legacy, fn {name, arity, _, _} -> "#{name}/#{arity}" end) ++
        Enum.map(renames, fn {old, new, arity, _} -> "#{old}/#{arity} (renamed to #{new})" end)

    dead =
      if kind == :arke and Module.defines?(env.module, {:before_update, 2}) and
           not Module.defines?(env.module, {:before_update, 3}),
         do: ["before_update/2 was never invoked by the old pipeline and is NOT shimmed"],
         else: []

    warn? = Module.get_attribute(env.module, :arke_legacy_warning) != false

    if warn? and (heads != [] or dead != []) do
      IO.warn(
        """
        #{inspect(env.module)} defines legacy arke hooks: #{Enum.join(heads ++ dead, ", ")}.
        Legacy hooks run OUTSIDE the transaction (autocommit semantics preserved).
        DB writes: rename to before_write/after_write (arity-1 handlers over %Arke.Hook{}) to join the transaction.
        External effects (email, HTTP, Tasks, caches): move to after_commit or before_transaction.
        Set `@arke_legacy_warning false` to silence this warning while migrating.
        """,
        Macro.Env.stacktrace(env)
      )
    end
  end
end
