# Overview — Mental Model

## What problem Arke solves

Traditional Elixir apps hand-write an `Ecto.Schema` per domain model. Arke removes that step: models are **dynamic**. You can declare them in code (compile-time macros) or load them from the database at boot. The framework then provides uniform CRUD, validation, query, link management, and serialization over whatever models exist.

This makes Arke suited to:
- Multi-tenant SaaS where each tenant may need custom fields.
- Low-code / headless-CMS style products where non-developers define models.
- Systems where the shape of data evolves at runtime without deploys.

## The six core abstractions

Everything in Arke is built from these six concepts. Internalize them before reading anything else.

### 1. Unit — `Arke.Core.Unit`
The universal row shape. **Every persisted thing is a Unit** — a user record, a schema definition, a link, a group. The struct is:

```elixir
%Arke.Core.Unit{
  id:          :some_atom_or_uuid,
  arke_id:     :person,          # which Arke this Unit is an instance of
  data:        %{name: "Ada", email: "…"},  # the actual field values
  metadata:    %{project: :my_project},     # project tenancy + extras
  link:        nil,              # set when Unit came from a link query
  inserted_at: ~N[…],
  updated_at:  ~N[…],
  __module__:  MyApp.Person,     # optional module with lifecycle hooks
  runtime_data: %{}              # transient per-request context
}
```

The `__module__` field is key: it lets a Unit carry behavior (lifecycle hooks) without coupling the struct to a particular implementation.

### 2. Arke — `Arke.Core.Arke`
The blueprint. An Arke declares a set of Parameters that its Units will have. "Person" is an Arke; each actual person is a Unit whose `arke_id` is `:person`.

Arkes are themselves stored as Units (`arke_id: :arke`). This is the bootstrap: the schema system is its own first citizen.

### 3. Parameter — `Arke.Core.Parameter.*`
A typed field. Built-in types (each a submodule):
- **Scalar:** `:string`, `:integer`, `:float`, `:boolean`
- **Temporal:** `:date`, `:time`, `:datetime`
- **Structured:** `:dict`, `:list`, `:binary`
- **Relational:** `:link` (see below)
- **Special:** `:dynamic` (untyped)

Parameters are also Units (`arke_id` being the type, e.g. `:string`). They carry metadata: `required`, `nullable`, `default_*`, `min`/`max`, `values` (enum), `multiple`, `unique`, `persistence` (see [gotchas.md](gotchas.md)).

### 4. Group — `Arke.Core.Group`
A cross-Arke tag. A Group has an `arke_list` of member Arkes and can attach lifecycle hooks (`on_unit_create`, `on_unit_update`, …) that fire for every Unit of any member Arke. Groups let you apply cross-cutting behavior without touching each Arke.

Example: the built-in `parameter` group covers all `Arke.Core.Parameter.*` types, so `ParameterManager.create/1` runs in their shared `on_unit_create` hook.

### 5. Link — `Arke.Core.Link` / `Arke.LinkManager`
A directed, typed edge between two Units. Stored as a Unit with `arke_id: :arke_link` and fields `{parent_id, child_id, type, metadata}`. Links are how everything relates — including the schema itself: an Arke's parameters are links of type `"parameter"` from the Arke Unit to each Parameter Unit.

