# Reference — Public API Surface

Function-by-function reference for the modules you're likely to touch. Signatures reflect arke 0.6.0 source (not hexdocs, which lags). For each module, only public functions that callers use are listed; internal helpers are omitted.

## Module map

| Module | Role |
|---|---|
| `Arke.System` | Compile-time macros: `arke`, `parameter`, `group`, lifecycle hook overrides |
| `Arke.System.Group` | Same, for Group-level hooks |
| `Arke.Core.Unit` | Universal row struct + loaders/updaters |
| `Arke.Core.Query` | Query struct + low-level filter/order/limit builders |
| `Arke.QueryManager` | High-level CRUD + query entry point |
| `Arke.Boundary.ArkeManager` | ETS store for Arkes; parameter lookups on Arkes |
| `Arke.Boundary.ParameterManager` | ETS store for Parameters |
| `Arke.Boundary.GroupManager` | ETS store for Groups; group ↔ arke resolution |
| `Arke.Boundary.FileManager` | Signed-URL cache |
| `Arke.Validator` | Unit validation pipeline |
| `Arke.LinkManager` | Low-level link CRUD (`arke_link` Units) |
| `Arke.StructManager` | Encode Units to JSON-safe maps |
| `Arke.Core.Project` | Project Arke definition; create/delete project hooks |
| `Arke.Core.File` | File Arke definition; storage upload/signed URL hooks |
| `Arke.Utils.ErrorGenerator` | Standardized error shape |
| `Arke.Utils.DatetimeHandler` | Parse/format temporal values |
| `Arke.Errors.ArkeError` | Runtime exception type |

---

## `Arke.System` (the DSL)

Used as `use Arke.System` in a module that declares an Arke.

### Macros

```elixir
arke id: :person, label: "Person", active: true, type: "arke" do
  parameter :name, :string, required: true, min_length: 2, unique: true
  parameter :email, :string, required: true
  parameter :age, :integer, min: 0, max: 150
  parameter :role, :string, values: ["admin", "user", "guest"]
  group :searchable
end
```

- `arke/1`, `arke/2` — declares the Arke. Opts: `:id` (atom, defaults to module name underscored), `:label`, `:active` (default `true`), `:type` (default `"arke"`), `:metadata`. Body contains `parameter` and `group` calls.
- `parameter/2`, `parameter/3` — declares a field. Args: `id :: atom`, `type :: atom`, `opts :: keyword`. Common opts:
  - `:required` (bool, default `false`)
  - `:nullable` (bool, default `true`)
  - `:default` / `:default_string` / `:default_integer` / `:default_boolean` / `:default_list` / `:default_dict` / `:default_date` / `:default_datetime` / `:default_time` / `:default_link` — type-specific defaults
  - `:values` — enum list or list of `%{label:, value:}` maps (only `:string`, `:integer`, `:float`)
  - `:multiple` (bool) — allow multi-select for enum or link
  - `:unique` (bool, `:string`) — uniqueness check on create
  - `:min`, `:max` — numeric bounds
  - `:min_length`, `:max_length`, `:strip` — string bounds
  - `:persistence` — `"table_column"` (direct column) or `"arke_parameter"` (dynamic-schema column, default)
  - For `:link` parameters: `:arke_or_group_id`, `:connection_type`, `:direction` (`"child"` | `"parent"`), `:depth`, `:filter_keys`
- `group/1`, `group/2` — tags this Arke as a member of the named Group.

### Lifecycle hooks (defoverridable)

Override any of these in your module. All receive `arke` as first arg; returning `{:ok, unit}` continues, `{:error, errors}` halts.

```elixir
def on_load(unit, persistence_fn), do: {:ok, unit}
def before_load(data, persistence_fn), do: {:ok, data}
def on_validate(arke, unit), do: {:ok, unit}
def before_validate(arke, unit), do: {:ok, unit}
def on_create(arke, unit), do: {:ok, unit}
def before_create(arke, unit), do: {:ok, unit}
def on_update(arke, old_unit, unit), do: {:ok, unit}
def before_update(arke, old_unit, unit), do: {:ok, unit}
def on_delete(arke, unit), do: {:ok, unit}
def before_delete(arke, unit), do: {:ok, unit}
def before_struct_encode(arke, unit), do: {:ok, unit}
def on_struct_encode(arke, unit, data, opts), do: {:ok, data}
def after_get_struct(arke, unit, struct), do: struct
```

Hook firing order within CRUD — see `overview.md#the-crud-pipeline`.

