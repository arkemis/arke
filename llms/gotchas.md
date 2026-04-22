# Gotchas — Sharp Edges

Operational surprises you'll hit when working with arke. These are distinct from design rationale (see [design.md](design.md) for the "why"); this file is the "what trips people up."

---

## The `:arke_system` fallback

`Manager.get/2` looks up `{unit_id, requested_project}` first, then `{unit_id, :arke_system}` if the first lookup misses (see `unit_manager.ex:67`).

**Why it exists:** system Arkes (`:arke`, `:arke_link`, `:arke_project`, the Parameter types) live only in `:arke_system`. Every real project needs to see them, so the lookup falls through.

**Why it trips people up:**
- Silent coupling — a project-specific Arke with the same ID as a system one will mask the system one *only in that project*.
- If you've meant to create a project-scoped override and forgot a step, the system Arke is used transparently and your override never ran.
- Bugs here are invisible from logs; you get "correct-ish" behavior from the wrong Arke.

**What to do:** when debugging missing/wrong behavior on a specific project, always check `ArkeManager.get(arke_id, :arke_system)` alongside `ArkeManager.get(arke_id, your_project)` to see which one actually resolved.

---

## String IDs vs atom IDs — `String.to_existing_atom` traps

Arke converts string IDs to atoms all over the place (managers, validators, link manager, query manager). `String.to_existing_atom/1` is used intentionally — it refuses to create new atoms at runtime. If the atom doesn't exist yet (e.g. because its Arke hasn't been loaded), you get an `ArgumentError` rescued to `nil`.

**Symptom:** `Manager.get("some_id", project)` returns `nil` even though you're sure the Unit exists.

**Causes:**
- Arke module wasn't loaded (not in deps, or boot order wrong).
- Registry JSON wasn't seeded (`mix arke.seed_project` not run for this project).
- Typo in the ID — the atom literally never existed.

**What to do:** ensure compile-time Arke modules are in deps and the project has been seeded. Use `Code.ensure_loaded?(MyApp.Person)` to confirm module availability.

---

## `:link` parameters have side effects

Setting a `:link` parameter value on `QueryManager.update/2` **implicitly creates or deletes `arke_link` Units** (`query_manager.ex:755` `handle_link_parameters/2`).

```elixir
QueryManager.update(invoice, customer: "bob")
# If invoice.customer was "alice", this:
#   1. Deletes the arke_link {parent: invoice, child: alice, type: "invoice_customer"}
#   2. Creates a new arke_link {parent: invoice, child: bob, type: "invoice_customer"}
```

**Surprises:**
- For `multiple: true` parameters, the old and new lists are diffed and changes applied node-by-node (no bulk op). Large list changes are many individual writes.
- The link's `direction` metadata flips parent/child in the graph. `"child"` vs `"parent"` affects which side of the `arke_link` the Unit goes on.
- If the child ID doesn't exist, the link creation silently fails — no error bubbled up to the caller.

**What to do:** for bulk link changes, consider using `LinkManager.add_node/5` / `delete_node/5` directly. Be explicit about `direction` in the parameter metadata.

---

## Persistence must be configured — or everything crashes

`@persistence = Application.get_env(:arke, :persistence)` is read at **module load time** in several places (`query_manager.ex:49`, `validator.ex`, `core/project.ex:23`). If the config isn't set *before* these modules compile, `@persistence` is `nil` and every CRUD call crashes trying to call `nil[:arke_postgres][:create]`.

**Symptom:** `** (ArgumentError) nil is not a list` or `** (FunctionClauseError) no function clause matching` from inside `QueryManager`.

**What to do:**
- Set `config :arke, persistence: %{...}` in `config/config.exs`, not at runtime.
- Never re-compile `Arke.QueryManager` without the config in place.
- If using releases, verify env is set before the VM starts (the attr is captured at compile, not at release runtime).

---

## Data values are wrapped `%{"value" => ..., "datetime" => ...}`

When a Unit is persisted, parameter values are wrapped with a per-field timestamp (`unit.ex:264` `update_encoded_unit_data`):

```elixir
# In DB:
%{"name" => %{"value" => "Ada", "datetime" => "2026-01-15T…"}}

# In memory (after Unit.load):
%Unit{data: %{name: "Ada"}}  # unwrapped
```

