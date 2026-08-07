defmodule Arke.Core.UnitTest do
  use Arke.Test.RepoCase

  describe "Unit" do
    test "new" do
      # id, data, arke_id, link, metadata, inserted_at, updated_at, __module__
      now = Date.utc_today()

      # when is_atom(id)
      unit =
        Unit.new(:unit_test_id, [label: "Unit test id"], :arke, nil, %{}, now, now, __MODULE__)

      # when is_binary(id)
      unit_bin =
        Unit.new(:unit_test_id, [label: "Unit test id"], :arke, nil, %{}, now, now, __MODULE__)

      assert unit.id == :unit_test_id
      assert unit.arke_id == :arke
      assert unit_bin.id == :unit_test_id
      assert unit_bin.arke_id == :arke

      assert Unit.new(12, [label: "Unit test id"], :arke, nil, %{}, now, now, __MODULE__) ==
               {:error, [%{context: "parameter_validation", message: "id cannot be a number"}]}
    end

    test "load" do
      arke_model = ArkeManager.get(:arke, :arke_system)
      data = [id: :unit_test_id, label: "Unit test id"]

      # when is_list(opts)
      unit_list = Unit.load(arke_model, data)

      assert unit_list.id == :unit_test_id
      assert unit_list.arke_id == :arke

      # when opts metadata is nil
      data = [id: :unit_test_id, label: "Unit test id", metadata: nil]
      unit_list = Unit.load(arke_model, data)

      assert unit_list.id == :unit_test_id
      assert unit_list.metadata == arke_model.metadata

      # check default assignment
      arke_model = ArkeManager.get(:arke_test_support, :arke_system)

      unit_default = Unit.load(arke_model, [])

      assert unit_default.data.boolean_support == false
      assert unit_default.data.date_support == ~D[1999-11-08]
      assert unit_default.data.datetime_support == ~U[1999-11-08 09:55:13.416444Z]
      assert unit_default.data.dict_support == %{starting: "value"}
      assert unit_default.data.enum_float_support == nil
      assert unit_default.data.enum_integer_support == nil
      assert unit_default.data.enum_string_support == nil
      assert unit_default.data.float_support == 2.5
      assert unit_default.data.integer_support == 5
      assert unit_default.data.list_support == ["list", "of", "values"]
      assert unit_default.data.string_support == "test_default"
      assert unit_default.data.time_support == ~T[09:55:13.416444]

      # Generate unit with data

      datetime_now = DateTime.utc_now()
      date_now = Date.utc_today()
      time_now = Time.utc_now()

      unit_data = [
        boolean_support: true,
        date_support: date_now,
        datetime_support: datetime_now,
        dict_support: %{new: "value"},
        float_support: 4.5,
        integer_support: 10,
        list_support: ["edited", "value"],
        string_support: "new_value",
        time_support: time_now,
        enum_float_support: 3.5,
        enum_integer_support: [1, 4],
        enum_string_support: "second"
      ]

      unit = Unit.load(arke_model, unit_data)

      assert unit.data.boolean_support == true
      assert unit.data.date_support == date_now
      assert unit.data.datetime_support == datetime_now
      assert unit.data.dict_support == %{new: "value"}
      assert unit.data.enum_float_support == 3.5
      assert unit.data.enum_integer_support == [1, 4]
      assert unit.data.enum_string_support == "second"
      assert unit.data.float_support == 4.5
      assert unit.data.integer_support == 10
      assert unit.data.list_support == ["edited", "value"]
      assert unit.data.string_support == "new_value"
      assert unit.data.time_support == time_now
    end

    test "load_data" do
      arke_model = ArkeManager.get(:arke, :arke_system)
      data = %{id: :unit_test_id, label: "Unit test id"}

      unit_data = Unit.load_data(arke_model, %{}, data)

      assert unit_data.label == data.label
      assert unit_data.type == "arke"
      assert Map.get(unit_data, :id) == nil
    end

    test "update" do
      arke_model = ArkeManager.get(:arke_test_support, :arke_system)

      unit_default = Unit.load(arke_model, [])

      unit_updated =
        Unit.update(unit_default,
          float_support: 4.5,
          integer_support: 10,
          list_support: ["edited", "value"],
          string_support: "new_value"
        )

      assert unit_updated.data.float_support != unit_default.data.float_support
      assert unit_updated.data.integer_support != unit_default.data.integer_support
      assert unit_updated.data.list_support != unit_default.data.list_support
      assert unit_updated.data.string_support != unit_default.data.string_support
    end
  end

  describe "Unit.new/8 inserted_at and updated_at" do
    @datetime_msg "must be %DateTime{} | %NaiveDatetime{} | ~N[YYYY-MM-DDTHH:MM:SS] | ~N[YYYY-MM-DD HH:MM:SS] | ~U[YYYY-MM-DD HH:MM:SS]  format"

    defp build(inserted_at, updated_at \\ nil) do
      Unit.new(:temporal_test, [label: "x"], :arke, nil, %{}, inserted_at, updated_at, __MODULE__)
    end

    test "keeps nil as nil" do
      unit = build(nil, nil)
      assert unit.inserted_at == nil
      assert unit.updated_at == nil
    end

    test "passes a DateTime through unchanged" do
      unit = build(~U[2024-03-05 10:20:30Z])
      assert unit.inserted_at == ~U[2024-03-05 10:20:30Z]
    end

    test "promotes a NaiveDateTime to UTC" do
      unit = build(~N[2024-03-05 10:20:30])
      assert unit.inserted_at == ~U[2024-03-05 10:20:30Z]
    end

    test "accepts a zone-less iso8601 string as UTC" do
      unit = build("2022-10-31T16:44:19")
      assert unit.inserted_at == ~U[2022-10-31 16:44:19Z]
    end

    test "accepts a space-separated string with a zone" do
      unit = build("2010-12-11 23:12:32Z")
      assert unit.inserted_at == ~U[2010-12-11 23:12:32Z]
    end

    test "stores an error tuple when given a Date" do
      unit = build(~D[2026-08-03])
      assert unit.inserted_at == {:error, @datetime_msg}
    end

    test "stores an error tuple when given an unparseable string" do
      unit = build("nope")
      assert unit.inserted_at == {:error, @datetime_msg}
    end
  end

  # Every value coming in from an import or a CSV is a string. `parse_value/2`
  # is private, so it is exercised through `Unit.load/2`, its entry point.
  describe "Unit string coercion" do
    defp support(opts), do: Unit.load(ArkeManager.get(:arke_test_support, :arke_system), opts)

    test "reads \"null\" and \"undefined\" as nil" do
      assert support(string_support: "null").data.string_support == nil
      assert support(string_support: "undefined").data.string_support == nil
      assert support(integer_support: "null").data.integer_support == nil
    end

    test "reads the truthy spellings of a boolean" do
      for value <- ["true", "TRUE", "1", true] do
        assert support(boolean_support: value).data.boolean_support == true
      end
    end

    test "reads the falsy spellings of a boolean" do
      for value <- ["false", "FALSE", "0", false] do
        assert support(boolean_support: value).data.boolean_support == false
      end
    end

    test "leaves an unrecognised boolean spelling alone for the validator to reject" do
      assert support(boolean_support: "maybe").data.boolean_support == "maybe"
    end

    test "parses an integer" do
      assert support(integer_support: "42").data.integer_support == 42
      assert support(integer_support: "-7").data.integer_support == -7
      assert support(integer_support: "3 apples").data.integer_support == 3
    end

    test "reports an unparseable integer" do
      assert support(integer_support: "apples").data.integer_support ==
               [%{context: "validation", message: "invalid integer"}]
    end

    test "parses a float" do
      assert support(float_support: "2.5").data.float_support == 2.5
      assert support(float_support: "-0.75").data.float_support == -0.75
      assert support(float_support: "1.5kg").data.float_support == 1.5
    end

    test "reports an unparseable float" do
      assert support(float_support: "kg").data.float_support ==
               [%{context: "validation", message: "invalid float"}]
    end

    test "splits a bracketed string into a list for a multiple parameter" do
      group_model = ArkeManager.get(:group, :arke_system)

      # arke_list is a multiple link parameter
      assert Unit.load(group_model, arke_list: "[first,second]").data.arke_list ==
               ["first", "second"]

      assert Unit.load(group_model, arke_list: "['first','second']").data.arke_list ==
               ["first", "second"]

      # quotes are only stripped when they are flush against the comma, so a
      # space keeps them. Pinned, not endorsed.
      assert Unit.load(group_model, arke_list: "['first', 'second']").data.arke_list ==
               ["first", " 'second"]

      assert Unit.load(group_model, arke_list: "single").data.arke_list == ["single"]
      assert Unit.load(group_model, arke_list: "[]").data.arke_list == []
    end

    test "leaves a value of the right type untouched" do
      assert support(integer_support: 42).data.integer_support == 42
      assert support(float_support: 2.5).data.float_support == 2.5
      assert support(dict_support: %{a: 1}).data.dict_support == %{a: 1}
    end
  end

  describe "Unit.encode_unit_data/2" do
    test "drops parameters flagged only_runtime" do
      arke = ArkeManager.get(:arke_file, :arke_system)

      encoded = Unit.encode_unit_data(arke, %{name: "photo.png", binary_data: <<1, 2, 3>>})

      assert Map.keys(encoded) == ["name"]
    end

    test "drops keys that are not parameters of the arke" do
      arke = ArkeManager.get(:arke_test_support, :arke_system)

      encoded = Unit.encode_unit_data(arke, %{string_support: "a", not_a_parameter: "b"})

      assert Map.keys(encoded) == ["string_support"]
    end
  end

  describe "Unit.encode_unit_data/2 timestamp" do
    test "stamps each encoded parameter with a second-precision UTC datetime" do
      arke = ArkeManager.get(:arke_test_support, :arke_system)
      before = DateTime.utc_now() |> DateTime.truncate(:second)

      encoded = Unit.encode_unit_data(arke, %{string_support: "a value"})

      assert %{"string_support" => %{value: "a value", datetime: stamped}} = encoded
      assert %DateTime{} = stamped
      assert stamped.time_zone == "Etc/UTC"
      assert stamped.microsecond == {0, 0}
      assert DateTime.compare(stamped, before) in [:eq, :gt]
    end
  end

  describe "Unit.as_args/2 generated id" do
    @uuid_v1 ~r/^[0-9a-f]{8}-[0-9a-f]{4}-1[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

    test "generates a lowercase, dash-separated v1 uuid when the unit has no id" do
      arke = ArkeManager.get(:arke_test_support, :arke_system)
      unit = Unit.load(arke, label: "no id")

      assert is_nil(unit.id)

      id = Keyword.fetch!(Unit.as_args(arke, unit), :id)

      assert is_binary(id)
      assert String.length(id) == 36
      assert id =~ @uuid_v1
    end

    test "generates a distinct id on every call" do
      arke = ArkeManager.get(:arke_test_support, :arke_system)
      unit = Unit.load(arke, label: "no id")

      ids = for _ <- 1..20, do: Keyword.fetch!(Unit.as_args(arke, unit), :id)

      assert length(Enum.uniq(ids)) == 20
    end

    test "keeps an id the unit already has" do
      arke = ArkeManager.get(:arke_test_support, :arke_system)
      unit = Unit.load(arke, id: :existing_id, label: "has id")

      assert Keyword.fetch!(Unit.as_args(arke, unit), :id) == "existing_id"
    end
  end

  describe "Unit.get_default_value/2" do
    test "reads default_<arke_id> for every parameter type" do
      for type <- ~w[string integer float boolean date time datetime dict list link]a do
        parameter = %{arke_id: type, data: %{:"default_#{type}" => {:default, type}}}
        assert Unit.get_default_value(nil, parameter) == {:default, type}
      end
    end

    test "supports a parameter type nobody wrote a clause for" do
      parameter = %{arke_id: :brand_new_type, data: %{default_brand_new_type: "works"}}
      assert Unit.get_default_value(nil, parameter) == "works"
    end

    test "returns nil when the parameter has no matching default key" do
      assert Unit.get_default_value(nil, %{arke_id: :string, data: %{default_integer: 1}}) == nil
      assert Unit.get_default_value(nil, %{arke_id: :string, data: %{}}) == nil
      assert Unit.get_default_value(nil, %{}) == nil
    end

    test "keeps a given value over the default" do
      parameter = %{arke_id: :string, data: %{default_string: "fallback"}}
      assert Unit.get_default_value("given", parameter) == "given"
      assert Unit.get_default_value(false, parameter) == false
    end
  end
end
