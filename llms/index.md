# Arke — LLM Knowledge Pack

Arke is the **core of the Arke ecosystem** — an Elixir package that lets you declare domain models ("Arkes") whose schema is dynamic (definable at compile time *or* loaded from a database at boot), multi-tenant (every row keyed by project), and pluggable on persistence. Everything — user records, schema definitions, links between records — is stored as a `Unit`, a universal row shape.

This library is the substrate. Sibling packages (`arke_postgres`, `arke_auth`, `arke_server`) plug into it through a persistence-function seam.

**Current version:** 0.6.0 · **License:** Apache-2.0 · **Source:** <https://github.com/arkemis/arke> · **Hex:** <https://hex.pm/packages/arke>

## Read order

Start with `overview.md`. After that the files are independent — jump to whichever matches the task.

| File | When to read |
|---|---|
| [overview.md](overview.md) | **Always read first.** Mental model: Unit / Arke / Parameter / Group / Link / Project, runtime architecture, persistence seam. |
| [reference.md](reference.md) | Looking up a specific module or function signature. |
| [recipes.md](recipes.md) | Common tasks: defining an Arke, CRUD, queries with filters/links, encoding, lifecycle hooks. |
| [gotchas.md](gotchas.md) | Something behaves unexpectedly. Sharp edges and non-obvious defaults. |
| [design.md](design.md) | Questions about *why* something is shaped this way — useful when debugging or evaluating roadmap changes. |

## What Arke is not

- Not an ORM. Ecto schemas are not generated. The "schema" is runtime state in ETS.
- Not a standalone persistence layer. Core Arke does no I/O; `arke_postgres` (or an alternative) must be configured.
- Not a Phoenix replacement. `arke_server` provides HTTP layer; this package is framework-agnostic.

## Minimum you need to use it

```elixir
# mix.exs
{:arke, "~> 0.6.0"},
{:arke_postgres, "~> x.y.z"}  # or equivalent persistence plug

# config/config.exs
config :arke,
  persistence: %{
    arke_postgres: %{
      create: &ArkePostgres.create/2,
      update: &ArkePostgres.update/2,
      delete: &ArkePostgres.delete/2,
      execute_query: &ArkePostgres.execute_query/2,
      create_project: &ArkePostgres.create_project/1,
      delete_project: &ArkePostgres.delete_project/1
    }
  }
```

Without the `persistence` config, all CRUD through `Arke.QueryManager` will crash. See [overview.md](overview.md#runtime-architecture) for why.
