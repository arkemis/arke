# Defining Arkes

- The registry JSON is the source of truth for schema. Define an Arke and its
  parameters there (e.g. `lib/registry/shared/arke.json` in your app), then
  seed the project:

  ```json
  {"arke": [{"id": "person", "label": "Person",
    "parameters": [
      {"id": "name",  "metadata": {"required": true, "min_length": 2, "unique": true}},
      {"id": "email", "metadata": {"required": true}},
      {"id": "age",   "metadata": {"min": 0, "max": 150}}
    ]}]}
  ```

- The Elixir module carries only BEHAVIOR (lifecycle hooks), bound to the
  loaded Arke by id match:

  ```elixir
  defmodule MyApp.Person do
    use Arke.System
    alias Arke.{Core.Unit, Hook}

    arke id: :person do
    end

    before_write :downcase_email, on: [:create, :update]

    defp downcase_email(%Hook{unit: unit} = hook),
      do: {:ok, %{hook | unit: Unit.update(unit, email: String.downcase(unit.data.email))}}
  end
  ```

- **Avoid declaring parameters with the `parameter` macro inside
  `arke do ... end`.** There is no sync mechanism between macro declarations
  and the registry: when the Arke is loaded from registry/DB (the only way it
  becomes live), the registry definition wins and the macro's parameter list
  is ignored. Declaring parameters in both places means maintaining two
  schema definitions that silently diverge — keep the macro block empty and
  the schema in JSON.
- The module alone is inert: `use Arke.System` registers nothing. Arkes
  become live only when loaded from registry JSON (`mix arke.seed_project`)
  or from the DB at boot. A module without a matching registry/DB entry never
  fires its hooks.
- Write-path hooks are declared with the registration DSL
  (`before_transaction`, `before_write`, `after_write`, `after_commit`,
  `after_rollback`). Handlers are private arity-1 functions over
  `%Arke.Hook{}` (fields: `op`, `arke`, `group`, `project`, `unit`,
  `old_unit`, `error`) returning `{:ok, hook}` or `{:error, reason}`; the op
  is `hook.op`, `on:` filters it, registration order is execution order:
  - `before_transaction`: outside the txn, before any write — external calls
    and slow work (bcrypt, HTTP, file staging); an error aborts everything.
  - `before_write` / `after_write`: inside the txn, around the persist.
    Mutate `hook.unit` in `before_write`; an error in either rolls the whole
    write back.
  - `after_commit`: after the OUTERMOST commit, success only — the only legal
    home for effects (email, push, Tasks, cache sync). It cannot mutate the
    persisted row.
  - `after_rollback`: after rollback, failure only — compensation
    (`hook.error` carries the reason). Both post-outcome slots are isolated:
    a raising entry is logged and never changes the caller's result.
- Read/build-path hooks stay overridable callback heads: `before_load/2`,
  `after_load/2`, `before_validate/2`, `after_validate/2`,
  `before_struct_encode/2`, `after_struct_encode/4`, `after_get_struct/2`.
  They return `{:ok, value}` or `{:error, errors}`.
- Legacy callbacks (`before_create/2`, `on_create/2`, `before_update/3`,
  `on_update/3`, `before_delete/2`, `on_delete/2` and the group
  `before_unit_*`/`on_unit_*` heads) still work through a compile-time shim
  but run OUTSIDE the transaction with their historical autocommit semantics:
  an `on_*` error is returned to the caller yet rolls nothing back. Migrate
  `before_*` to `before_write`, `on_*` to `after_write` (or `after_commit`
  for effects) to join the transaction. Silence the per-module deprecation
  warning during migration with `@arke_legacy_warning false`.
- Do not spawn Tasks that read the written row from inside the transaction
  (`before_write`/`after_write`): the row is not visible to other processes
  until commit — use `after_commit`.
- Group hooks: define a module with `use Arke.System.Group` and
  `group id: :my_group do end` (the do-block is required; only `:id` is
  kept). Membership comes from `group.json` (`"arke_list": [...]`) or an
  `arke_link` of type `"group"`:

  ```elixir
  # WRONG — `group :auditable` inside `arke do ... end` is inert; nothing reads it
  arke id: :person do
    group :auditable
  end

  # CORRECT — declare membership in group.json
  {"group": [{"id": "auditable", "label": "Auditable", "arke_list": ["person"]}]}
  ```

- Hook execution order (create/update): `before_load` → validate →
  `before_transaction` (arke, then groups) → [txn: `before_write` (arke,
  then groups) → persistence → `after_write` (arke) → link sync →
  `after_write` (groups)] → commit → `after_commit`. On delete the group/arke
  order is inverted on the after side, and persistence runs BEFORE the
  `after_write` hooks — they cannot veto the delete, but their error still
  rolls it back.
- Group modules use the same DSL slots; while a group's hooks run,
  `hook.group` is set to the group unit.
- To skip persisting a parameter, set `only_runtime: true` in the parameter's
  metadata override on the Arke (note: the registered global parameter id is
  `only_run_time`, but the metadata key the code honors is `only_runtime`).
- The xlsx `import/1` function bulk-inserts in 5000-row chunks and BYPASSES
  `on_create` hooks — use `on_unit_import/4` for post-insert work. It also
  requires the template header to be a subset of the file header.
