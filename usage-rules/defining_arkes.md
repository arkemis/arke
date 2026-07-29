# Defining Arkes

- Declare an Arke with the `Arke.System` DSL:

  ```elixir
  defmodule MyApp.Person do
    use Arke.System
    alias Arke.Core.Unit

    arke id: :person, label: "Person" do
      parameter :name,  :string,  required: true, min_length: 2, unique: true
      parameter :email, :string,  required: true
      parameter :age,   :integer, min: 0, max: 150
      parameter :role,  :string,  values: ["admin", "user", "guest"], default_string: "user"
      parameter :bio,   :dict,    default_dict: %{}
    end

    def before_create(_arke, unit),
      do: {:ok, Unit.update(unit, email: String.downcase(unit.data.email))}
  end
  ```

- The module alone is inert: you MUST also register the Arke in a registry
  JSON (e.g. `lib/registry/shared/arke.json` in your app) and seed the
  project, or have the Arke in the DB. The module is bound to the loaded Arke
  by id match:

  ```json
  {"arke": [{"id": "person", "label": "Person",
    "parameters": [{"id": "name", "metadata": {"required": true, "min_length": 2, "unique": true}}]}]}
  ```

- When the same id exists both in code and registry/DB, the registry/DB
  definition wins for data; the module contributes only hooks.
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
