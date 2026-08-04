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

    test "get_struct (error)" do
      assert_raise RuntimeError, "Must pass a valid arke or unit", fn ->
        StructManager.get_struct(%{arke_id: :test_arke_struct, data: %{}})
      end
    end

    test "decode (error)" do
      assert_raise RuntimeError, "Must pass valid data", fn ->
        StructManager.decode(:test_schema, :test_arke_struct, %{}, :xml)
      end
    end
  end

  describe "StructManager link parameters" do
    setup do
      arke_model = ArkeManager.get(:arke, :arke_system)
      link_model = ArkeManager.get(:link, :arke_system)
      group_model = ArkeManager.get(:group, :arke_system)

      for id <- ["struct_source", "struct_target"] do
        QueryManager.create(:test_schema, arke_model, %{id: id, label: id})
      end

      QueryManager.create(:test_schema, group_model, %{id: "struct_group", label: "Struct Group"})

      QueryManager.create(:test_schema, link_model, %{
        id: "struct_link",
        label: "Struct Link",
        arke_or_group_id: "struct_target",
        connection_type: "struct_conn",
        direction: "child",
        multiple: false
      })

      QueryManager.create(:test_schema, link_model, %{
        id: "struct_group_link",
        label: "Struct Group Link",
        arke_or_group_id: "struct_group",
        connection_type: "struct_conn",
        direction: "child",
        multiple: false
      })

      LinkManager.add_node(
        :test_schema,
        ArkeManager.get(:struct_source, :test_schema),
        ParameterManager.get(:struct_link, :test_schema),
        "parameter",
        %{}
      )

      target_model = ArkeManager.get(:struct_target, :test_schema)

      {:ok, target} =
        QueryManager.create(:test_schema, target_model, %{id: "target_1", label: "Target 1"})

      {:ok, source} =
        QueryManager.create(:test_schema, ArkeManager.get(:struct_source, :test_schema), %{
          id: "source_1",
          label: "Source 1",
          struct_link: "target_1"
        })

      {:ok, source: source, target: target}
    end

    test "encode leaves a link as its id by default", %{source: source} do
      assert StructManager.encode(source, type: :json).struct_link == "target_1"
    end

    test "encode with load_links inlines the linked unit", %{source: source} do
      encoded = StructManager.encode(source, type: :json, load_links: true)

      assert encoded.struct_link.id == "target_1"
      assert encoded.struct_link.arke_id == "struct_target"
    end

    test "encode with load_links on a list of units", %{source: source} do
      [encoded] = StructManager.encode([source], type: :json, load_links: true)

      assert encoded.struct_link.id == "target_1"
    end

    test "encode with load_links and nothing linked", %{target: target} do
      assert StructManager.encode(target, type: :json, load_links: true).id == "target_1"
    end

    test "get_struct resolves link_ref through the ArkeManager" do
      arke = ArkeManager.get(:struct_source, :test_schema)
      struct = StructManager.get_struct(arke)

      parameter = Enum.find(struct.parameters, fn p -> p.id == "struct_link" end)

      assert parameter.type == "link"
      assert parameter.link_ref.id == "struct_target"
      assert is_list(parameter.link_ref.parameters)
    end

    test "get_struct falls back to the GroupManager for link_ref" do
      arke = ArkeManager.get(:struct_source, :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke,
        ParameterManager.get(:struct_group_link, :test_schema),
        "parameter",
        %{}
      )

      struct = StructManager.get_struct(ArkeManager.get(:struct_source, :test_schema))
      parameter = Enum.find(struct.parameters, fn p -> p.id == "struct_group_link" end)

      assert parameter.link_ref.id == "struct_group"
      assert parameter.link_ref.arke_id == "group"
    end

    test "get_struct leaves link_ref nil when the target does not exist" do
      link_model = ArkeManager.get(:link, :arke_system)

      QueryManager.create(:test_schema, link_model, %{
        id: "struct_dangling_link",
        label: "Dangling",
        arke_or_group_id: "not_a_thing"
      })

      arke = ArkeManager.get(:struct_source, :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke,
        ParameterManager.get(:struct_dangling_link, :test_schema),
        "parameter",
        %{}
      )

      struct = StructManager.get_struct(ArkeManager.get(:struct_source, :test_schema))
      parameter = Enum.find(struct.parameters, fn p -> p.id == "struct_dangling_link" end)

      assert parameter.link_ref == nil
    end
  end

  describe "StructManager.get_struct/3 add_value" do
    setup do
      arke_model = ArkeManager.get(:arke, :arke_system)

      QueryManager.create(:test_schema, arke_model, %{id: "struct_base", label: "Struct Base"})

      for parameter_id <- [:id, :arke_id, :metadata, :inserted_at, :updated_at, :label] do
        LinkManager.add_node(
          :test_schema,
          ArkeManager.get(:struct_base, :test_schema),
          ParameterManager.get(parameter_id, :arke_system),
          "parameter",
          %{}
        )
      end

      arke = ArkeManager.get(:struct_base, :test_schema)

      unit =
        Unit.load(arke, %{
          id: "base_unit",
          label: "Base Unit",
          inserted_at: ~U[2024-01-02 03:04:05Z],
          updated_at: ~U[2024-01-03 03:04:05Z],
          metadata: %{project: :test_schema, tag: "x"}
        })

      {:ok, arke: arke, unit: unit}
    end

    test "reads the value of every base parameter off the unit", %{arke: arke, unit: unit} do
      values =
        StructManager.get_struct(arke, unit, [])
        |> Map.fetch!(:parameters)
        |> Map.new(fn p -> {p.id, p.value} end)

      assert values["id"] == :base_unit
      assert values["arke_id"] == :struct_base
      assert values["metadata"] == %{tag: "x"}
      assert values["inserted_at"] == ~U[2024-01-02 03:04:05Z]
      assert values["updated_at"] == ~U[2024-01-03 03:04:05Z]
      assert values["label"] == "Base Unit"
    end

    test "include and exclude filter the parameters", %{arke: arke, unit: unit} do
      included =
        StructManager.get_struct(arke, unit, %{"include" => ["label"]})
        |> Map.fetch!(:parameters)
        |> Enum.map(& &1.id)

      assert included == ["label"]

      excluded =
        StructManager.get_struct(arke, unit, %{"exclude" => ["label"]})
        |> Map.fetch!(:parameters)
        |> Enum.map(& &1.id)

      refute "label" in excluded
      assert "id" in excluded
    end
  end
end
