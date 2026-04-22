# Design — Why It's Shaped This Way

Rationale behind the load-bearing decisions in arke. Useful for:
- **Devs** making sense of unexpected behavior ("it's this way because…")

These are architectural commitments, not implementation details. Changing them would cascade through the whole library.

---

## Why Units are universal

**The choice:** every persisted thing is an `Arke.Core.Unit` — schema definitions (Arkes), field types (Parameters), groupings (Groups), edges (Links), user data (Person, Invoice, whatever), files (`arke_file`) — all share the same struct.

**What this buys:**
- One CRUD pipeline handles everything. `QueryManager.create` can create a user record *or* a new schema definition at runtime, with the same validation, hook, and persistence path.
- Bootstrapping: the schema system is its own first citizen. Arkes are created by loading Units whose `arke_id` is `:arke`. No separate meta-layer.
- Uniform serialization, link handling, validation.

**The cost:**
- Weak type discrimination — you can't tell a `%Unit{arke_id: :person}` from a `%Unit{arke_id: :arke}` at the type level.
- The `data` field is a map of arbitrary shape; static analysis (Dialyzer) gives little help.
- New contributors can't answer "what fields does a Person have?" from the struct — they have to know to query `ArkeManager`.

---

## Why managers + ETS instead of pure DB

**The choice:** ArkeManager, ParameterManager, GroupManager hold schema state in named ETS tables at runtime. The DB is the source of truth for *persistence*; ETS is the source of truth for *validation, hooks, and query construction during a request*.

**What this buys:**
- Schema reads are O(1), no DB hit per request. Every `QueryManager.create` looks up the Arke + its Parameters dozens of times (validator iterates all params, encoder iterates, link handler iterates) — hitting the DB for each would be crushing.
- GenServer ownership gives a natural place to centralize mutations and fan them out to cluster peers via `:rpc.multicall`.
- Clean separation: "what the schema is right now" lives in ETS; "what it was last persisted as" lives in the DB.

