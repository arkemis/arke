defmodule Arke.ValidatorTest do
  use Arke.Test.RepoCase

  describe "Validator.validate/2" do
    test "update :ok" do
      arke = ArkeManager.get(:arke, :arke_system)

      unit =
        Arke.Core.Unit.load(arke, %{
          id: :test,
          label: "Test",
          type: "arke",
          active: true,
          parameters: [],
          metadata: %{}
        })

      {:ok, validate} = Arke.Validator.validate(unit, :update, :test_schema)
      assert validate.id == :test and validate.data.label == "Test"
    end

    test "create (error)" do
      arke = ArkeManager.get(:arke, :arke_system)

      unit =
        Arke.Core.Unit.load(arke, %{
          id: :test,
          type: "arke",
          active: true,
          parameters: [],
          metadata: %{}
        })

      {:error, [%{context: c, message: msg}]} =
        Arke.Validator.validate(unit, :create, :test_schema)

      assert c == "parameter_validation" and msg == "label: is required"
    end
  end

  describe "Validator.validate_parameter/3" do
    test "when is_atom()" do
      arke = ArkeManager.get(:arke, :arke_system)
      assert Arke.Validator.validate_parameter(arke, :label, "Test", :test_schema) == {"Test", []}
    end

    test " when is_atom() (error)" do
      arke = ArkeManager.get(:arke, :arke_system)

      assert Arke.Validator.validate_parameter(arke, :label, 12, :arke_system) ==
               {12, [{"Label", "must be a string"}]}
    end

    test "string" do
      arke_string = ArkeManager.get(:arke, :arke_system)
      parameter = ParameterManager.get(:name, :arke_system)

      assert Arke.Validator.validate_parameter(
               arke_string,
               parameter,
               "Test String",
               :test_schema
             ) == {"Test String", []}
    end

    test "string (error)" do
      arke_string = ArkeManager.get(:string, :arke_system)
      parameter = ParameterManager.get(:name, :arke_system)

      assert Arke.Validator.validate_parameter(arke_string, parameter, 12, :test_schema) ==
               {12, [{"Name", "must be a string"}]}
    end

    test "integer" do
      arke_integer = ArkeManager.get(:integer, :arke_system)
      parameter = ParameterManager.get(:default_integer, :arke_system)

      assert Arke.Validator.validate_parameter(arke_integer, parameter, 4, :test_schema) ==
               {4, []}
    end

    test "integer (error)" do
      arke_integer = ArkeManager.get(:integer, :arke_system)
      parameter = ParameterManager.get(:default_integer, :arke_system)

      assert Arke.Validator.validate_parameter(arke_integer, parameter, "not_valid", :test_schema) ==
               {"not_valid", [{"Default", "must be an integer"}]}
    end

    test "float" do
      arke_float = ArkeManager.get(:float, :arke_system)
      parameter = ParameterManager.get(:default_float, :arke_system)
      assert Arke.Validator.validate_parameter(arke_float, parameter, 6, :test_schema) == {6, []}
    end

    test "float (error)" do
      arke_float = ArkeManager.get(:float, :arke_system)
      parameter = ParameterManager.get(:default_float, :arke_system)

      assert Arke.Validator.validate_parameter(arke_float, parameter, "not_valid", :test_schema) ==
               {"not_valid", [{"Default", "must be a float"}]}
    end

    test "boolean" do
      arke_boolean = ArkeManager.get(:boolean, :arke_system)
      parameter = ParameterManager.get(:default_boolean, :arke_system)

      assert Arke.Validator.validate_parameter(arke_boolean, parameter, false, :test_schema) ==
               {false, []}
    end

    test "boolean (error)" do
      arke_boolean = ArkeManager.get(:boolean, :arke_system)
      parameter = ParameterManager.get(:default_boolean, :arke_system)

      assert Arke.Validator.validate_parameter(arke_boolean, parameter, "not_valid", :test_schema) ==
               {"not_valid", [{"Default", "must be a boolean"}]}
    end

    test "dict" do
      arke_dict = ArkeManager.get(:dict, :arke_system)
      parameter = ParameterManager.get(:default_dict, :arke_system)

      assert Arke.Validator.validate_parameter(
               arke_dict,
               parameter,
               %{keyword: "value"},
               :test_schema
             ) == {%{keyword: "value"}, []}
    end

    test "dict (error)" do
      arke_dict = ArkeManager.get(:dict, :arke_system)
      parameter = ParameterManager.get(:default_dict, :arke_system)

      assert Arke.Validator.validate_parameter(arke_dict, parameter, "not_valid", :test_schema) ==
               {"not_valid", [{"Default", "must be a map"}]}
    end

    test "enum" do
      ## STRING
      arke_string = ArkeManager.get(:string, :arke_system)

      new_param_string =
        Arke.Core.Unit.load(arke_string, %{
          id: :test_enum_string,
          label: "Test Enum",
          values: [%{label: "label 1", value: "value1"}, %{label: "label 2", value: "value2"}]
        })

      ParameterManager.create(new_param_string, :test_schema)
      parameter_string = ParameterManager.get(:test_enum_string, :test_schema)

      ## INTEGER
      arke_integer = ArkeManager.get(:integer, :arke_system)

      new_param_integer =
        Arke.Core.Unit.load(arke_integer, %{
          id: :test_enum_integer,
          label: "Test Enum",
          values: [%{label: "label 1", value: 1}, %{label: "label 2", value: 2}]
        })

      ParameterManager.create(new_param_integer, :test_schema)
      parameter_integer = ParameterManager.get(:test_enum_integer, :test_schema)

      ## FLOAT
      arke_float = ArkeManager.get(:float, :arke_system)

      new_param_float =
        Arke.Core.Unit.load(arke_float, %{
          id: :test_enum_float,
          label: "Test Enum",
          values: [%{label: "label 1", value: 1.5}, %{label: "label 2", value: 2.6}]
        })

      ParameterManager.create(new_param_float, :test_schema)
      parameter_float = ParameterManager.get(:test_enum_float, :test_schema)

      assert Arke.Validator.validate_parameter(
               arke_string,
               parameter_string,
               "value1",
               :test_schema
             ) == {"value1", []}

      assert Arke.Validator.validate_parameter(arke_integer, parameter_integer, 1, :test_schema) ==
               {1, []}

      assert Arke.Validator.validate_parameter(arke_float, parameter_float, 2.6, :test_schema) ==
               {2.6, []}
    end

    test "enum (create from list)" do
      arke_string = ArkeManager.get(:string, :arke_system)
      arke_integer = ArkeManager.get(:integer, :arke_system)
      arke_float = ArkeManager.get(:float, :arke_system)

      new_param_string =
        Arke.Core.Unit.load(arke_string, %{
          id: :test_enum_string,
          label: "Test Enum String",
          values: ["1", "2"]
        })

      new_param_integer =
        Arke.Core.Unit.load(arke_integer, %{
          id: :test_enum_integer,
          label: "Test Enum Integer",
          values: [1, 2]
        })

      new_param_float =
        Arke.Core.Unit.load(arke_float, %{
          id: :test_enum_float,
          label: "Test Enum Float",
          values: [1.4, 2.6]
        })

      assert new_param_string.data.values == [
               %{label: "1", value: "1"},
               %{label: "2", value: "2"}
             ]

      assert new_param_integer.data.values == [%{label: "1", value: 1}, %{label: "2", value: 2}]

      assert new_param_float.data.values == [
               %{label: "1.4", value: 1.4},
               %{label: "2.6", value: 2.6}
             ]
    end

    test "enum string (error)" do
      arke_string = ArkeManager.get(:string, :arke_system)

      new_param_string =
        Arke.Core.Unit.load(arke_string, %{
          id: :test_enum_string,
          label: "Test Enum String",
          values: [%{label: "label 1", value: "value1"}, %{label: "label 2", value: "value2"}]
        })

      with {:ok, _} <- ParameterManager.create(new_param_string, :test_schema) do
        parameter_string = ParameterManager.get(:test_enum_string, :test_schema)

        assert Arke.Validator.validate_parameter(
                 arke_string,
                 parameter_string,
                 "not_valid",
                 :test_schema
               ) ==
                 {"not_valid",
                  [{"allowed values for test_enum_string are", ["value1", "value2"]}]}
      end
    end

    test "enum integer (error)" do
      arke_integer = ArkeManager.get(:integer, :arke_system)

      new_param_integer =
        Arke.Core.Unit.load(arke_integer, %{
          id: :test_enum_integer,
          label: "Test Enum Integer",
          values: [%{label: "label 1", value: 1}, %{label: "label 2", value: 2}]
        })

      with {:ok, _} <- ParameterManager.create(new_param_integer, :test_schema) do
        parameter_integer = ParameterManager.get(:test_enum_integer, :test_schema)

        assert Arke.Validator.validate_parameter(arke_integer, parameter_integer, 4, :test_schema) ==
                 {4, [{"allowed values for test_enum_integer are", [1, 2]}]}
      end
    end

    test "enum float (error)" do
      arke_float = ArkeManager.get(:float, :arke_system)

      new_param_float =
        Arke.Core.Unit.load(arke_float, %{
          id: :test_enum_float,
          label: "Test Enum Float",
          values: [%{label: "label 1", value: 1.4}, %{label: "label 2", value: 2.6}]
        })

      with {:ok, _} <- ParameterManager.create(new_param_float, :test_schema) do
        parameter_float = ParameterManager.get(:test_enum_float, :test_schema)

        assert Arke.Validator.validate_parameter(arke_float, parameter_float, 0.5, :test_schema) ==
                 {0.5, [{"allowed values for test_enum_float are", [1.4, 2.6]}]}
      end
    end

    test "enum (error creation)" do
      ## STRING
      arke_string = ArkeManager.get(:string, :arke_system)

      new_param_string =
        Arke.Core.Unit.load(arke_string, %{
          id: :test_enum_string,
          label: "Test Enum String",
          values: [%{label: "label 1", value: 1}, %{label: "label 2", value: 2}]
        })

      ## INTEGER
      arke_integer = ArkeManager.get(:integer, :arke_system)

      new_param_integer =
        Arke.Core.Unit.load(arke_integer, %{
          id: :test_enum_integer,
          label: "Test Enum Integer",
          values: [%{label: "label 1", value: "not_number"}, %{label: "label 2", value: "string"}]
        })

      ## FLOAT
      arke_float = ArkeManager.get(:float, :arke_system)

      new_param_float =
        Arke.Core.Unit.load(arke_float, %{
          id: :test_enum_float,
          label: "Test Enum Float",
          values: [%{label: "label 1", value: "not_number"}, %{label: "label 2", value: "string"}]
        })

      assert new_param_string.data.values == nil
      assert new_param_integer.data.values == nil
      assert new_param_float.data.values == nil
    end

    test "date" do
      arke_date = ArkeManager.get(:arke, :arke_system)
      parameter = ParameterManager.get(:default_date, :arke_system)

      assert Arke.Validator.validate_parameter(arke_date, parameter, "2020-01-01", :test_schema) ==
               {"2020-01-01", []}
    end

    test "date (error)" do
      arke_date = ArkeManager.get(:arke, :arke_system)
      parameter = ParameterManager.get(:default_date, :arke_system)

      assert Arke.Validator.validate_parameter(arke_date, parameter, "01/01/2020", :test_schema) ==
               {"01/01/2020",
                [{"Default", "must be %Date{} | ~D[YYYY-MM-DD] | iso8601 (YYYY-MM-DD) format"}]}
    end

    test "date (sigil ~D)" do
      arke_date = ArkeManager.get(:arke, :arke_system)
      parameter = ParameterManager.get(:default_date, :arke_system)

      assert Arke.Validator.validate_parameter(arke_date, parameter, ~D[2020-01-01], :test_schema) ==
               {~D[2020-01-01], []}
    end

    test "date %Date{}" do
      arke_date = ArkeManager.get(:arke, :arke_system)
      parameter = ParameterManager.get(:default_date, :arke_system)
      date = ~D[2020-01-01]

      assert Arke.Validator.validate_parameter(arke_date, parameter, date, :test_schema) ==
               {date, []}
    end

    test "time" do
      arke_time = ArkeManager.get(:arke, :arke_system)
      parameter = ParameterManager.get(:default_time, :arke_system)

      assert Arke.Validator.validate_parameter(arke_time, parameter, "23:14:12", :test_schema) ==
               {"23:14:12", []}
    end

    test "time (error)" do
      arke_time = ArkeManager.get(:arke, :arke_system)
      parameter = ParameterManager.get(:default_time, :arke_system)
      # TODO: must return message
      assert Arke.Validator.validate_parameter(arke_time, parameter, 9, :test_schema) ==
               {9,
                [{"Default", "must be must be %Time{} |~T[HH:MM:SS] | iso8601 (HH:MM:SS) format"}]}
    end

    test "time (sigil ~T)" do
      arke_time = ArkeManager.get(:arke, :arke_system)
      parameter = ParameterManager.get(:default_time, :arke_system)

      assert Arke.Validator.validate_parameter(arke_time, parameter, ~T[21:43:34], :test_schema) ==
               {~T[21:43:34], []}
    end

    test "time %Time{}" do
      arke_time = ArkeManager.get(:arke, :arke_system)
      parameter = ParameterManager.get(:default_time, :arke_system)
      time = ~T[21:43:34]

      assert Arke.Validator.validate_parameter(arke_time, parameter, time, :test_schema) ==
               {time, []}
    end

    test "datetime" do
      arke_datetime = ArkeManager.get(:arke, :arke_system)
      parameter = ParameterManager.get(:default_datetime, :arke_system)

      assert Arke.Validator.validate_parameter(
               arke_datetime,
               parameter,
               "2020-01-01 12:59:32",
               :test_schema
             ) == {"2020-01-01 12:59:32", []}

      assert Arke.Validator.validate_parameter(
               arke_datetime,
               parameter,
               "2010-12-11 23:12:32Z",
               :test_schema
             ) == {"2010-12-11 23:12:32Z", []}
    end

    test "datetime (error)" do
      arke_datetime = ArkeManager.get(:arke, :arke_system)
      parameter = ParameterManager.get(:default_datetime, :arke_system)

      assert Arke.Validator.validate_parameter(
               arke_datetime,
               parameter,
               "01/01/2020",
               :test_schema
             ) ==
               {"01/01/2020",
                [
                  {"Default",
                   "must be %DateTime{} | %NaiveDatetime{} | ~N[YYYY-MM-DDTHH:MM:SS] | ~N[YYYY-MM-DD HH:MM:SS] | ~U[YYYY-MM-DD HH:MM:SS]  format"}
                ]}
    end

    test "datetime (sigil ~N)" do
      arke_datetime = ArkeManager.get(:arke, :arke_system)
      parameter = ParameterManager.get(:default_datetime, :arke_system)

      assert Arke.Validator.validate_parameter(
               arke_datetime,
               parameter,
               ~N[2020-01-01 12:34:45],
               :test_schema
             ) == {~N[2020-01-01 12:34:45], []}
    end

    test "datetime %NaiveDateTime{}" do
      arke_datetime = ArkeManager.get(:arke, :arke_system)
      parameter = ParameterManager.get(:default_datetime, :arke_system)
      naive = ~N[2020-01-01 12:34:45]

      assert Arke.Validator.validate_parameter(arke_datetime, parameter, naive, :test_schema) ==
               {naive, []}
    end

    test "datetime sigil ~U" do
      arke_datetime = ArkeManager.get(:arke, :arke_system)
      parameter = ParameterManager.get(:default_datetime, :arke_system)

      assert Arke.Validator.validate_parameter(
               arke_datetime,
               parameter,
               ~U[2020-01-01 12:34:45Z],
               :test_schema
             ) == {~U[2020-01-01 12:34:45Z], []}
    end

    test "datetime %DateTime{}" do
      arke_datetime = ArkeManager.get(:arke, :arke_system)
      parameter = ParameterManager.get(:default_datetime, :arke_system)
      datetime = ~U[2020-01-01 12:34:45Z]

      assert Arke.Validator.validate_parameter(arke_datetime, parameter, datetime, :test_schema) ==
               {datetime, []}
    end

    test "unique" do
      arke = ArkeManager.get(:arke_test_support, :arke_system)

      QueryManager.create(:test_schema, arke, %{
        string_support: "unique_username",
        enum_integer_support: [1]
      })

      assert Arke.Validator.validate_parameter(
               arke,
               :string_support,
               "unique_username",
               :test_schema
             ) == {"unique_username", [{"duplicate values are not allowed for", :string_support}]}
    end
  end

  describe "default_values" do
    test "string" do
      # Create string
      opts = [
        id: :string_test_default,
        label: "Test String",
        min_length: 3,
        max_length: nil,
        nullable: false,
        required: false,
        helper_text: nil,
        multiple: false,
        unique: false,
        default_string: nil
      ]

      arke_string = ArkeManager.get(:string, :arke_system)
      QueryManager.create(:test_schema, arke_string, opts)
      parameter_string = ParameterManager.get(:string_test_default, :test_schema)

      # Create Arke
      arke_model = ArkeManager.get(:arke, :arke_system)
      arke_data = [id: :test_arke_default, label: "Test Arke Default"]
      QueryManager.create(:test_schema, arke_model, arke_data)

      # Create association
      arke_link = ArkeManager.get(:arke_link, :arke_system)

      defaults = %{
        min_length: nil,
        max_length: 10,
        helper_text: "Helper Text",
        default_string: "Default",
        required: true
      }

      link_data = [
        parent_id: "test_arke_default",
        child_id: "string_test_default",
        type: "parameter",
        metadata: defaults
      ]

      QueryManager.create(:test_schema, arke_link, link_data)

      # Get arke and the parameter just linked
      arke = ArkeManager.get(:test_arke_default, :test_schema)
      param = ArkeManager.get_parameter(arke, :string_test_default)

      assert param.id == parameter_string.id
      assert param.data.default_string == defaults[:default_string]
      assert param.data.helper_text == defaults[:helper_text]
      assert param.data.label == parameter_string.data.label
      assert param.data.max_length == defaults[:max_length]
      assert param.data.min_length == defaults[:min_length]
      assert param.metadata.project == parameter_string.metadata.project

      assert Arke.Validator.validate_parameter(
               arke,
               :string_test_default,
               "Max length exceeded",
               :test_schema
             ) == {"Max length exceeded", [{"Test String", "max length is 10"}]}

      assert Arke.Validator.validate_parameter(arke, :string_test_default, nil, :test_schema) ==
               {"Default", []}
    end

    test "integer" do
      # Create string
      opts = [
        id: :integer,
        label: "Test Integer",
        min: 3,
        max: nil,
        nullable: false,
        required: false,
        helper_text: nil,
        multiple: false,
        unique: false,
        default_string: nil
      ]

      arke_integer = ArkeManager.get(:integer, :arke_system)
      QueryManager.create(:test_schema, arke_integer, opts)
      parameter_integer = ParameterManager.get(:integer, :test_schema)

      # Create Arke
      arke_model = ArkeManager.get(:arke, :arke_system)
      arke_data = [id: :test_arke_default, label: "Test Arke Default"]
      QueryManager.create(:test_schema, arke_model, arke_data)

      # Create association
      arke_link = ArkeManager.get(:arke_link, :arke_system)

      defaults = %{
        min: nil,
        max: 10,
        helper_text: "Helper Text",
        default_integer: 4,
        required: true
      }

      link_data = [
        parent_id: "test_arke_default",
        child_id: "integer",
        type: "parameter",
        metadata: defaults
      ]

      QueryManager.create(:test_schema, arke_link, link_data)

      # Get arke and the parameter just linked
      arke = ArkeManager.get(:test_arke_default, :test_schema)
      param = ArkeManager.get_parameter(arke, :integer)

      assert param.id == parameter_integer.id
      assert param.data.default_integer == defaults[:default_integer]
      assert param.data.helper_text == defaults[:helper_text]
      assert param.data.label == parameter_integer.data.label
      assert param.data.max == defaults[:max]
      assert param.data.min == defaults[:min]
      assert param.metadata.project == parameter_integer.metadata.project

      assert Arke.Validator.validate_parameter(arke, :integer, 11, :test_schema) ==
               {11, [{"Test Integer", "max is 10"}]}

      assert Arke.Validator.validate_parameter(arke, :integer, nil, :test_schema) == {4, []}
    end

    test "float" do
      # Create string
      opts = [
        id: :float,
        label: "Test Float",
        min: 3,
        max: nil,
        nullable: false,
        required: false,
        helper_text: nil,
        multiple: false,
        unique: false,
        default_string: nil
      ]

      arke_float = ArkeManager.get(:float, :arke_system)
      QueryManager.create(:test_schema, arke_float, opts)
      parameter_float = ParameterManager.get(:float, :test_schema)

      # Create Arke
      arke_model = ArkeManager.get(:arke, :arke_system)
      arke_data = [id: :test_arke_default, label: "Test Arke Default"]
      QueryManager.create(:test_schema, arke_model, arke_data)

      # Create association
      arke_link = ArkeManager.get(:arke_link, :arke_system)

      defaults = %{
        min: nil,
        max: nil,
        helper_text: "Helper Text",
        required: true,
        values: [
          %{label: "first", value: 3.67},
          %{label: "second", value: 4.5},
          %{label: "third", value: 9.08}
        ]
      }

      link_data = [
        parent_id: "test_arke_default",
        child_id: "float",
        type: "parameter",
        metadata: defaults
      ]

      QueryManager.create(:test_schema, arke_link, link_data)

      # Get arke and the parameter just linked
      arke = ArkeManager.get(:test_arke_default, :test_schema)
      param = ArkeManager.get_parameter(arke, :float)

      assert param.id == parameter_float.id
      assert param.data.default_float == defaults[:default_float]
      assert param.data.helper_text == defaults[:helper_text]
      assert param.data.label == parameter_float.data.label
      assert param.data.max == defaults[:max]
      assert param.data.min == defaults[:min]
      assert param.metadata.project == parameter_float.metadata.project

      assert Arke.Validator.validate_parameter(arke, :float, nil, :test_schema) ==
               {nil, [{:float, "is required"}]}

      assert Arke.Validator.validate_parameter(arke, :float, 12.35, :test_schema) ==
               {12.35, [{"allowed values for float are", [3.67, 4.5, 9.08]}]}
    end
  end
end
