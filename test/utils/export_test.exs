defmodule Arke.Utils.ExportTest do
  use Arke.Test.RepoCase

  alias Arke.Utils.Export

  setup do
    arke_model = ArkeManager.get(:arke, :arke_system)
    string_model = ArkeManager.get(:string, :arke_system)
    group_model = ArkeManager.get(:group, :arke_system)
    arke_link = ArkeManager.get(:arke_link, :arke_system)

    QueryManager.create(:test_schema, arke_model, %{id: "export_arke", label: "Export Arke"})

    QueryManager.create(:test_schema, string_model, %{
      id: "export_string",
      label: "Export String"
    })

    QueryManager.create(:test_schema, group_model, %{
      id: "export_group",
      label: "Export Group",
      description: "a group"
    })

    QueryManager.create(:test_schema, arke_link, %{
      parent_id: "export_arke",
      child_id: "export_string",
      type: "parameter",
      metadata: %{required: true}
    })

    QueryManager.create(:test_schema, arke_link, %{
      parent_id: "export_arke",
      child_id: "export_string",
      type: "permission",
      metadata: %{get: true}
    })

    :ok
  end

  defp ids(units), do: units |> Enum.map(&to_string(&1.id)) |> Enum.sort()

  describe "get_data/2" do
    test "no flag exports everything" do
      data = Export.get_data(:test_schema, [])

      assert ids(data.arke) == ["export_arke"]
      assert ids(data.group) == ["export_group"]
      assert ids(data.parameter) == ["export_string"]
      assert Enum.map(data.permission, & &1.data.type) == ["permission"]
      assert Enum.map(data.arke_parameter, & &1.data.type) == ["parameter"]
    end

    test "the arke flag exports arkes only" do
      data = Export.get_data(:test_schema, arke: true)

      assert ids(data.arke) == ["export_arke"]
      assert data.group == []
      assert data.parameter == []
    end

    test "the parameter flag exports parameters only" do
      data = Export.get_data(:test_schema, parameter: true)

      assert data.arke == []
      assert data.group == []
      assert ids(data.parameter) == ["export_string"]
    end

    test "the group flag exports groups only" do
      data = Export.get_data(:test_schema, group: true)

      assert data.arke == []
      assert ids(data.group) == ["export_group"]
      assert data.parameter == []
    end

    test "links come along with any flag" do
      data = Export.get_data(:test_schema, arke: true)

      assert Enum.map(data.permission, & &1.data.type) == ["permission"]
      assert Enum.map(data.arke_parameter, & &1.data.type) == ["parameter"]
    end

    test "a project with nothing in it" do
      data = Export.get_data(:empty_schema, [])

      assert data.arke == []
      assert data.group == []
      assert data.parameter == []
      assert data.permission == []
      assert data.arke_parameter == []
    end
  end

  describe "get_db_structure/2" do
    test "shapes the export for seed_project" do
      structure = Export.get_db_structure(:test_schema)

      assert [%{id: "export_arke", label: "Export Arke", parameters: parameters}] = structure.arke
      assert parameters == [%{id: "export_string", metadata: %{required: true}}]

      assert [%{id: "export_group", label: "Export Group", description: "a group"}] =
               structure.group

      assert [%{id: "export_string", type: "string", label: "Export String"}] =
               structure.parameter

      assert structure.link == [
               %{
                 parent: "export_arke",
                 child: "export_string",
                 type: "permission",
                 metadata: %{get: true}
               }
             ]
    end

    test "an empty project shapes to empty lists" do
      assert Export.get_db_structure(:empty_schema) ==
               %{arke: [], group: [], parameter: [], link: []}
    end
  end
end
