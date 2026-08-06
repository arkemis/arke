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
  """

  @slots [:before_transaction, :before_write, :after_write, :after_commit, :after_rollback]

  def slots(), do: @slots

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
end