**Where this leaks:**
- Reading `unit.data[:name]` in memory gets the unwrapped value.
- But if you query raw DB data (e.g. through `QueryManager.raw`), you see the wrapped shape.
- `Unit.get_value/2` handles both shapes defensively; prefer it over direct map access when you might receive either.

**What to do:** use `Unit.get_value(unit, :name)` when in doubt. Don't build DB queries that compare `data->>'name' = 'Ada'` — the actual key is `data->'name'->>'value'`.

---

## Base parameters are auto-injected

Every Arke gets these five parameters prepended for free (in `system.ex:313` `get_base_arke_parameters/1` and `arke.ex:149` `base_parameters/1`):

- `:id` (`:string`, `required: true`, `persistence: "table_column"`)
- `:arke_id` (`:string`, `persistence: "table_column"`)
- `:metadata` (`:dict`, `persistence: "table_column"`)
- `:inserted_at` (`:datetime`, `persistence: "table_column"`)
- `:updated_at` (`:datetime`, `persistence: "table_column"`)

**Surprises:**
- Declaring your own `:id` parameter silently merges with the auto-injected one.
- Groups don't get these auto-injected — only Arkes of `type: "arke"`.
- The `:id` is `required: true`; if you `QueryManager.create/3` without providing one, `Unit.as_args/2` falls back to `UUID.uuid1()`.

---

## `persistence: "table_column"` vs `"arke_parameter"`

Parameters have a `persistence` metadata field:
- `"table_column"` — stored as a direct column (the five base parameters, plus anything flagged via metadata).
- `"arke_parameter"` — **default.** Stored inside a JSONB `data` column that arke_postgres maintains.

Validator filters to only `"arke_parameter"` ones for type checks (`validator.ex:54`) — so `"table_column"` values skip validation. If you mark something `"table_column"`, it had better already match the type (or your DB schema won't accept it).

---

## Libcluster multi-node manager sync

Managers propagate create/update/add_link/remove_link via `:rpc.multicall(Node.list(), …)` (`unit_manager.ex:241`). This is best-effort:
- Failed RPCs log a warning but don't rollback the local write.
- If a node joins the cluster *after* some writes, its ETS is stale until re-seeded.
- No guarantee of ordering across nodes under contention.

**What to do:** for single-node deploys, ignore. For multi-node, treat manager state as eventually consistent and re-seed on node join if divergence is a problem.

---

## `arke_or_group_id` ambiguity

A `:link` parameter's `arke_or_group_id` can point to either an Arke or a Group. `QueryManager.handle_create_on_link_parameters_unit/5` calls `ArkeManager.get/2` on it (`query_manager.ex:171`) — so if you point at a Group by mistake, you get a silent `nil` and your nested-create is skipped.

**What to do:** stick to pointing at Arkes for `:link` parameters until Group-target support is explicitly documented.

---

## `ArkeError` on missing arke in queries

`QueryManager.get_arke/2` raises `Arke.Errors.ArkeError` when `arke:` refers to an unknown ID (`query_manager.ex:372`). This is one of the few places arke raises instead of returning `{:error, _}`.

```elixir
QueryManager.query(project: :p, arke: :does_not_exist)
# ** (Arke.Errors.ArkeError) context: query, message: arke not found
```

Rescue explicitly if you need a graceful fallback:
```elixir
try do
  QueryManager.filter_by(arke: :maybe_exists, project: :p)
rescue
  Arke.Errors.ArkeError -> []
end
```

---

## `get_parameter` fails silently on missing parameters

`ArkeManager.get_parameter/3` returns `nil` both when the Arke doesn't exist *and* when the parameter isn't attached to the Arke. You can't tell the two cases apart without a second lookup.

**What to do:** when building a query, check `ArkeManager.get(arke_id, project)` separately if you need to distinguish "no arke" from "arke without that parameter."

---

## Compile-time Arke attrs vs runtime DB Arkes

An Arke defined via `use Arke.System` and an Arke loaded from the DB coexist. If both have the same ID, the DB version wins on the second pass of `handle_manager/4` during `mix arke.seed_project`.

**What to do:** don't rely on the compile-time module's lifecycle hooks being called unless the Arke's `__module__` field matches. If you need hooks to fire, either (a) have the DB Arke's `metadata` reference the module, or (b) don't seed that Arke to the DB.
