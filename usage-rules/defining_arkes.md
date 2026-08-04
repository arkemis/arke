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
    alias Arke.Core.Unit

    arke id: :person do
    end

    def before_create(_arke, unit),
      do: {:ok, Unit.update(unit, email: String.downcase(unit.data.email))}
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
- Lifecycle hooks on the Arke module: `before_load/2`, `on_load/2`,
  `before_validate/2`, `on_validate/2`, `before_create/2`, `on_create/2`,
  `before_update/3`, `on_update/3`, `before_delete/2`, `on_delete/2`,
  `before_struct_encode/2`, `on_struct_encode/4`, `after_get_struct/2`. All
  return `{:ok, unit}` or `{:error, errors}`.
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

- Hook execution order (create): `before_load` → validate → `before_create` →
  group `before_unit_create` → persistence → `on_create` → group
  `on_unit_create`. On delete the group/arke order is inverted: persistence
  runs BEFORE `on_unit_delete`/`on_delete`, so "after" delete hooks cannot
  veto the delete.
- To skip persisting a parameter, set `only_runtime: true` in the parameter's
  metadata override on the Arke (note: the registered global parameter id is
  `only_run_time`, but the metadata key the code honors is `only_runtime`).
- The xlsx `import/1` function bulk-inserts in 5000-row chunks and BYPASSES
  `on_create` hooks — use `on_unit_import/4` for post-insert work. It also
  requires the template header to be a subset of the file header.
