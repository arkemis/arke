defmodule Arke.Core.LinkManagerTest do
  use Arke.Test.RepoCase

  defp create_units(_) do
    arke_model = ArkeManager.get(:arke, :arke_system)

    QueryManager.create(:test_schema, arke_model, %{
      id: "test_arke_link_1",
      label: "Test Arke Link 1"
    })

    new_arke_model = ArkeManager.get(:test_arke_link_1, :test_schema)

    {:ok, unit_1} =
      QueryManager.create(:test_schema, new_arke_model, %{
        id: "test_unit_arke_1",
        label: "Test Unit 1"
      })

    QueryManager.create(:test_schema, arke_model, %{
      id: "test_arke_link_2",
      label: "Test Arke Link 2"
    })

    new_arke_model = ArkeManager.get(:test_arke_link_2, :test_schema)

    {:ok, unit_2} =
      QueryManager.create(:test_schema, new_arke_model, %{
        id: "test_unit_arke_2",
        label: "Test Unit 2"
      })

    {:ok, unit_1: unit_1, unit_2: unit_2}
  end

  describe "Link" do
    setup [:create_units]

    test "should create with %Unit{}", %{unit_1: unit_1, unit_2: unit_2} do
      {:ok, link} = LinkManager.add_node(:test_schema, unit_1, unit_2, "link_test", %{})

      # Keep error until fixme is resolved
      assert link.data.parent_id == to_string(unit_1.id)
      assert link.data.child_id == to_string(unit_2.id)
      assert link.data.type == "link_test"
      assert link.metadata.project == :test_schema
    end
  end
end
