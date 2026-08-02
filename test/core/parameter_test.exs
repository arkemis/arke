defmodule Arke.Core.ParameterTest do
  use Arke.Test.RepoCase

  defp check_arke(context) do
    arke_model = ArkeManager.get(:arke, :arke_system)
    arke_opts = [id: "test_arke_parameter", label: "test_arke_parameter", active: true]
    unit = Unit.load(arke_model, arke_opts)
    ArkeManager.create(unit, :test_schema)
    :ok
  end

  defp create_param(%{describe: type, opts: values} = _context) do
    id = String.to_atom(String.downcase(type))
    create_param(id, values)
  end

  defp create_param(id, values) do
    parameter_model = ArkeManager.get(id, :arke_system)
    unit = Unit.load(parameter_model, values)
    ParameterManager.create(unit, :test_schema)
    :ok
  end

  defp check_parameter_node(%{describe: _type, opts: values} = _context) do
    param_id = values[:id]
    arke = ArkeManager.get(:test_arke_parameter, :test_schema)
    param = ParameterManager.get(param_id, :test_schema)

    with true <-
           length(Enum.filter(ArkeManager.get_parameters(arke), fn p -> p.id == param_id end)) > 0 do
      %{link_status: "found"}
    else
      _ ->
        LinkManager.add_node(
          :test_schema,
          arke,
          param,
          "parameter",
          %{}
        )

        %{link_status: "missing"}
    end
  end

  describe "String" do
    defp get_string_opts(_context),
      do: %{opts: [id: :string_test, label: "Test String", min_length: 3, max_length: 5]}

    setup [:get_string_opts, :create_param, :check_arke, :check_parameter_node]

    test "create" do
      # Creation happens in the setup
      param = ParameterManager.get(:string_test, :test_schema)
      assert param.id == :string_test
    end

    test "associate" do
      parameter_model = ArkeManager.get(:string, :arke_system)

      QueryManager.create(:test_schema, parameter_model,
        id: :test_association_string,
        label: "Test Association String"
      )

      arke = ArkeManager.get(:test_arke_parameter, :test_schema)
      param = ParameterManager.get(:test_association_string, :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke,
        param,
        "parameter",
        %{}
      )

      arke_with_param = ArkeManager.get(:test_arke_parameter, :test_schema)

      assert Enum.find(arke.data.parameters, fn p -> p.id == :test_association_string end) == nil

      assert Enum.find(arke_with_param.data.parameters, fn p ->
               p.id == :test_association_string
             end) !=
               nil
    end

    test "create unit" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          string_test: "test",
          label: "First string unit"
        })

      assert unit.data.string_test == "test"
    end

    test "create unit (error)" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:error, msg} =
        QueryManager.create(:test_schema, arke_model, %{
          string_test: "test not valid",
          label: "First string unit"
        })

      assert msg == [%{context: "parameter_validation", message: "Test String: max length is 5"}]

      {:error, msg} =
        QueryManager.create(:test_schema, arke_model, %{
          string_test: "nv",
          label: "First string unit"
        })

      assert msg == [%{context: "parameter_validation", message: "Test String: min length is 3"}]
    end

    test "values" do
      opts = [id: :string_test_values, label: "Test String", values: ["first", "second"]]
      parameter_model = ArkeManager.get(:string, :arke_system)
      {:ok, parameter_unit} = QueryManager.create(:test_schema, parameter_model, opts)
      arke = ArkeManager.get(:test_arke_parameter, :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke,
        parameter_unit,
        "parameter",
        %{}
      )

      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model,
          string_test_values: "first",
          label: "First string unit values"
        )

      {:error, msg} =
        QueryManager.create(:test_schema, arke_model,
          string_test_values: "not_valid",
          label: "First string unit values"
        )

      QueryManager.delete(:test_schema, unit)

      assert parameter_unit.data.values == [
               %{label: "First", value: "first"},
               %{label: "Second", value: "second"}
             ]

      assert unit.data.string_test_values == "first"

      assert msg == [
               %{
                 context: "parameter_validation",
                 message: "allowed values for string_test_values are: first, second"
               }
             ]
    end

    test "delete" do
      values = [
        id: :string_test_delete,
        label: "Test string delete",
        min_length: 3,
        max_length: 5
      ]

      create_param(:string, values)
      unit = ParameterManager.get(:string_test_delete, :test_schema)

      param = ParameterManager.get(values[:id], :test_schema)
      assert param.id == values[:id]

      QueryManager.delete(:test_schema, unit)

      assert ParameterManager.get(values[:id], :test_schema) == nil
    end
  end

  describe "Integer" do
    defp get_integer_opts(_context),
      do: %{opts: [id: :integer_test, label: "Test Integer", min: 3, max: 5]}

    setup [:get_integer_opts, :create_param, :check_arke, :check_parameter_node]

    test "create" do
      # Creation happens in the setup
      param = ParameterManager.get(:integer_test, :test_schema)
      assert param.id == :integer_test
    end

    test "associate" do
      parameter_model = ArkeManager.get(:integer, :arke_system)

      QueryManager.create(:test_schema, parameter_model,
        id: :test_association_integer,
        label: "Test Association integer"
      )

      arke = ArkeManager.get(:test_arke_parameter, :test_schema)
      param = ParameterManager.get(:test_association_integer, :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke,
        param,
        "parameter",
        %{}
      )

      arke_with_param = ArkeManager.get(:test_arke_parameter, :test_schema)

      assert Enum.find(arke.data.parameters, fn p -> p.id == :test_association_integer end) == nil

      assert Enum.find(arke_with_param.data.parameters, fn p ->
               p.id == :test_association_integer
             end) !=
               nil
    end

    test "create unit" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          integer_test: 3,
          label: "First integer unit"
        })

      assert unit.data.integer_test == 3
    end

    test "create unit (error)" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:error, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          integer_test: 10,
          label: "First integer unit"
        })

      assert unit == [%{context: "parameter_validation", message: "Test Integer: max is 5"}]

      {:error, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          integer_test: 1,
          label: "First integer unit"
        })

      assert unit == [%{context: "parameter_validation", message: "Test Integer: min is 3"}]
    end

    test "values" do
      opts = [
        id: :integer_test_values,
        label: "Test integer",
        values: [1, 2, 3, 4],
        multiple: true
      ]

      parameter_model = ArkeManager.get(:integer, :arke_system)
      {:ok, parameter_unit} = QueryManager.create(:test_schema, parameter_model, opts)
      arke = ArkeManager.get(:test_arke_parameter, :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke,
        parameter_unit,
        "parameter",
        %{}
      )

      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)
      # TODO: fix parsing if list of values is passed
      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model,
          integer_test_values: [1, 2],
          label: "First integer unit values"
        )

      {:error, msg} =
        QueryManager.create(:test_schema, arke_model,
          integer_test_values: 9,
          label: "First integer unit values"
        )

      QueryManager.delete(:test_schema, unit)

      assert parameter_unit.data.values == [
               %{label: "1", value: 1},
               %{label: "2", value: 2},
               %{label: "3", value: 3},
               %{label: "4", value: 4}
             ]

      assert unit.data.integer_test_values == [1, 2]

      assert msg == [
               %{
                 context: "parameter_validation",
                 message: "allowed values for integer_test_values are: 1, 2, 3, 4"
               }
             ]
    end

    test "delete" do
      values = [id: :integer_test_delete, label: "Test integer delete"]
      create_param(:integer, values)
      unit = ParameterManager.get(:integer_test_delete, :test_schema)

      param = ParameterManager.get(values[:id], :test_schema)
      assert param.id == values[:id]

      QueryManager.delete(:test_schema, unit)

      assert ParameterManager.get(values[:id], :test_schema) == nil
    end
  end

  describe "Float" do
    defp get_float_opts(_context),
      do: %{opts: [id: :float_test, label: "Test float", min: 3, max: 5]}

    setup [:get_float_opts, :create_param, :check_arke, :check_parameter_node]

    test "create" do
      # Creation happens in the setup
      param = ParameterManager.get(:float_test, :test_schema)
      assert param.id == :float_test
    end

    test "associate" do
      parameter_model = ArkeManager.get(:float, :arke_system)

      QueryManager.create(:test_schema, parameter_model,
        id: :test_association_float,
        label: "Test Association float"
      )

      arke = ArkeManager.get(:test_arke_parameter, :test_schema)
      param = ParameterManager.get(:test_association_float, :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke,
        param,
        "parameter",
        %{}
      )

      arke_with_param = ArkeManager.get(:test_arke_parameter, :test_schema)

      assert Enum.find(arke.data.parameters, fn p -> p.id == :test_association_float end) == nil

      assert Enum.find(arke_with_param.data.parameters, fn p ->
               p.id == :test_association_float
             end) !=
               nil
    end

    test "create unit" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{float_test: 3, label: "First float unit"})

      assert unit.data.float_test == 3
    end

    test "create unit (error)" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:error, unit} =
        QueryManager.create(:test_schema, arke_model, %{float_test: 10, label: "First float unit"})

      assert unit == [%{context: "parameter_validation", message: "Test float: max is 5"}]

      {:error, unit} =
        QueryManager.create(:test_schema, arke_model, %{float_test: 1, label: "First float unit"})

      assert unit == [%{context: "parameter_validation", message: "Test float: min is 3"}]
    end

    test "values" do
      opts = [id: :float_test_values, label: "Test float", values: [1, 2, 3, 4], multiple: true]
      parameter_model = ArkeManager.get(:float, :arke_system)
      {:ok, parameter_unit} = QueryManager.create(:test_schema, parameter_model, opts)
      arke = ArkeManager.get(:test_arke_parameter, :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke,
        parameter_unit,
        "parameter",
        %{}
      )

      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model,
          float_test_values: [1, 2],
          label: "First float unit values"
        )

      {:error, msg} =
        QueryManager.create(:test_schema, arke_model,
          float_test_values: 9,
          label: "First float unit values"
        )

      QueryManager.delete(:test_schema, unit)

      # TODO: fix parsing if list of values is passed
      assert parameter_unit.data.values == [
               %{label: "1", value: 1},
               %{label: "2", value: 2},
               %{label: "3", value: 3},
               %{label: "4", value: 4}
             ]

      assert unit.data.float_test_values == [1, 2]

      assert msg == [
               %{
                 context: "parameter_validation",
                 message: "allowed values for float_test_values are: 1, 2, 3, 4"
               }
             ]
    end

    test "delete" do
      values = [id: :float_test_delete, label: "Test float delete"]
      create_param(:float, values)
      unit = ParameterManager.get(:float_test_delete, :test_schema)

      param = ParameterManager.get(values[:id], :test_schema)
      assert param.id == values[:id]

      QueryManager.delete(:test_schema, unit)

      assert ParameterManager.get(values[:id], :test_schema) == nil
    end
  end

  describe "Boolean" do
    defp get_bool_opts(_context),
      do: %{opts: [id: :boolean_test, label: "Test boolean", default_boolean: true]}

    setup [:get_bool_opts, :create_param, :check_arke, :check_parameter_node]

    test "create" do
      # Creation happens in the setup
      param = ParameterManager.get(:boolean_test, :test_schema)
      assert param.id == :boolean_test
    end

    test "associate" do
      parameter_model = ArkeManager.get(:boolean, :arke_system)

      QueryManager.create(:test_schema, parameter_model,
        id: :test_association_boolean,
        label: "Test Association boolean"
      )

      arke = ArkeManager.get(:test_arke_parameter, :test_schema)
      param = ParameterManager.get(:test_association_boolean, :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke,
        param,
        "parameter",
        %{}
      )

      arke_with_param = ArkeManager.get(:test_arke_parameter, :test_schema)

      assert Enum.find(arke.data.parameters, fn p -> p.id == :test_association_boolean end) == nil

      assert Enum.find(arke_with_param.data.parameters, fn p ->
               p.id == :test_association_boolean
             end) !=
               nil
    end

    test "create unit" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:ok, unit} = QueryManager.create(:test_schema, arke_model, %{label: "First boolean unit"})
      assert unit.data.boolean_test == true
    end

    test "create unit (error)" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:error, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          boolean_test: "string not valid",
          label: "First boolean unit"
        })

      assert unit == [
               %{context: "parameter_validation", message: "Test boolean: must be a boolean"}
             ]
    end

    test "delete" do
      values = [id: :bool_test_delete, label: "Test boolean delete"]
      create_param(:boolean, values)
      unit = ParameterManager.get(:bool_test_delete, :test_schema)

      param = ParameterManager.get(values[:id], :test_schema)
      assert param.id == values[:id]

      QueryManager.delete(:test_schema, unit)

      assert ParameterManager.get(values[:id], :test_schema) == nil
    end
  end

  describe "Dict" do
    defp get_dict_opts(_context), do: %{opts: [id: :dict_test, label: "Test dict"]}
    setup [:get_dict_opts, :create_param, :check_arke, :check_parameter_node]

    test "create" do
      # Creation happens in the setup
      param = ParameterManager.get(:dict_test, :test_schema)
      assert param.id == :dict_test
    end

    test "associate" do
      parameter_model = ArkeManager.get(:dict, :arke_system)

      QueryManager.create(:test_schema, parameter_model,
        id: :test_association_dict,
        label: "Test Association dict"
      )

      arke = ArkeManager.get(:test_arke_parameter, :test_schema)
      param = ParameterManager.get(:test_association_dict, :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke,
        param,
        "parameter",
        %{}
      )

      arke_with_param = ArkeManager.get(:test_arke_parameter, :test_schema)

      assert Enum.find(arke.data.parameters, fn p -> p.id == :test_association_dict end) == nil

      assert Enum.find(arke_with_param.data.parameters, fn p -> p.id == :test_association_dict end) !=
               nil
    end

    test "create unit" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          dict_test: %{"key" => "value"},
          label: "First dict unit"
        })

      assert unit.data.dict_test == %{"key" => "value"}
    end

    test "create unit (error)" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)
      # should accept only true/false
      {:error, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          dict_test: "string not valid",
          label: "First dict unit"
        })

      assert unit == [%{context: "parameter_validation", message: "Test dict: must be a map"}]
    end

    test "delete" do
      values = [id: :dict_test_delete, label: "Test dict delete"]
      create_param(:dict, values)
      unit = ParameterManager.get(:dict_test_delete, :test_schema)

      param = ParameterManager.get(values[:id], :test_schema)
      assert param.id == values[:id]

      QueryManager.delete(:test_schema, unit)

      assert ParameterManager.get(values[:id], :test_schema) == nil
    end
  end

  describe "List" do
    defp get_list_opts(_context), do: %{opts: [id: :list_test, label: "Test list"]}
    setup [:get_list_opts, :create_param, :check_arke, :check_parameter_node]

    test "create" do
      # Creation happens in the setup
      param = ParameterManager.get(:list_test, :test_schema)
      assert param.id == :list_test
    end

    test "associate" do
      parameter_model = ArkeManager.get(:list, :arke_system)

      QueryManager.create(:test_schema, parameter_model,
        id: :test_association_list,
        label: "Test Association list"
      )

      arke = ArkeManager.get(:test_arke_parameter, :test_schema)
      param = ParameterManager.get(:test_association_list, :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke,
        param,
        "parameter",
        %{}
      )

      arke_with_param = ArkeManager.get(:test_arke_parameter, :test_schema)

      assert Enum.find(arke.data.parameters, fn p -> p.id == :test_association_list end) == nil

      assert Enum.find(arke_with_param.data.parameters, fn p ->
               p.id == :test_association_list
             end) !=
               nil
    end

    test "create unit" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          list_test: ["first value", 2, true],
          label: "First list unit"
        })

      assert unit.data.list_test == ["first value", 2, true]
    end

    test "create unit (error)" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)
      # should accept only true/false
      {:error, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          list_test: "string not valid",
          label: "First list unit"
        })

      assert unit == [%{context: "parameter_validation", message: "Test list: must be a list"}]
    end

    test "delete" do
      values = [id: :list_test_delete, label: "Test list delete"]
      create_param(:list, values)
      unit = ParameterManager.get(:list_test_delete, :test_schema)

      param = ParameterManager.get(values[:id], :test_schema)
      assert param.id == values[:id]

      QueryManager.delete(:test_schema, unit)

      assert ParameterManager.get(values[:id], :test_schema) == nil
    end
  end

  describe "Date" do
    defp get_date_opts(_context), do: %{opts: [id: :date_test, label: "Test date"]}
    setup [:get_date_opts, :create_param, :check_arke, :check_parameter_node]

    test "create" do
      # Creation happens in the setup
      param = ParameterManager.get(:date_test, :test_schema)
      assert param.id == :date_test
    end

    test "associate" do
      parameter_model = ArkeManager.get(:date, :arke_system)

      QueryManager.create(:test_schema, parameter_model,
        id: :test_association_date,
        label: "Test Association date"
      )

      arke = ArkeManager.get(:test_arke_parameter, :test_schema)
      param = ParameterManager.get(:test_association_date, :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke,
        param,
        "parameter",
        %{}
      )

      arke_with_param = ArkeManager.get(:test_arke_parameter, :test_schema)

      assert Enum.find(arke.data.parameters, fn p -> p.id == :test_association_date end) == nil

      assert Enum.find(arke_with_param.data.parameters, fn p ->
               p.id == :test_association_date
             end) !=
               nil
    end

    test "create unit" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          date_test: "1999-01-31",
          label: "First date unit"
        })

      assert unit.data.date_test == ~D[1999-01-31]

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          date_test: ~D[2000-04-25],
          label: "First date unit"
        })

      assert unit.data.date_test == ~D[2000-04-25]

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          date_test: %Date{day: 15, month: 11, year: 1993},
          label: "First date unit"
        })

      assert unit.data.date_test == ~D[1993-11-15]

      {:ok, date} = Date.new(1993, 11, 15)

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{date_test: date, label: "First date unit"})

      assert unit.data.date_test == ~D[1993-11-15]
    end

    test "create unit (error)" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)
      # should accept only true/false
      {:error, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          date_test: "31-01-1999",
          label: "First date unit"
        })

      assert unit == [
               %{
                 context: "parameter_validation",
                 message:
                   "Test date: must be %Date{} | ~D[YYYY-MM-DD] | iso8601 (YYYY-MM-DD) format"
               }
             ]
    end

    test "delete" do
      values = [id: :date_test_delete, label: "Test date delete"]
      create_param(:date, values)
      unit = ParameterManager.get(:date_test_delete, :test_schema)

      param = ParameterManager.get(values[:id], :test_schema)
      assert param.id == values[:id]

      QueryManager.delete(:test_schema, unit)

      assert ParameterManager.get(values[:id], :test_schema) == nil
    end
  end

  describe "Time" do
    defp get_time_opts(_context), do: %{opts: [id: :time_test, label: "Test time"]}
    setup [:get_time_opts, :create_param, :check_arke, :check_parameter_node]

    test "create" do
      # Creation happens in the setup
      param = ParameterManager.get(:time_test, :test_schema)
      assert param.id == :time_test
    end

    test "associate" do
      parameter_model = ArkeManager.get(:time, :arke_system)

      QueryManager.create(:test_schema, parameter_model,
        id: :test_association_time,
        label: "Test Association time"
      )

      arke = ArkeManager.get(:test_arke_parameter, :test_schema)
      param = ParameterManager.get(:test_association_time, :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke,
        param,
        "parameter",
        %{}
      )

      arke_with_param = ArkeManager.get(:test_arke_parameter, :test_schema)

      assert Enum.find(arke.data.parameters, fn p -> p.id == :test_association_time end) == nil

      assert Enum.find(arke_with_param.data.parameters, fn p ->
               p.id == :test_association_time
             end) !=
               nil
    end

    test "create unit" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          time_test: "23:59:12",
          label: "First time unit"
        })

      assert unit.data.time_test == ~T[23:59:12]

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          time_test: ~T[11:59:12],
          label: "First time unit"
        })

      assert unit.data.time_test == ~T[11:59:12]

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          time_test: %Time{second: 15, hour: 06, minute: 45},
          label: "First time unit"
        })

      assert unit.data.time_test == ~T[06:45:15]

      {:ok, time} = Time.new(06, 45, 15)

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{time_test: time, label: "First time unit"})

      assert unit.data.time_test == ~T[06:45:15]
    end

    test "create unit (error)" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)
      # should accept only true/false
      {:error, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          time_test: "31-01-1999",
          label: "First time unit"
        })

      assert unit == [
               %{
                 context: "parameter_validation",
                 message:
                   "Test time: must be must be %Time{} |~T[HH:MM:SS] | iso8601 (HH:MM:SS) format"
               }
             ]
    end

    test "delete" do
      values = [id: :time_test_delete, label: "Test time delete"]
      create_param(:time, values)
      unit = ParameterManager.get(:time_test_delete, :test_schema)

      param = ParameterManager.get(values[:id], :test_schema)
      assert param.id == values[:id]

      QueryManager.delete(:test_schema, unit)

      assert ParameterManager.get(values[:id], :test_schema) == nil
    end
  end

  describe "DateTime" do
    defp get_datetime_opts(_context), do: %{opts: [id: :datetime_test, label: "Test datetime"]}
    setup [:get_datetime_opts, :create_param, :check_arke, :check_parameter_node]

    test "create" do
      # Creation happens in the setup
      param = ParameterManager.get(:datetime_test, :test_schema)
      assert param.id == :datetime_test
    end

    test "associate" do
      parameter_model = ArkeManager.get(:datetime, :arke_system)

      QueryManager.create(:test_schema, parameter_model,
        id: :test_association_datetime,
        label: "Test Association datetime"
      )

      arke = ArkeManager.get(:test_arke_parameter, :test_schema)
      param = ParameterManager.get(:test_association_datetime, :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke,
        param,
        "parameter",
        %{}
      )

      arke_with_param = ArkeManager.get(:test_arke_parameter, :test_schema)

      assert Enum.find(arke.data.parameters, fn p -> p.id == :test_association_datetime end) ==
               nil

      assert Enum.find(arke_with_param.data.parameters, fn p ->
               p.id == :test_association_datetime
             end) !=
               nil
    end

    test "create unit" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:ok, date} = Date.new(1999, 01, 31)
      {:ok, time} = Time.new(23, 59, 12)
      {:ok, datetime} = DateTime.new(date, time)

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          datetime_test: "1999-01-31 23:59:12",
          label: "First datetime unit"
        })

      assert unit.data.datetime_test == datetime

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          datetime_test: ~N[2000-01-31 23:59:12],
          label: "First datetime unit"
        })

      assert unit.data.datetime_test == ~U[2000-01-31 23:59:12Z]

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          datetime_test: ~U[1999-01-31 23:59:12Z],
          label: "First datetime unit"
        })

      assert unit.data.datetime_test == datetime

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          datetime_test: datetime,
          label: "First datetime unit"
        })

      assert unit.data.datetime_test == ~U[1999-01-31 23:59:12Z]
    end

    test "create unit (error)" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)
      # should accept only true/false
      {:error, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          datetime_test: "31-01-1999",
          label: "First datetime unit"
        })

      assert unit == [
               %{
                 context: "parameter_validation",
                 message:
                   "Test datetime: must be %DateTime{} | %NaiveDatetime{} | ~N[YYYY-MM-DDTHH:MM:SS] | ~N[YYYY-MM-DD HH:MM:SS] | ~U[YYYY-MM-DD HH:MM:SS]  format"
               }
             ]
    end

    test "delete" do
      values = [id: :datetime_test_delete, label: "Test datetime delete"]
      create_param(:datetime, values)
      unit = ParameterManager.get(:datetime_test_delete, :test_schema)

      param = ParameterManager.get(values[:id], :test_schema)
      assert param.id == values[:id]

      QueryManager.delete(:test_schema, unit)

      assert ParameterManager.get(values[:id], :test_schema) == nil
    end
  end

  describe "Link" do
    defp get_link_opts(_context),
      do: %{
        opts: [id: :link_test, label: "Test link", arke_or_group_id: "test_arke_parameter"]
      }

    setup [:get_link_opts, :create_param, :check_arke, :check_parameter_node]

    test "create" do
      # Creation happens in the setup
      param = ParameterManager.get(:link_test, :test_schema)
      assert param.id == :link_test
    end

    test "associate" do
      parameter_model = ArkeManager.get(:link, :arke_system)

      QueryManager.create(:test_schema, parameter_model,
        id: :test_association_link,
        label: "Test Association link",
        arke_or_group_id: "test_arke_parameter"
      )

      arke = ArkeManager.get(:test_arke_parameter, :test_schema)
      param = ParameterManager.get(:test_association_link, :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke,
        param,
        "parameter",
        %{}
      )

      arke_with_param = ArkeManager.get(:test_arke_parameter, :test_schema)

      assert Enum.find(arke.data.parameters, fn p -> p.id == :test_association_link end) == nil

      assert Enum.find(arke_with_param.data.parameters, fn p ->
               p.id == :test_association_link
             end) !=
               nil
    end

    test "create unit" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          link_test: ["to define"],
          label: "First link unit"
        })

      assert unit.data.link_test == ["to define"]
    end

    # TODO: link values are not validated. Once a validator exists for the link
    # type this should assert {:error, ...} instead of a successful create.
    test "create unit (invalid value is not rejected)" do
      arke_model = ArkeManager.get(:test_arke_parameter, :test_schema)

      {:ok, unit} =
        QueryManager.create(:test_schema, arke_model, %{
          link_test: "31-01-1999",
          label: "First link unit"
        })

      assert unit.data.link_test == "31-01-1999"
    end

    test "delete" do
      values = [id: :link_test_delete, label: "Test link delete"]
      create_param(:link, values)
      unit = ParameterManager.get(:link_test_delete, :test_schema)

      param = ParameterManager.get(values[:id], :test_schema)
      assert param.id == values[:id]

      QueryManager.delete(:test_schema, unit)

      assert ParameterManager.get(values[:id], :test_schema) == nil
    end
  end
end
