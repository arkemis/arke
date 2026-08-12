# Core concepts

- **Unit** (`Arke.Core.Unit`): the universal struct —
  `id, data, arke_id, link, metadata, inserted_at, updated_at, __module__,
  runtime_data`. `id` is an atom; `metadata.project` carries tenancy;
  `__module__` carries behavior (lifecycle hooks); `runtime_data` is
  transient and never persisted.
- **Arke**: a Unit with `arke_id: :arke` whose `data.parameters` lists the
  attached parameters. Instances are Units whose `arke_id` equals the Arke's
  id.
- **Parameter**: also a Unit; its `arke_id` is the type (`:string`,
  `:integer`, `:float`, `:boolean`, `:date`, `:time`, `:datetime`, `:dict`,
  `:list`, `:binary`, `:link`, `:dynamic`). Parameters are global Units in
  `ParameterManager`; the per-Arke `metadata` overrides are merged over the
  global definition at lookup time — that is how one `:label` parameter can
  be `required: true` on one Arke and optional on another.
- **Group**: a tag over Arkes with an `arke_list`; its hooks (same DSL slots
  as arkes) fire for every Unit of every member Arke.
- **Link**: a Unit with `arke_id: :arke_link` (`parent_id`, `child_id`,
  `type`, `metadata`). Two link types are magic and maintain ETS state:
  `type: "parameter"` (attaches a Parameter to an Arke) and `type: "group"`
  (adds an Arke to a Group).
- **Project**: the tenant atom. Manager ETS keys are `{unit_id, project}`;
  `:arke_system` is the shared project and the implicit fallback for every
  manager lookup miss. A project-scoped Arke with the same id silently masks
  the system one — you cannot ask for "this project only".
- **Managers** (`Arke.Boundary.ArkeManager` / `ParameterManager` /
  `GroupManager` / `FileManager`): GenServers owning public ETS tables. Reads
  hit ETS directly; writes go through the GenServer and are best-effort
  replicated to other nodes (`:rpc.multicall` — failures only log, no
  rollback).
- `Manager.get("id", project)` returns `nil` both for "not found" AND for
  "atom never existed" (module not loaded / project not seeded) — a `nil`
  here often means a seeding problem, not missing data.
- `Manager.get_all/1` returns `{unit_id, project}` tuples, NOT Units.
- **Persisted value wrapper**: on disk every value is
  `%{"value" => v, "datetime" => ts}`; in memory it is unwrapped. Read values
  with `Arke.Core.Unit.get_value/2`; in raw SQL address
  `data->'field'->>'value'`.
- Five base parameters are auto-injected into every `type: "arke"` Arke:
  `id`, `arke_id`, `metadata`, `inserted_at`, `updated_at` (all
  `persistence: "table_column"`). Parameters with
  `persistence: "table_column"` are NOT validated by `Arke.Validator` — only
  `"arke_parameter"` ones are.
- Missing `id` on create falls back to a generated UUID (as a string id).
- Errors are `{:error, [%{context: "...", message: "..."}]}` with **string**
  context (`Arke.Utils.ErrorGenerator`). The one raised exception is
  `Arke.Errors.ArkeError` (e.g. unknown `arke:` in a query).