A `:link` Parameter on an Arke is syntactic sugar: reading/writing the field implicitly creates or deletes `arke_link` Units. See [gotchas.md](gotchas.md#link-parameters-have-side-effects) — this is a sharp edge.

### 6. Project — `Arke.Core.Project`
A multi-tenant namespace. Every manager ETS key is `{unit_id, project}`; every DB row is keyed by project (the persistence layer handles row-level / schema-level isolation).

- `:arke_system` is the shared/default project — built-in Arkes, Parameters, Groups live here.
- Missing lookups in a custom project fall back to `:arke_system` (see [gotchas.md](gotchas.md#the-arke_system-fallback)).

## Runtime architecture

When the `:arke` application starts (`Arke.Application`), four GenServer managers spin up, each owning a named ETS table:

| Manager | Table | Holds |
|---|---|---|
| `Arke.Boundary.ArkeManager` | `:arke` | Arke Units (schemas) |
| `Arke.Boundary.ParameterManager` | `:parameter` | Parameter Units (field types) |
| `Arke.Boundary.GroupManager` | `:group` | Group Units |
| `Arke.Boundary.FileManager` | `:file_manager_cache` | Signed-URL cache (ephemeral) |

Plus `Cluster.Supervisor` from `libcluster` — the managers RPC each other across nodes so ETS state stays consistent (see `unit_manager.ex:241` `call_nodes_manager/3`).

### How schemas land in ETS

Two paths, both via `Arke.handle_manager/4`:

1. **Compile-time:** modules that `use Arke.System` register an `@arke` attribute via the `arke do … end` macro. At boot, `Arke.init/0` walks loaded modules and pushes their Arke into `ArkeManager`.
2. **Database:** `ArkePostgres` (or equivalent) loads persisted Arke/Parameter/Group Units from its tables and hands them to `handle_manager/4`, which creates the ETS entries.

The `mix arke.seed_project` task (in `lib/mix/tasks/`) bootstraps a project by reading JSON registry files (`lib/registry/system/*.json` for the `:arke_system` project, `lib/registry/shared/*.json` for others) and calling `QueryManager.create/3` for each.

### The CRUD pipeline

`Arke.QueryManager` is the single front door. Every mutation flows through the same pipeline of `before_*` / `on_*` hooks:

```
QueryManager.create(project, arke, args)
  → Unit.load/3                                # build %Unit{}
  → Validator.validate(:create)                # type/enum/required checks
  → ArkeManager.call_func(:before_create)      # Arke-defined hook
  → GroupManager → before_unit_create          # for every Group the Arke is in
  → handle_link_parameters_unit                # create linked Units in nested writes
  → persistence_fn.(project, unit)             # <-- INJECTED, actual DB write
  → ArkeManager.call_func(:on_create)
  → handle_link_parameters                     # sync :link parameter values to arke_link Units
  → GroupManager → on_unit_create
```

`persistence_fn` is read from `Application.get_env(:arke, :persistence)` at module-load time. That's the seam: core Arke does no I/O. `arke_postgres` provides the functions; an alternative backend could replace it without changing core code.

### Query

`%Arke.Core.Query{}` is a data structure (project, arke, filters, orders, link, offset, limit). You build it through `Arke.QueryManager`:

```elixir
import Arke.QueryManager

query(project: :my_project, arke: :person)
|> where(name__icontains: "ada", age__gte: 18)
|> order(:inserted_at, :desc)
|> limit(10)
|> all()
```

Operators are Django-style, suffix after `__`: `eq`, `contains`, `icontains`, `startswith`, `istartswith`, `endswith`, `iendswith`, `lt`, `lte`, `gt`, `gte`, `in`, `isnull`. Filters compose with `and_` / `or_` and can be nested. `link/3` adds a topology filter (walk the graph by direction + depth).

`execute_query/2` delegates to `persistence[:arke_postgres][:execute_query]` — same seam as writes.

### Encode

`Arke.StructManager.encode/2` turns Units (or lists of them) into JSON-safe maps. This runs `before_struct_encode` → build raw data → `on_struct_encode` per-Arke hook, optionally loading linked Units inline. It's the shape your HTTP layer (typically `arke_server`) serializes.

## Boundaries at a glance

```
┌─────────────────────────────────────────────────────┐
│                 Your application                    │
│   (or arke_server / arke_auth / other siblings)     │
└───────────────┬─────────────────────────────────────┘
                │
                ▼
     ┌────────────────────┐
     │  Arke.QueryManager │   ◄── single front door for CRUD + Query
     └─────────┬──────────┘
               │
       ┌───────┼────────┐
       ▼       ▼        ▼
  ┌────────┐ ┌───────┐ ┌─────────────────┐
  │Boundary│ │Core   │ │Persistence      │
  │Managers│ │ Unit  │ │  (injected fn)  │
  │(ETS)   │ │ Arke  │ │  arke_postgres  │
  │        │ │ Query │ │  or alternative │
  └────────┘ └───────┘ └─────────────────┘
```

- **Core** (`lib/arke/core/`) — pure structs and data. No I/O.
- **Boundary** (`lib/arke/boundary/`) — GenServer-backed state holders over ETS.
- **Managers & pipeline** (`lib/arke/{query,link,struct}_manager.ex`, `validator.ex`) — orchestrate. Read the persistence seam from app env.
- **System macros** (`lib/arke/system.ex`, `lib/arke/group.ex`) — compile-time DSL.
- **Utils** (`lib/arke/utils/`) — datetime parsing, GCP file storage, error generator, xlsx export.

## Scope boundary vs. sibling packages

| Concern | Where it lives |
|---|---|
| Schema definition, validation, CRUD pipeline, query builder, link graph | **arke** (this package) |
| Postgres persistence (Ecto repo, table migrations, SQL translation) | `arke_postgres` |
| Authentication, JWT, permissions | `arke_auth` |
| HTTP routes, REST conventions, controllers | `arke_server` |
| React/Next.js UI components | frontend packages |

If you're working on something here and find yourself reaching for SQL, Phoenix routes, or JWT — you're in the wrong package.
