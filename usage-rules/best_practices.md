# Best practices

- Don't pass an atom as the `arke` argument to `QueryManager.create/3` — get
  the `%Unit{}` from `ArkeManager.get/2` first.
- Don't set `config :arke, :persistence` at runtime — it is captured at
  compile time.
- Don't assume `use Arke.System` alone registers an Arke — registration comes
  from registry JSON / DB via seeding or boot.
- Don't use `group :x` inside `arke do ... end` and expect group hooks —
  membership lives in `group.json` or group-type links.
- Don't reach for SQL, Ecto, Plug or JWT inside this package's abstractions —
  wrong layer; that's `arke_postgres`/`arke_server`/`arke_auth`.
- Don't compare `data->>'field'` in raw SQL — the persisted shape is
  `data->'field'->>'value'`.
- Don't rely on `Manager.get_all/1` returning Units — it returns
  `{unit_id, project}` tuples.
- Don't call legacy/dead code: `Unit.get_data/1`, `Unit.data_as_klist/1`
  (they crash on real Units).
- Don't create multi-tenant data without seeding the project first — most
  `String.to_existing_atom` crashes and `nil` manager lookups trace back to
  an unseeded project or unloaded module.
- Create projects through the `:arke_project` Arke so the persistence
  lifecycle runs:

  ```elixir
  project_arke = Arke.Boundary.ArkeManager.get(:arke_project, :arke_system)
  {:ok, _} = Arke.QueryManager.create(:arke_system, project_arke,
    id: "client_acme", label: "ACME")
  # then: mix arke.seed_project --project client_acme
  ```

- Unique + nil values are not checked (`unique: true` with a `nil` value
  passes validation) — enforce NOT NULL semantics with `required: true`.
- Cluster replication of manager writes is best-effort: no rollback, no
  ordering guarantee, late-joining nodes stay stale until reseeded/rebooted.
- Version notes: `update_key/2` and nested logic operators require ≥ 0.6.0;
  0.5.0 moved file caching to `Arke.Boundary.FileManager` (breaking).
