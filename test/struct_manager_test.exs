defmodule StructManagerTest do
  use Arke.Test.RepoCase

  @base_keys [:id, :arke_id, :inserted_at, :updated_at, :metadata]

  defp get_parameter_list(),
    do: [:string, :integer, :float, :date, :time, :datetime, :dict, :list, :boolean]

  defp get_date() do
    {:ok, date} = Date.new(1999, 12, 30)
    date
  end

  defp get_time() do
    {:ok, time} = Time.new(23, 59, 15)
    time
  end

  defp get_datetime() do
    {:ok, datetime} = DateTime.new(get_date(), get_time())
    datetime
  end

  defp get_parameter_values_decode() do
    [
      label: "unit struct test",
      string_struct_test: "struct_test",
      integer_struct_test: 2,
      float_struct_test: 5.5,
      date_struct_test: "1999-12-30",
      time_struct_test: "23:59:15",
      datetime_struct_test: "2022-10-31T16:44:19",
      dict_struct_test: %{key: "value"},
      list_struct_test: ["list", "of", "values"],
      boolean_struct_test: true
    ]
  end

  defp get_parameter_values_encode() do
    [
      label: "unit struct test",
      string_struct_test: "struct_test",
      integer_struct_test: 2,
      float_struct_test: 5.5,
      date_struct_test: get_date(),
      time_struct_test: get_time(),
      datetime_struct_test: get_datetime(),
      dict_struct_test: %{key: "value"},
      list_struct_test: ["list", "of", "values"],
      boolean_struct_test: true
    ]
  end

  defp create_arke_test(_context) do
    arke_model = ArkeManager.get(:arke, :arke_system)
    arke_opts = [id: "test_arke_struct", label: "test_arke_struct", active: true]
    arke_unit = Unit.load(arke_model, arke_opts)
    ArkeManager.create(arke_unit, :test_schema)

    param_list = get_parameter_list()
    Enum.each(param_list, &create_param(&1))

    new_arke_model = ArkeManager.get(:test_arke_struct, :test_schema)
    values = get_parameter_values_encode()
    unit = Unit.load(new_arke_model, values)
    ArkeManager.create(unit, :test_schema)

    :ok
  end

  defp create_param(type) do
    parameter_model = ArkeManager.get(type, :arke_system)

    unit =
      Unit.load(parameter_model, %{
        id: "#{type}_struct_test",
        label: "#{String.upcase(to_string(type))} Struct Test Label"
      })

    ParameterManager.create(unit, :test_schema)

    parent = ArkeManager.get("test_arke_struct", :test_schema)
    child = ParameterManager.get("#{type}_struct_test", :test_schema)

    LinkManager.add_node(
      :test_schema,
      parent,
      child,
      "parameter",
      %{}
    )

    :ok
  end

  describe "StructManager" do
    setup [:create_arke_test]

    test "encode (when is list)" do
      model = ArkeManager.get(:test_arke_struct, :test_schema)
      unit = Unit.load(model, get_parameter_values_decode())

      struct_list = StructManager.encode([unit], type: :json)
      keys = Enum.map(@base_keys, fn k -> Map.has_key?(List.first(struct_list), k) end)

      assert length(struct_list) > 0
      assert Enum.all?(keys, &(&1 == true)) == true
    end

    test "encode" do
      model = ArkeManager.get(:test_arke_struct, :test_schema)
      unit = Unit.load(model, get_parameter_values_decode())

      struct = StructManager.encode(unit, type: :json)
      keys = Enum.map(@base_keys, fn k -> Map.has_key?(struct, k) end)
      assert Enum.all?(keys, &(&1 == true)) == true
    end

    test "encode normalises inserted_at and updated_at to UTC datetimes" do
      model = ArkeManager.get(:test_arke_struct, :test_schema)

      opts =
        get_parameter_values_decode()
        |> Keyword.put(:inserted_at, "2022-10-31T16:44:19")
        |> Keyword.put(:updated_at, ~N[2023-01-02 03:04:05])

      struct = StructManager.encode(Unit.load(model, opts), type: :json)

      assert struct.inserted_at == ~U[2022-10-31 16:44:19Z]
      assert struct.updated_at == ~U[2023-01-02 03:04:05Z]
    end

    test "encode keeps nil timestamps as nil" do
      model = ArkeManager.get(:test_arke_struct, :test_schema)
      unit = Unit.load(model, get_parameter_values_decode())

      struct = StructManager.encode(unit, type: :json)

      assert struct.inserted_at == nil
      assert struct.updated_at == nil
    end

    test "encode (nil data)" do
      model = ArkeManager.get(:test_arke_struct, :test_schema)
      unit = Unit.load(model, get_parameter_values_decode())

      unit_nil = Map.put_new(Map.delete(unit, :data), :data, nil)

      struct = StructManager.encode(unit_nil, type: :json)
      keys = Enum.map(@base_keys, fn k -> Map.has_key?(struct, k) end)

      assert Map.keys(struct) -- @base_keys == []
    end

    test "encode (empty data)" do
      model = ArkeManager.get(:test_arke_struct, :test_schema)
      unit = Unit.load(model, get_parameter_values_decode())

      unit_nil = Map.put_new(Map.delete(unit, :data), :data, %{})

      struct = StructManager.encode(unit_nil, type: :json)

      assert Map.keys(struct) -- @base_keys == []
    end

    test "decode when is_atom(arke_id)" do
      values = get_parameter_values_decode()

      # decode when is_atom(arke_id)
      struct = StructManager.decode(:test_schema, :test_arke_struct, values, :json)

      assert struct.__struct__ == Arke.Core.Unit
      assert struct.arke_id == :test_arke_struct
      assert struct.data.float_struct_test == 5.5
    end

    test "decode when is_string(arke_id)" do
      values = get_parameter_values_decode()

      struct = StructManager.decode(:test_schema, "test_arke_struct", values, :json)

      assert struct.__struct__ == Arke.Core.Unit
      assert struct.arke_id == :test_arke_struct
      assert struct.data.integer_struct_test == 2
    end

    test "decode (datetime not iso8601)" do
      values =
        get_parameter_values_decode()
        |> Keyword.replace(:date_struct_test, "1999/12/30")

      struct_date = StructManager.decode(:test_schema, :test_arke_struct, values, :json)

      # TODO: better to raise an error and not load the unit if there is an error
      assert struct_date.data.date_struct_test ==
               "must be %Date{} | ~D[YYYY-MM-DD] | iso8601 (YYYY-MM-DD) format"

      values = Keyword.replace(values, :datetime_struct_test, "2022/10/31T16:44:19")
      struct_dt = StructManager.decode(:test_schema, :test_arke_struct, values, :json)

      assert struct_dt.data.datetime_struct_test ==
               "must be %DateTime{} | %NaiveDatetime{} | ~N[YYYY-MM-DDTHH:MM:SS] | ~N[YYYY-MM-DD HH:MM:SS] | ~U[YYYY-MM-DD HH:MM:SS]  format"
    end

    test "get_struct" do
      # get_struct with arke
      arke_model = ArkeManager.get(:arke, :arke_system)
      struct = StructManager.get_struct(arke_model)

      assert String.downcase(struct.label) == "arke"
      assert is_list(struct.parameters) == true
      assert length(struct.parameters) > 0

      test_arke = ArkeManager.get(:test_arke_struct, :test_schema)
      unit = ArkeManager.get(:test_arke_struct, :test_schema)

      struct = StructManager.get_struct(test_arke, unit, [])

      param_with_value =
        Enum.find(struct.parameters, fn param -> param.id == "string_struct_test" end)

      assert param_with_value.value == nil
    end
  end
end
