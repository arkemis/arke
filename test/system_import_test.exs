defmodule Arke.SystemImportTest do
  use Arke.Test.RepoCase

  alias Arke.Test.Xlsx

  defmodule ImportArke do
    use Arke.System

    defp check_existing_units_for_import(_project, _arke, _header, _args, _existing), do: false
  end

  @header ["string_support", "integer_support", "enum_integer_support"]

  setup do
    path = Path.join(System.tmp_dir!(), "import.xlsx")
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  defp arke(body_params) do
    :arke_test_support
    |> ArkeManager.get(:arke_system)
    |> Map.put(:runtime_data, %{conn: %{method: "POST", body_params: body_params}})
  end

  defp import_rows(rows, path) do
    Xlsx.write(rows, path)
    ImportArke.import(arke(%{"file" => %{path: path}}))
  end

  describe "import/1" do
    test "rejects a body without a file" do
      assert ImportArke.import(arke(%{})) == {:error, "file is required", 400}
    end

    test "inserts a valid row", %{path: path} do
      rows = [@header, ["hello", 3, 1]]

      assert {:ok, res, 201} = import_rows(rows, path)
      assert res.count_inserted == 1
      assert res.count_error == 0
      assert res.total_count == 1
      assert res.error_units == []

      assert_received {:insert_all, "arke_unit", [row], prefix: "arke_system"}
      assert row[:string_support] == "hello"
    end

    test "collects the failing row with its errors", %{path: path} do
      rows = [@header, ["hello", 3, 1], ["a", 4, 1]]

      assert {:ok, res, 201} = import_rows(rows, path)
      assert res.count_inserted == 1
      assert res.count_error == 1
      assert res.total_count == 2
      assert [%{"string_support" => "a", "errors" => [_ | _]}] = res.error_units
    end

    test "skips rows that are entirely empty", %{path: path} do
      rows = [@header, [nil, nil, nil], ["hello", 3, 1]]

      assert {:ok, res, 201} = import_rows(rows, path)
      assert res.total_count == 1
    end

    test "writes units in chunks of 5000", %{path: path} do
      rows = [["integer_support", "enum_integer_support"] | List.duplicate([3, 1], 5001)]

      assert {:ok, res, 201} = import_rows(rows, path)
      assert res.count_inserted == 5001

      assert_received {:insert_all, "arke_unit", first, prefix: "arke_system"}
      assert_received {:insert_all, "arke_unit", second, prefix: "arke_system"}
      assert length(first) == 5000
      assert length(second) == 1
    end

    test "ignores columns that are not parameters of the arke", %{path: path} do
      rows = [@header ++ ["label"], ["hello", 3, 1, "ignored"]]

      assert {:ok, res, 201} = import_rows(rows, path)
      assert res.count_inserted == 1
      assert res.count_error == 0
    end
  end
end
