# Rules for working with Arke

## Understanding Arke

Arke is the core of the Arke framework: a metadata-driven, multi-tenant entity
framework for Elixir where domain models ("Arkes") are runtime data rather than
compile-time Ecto schemas. Every persisted thing — a record, a schema
definition, a field type, a group, a graph edge — is an `Arke.Core.Unit` with
the same struct shape, keyed by a project (tenant). Schemas are declared with
the `Arke.System` macro DSL and/or JSON registry files, live in ETS behind
GenServer managers, and all CRUD flows through `Arke.QueryManager`, which runs
a validation + lifecycle-hook pipeline and delegates I/O to an injected
persistence layer (usually `arke_postgres`) — core Arke performs no I/O itself.

Do not assume Ecto, ActiveRecord or JSON-schema conventions apply: read the
topic rules in `usage-rules/` before using a feature. Sibling packages plug
in: `arke_postgres` (persistence), `arke_auth` (identity), `arke_server`
(HTTP API).
