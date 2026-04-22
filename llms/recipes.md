# Recipes — Common Tasks

Task-oriented snippets. Each recipe is self-contained; read [overview.md](overview.md) first for the mental model.

All recipes assume:
- `:arke` application started.
- `config :arke, persistence: %{...}` configured (see [index.md](index.md#minimum-you-need-to-use-it)).
- `alias Arke.QueryManager`, `alias Arke.Boundary.{ArkeManager, ParameterManager, GroupManager}`, `alias Arke.Core.Unit` in scope.

---

## Define a new Arke in code

```elixir
defmodule MyApp.Person do
  use Arke.System

  arke id: :person, label: "Person" do
    parameter :name,  :string,  required: true, min_length: 2, unique: true
    parameter :email, :string,  required: true
    parameter :age,   :integer, min: 0, max: 150
    parameter :role,  :string,  values: ["admin", "user", "guest"], default_string: "user"
    parameter :bio,   :dict,    default_dict: %{}
    parameter :tags,  :string,  values: ["vip", "churned", "new"], multiple: true
  end

  # Optional lifecycle hooks
  def before_create(_arke, unit) do
    normalized_email = unit.data.email |> String.downcase() |> String.trim()
    {:ok, Unit.update(unit, email: normalized_email)}
  end

  def on_create(_arke, unit) do
    # side effects here — e.g. enqueue a welcome email
    {:ok, unit}
  end
end
```

At app boot, `Arke.init/0` discovers this module and registers the Arke in `ArkeManager` under `:arke_system`. If you want it persisted to the DB, run `mix arke.seed_project --project your_proj` after adding a registry JSON entry in `lib/registry/shared/arke.json`.

---

## Create a Unit

```elixir
arke = ArkeManager.get(:person, :my_project)

{:ok, unit} =
  QueryManager.create(:my_project, arke,
    name: "Ada Lovelace",
    email: "ada@example.com",
    age: 36,
    role: "admin"
  )

unit.id          # :some_uuid_atom (auto-generated if not provided)
unit.data.name   # "Ada Lovelace"
```

- `arke` must be a `%Unit{}`, not an atom. Fetch it from `ArkeManager.get/2`.
- Pass `args` as a keyword list **or** map.
- Provide `id:` explicitly if you want a deterministic ID (useful for system Arkes / fixtures).
- `QueryManager.create/3` returns `{:error, errors}` on validation failure — always pattern-match.

---

## Read a Unit

```elixir
# by id
QueryManager.get_by(id: "some_id", project: :my_project)
# -> %Unit{} | nil

# by arke_id + any parameter
QueryManager.get_by(arke_id: "person", email: "ada@example.com", project: :my_project)
```

For many results:
```elixir
QueryManager.filter_by(arke_id: "person", project: :my_project, role: "admin")
# -> [%Unit{}, ...]
```

---

## Update a Unit

```elixir
unit = QueryManager.get_by(id: "ada", project: :my_project)

{:ok, updated} = QueryManager.update(unit, age: 37, role: "user")
```

- `update/2` runs `before_update` / `on_update` hooks and re-validates.
- For in-place JSONB updates on `:dict` fields (no full round-trip), use `update_key/2`.

---

## Delete a Unit

```elixir
unit = QueryManager.get_by(id: "ada", project: :my_project)
{:ok, nil} = QueryManager.delete(:my_project, unit)
```

`on_delete` / `before_delete` hooks fire. For `:link` parameters, associated `arke_link` Units are cleaned up via the `handle_link_parameters` step.

---

## Query with filters

```elixir
import Arke.QueryManager

query(project: :my_project, arke: :person)
|> where(name__icontains: "ada", age__gte: 18, role__eq: "admin")
|> order(:inserted_at, :desc)
|> limit(20)
|> all()
```

Operator suffix cheatsheet:

| Suffix | Meaning |
|---|---|
| `__eq` | exact equality (default if no suffix) |
| `__contains` / `__icontains` | substring (case-sensitive / insensitive) |
| `__startswith` / `__istartswith` | prefix match |
| `__endswith` / `__iendswith` | suffix match |
| `__lt`, `__lte`, `__gt`, `__gte` | numeric/temporal comparisons |
| `__in` | value is in a list |
| `__isnull` | null check |

## Compose OR and AND explicitly

```elixir
q = query(project: :my_project, arke: :person)

q
|> and_(false, conditions(role__eq: "admin", age__gte: 40))
|> or_(false, conditions(tags__in: ["vip"]))
|> all()
```

---

## Pagination

```elixir
{count, units} =
  query(project: :my_project, arke: :person)
  |> where(role__eq: "user")
  |> pagination(40, 20)   # offset, limit
```

`pagination/3` runs a count query (with orders stripped) and the paged fetch.

---

## Topology / link queries

Walk the link graph starting from a reference Unit.

```elixir
ada = QueryManager.get_by(id: "ada", project: :my_project)

# All Units linked to ada as children via "friendship" type, up to depth 3
query(project: :my_project, arke: :person)
|> link(ada, direction: :child, depth: 3, type: "friendship")
|> all()
```

Options:
- `direction:` — `:child` (from parent toward children) or `:parent`
- `depth:` — integer, default `500`
- `type:` — link type string (matches the `arke_link.type` field)

---

## Create / delete links directly

```elixir
alias Arke.LinkManager

LinkManager.add_node(:my_project, parent_unit, child_unit, "friendship", %{since: "2024"})
LinkManager.update_node(:my_project, parent_unit, child_unit, "friendship", %{weight: 0.8})
LinkManager.delete_node(:my_project, parent_unit, child_unit, "friendship")
```

`parent` and `child` may also be string IDs; LinkManager will fetch them.

---

## `:link` parameters (preferred over LinkManager for most cases)

Declare a `:link` parameter on an Arke and set its value like any other field. Underlying `arke_link` Units are created/deleted automatically.

```elixir
arke id: :invoice do
  parameter :customer, :link,
    arke_or_group_id: "person",
    connection_type: "invoice_customer",
    direction: "parent",
    multiple: false
end

# Creating an invoice with a customer reference:
{:ok, inv} = QueryManager.create(:my_project, invoice_arke,
  number: "INV-001",
  customer: "ada"   # just the child Unit id as a string
)

# Updating changes the arke_link Unit:
{:ok, _inv} = QueryManager.update(inv, customer: "grace")
# Old arke_link removed, new one added.
```

With `multiple: true`, the value is a list of IDs. See [gotchas.md](gotchas.md#link-parameters-have-side-effects) for edge cases.

---

## Encode Units for an API response

```elixir
alias Arke.StructManager

unit = QueryManager.get_by(id: "ada", project: :my_project)

StructManager.encode(unit, type: :json)
# -> %{id: "ada", arke_id: "person", data: %{...}, metadata: %{...}, inserted_at: ..., updated_at: ...}

# Inline expand link parameters:
StructManager.encode(unit, type: :json, load_links: true)

# Resolve signed URLs for arke_file Units:
StructManager.encode(unit, type: :json, load_files: true)

# Lists work too:
units = QueryManager.filter_by(arke_id: "person", project: :my_project)
StructManager.encode(units, type: :json)
```

---

## Add a custom validation hook

Per-Arke: override `on_validate` or `before_validate` in the module.

```elixir
defmodule MyApp.Person do
  use Arke.System
  arke id: :person do
    parameter :email, :string, required: true
  end

  def on_validate(_arke, unit) do
    if unit.data.email =~ ~r/@example\.com$/ do
      {:ok, unit}
    else
      Arke.Utils.ErrorGenerator.create(:validation, "email must be @example.com")
    end
  end
end
```

Return `{:ok, unit}` to continue, `{:error, errors}` to abort the pipeline.

---

## Add a cross-Arke hook via a Group

```elixir
defmodule MyApp.Auditable do
  use Arke.System.Group

  group id: :auditable do
  end

  def on_unit_create(_arke, unit) do
    MyApp.AuditLog.record(:create, unit)
    {:ok, unit}
  end

  def on_unit_update(_arke, unit) do
    MyApp.AuditLog.record(:update, unit)
    {:ok, unit}
  end
end
```

Then add `group :auditable` inside any Arke's `arke do … end` block. The hook fires for every Unit of every Arke that's in the group.

---

## Multi-tenant: create a project

```elixir
project_arke = ArkeManager.get(:arke_project, :arke_system)

{:ok, _unit} = QueryManager.create(:arke_system, project_arke,
  id: "client_acme",
  label: "ACME Corp"
)
# `on_create` calls persistence[:arke_postgres][:create_project] → provisions the schema/DB.
```

Then seed the new project:
```bash
mix arke.seed_project --project client_acme
```

## Switch projects in queries

Every `QueryManager` function takes a `project:` option. The project atom scopes all reads and writes.

```elixir
acme_people = QueryManager.filter_by(arke_id: "person", project: :client_acme)
```

System-level Arkes (the schema Arkes themselves) transparently resolve via the `:arke_system` fallback — see [gotchas.md](gotchas.md#the-arke_system-fallback).

---

## Bulk import from xlsx

The `Arke.System.import/1` hook (provided by `use Arke.System`) parses an xlsx file uploaded via a Plug conn and bulk-inserts.

```elixir
# In a controller / handler receiving a file upload:
arke = ArkeManager.get(:person, :my_project)
arke_with_conn = %{arke | runtime_data: %{conn: conn}, metadata: %{project: :my_project}}
Arke.System.Arke.import(arke_with_conn)
# -> {:ok, %{count_inserted, count_existing, count_error, total_count, error_units}, 201}
```

Customize by overriding `get_header_for_import/3`, `load_units/6`, `check_existing_units_for_import/5`, `before_unit_import/4`, `on_unit_import/4`.

The import uses `ArkePostgres.Repo.insert_all/3` in 5000-row chunks — bypasses `on_create` hooks, so use `on_unit_import/4` for post-insert work.

---

## Export project data

```bash
mix arke.export_data --project my_project --split_file
# writes JSON files of arkes/parameters/groups/links to disk
```

Useful for project-to-project migration or creating registry fixtures.

---

## Use a custom persistence backend

Implement the same function signatures as `arke_postgres` and wire them up:

```elixir
config :arke,
  persistence: %{
    arke_postgres: %{
      create:         &MyBackend.create/2,
      update:         &MyBackend.update/2,
      update_key:     &MyBackend.update_key/2,
      delete:         &MyBackend.delete/2,
      execute_query:  &MyBackend.execute/2,
      create_project: &MyBackend.create_project/1,
      delete_project: &MyBackend.delete_project/1,
      repo:           MyBackend.Repo
    }
  }
```

Note the top-level key is still `:arke_postgres` regardless of the actual backend — the config shape is hardcoded. See [design.md](design.md#why-persistence-is-function-injected) for why.

## Use a custom file storage backend

```elixir
config :arke, file_storage_module: MyApp.S3Storage
```

Implement `upload_file/3`, `delete_file/1`, `get_public_url/1`, `get_bucket_file_signed_url/1`. Default is `Arke.Utils.Gcp` (Google Cloud Storage).
