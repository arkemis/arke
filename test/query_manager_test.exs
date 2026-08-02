defmodule Arke.QueryManagerTest do
  use Arke.Test.RepoCase

  test "CRUD functions" do
    arke_model = ArkeManager.get(:arke, :arke_system)

    # Create
    not_found = ArkeManager.get(:query_create, :test_schema)

    {:ok, unit} =
      QueryManager.create(:test_schema, arke_model,
        id: :query_create,
        label: "Query arke created"
      )

    created_manager = ArkeManager.get(:query_create, :test_schema)

    assert created_manager.id == :query_create
    assert unit.id == :query_create

    assert not_found == nil

    # Delete
    QueryManager.delete(:test_schema, unit)

    assert ArkeManager.get(:query_create, :test_schema) == nil
  end

  defp load_unit(_context) do
    arke_model = ArkeManager.get(:arke, :arke_system)
    %{unit: Unit.load(arke_model, id: :unit_query_test, label: "Unit query test")}
  end

  defp get_query(_context) do
    %{query: QueryManager.query(project: :test_schema, arke: :string)}
  end

  defp create_projects() do
    arke_project = ArkeManager.get(:arke_project, :arke_system)

    Enum.map(["query_project_a", "query_project_b"], fn id ->
      {:ok, unit} =
        QueryManager.create(:arke_system, arke_project, %{
          id: id,
          name: id,
          description: id,
          type: "postgres_schema",
          label: id
        })

      unit
    end)
  end

  defp project_query() do
    QueryManager.query(project: :arke_system) |> QueryManager.where(arke_id__contains: "project")
  end

  describe "query" do
    setup [:load_unit, :get_query]

    test "new" do
      # when is nil (arke)
      query = QueryManager.query(project: :test_schema, arke: nil)
      assert query.arke == nil

      # when is binary (arke)
      query = QueryManager.query(project: :test_schema, arke: "string")
      assert query.arke.id == :string

      # when is atom (arke)
      query = QueryManager.query(project: :test_schema, arke: :string)
      assert query.arke.id == :string

      # when got from ArkeManager
      arke_model = ArkeManager.get(:string, :arke_system)
      query = QueryManager.query(project: :test_schema, arke: arke_model)
      assert query.arke.id == :string
    end

    test "link", %{unit: data} = _context do
      query = QueryManager.query(project: :test_schema, arke: :string)

      # all atoms
      query_link = QueryManager.link(query, data, direction: :child, depth: 5, type: :parameter)

      assert query_link.link.unit.id == :unit_query_test
      assert query_link.link.depth == 5
      assert query_link.link.direction == :child
      assert query_link.link.type == :parameter

      # depth string
      query_link =
        QueryManager.link(query, data, direction: :child, depth: "10", type: :parameter)

      assert query_link.link.unit.id == :unit_query_test
      assert query_link.link.depth == 10
      assert query_link.link.direction == :child
      assert query_link.link.type == :parameter

      # depth invalid
      query_link = QueryManager.link(query, data, direction: :child, depth: nil, type: :parameter)

      assert query_link.link.unit.id == :unit_query_test
      assert query_link.link.depth == 500
      assert query_link.link.direction == :child
      assert query_link.link.type == :parameter

      # direction binary
      query_link =
        QueryManager.link(query, data, direction: "parent", depth: nil, type: :parameter)

      assert query_link.link.unit.id == :unit_query_test
      assert query_link.link.depth == 500
      assert query_link.link.direction == :parent
      assert query_link.link.type == :parameter
    end

    test "get_by" do
      assert QueryManager.get_by(id: :test_schema, project: :arke_system) == nil
    end

    test "filter_by" do
      create_projects()

      assert QueryManager.filter_by(arke_id: :arke_project, project: :arke_system)
             |> Enum.map(& &1.id)
             |> Enum.sort() == [:query_project_a, :query_project_b]

      assert QueryManager.filter_by(arke_id: :arke_project, project: :another_project) == []
    end

    test "and_", %{query: query} = _context do
      assert_raise RuntimeError, "filters must be a list", fn ->
        QueryManager.and_(query, false, "invalid_filters") == "filters must be a list"
      end

      filter = QueryManager.conditions(arke_id__eq: "string")
      new_query = QueryManager.and_(query, false, filter)

      assert is_list(new_query.filters) == true
      assert List.first(new_query.filters).logic == :and
      assert List.first(List.first(new_query.filters).base_filters).operator == :eq
      assert List.first(List.first(new_query.filters).base_filters).negate == false
      assert List.first(List.first(new_query.filters).base_filters).value == "string"
    end

    test "or_", %{query: query} = _context do
      assert_raise RuntimeError, "filters must be a list", fn ->
        QueryManager.or_(query, false, "invalid_filters") == "filters must be a list"
      end

      filter = QueryManager.conditions(arke_id__contains: "string")
      new_query = QueryManager.or_(query, true, filter)

      assert is_list(new_query.filters) == true
      assert List.first(new_query.filters).logic == :or
      assert List.first(new_query.filters).negate == true
      assert List.first(List.first(new_query.filters).base_filters).operator == :contains
      assert List.first(List.first(new_query.filters).base_filters).negate == false
      assert List.first(List.first(new_query.filters).base_filters).value == "string"
    end

    test "condition" do
      cond = QueryManager.condition(:integer, :gte, 14, false)
      assert cond.parameter == :integer
      assert cond.operator == :gte
      assert cond.value == 14
      assert cond.negate == false
    end

    test "conditions" do
      cond = QueryManager.conditions(arke_id__contains: "string", age__gte: 12)
      cond0 = Enum.at(cond, 0)
      cond1 = Enum.at(cond, 1)

      assert length(cond) == 2

      assert cond0.parameter == "age"
      assert cond0.operator == :gte
      assert cond0.value == 12

      assert cond1.parameter == "arke_id"
      assert cond1.operator == :contains
      assert cond1.value == "string"
    end

    test "where", %{query: query} = _context do
      where = QueryManager.where(query, arke_id__contains: "string")
      where_filter = List.first(List.first(where.filters).base_filters)

      assert where_filter.operator == :contains
      assert where_filter.value == "string"
    end

    test "filter/2", %{query: query} = _context do
      parameter = ParameterManager.get(:id, :arke_system)
      filter = Arke.Core.Query.new_filter(parameter, :equal, "name", false)
      new_query = QueryManager.filter(query, filter)
      new_query_filters = List.first(List.first(new_query.filters).base_filters)

      assert new_query_filters.parameter.id == :id
      assert new_query_filters.operator == :equal
      assert new_query_filters.value == "name"
    end

    test "filter/4", %{query: query} = _context do
      new_query = QueryManager.filter(query, :min_length, :gte, 12, true)
      new_query_filters = List.first(List.first(new_query.filters).base_filters)

      assert new_query_filters.parameter.id == :min_length
      assert new_query_filters.operator == :gte
      assert new_query_filters.value == 12
      assert new_query_filters.negate == true
    end

    test "filter/4 (group as string)", %{query: query} = _context do
      new_query = QueryManager.filter(query, "group", :eq, "parameter", true)
      new_query_filters = List.first(List.first(new_query.filters).base_filters)

      assert new_query_filters.parameter.id == :arke_id
      assert new_query_filters.operator == :in
      assert is_list(new_query_filters.value) == true
      assert Enum.any?(new_query_filters.value, fn key -> key == "integer" end) == true
      assert new_query_filters.negate == true
    end

    test "filter/4 (group_id as string)", %{query: query} = _context do
      # group_id as string
      new_query = QueryManager.filter(query, "group_id", :eq, "parameter", true)
      new_query_filters = List.first(List.first(new_query.filters).base_filters)

      assert new_query_filters.parameter.id == :arke_id
      assert new_query_filters.operator == :in
      assert is_list(new_query_filters.value) == true
      assert Enum.any?(new_query_filters.value, fn key -> key == "integer" end) == true
      assert new_query_filters.negate == true
    end

    test "filter/4 (group as atom)", %{query: query} = _context do
      new_query = QueryManager.filter(query, :group, :eq, "parameter", true)
      new_query_filters = List.first(List.first(new_query.filters).base_filters)

      assert new_query_filters.parameter.id == :arke_id
      assert new_query_filters.operator == :in
      assert is_list(new_query_filters.value) == true
      assert Enum.any?(new_query_filters.value, fn key -> key == "integer" end) == true
      assert new_query_filters.negate == true
    end

    test "filter/4 (group_id as atom)", %{query: query} = _context do
      new_query = QueryManager.filter(query, :group_id, :eq, "parameter", true)
      new_query_filters = List.first(List.first(new_query.filters).base_filters)

      assert new_query_filters.parameter.id == :arke_id
      assert new_query_filters.operator == :in
      assert is_list(new_query_filters.value) == true
      assert Enum.any?(new_query_filters.value, fn key -> key == "integer" end) == true
      assert new_query_filters.negate == true
    end

    test "order", %{query: query} = _context do
      # Arke in query nil
      new_query = QueryManager.query(project: :test_schema)
      add_order_query = QueryManager.order(new_query, :name, :asc)
      order = List.first(add_order_query.orders)

      assert order.parameter.id == :name
      assert order.direction == :asc

      parameter = ParameterManager.get(:id, :arke_system)

      add_order_query = QueryManager.order(new_query, parameter, :desc)
      order = List.first(add_order_query.orders)

      assert order.parameter.id == :id
      assert order.direction == :desc

      # Arke got from ArkeManager

      parameter = ParameterManager.get(:min_length, :arke_system)
      add_order_query = QueryManager.order(query, parameter, :asc)
      order = List.first(add_order_query.orders)

      assert order.parameter.id == :min_length
      assert order.direction == :asc

      add_order_query = QueryManager.order(query, "max_length", :desc)
      order = List.first(add_order_query.orders)

      assert order.parameter.id == :max_length
      assert order.direction == :desc

      add_order_query = QueryManager.order(query, :helper_text, :asc)
      order = List.first(add_order_query.orders)

      assert order.parameter.id == :helper_text
      assert order.direction == :asc

      add_order_query = QueryManager.order(query, :not_valid, :asc)
      order = List.first(add_order_query.orders)

      assert order.parameter == nil
      assert order.direction == :asc

      assert_raise ArgumentError, fn -> QueryManager.order(query, "not_existing_atom", :asc) end
    end

    test "offset", %{query: query} = _context do
      query_offset = QueryManager.offset(query, 5)
      assert query_offset.offset == 5
    end

    test "limit", %{query: query} = _context do
      query_limit = QueryManager.limit(query, 5)
      assert query_limit.limit == 5
    end

    test "pagination" do
      create_projects()

      {count, units} = QueryManager.pagination(project_query(), 0, 10)

      assert count == 2
      assert Enum.map(units, & &1.id) |> Enum.sort() == [:query_project_a, :query_project_b]

      {count, units} = QueryManager.pagination(project_query(), 1, 10)

      assert count == 2
      assert length(units) == 1
    end

    test "all" do
      create_projects()

      assert QueryManager.all(project_query()) |> Enum.map(& &1.id) |> Enum.sort() ==
               [:query_project_a, :query_project_b]
    end

    test "one" do
      assert QueryManager.one(project_query()) == nil

      create_projects()

      assert QueryManager.one(project_query()).arke_id == :arke_project
    end

    test "raw" do
      create_projects()

      assert QueryManager.raw(project_query()) |> length() == 2
    end

    test "count" do
      assert QueryManager.count(project_query()) == 0

      create_projects()

      assert QueryManager.count(project_query()) == 2
    end

    test "pseudo_query" do
      query = project_query()

      assert QueryManager.pseudo_query(query).project == :arke_system
      assert QueryManager.pseudo_query(query).filters == query.filters
    end
  end
end
