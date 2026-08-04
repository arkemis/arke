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
end