Bulk-import hooks (for `Arke.System.import/1` with xlsx): `import_units/5`, `get_header_for_import/3`, `load_units/6`, `get_existing_units_for_import/4`, `check_existing_units_for_import/5`, `before_unit_import/4`, `on_unit_import/4`.

## `Arke.System.Group`

Used as `use Arke.System.Group` in a module that declares a Group.

```elixir
group id: :parameter do
  # (no parameters — groups tag Arkes, not define fields)
end
```

### Lifecycle hooks

These fire for Units of **any Arke that belongs to this Group**. Useful for cross-cutting behavior (e.g. all Parameter subtypes share a group that wires up ParameterManager).

```elixir
def on_unit_load(arke, data, persistence_fn), do: {:ok, data}
def before_unit_load(arke, data, persistence_fn), do: {:ok, data}
def on_unit_validate(arke, unit), do: {:ok, unit}
def before_unit_validate(arke, unit), do: {:ok, unit}
def on_unit_create(arke, unit), do: {:ok, unit}
def before_unit_create(arke, unit), do: {:ok, unit}
def on_unit_update(arke, unit), do: {:ok, unit}
def before_unit_update(arke, unit), do: {:ok, unit}
def on_unit_delete(arke, unit), do: {:ok, unit}
def before_unit_delete(arke, unit), do: {:ok, unit}
def on_unit_struct_encode(unit, _), do: {:ok, unit}
```

---

## `Arke.Core.Unit`

```elixir
%Arke.Core.Unit{
  id, data, arke_id, link, metadata,
  inserted_at, updated_at, __module__, runtime_data
}
```

### Construction

```elixir
Unit.new(id, data, arke_id, link, metadata, inserted_at, updated_at, module, runtime_data \\ %{})
```
Low-level struct constructor. `id` may be atom, string (converted via `String.to_atom`), or `nil`; numeric IDs return `{:error, _}`.

```elixir
Unit.load(arke, opts, persistence_fn \\ :get)
```
High-level loader. `arke` is a `%Unit{arke_id: :arke}` (from `ArkeManager.get`); `opts` is a keyword list or map of field values. Runs `before_load` and `on_load` hooks, applies defaults, parses values per parameter type. Returns a `%Unit{}`.

### Read

```elixir
Unit.get_value(unit_or_data, parameter_id)       # parameter_id: atom | binary
```
Extracts the value for one parameter. Unwraps the `%{"value" =>, "datetime" =>}` shape automatically.

```elixir
Unit.data_as_klist(%{arke:, data: data})          # -> [key: value, ...]
```

```elixir
Unit.get_data([unit1, unit2, ...])                # -> [data1, data2, ...]
```

### Write

```elixir
Unit.update(unit, args)                            # args: list or map
```
Returns a new `%Unit{}`. Parses values per parameter type. Does not persist — use `Arke.QueryManager.update/2` for that.

### Serialize

```elixir
Unit.as_args(arke, unit)     # -> keyword list suitable for Repo.insert_all
Unit.encode_unit_data(arke, data)  # -> map with %{"value" =>, "datetime" =>} wrappers
```

---

## `Arke.Core.Query`

Low-level query struct. You usually build queries via `Arke.QueryManager` instead of calling these directly, but the building blocks are here.

```elixir
%Query{project, arke, distinct, persistence, filters, orders, link, offset, limit}
```

### Sub-structs

- `%Query.Filter{logic, negate, base_filters}` — `:and` / `:or` bag of `BaseFilter`s
- `%Query.BaseFilter{parameter, operator, value, negate, path}` — a single atomic condition
- `%Query.LinkFilter{unit, depth, direction, type}` — topology filter
- `%Query.Order{parameter, direction, path}`

### Functions

```elixir
Query.new(arke, project, distinct \\ nil)
Query.add_filter(query, filter)
Query.add_filter(query, parameter, operator, value, negate, path \\ [])
Query.add_filter(query, logic, negate, base_filters)
Query.add_link_filter(query, unit, depth, direction, type)
Query.add_order(query, parameter, direction)
Query.set_offset(query, n)
Query.set_limit(query, n)
Query.new_filter(parameter, operator, value, negate, path \\ [])
Query.new_filter(logic, negate, base_filters)
Query.new_base_filter(parameter, operator, value, negate, path \\ [])
```

### Operators (atoms)

`:eq`, `:contains`, `:icontains`, `:startswith`, `:istartswith`, `:endswith`, `:iendswith`, `:lte`, `:lt`, `:gt`, `:gte`, `:in`, `:isnull`

---

## `Arke.QueryManager` — the front door

### CRUD

