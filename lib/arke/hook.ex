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

defmodule Arke.Hook do
  @moduledoc """
  Context token passed to every write-pipeline hook.

  All handlers are arity-1 over the token and return `{:ok, hook}` or
  `{:error, reason}`. The operation, previous unit and failure reason are
  fields, not extra arguments: one signature everywhere. Mutating `hook.unit`
  before the write is how data transforms happen.

    * `:op` — `:create` | `:update` | `:delete`
    * `:arke` — the arke definition unit
    * `:group` — the group definition unit, set while a group module's hooks run
    * `:project` — the project the write targets
    * `:unit` — the unit being written
    * `:old_unit` — the pre-update unit (`:update` only)
    * `:error` — the failure reason (`after_rollback` only)
  """

  defstruct [:op, :arke, :group, :project, :unit, :old_unit, :error]

  @type op() :: :create | :update | :delete

  @type t() :: %__MODULE__{
          op: op(),
          arke: Arke.Core.Unit.t() | nil,
          group: Arke.Core.Unit.t() | nil,
          project: atom(),
          unit: Arke.Core.Unit.t() | nil,
          old_unit: Arke.Core.Unit.t() | nil,
          error: any()
        }
end
