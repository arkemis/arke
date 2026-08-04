defmodule Arke.Core.QueryTest do
  use Arke.Test.RepoCase

  defp get_query(_context), do: %{query: Query.new(nil, :test_schema)}

  describe "Query" do
    setup [:get_query]

    test "new" do
      query = Query.new(nil, :test_schema)
      assert query.arke == nil
      assert query.project == :test_schema
    end

    test "add_link_filter", %{query: query} = _context do
      arke_model = ArkeManager.get(:arke, :arke_system)
      unit = Unit.load(arke_model, id: :unit_query_test, label: "Unit query test")
      link_filter = Query.add_link_filter(query, unit, 10, :child, "parameter")

      assert link_filter.link.depth == 10
      assert link_filter.link.unit.id == :unit_query_test
      assert link_filter.link.direction == :child
      assert link_filter.link.type == "parameter"
    end

    test "add_filter", %{query: query} = _context do
      # Filter struct
      parameter = ParameterManager.get(:default_string, :arke_system)
      filter = Query.new_filter(parameter, :eq, "name", false)

      struct_filter = Query.add_filter(query, filter)

      assert is_list(struct_filter.filters) == true

      assert List.first(List.first(struct_filter.filters).base_filters).parameter.id ==
               :default_string
    end

    # SHOULD BE THE SAME AS add_filter/2
    test "add_filter/4", %{query: query} = _context do
      # Filter struct
      parameter = ParameterManager.get(:default_string, :arke_system)

      base_filter = Query.new_base_filter(parameter, :contains, "test", false)

      filter = Query.add_filter(query, :or, false, [base_filter])
      struct_filter = Query.add_filter(query, filter)

      query_filter = List.first(struct_filter.filters).filters

      assert is_list(struct_filter.filters) == true
      assert List.first(List.first(query_filter).base_filters).parameter.id == :default_string
    end

    # SHOULD BE THE SAME AS add_filter/2
    test "add_filter/5", %{query: query} = _context do
      # Filter struct

      filter = Query.add_filter(query, :min_length, :contains, "test", true)

      assert is_list(filter.filters) == true
      assert List.first(List.first(filter.filters).base_filters).parameter == :min_length
    end

    # TODO: new_base_filter should accept only parameter struct and raise an error if an atom is given
    test "new_filter/3" do
      filter =
        Query.new_filter(
          :or,
          true,
          Query.new_base_filter(:default_string, :contains, "test", false)
        )

      assert filter.__struct__ == Arke.Core.Query.Filter
      assert filter.logic == :or
      assert List.first(filter.base_filters).parameter == :default_string
    end

    test "new_filter/4" do
      filter = Query.new_filter(:default_integer, :gte, 12, false)
      assert filter.__struct__ == Arke.Core.Query.Filter
      assert filter.logic == :and
      assert List.first(filter.base_filters).operator == :gte
    end

    test "add_order", %{query: query} = _context do
      # SHOULD WORK ALSO WITH ATOMS

      parameter = ParameterManager.get(:default_string, :arke_system)
      order = Query.add_order(query, parameter, :parent)

      assert List.first(order.orders).__struct__ == Arke.Core.Query.Order
      assert List.first(order.orders).direction == :parent
      assert List.first(order.orders).parameter.id == :default_string
    end

    test "set_offset", %{query: query} = _context do
      # set_offset/2 when is_nil(nil)
      query_offset = Query.set_offset(query, nil)

      assert query_offset.offset == nil
      # set_offset/2 when is_binary(offset)
      query_offset = Query.set_offset(query, "5")

      assert query_offset.offset == 5

      # set_offset/2 when is_integer(offset)
      query_offset = Query.set_offset(query, 2)

      assert query_offset.offset == 2

      # set_offset/2 when offset is not valid
      query_offset = Query.set_offset(query, 2.5)

      assert query_offset == nil
      query_offset = Query.set_offset(query, :not_valid)

      assert query_offset == nil
    end

    test "set_limit", %{query: query} = __context do
      # set_limit/2 when is_nil(nil)
      query_limit = Query.set_limit(query, nil)

      assert query_limit.limit == nil
      # set_limit/2 when is_binary(offset)
      query_limit = Query.set_limit(query, "5")

      assert query_limit.limit == 5

      # set_limit/2 when is_integer(offset)
      query_limit = Query.set_limit(query, 2)

      assert query_limit.limit == 2

      # set_limit/2 when offset is not valid
      query_limit = Query.set_limit(query, 2.5)

      assert query_limit == nil
      query_limit = Query.set_limit(query, :not_valid)

      assert query_limit == nil
    end
  end

  describe "BaseFilter value casting" do
    defp filter_value(parameter_id, value) do
      parameter = ParameterManager.get(parameter_id, :arke_system)
      Query.new_base_filter(parameter, :eq, value, false, []).value
    end

    test "casts strings to the parameter type" do
      assert filter_value(:default_integer, "4") == 4
      assert filter_value(:default_float, "6.12") == 6.12
      assert filter_value(:default_boolean, "true") == true
      assert filter_value(:default_boolean, "false") == false
    end

    test "accepts an integer literal for a float parameter" do
      assert filter_value(:default_float, "20") == 20.0
    end

    test "leaves already typed values alone" do
      assert filter_value(:default_integer, 4) == 4
      assert filter_value(:default_float, 6.12) == 6.12
      assert filter_value(:default_boolean, true) == true
      assert filter_value(:name, "a string") == "a string"
    end

    test "casts every element of a list" do
      assert filter_value(:default_integer, ["3", "10"]) == [3, 10]
      assert filter_value(:default_float, ["3", "10.5"]) == [3.0, 10.5]
      assert filter_value(:name, ["a", "b"]) == ["a", "b"]
    end

    test "casts temporal parameters" do
      assert filter_value(:default_date, "2026-08-02") == ~D[2026-08-02]
      assert filter_value(:default_time, "09:55:13") == ~T[09:55:13]
      assert %DateTime{} = filter_value(:default_datetime, "2026-08-02T09:55:13Z")
    end

    test "casts datetimes to an exact UTC value" do
      assert filter_value(:default_datetime, "2026-08-02T09:55:13Z") ==
               ~U[2026-08-02 09:55:13Z]
    end

    test "casts a zone-less datetime string as UTC" do
      assert filter_value(:default_datetime, "2026-08-02T09:55:13") ==
               ~U[2026-08-02 09:55:13Z]
    end

    test "casts a space-separated datetime string" do
      assert filter_value(:default_datetime, "2026-08-02 09:55:13Z") ==
               ~U[2026-08-02 09:55:13Z]
    end

    test "normalises a non-UTC offset when casting" do
      assert filter_value(:default_datetime, "2026-08-02T09:55:13+02:00") ==
               ~U[2026-08-02 07:55:13Z]
    end

    test "passes already typed temporal values through" do
      assert filter_value(:default_date, ~D[2026-08-02]) == ~D[2026-08-02]
      assert filter_value(:default_time, ~T[09:55:13]) == ~T[09:55:13]
      assert filter_value(:default_datetime, ~U[2026-08-02 09:55:13Z]) == ~U[2026-08-02 09:55:13Z]
    end

    test "raises on temporal values that cannot be cast" do
      assert_raise ArgumentError, fn -> filter_value(:default_time, "not a time") end
      assert_raise ArgumentError, fn -> filter_value(:default_datetime, "not a datetime") end
    end

    test "passes nil through for every type" do
      for id <- [:default_integer, :default_float, :default_boolean, :default_datetime, :name] do
        assert filter_value(id, nil) == nil
      end
    end

    test "raises on values that cannot be cast" do
      assert_raise ArgumentError, fn -> filter_value(:default_integer, "not a number") end
      assert_raise ArgumentError, fn -> filter_value(:default_float, "not a number") end
      assert_raise ArgumentError, fn -> filter_value(:default_boolean, "maybe") end
      assert_raise ArgumentError, fn -> filter_value(:default_date, "not a date") end
    end

    test "casts without a parameter by leaving the value untouched" do
      assert Query.new_base_filter(nil, :eq, "4", false, []).value == "4"
    end
  end
end