```elixir
QueryManager.create(project :: atom, arke :: %Unit{}, args :: list | map)
# -> {:ok, %Unit{}} | {:error, errors}

QueryManager.update(%Unit{} = unit, args :: list | map)
# -> {:ok, %Unit{}} | {:error, errors}

QueryManager.update_key(%Unit{} = unit, args)
# JSONB-level in-place update for :dict parameters (see arke v0.6.0 changelog).
# Does NOT re-run before_update/on_update; persistence is via the :update_key
# persistence function.

QueryManager.delete(project :: atom, %Unit{} = unit)
# -> {:ok, nil} | {:error, errors}
```

### Query builders

```elixir
QueryManager.query(project: :p, arke: :person, distinct: nil)
# -> %Query{}

QueryManager.where(query, [name__icontains: "ada", age__gte: 18])
QueryManager.filter(query, parameter, operator, value, negate \\ false)
QueryManager.filter(query, %Query.Filter{})
QueryManager.and_(query, negate, [conditions...])
QueryManager.or_(query, negate, [conditions...])
QueryManager.condition(parameter, operator, value, negate \\ false, path \\ [])
QueryManager.conditions(parameter__eq: "x", name__contains: "y")  # builds list
QueryManager.order(query, parameter, :asc | :desc)
QueryManager.offset(query, n)
QueryManager.limit(query, n)
QueryManager.link(query, unit, direction: :child, depth: 500, type: "parameter")
```

The `where/2` suffix syntax (`name__eq`, `age__gte`) is the most common form. Nested paths use dots: `"link_param.name__eq"`.

### Execute

```elixir
QueryManager.all(query)        # -> [%Unit{}, ...]
QueryManager.one(query)        # -> %Unit{} | nil
QueryManager.count(query)      # -> integer
QueryManager.raw(query)        # -> String.t  (SQL, if persistence supports it)
QueryManager.pseudo_query(q)   # -> Ecto.Query.t (before execution)
QueryManager.pagination(q, offset, limit)  # -> {count, [units]}
```

### Shortcuts

```elixir
QueryManager.get_by(id: "x", project: :p)              # -> %Unit{} | nil
QueryManager.filter_by(arke: :person, project: :p)     # -> [%Unit{}, ...]
```

Shortcut filters apply to direct parameters; for complex conditions, use `query |> where |> all`.

---

## Boundary managers

All four `Arke.Boundary.*` managers (except `FileManager`) use the `Arke.Boundary.UnitManager` macro, so they share this surface:

```elixir
Manager.get(unit_id, project)         # -> %Unit{} | nil | {:error, _}
Manager.get_all(project \\ :arke_system)  # -> [{unit_id, project}, ...]
Manager.create(unit, project \\ project_from_unit, opts \\ [])
Manager.update(unit_id, project, new_unit)
Manager.update(%Unit{} = unit, new_unit)
Manager.remove(unit_id, project)
Manager.remove(%Unit{} = unit)
Manager.call_func(unit_or_id, project_or_func, func_or_opts, opts? \\ [])
Manager.get_link(unit_or_id, project_or_param_id, param_id?)
Manager.add_link(unit_or_id, project_or_param_id, param_id_or_child, child_or_metadata, metadata?)
Manager.remove_link(unit_or_id, project_or_param_id, param_id_or_child, child?)
```

`get/2` falls back to `:arke_system` if the unit isn't found in the requested project — see [gotchas.md](gotchas.md#the-arke_system-fallback).

### `Arke.Boundary.ArkeManager` extras

```elixir
ArkeManager.get_parameters(%Unit{} = arke)
# -> [%Unit{}, ...]  -- the Parameter Units attached to this Arke

ArkeManager.get_parameter(arke_id_or_unit, project, parameter_id)
# -> %Unit{} | nil

ArkeManager.update_parameter(arke_id, parameter_id, project, metadata)
# -> {:ok, %Unit{}} | {:error, _}
```

### `Arke.Boundary.GroupManager` extras

```elixir
GroupManager.get_arke_list(%Unit{} = group)
# -> [%Unit{}, ...]  -- Arke Units that belong to this group

GroupManager.get_arke(group_id_or_unit, project, arke_id)
GroupManager.get_groups_by_arke(arke_id_or_unit, project?)
# -> [%Unit{}, ...]  -- groups this arke is a member of

GroupManager.get_parameters(group_id_or_unit, project?)
# -> [%Unit{}, ...]  -- union of parameters across member arkes
```

### `Arke.Boundary.FileManager`

Dedicated cache for signed URLs (not a UnitManager). Expired entries purged hourly.

```elixir
FileManager.add(%Unit{}, %{signed_url:, expiration:})
FileManager.add(unit_id, project, signed_url, expiration)
FileManager.get(unit_id, project)
FileManager.get_all(project)
FileManager.remove(unit_id, project)
FileManager.remove(%Unit{})
```

