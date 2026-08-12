# CRUD and querying

- All CRUD goes through `Arke.QueryManager`. The `arke` argument of
  `create/3` must be a `%Unit{}` from `ArkeManager.get/2`, never a bare atom:

  ```elixir
  alias Arke.QueryManager
  alias Arke.Boundary.ArkeManager

  arke = ArkeManager.get(:person, :my_project)          # %Unit{}, NOT :person
  {:ok, unit} = QueryManager.create(:my_project, arke, name: "Ada", email: "ada@x.io")

  unit   = QueryManager.get_by(id: "ada", project: :my_project)          # %Unit{} | nil
  people = QueryManager.filter_by(arke_id: "person", project: :my_project, role: "admin")

  {:ok, updated} = QueryManager.update(unit, age: 37)
  {:ok, nil}     = QueryManager.delete(:my_project, unit)
  ```

- `update/2` takes the unit first (project/arke come from its metadata).
  `update_key/2` is the surgical JSONB path — it still runs the FULL
  validation + hook pipeline, only the persistence call differs.
- In `get_by`/`filter_by`, `arke:` and `arke_id:` are NOT interchangeable:
  `arke:` scopes the query to that Arke (raises `ArkeError` if unknown,
  resolves parameters against it); `arke_id:` is just a column filter with
  global parameter resolution.
- Build queries with the pipeline DSL:

  ```elixir
  import Arke.QueryManager

  query(project: :my_project, arke: :person)
  |> where(name__icontains: "ada", age__gte: 18)
  |> order(:inserted_at, :desc)
  |> limit(20)
  |> all()
  ```

  Operators: `eq` (default), `contains`, `icontains`, `startswith`,
  `istartswith`, `endswith`, `iendswith`, `lt`, `lte`, `gt`, `gte`, `in`,
  `isnull`. Nested paths put the dot before the `__` suffix:
  `where(:"customer.name__eq" => "Ada")`.
- Executors: `all/1`, `one/1`, `count/1`, `raw/1` (SQL + params),
  `pseudo_query/1` (Ecto query), `pagination/3` (`{count, units}`).
- Every single write already runs in its own transaction (hooks included).
  Wrap MULTI-write flows in `QueryManager.transaction/3` — returning
  `{:error, reason}` rolls back every write; never raise to abort:

  ```elixir
  QueryManager.transaction(:my_project, fn ->
    with {:ok, a} <- QueryManager.create(:my_project, arke, args),
         {:ok, b} <- QueryManager.update(unit, args),
         do: {:ok, {a, b}}
  end, timeout: 600_000)
  ```

  Nested `QueryManager` writes join the enclosing transaction and their
  `after_commit` hooks defer to the outermost commit.
- For read-modify-write flows (balances, counters, caps) take a row lock with
  `lock: true` on `get_by`/`filter_by` (`SELECT ... FOR UPDATE`). It raises
  `ArgumentError` outside a transaction.
- Boolean composition: `conditions/1` output is UNRESOLVED and must go
  through `and_/3` / `or_/3` (which also accept nested filters); never pass
  it to `filter/2` directly:

  ```elixir
  q = query(project: :p, arke: :person)
  q
  |> and_(false, conditions(role__eq: "admin", age__gte: 40))
  |> or_(false, conditions(role__eq: "guest"))
  |> all()
  ```

- `where(q, group__eq: "my_group")` (or the `group`/`group_id` filter keys)
  expands to `arke_id IN <group's arke_list>` — the supported way to query a
  whole group.
- `limit/2` and `offset/2` return `nil` (not the query) for non-integer
  input — silently poisoning the pipeline. Only pass integers/binaries.
- `pagination/3` strips orders for its count query; the units query keeps
  them.
