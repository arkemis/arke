# Links

- Prefer `:link` parameters for domain relationships — setting them
  creates/deletes the underlying `arke_link` rows automatically:

  ```elixir
  # in the registry JSON, a parameter of type "link" with metadata:
  # {"arke_or_group_id": "person", "connection_type": "invoice_customer",
  #  "direction": "parent", "multiple": false}

  {:ok, inv} = QueryManager.create(:p, invoice_arke, number: "INV-001", customer: "ada")
  {:ok, _}   = QueryManager.update(inv, customer: "grace")  # old link deleted, new created
  ```

  `arke_or_group_id` must be an ARKE id — a Group id silently no-ops.
- Link sync is strict and transactional: a link value pointing at a unit that
  does not exist fails the WHOLE write with `{:error, _}` and rolls it back
  (definition units — arkes, groups, parameter types — keep best-effort sync).
  Create the target unit first.
- Two link parameters on the same unit pointing at the same target with the
  same `connection_type` collapse into ONE `arke_link` row (the key is
  `(type, parent_id, child_id)`); the second write surfaces
  "link already exists". Give such parameters distinct connection types.
- `direction` semantics are easy to invert: `direction: "child"` means the
  unit being created is the PARENT and the referenced id the child;
  `direction: "parent"` means the referenced id is the parent.
- `multiple: true` link updates diff old vs new lists one node at a time (no
  bulk); the first failing node fails the write and rolls everything back.
  For bulk link changes use `Arke.LinkManager` directly.
- Direct edge management:

  ```elixir
  Arke.LinkManager.add_node(:p, parent_unit, child_unit, "friendship", %{since: "2024"})
  Arke.LinkManager.delete_node(:p, "parent_id", "child_id", "friendship", %{})
  ```

  When using string ids, pass ALL five arguments — the default values live on
  the `%Unit{}` clauses, so a 4-argument call with strings raises.
- A duplicate `add_node` returns
  `{:error, [%{context: "link", message: "link already exists: ..."}]}` (the
  message names the parent/child/type) — an error tuple, not a raise.
- Graph traversal from a query:

  ```elixir
  query(project: :p, arke: :person)
  |> link(ada_unit, direction: :child, depth: 3, type: "friendship")
  |> all()
  ```

- Encode units for an API with `Arke.StructManager.encode/2`
  (`type: :json`, plus `load_links: true`, `load_values: true`,
  `load_files: true` as needed). Lists must be single-project — mixed-project
  lists read the project from the first unit only.