---

## `Arke.Validator`

```elixir
Validator.validate(%Unit{} = unit, persistence_fn :: :create | :update, project \\ :arke_system)
# -> {:ok, %Unit{}} | {:error, errors}
```

Runs `before_validate` → per-parameter type/enum/required/bounds checks → uniqueness check (on `:create`) → collects all errors. Returns the possibly-coerced Unit (values parsed to correct types).

---

## `Arke.LinkManager`

Low-level `arke_link` Unit CRUD. Usually you set `:link` parameter values on a Unit and let `QueryManager.update/2` handle it, but for direct graph work:

```elixir
LinkManager.add_node(project, parent, child, type \\ "link", metadata \\ %{})
LinkManager.update_node(project, parent, child, type, metadata)
LinkManager.delete_node(project, parent, child, type, metadata \\ %{})
```

`parent` and `child` may be `%Unit{}` or string IDs. If strings, `LinkManager` fetches the Units via `QueryManager.get_by`. Returns `{:ok, %Unit{}}` or `{:error, errors}`. Duplicate links raise `"link already exists"`.

---

## `Arke.StructManager`

```elixir
StructManager.encode(unit_or_units, opts \\ [])
# opts: type: :json (default), load_links: bool, load_files: bool
# -> map | [maps]
```

Produces a JSON-safe map: `%{id:, arke_id:, data, inserted_at:, updated_at:, metadata:}`. With `load_links: true`, inline-expands linked Units (resolves `:link` parameters). With `load_files: true`, resolves signed URLs for `arke_file` Units.

Per-Arke `before_struct_encode/2` and `on_struct_encode/4` hooks are invoked.

---

## `Arke.Core.Project`, `Arke.Core.File`

These are Arke definitions (not API modules). Notable hooks:

- `Arke.Core.Project.on_create/2` calls `persistence[:arke_postgres][:create_project]` — creates a tenant schema or equivalent in the backend.
- `Arke.Core.Project.on_delete/2` calls `:delete_project`.
- `Arke.Core.File.before_create/2` uploads the binary to the configured `file_storage_module` (default `Arke.Utils.Gcp`).
- `Arke.Core.File.before_delete/2` removes the stored object.
- `Arke.Core.File.on_struct_encode/4` resolves a signed URL when `load_files: true`.

Configure the storage backend:
```elixir
config :arke, file_storage_module: Arke.Utils.Gcp  # default; implement the behaviour to swap
```

---

## `Arke.Utils.ErrorGenerator`

```elixir
ErrorGenerator.create(context :: atom | string, errors :: list | string | atom)
# -> {:error, [%{context: "…", message: "…"}, ...]}
```

Used pervasively; the returned shape is the canonical error format across the library.

## `Arke.Utils.DatetimeHandler`

```elixir
DatetimeHandler.parse_date(value)
DatetimeHandler.parse_time(value)
DatetimeHandler.parse_datetime(value, iso8601? \\ false)
DatetimeHandler.now(:date | :time | :datetime | :naive_datetime)
DatetimeHandler.format(datetime, format_string)
```

Accepts strings, sigils, and native structs. See `Arke.Core.Parameter.DateTime` moduledoc for supported input formats.

---

## `Arke.Errors.ArkeError`

```elixir
raise Arke.Errors.ArkeError, message: "…", type: :not_found
```

Raised by `QueryManager.get_by` when the `arke:` option refers to a non-existent Arke. Message formatter unwraps `ErrorGenerator` lists.

---

## Mix tasks

```bash
mix arke.seed_project --project my_proj        # seed one project from registry JSONs
mix arke.seed_project --all                    # seed every project in the DB
mix arke.seed_project --project p --format json
mix arke.seed_project --persistence arke_postgres  # default

mix arke.export_data --project my_proj         # export arkes/params/groups/links to JSON
mix arke.export_data --project p --arke        # only arkes
mix arke.export_data --project p --split_file  # separate files per kind
```

Both tasks require `:persistence` configured and an `arke_postgres`-style backend that exposes a `:repo` module.

---

## What's NOT in this package

Search elsewhere for:
- Ecto schemas, repo definitions, migrations → `arke_postgres`
- HTTP plug / routes / controllers → `arke_server`
- Users, tokens, Guardian, permissions → `arke_auth`
- React components → frontend packages

The `ArkeAuth.Guardian.get_member(conn)` call inside `Arke.System.import/1` is a soft dependency on `arke_auth` — only reached when you use the bulk-import hook.