**The cost:**
- Two sources of truth that can diverge. Seeding (`mix arke.seed_project`) is what keeps them aligned on boot.
- Multi-node sync is best-effort, not transactional — see [gotchas.md](gotchas.md#libcluster-multi-node-manager-sync).
- `ets:lookup` with `read_concurrency: true` is fast but the GenServer serializes writes; high schema-mutation throughput is a bottleneck (not expected in practice — schema changes are rare).
- State lost on GenServer crash unless repopulated from DB.

---

## Why persistence is function-injected, not a behaviour

**The choice:** the DB plumbing is passed via `config :arke, persistence: %{arke_postgres: %{create: &Mod.fn/2, …}}`, read at module-load time into a `@persistence` attribute.

**What this buys:**
- **No compile-time dependency on any persistence package.** `arke` can compile and run in isolation (it's what the test suite does — see `test.exs` with a pure-Elixir `Arke.Support.PersistenceFn`).
- A future backend (DuckDB, FoundationDB, in-memory, anything) plugs in by exposing the same function signatures. No `@behaviour ArkePersistence` to implement.
- Sibling packages (`arke_auth`, `arke_server`) can test against a mock persistence map without pulling `arke_postgres`.

**The cost:**
- The function map shape is implicit — there's no compile-time check that a backend provides all required functions.
- The top-level key is hardcoded as `:arke_postgres` even for alternative backends, which is confusing (see [recipes.md](recipes.md#use-a-custom-persistence-backend)).
- Errors manifest at runtime (`** (ArgumentError) nil is not a list`) rather than as a missing-callback warning.

**Compared to `@behaviour`:** a behaviour would give better compile-time guarantees but couple the core to a named protocol module. The function-map choice optimizes for *swappability over safety* — an intentional tradeoff.

**When to revisit:** if the persistence API stabilizes and the set of backends grows, promoting it to a proper behaviour with `@callback` would be low-cost and add compile-time checks. A small step, big payoff.

---

## Why `arke_link` is itself an Arke

**The choice:** edges in the graph aren't a separate data type. They're Units of a special Arke (`:arke_link`) with fields `{parent_id, child_id, type, metadata}`.

**What this buys:**
- Links participate in the same CRUD pipeline — you get validation, hooks, and encoding for free.
- Querying links uses the same `%Query{}` struct and operators as querying data. No separate graph-query API to maintain.
- Links can carry arbitrary metadata (weights, timestamps, relationship sub-types) via the `metadata` field, just like any Unit.

**The cost:**
- Extra indirection at the storage layer — `arke_postgres` stores links in an `arke_unit` / `arke_link` table, not as foreign-key columns. Joining across a link requires a self-join, not a natural FK join.
- Link-heavy queries can be expensive at scale; the `depth: 500` default for link filters is generous.
- `:link` parameters add implicit write amplification — see [gotchas.md](gotchas.md#link-parameters-have-side-effects).

**Compared to foreign keys:** FKs are faster and give DB-level integrity. The Unit-based model trades that for uniformity and the ability to define new relationship types without migrations.

**When to revisit:** if a specific link type sees high volume and query hotness, denormalizing it to a FK column (marked `persistence: "table_column"`) is already possible today. The whole-sale abandonment of arke_link would be a much bigger architectural change.

---

## Why the `:arke_system` fallback

**The choice:** `Manager.get(id, project)` transparently falls back to `{id, :arke_system}` if the requested project doesn't have the Unit (`unit_manager.ex:67`).

**What this buys:**
- System Arkes (`:arke`, `:arke_link`, Parameter types, Groups) are defined once and inherited by every project without duplication.
- Each tenant project stays lean — only holds its own custom Arkes and data.
- Override pattern: creating a same-named Arke in a specific project silently supersedes the system one for that project only.

**The cost:**
- Lookups have implicit inheritance that isn't obvious from the call site.
- Debugging which Arke is actually resolving requires checking both the target project and `:arke_system`.
- There's no way to *explicitly prevent* the fallback — you can't ask for "only this project, fail if missing."

**Compared to explicit inheritance:** an alternative would be declaring `inherits_from: :arke_system` on each project's manager. The current fallback is implicit-by-default, which is ergonomically nice but opaque.

**When to revisit:** if a project needs to genuinely not see a system Arke (security, overrides that should fail-fast), an explicit "no fallback" mode would be a small addition.

---

## Why compile-time macros + runtime DB coexist

**The choice:** Arkes can be declared two ways — `use Arke.System` with `arke do … end` (compile-time) *and* loaded from DB on boot. Both land in the same ETS tables.

**What this buys:**
- Framework-internal Arkes (the bootstrap `:arke`, `:arke_link`, Parameter types) are compile-time — they must exist before the DB does.
- Application-defined Arkes can be either: compile-time for version-controlled models, DB-loaded for runtime-configurable tenants.
- Tooling like `mix arke.seed_project` reads compile-time Arkes first, then populates the DB — they're the canonical shape.

**The cost:**
- Two ways to define the same thing. Hooks fire only for the module-backed version (see [gotchas.md](gotchas.md#compile-time-arke-attrs-vs-runtime-db-arkes)).
- The interplay is subtle: DB-loaded Arkes with the same ID override compile-time ones, but without the module's hooks.
- Conceptually harder to onboard — new devs have to understand both paths.

**When to revisit:** if tenants consistently want custom hook logic on runtime-defined Arkes, the current model can't provide it without code deploys. A plugin/eval sandbox would be a major addition.

---

## Why xlsx import is in the core

**The choice:** `use Arke.System` injects an `import/1` function that parses xlsx uploads and bulk-inserts. Implemented via `xlsxir`.

**What this buys:**
- Every Arke gets "import from spreadsheet" for free — a very common low-code requirement.
- Overridable at multiple points (`load_units`, `before_unit_import`, `on_unit_import`) for custom validation or post-processing.

**The cost:**
- A hard dep on `xlsxir` (xlsx-specific) and a soft dep on `ArkeAuth.Guardian.get_member/1` — the core knows about auth.
- Bulk insert bypasses `on_create` hooks (uses `insert_all`), which is a footgun for any cross-cutting logic relying on them.
- Locks the import format to xlsx; CSV / JSON would need a parallel path.

**When to revisit:** if import becomes a pluggable concern, this is a natural thing to extract into `arke_importer` or similar. The `Arke.System.import/1` implementation is self-contained enough to lift cleanly.

---

## Decisions explicitly left flexible

- **File storage backend** — configurable via `:file_storage_module`; GCP is the default but not special.
- **Persistence backend** — function-injected, as discussed above.
- **Project creation / deletion** — delegated to persistence functions; core has no opinion on tenancy model (row-level vs schema-level vs database-level).

---

## Decisions that are non-negotiable (by current design)

- **Unit as universal row shape.** Removing this would mean redesigning the manager, validator, and query layers.
- **ETS-backed managers.** Removing this would mean hitting the DB on every schema lookup.
- **`arke_link` as a Unit.** Removing this would mean a parallel link storage model.

If a roadmap conversation touches any of these three, treat it as foundational work, not incremental.
