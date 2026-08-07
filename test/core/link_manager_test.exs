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

    test "should create with binary ids" do
      {:ok, link} =
        LinkManager.add_node(
          :test_schema,
          "test_unit_arke_1",
          "test_unit_arke_2",
          "link_test",
          %{}
        )

      assert link.data.parent_id == "test_unit_arke_1"
      assert link.data.child_id == "test_unit_arke_2"
    end

    test "create with an unknown binary id" do
      assert {:error, [%{context: "link", message: message}]} =
               LinkManager.add_node(:test_schema, "nope", "test_unit_arke_2", "link_test", %{})

      assert message == "parent: `nope` or child: `test_unit_arke_2` not found"
    end

    test "create the same link twice", %{unit_1: unit_1, unit_2: unit_2} do
      {:ok, _link} = LinkManager.add_node(:test_schema, unit_1, unit_2, "link_test", %{})

      assert LinkManager.add_node(:test_schema, unit_1, unit_2, "link_test", %{}) ==
               {:error, [%{context: "link", message: "link already exists"}]}
    end

    test "create with invalid parameters" do
      assert LinkManager.add_node(:test_schema, :not_a_unit, :not_a_unit, "link_test", %{}) ==
               {:error, [%{context: "link", message: "invalid parameters"}]}
    end

    test "should update with %Unit{}", %{unit_1: unit_1, unit_2: unit_2} do
      {:ok, _link} = LinkManager.add_node(:test_schema, unit_1, unit_2, "link_test", %{})

      {:ok, updated} =
        LinkManager.update_node(:test_schema, unit_1, unit_2, "link_test", %{order: 2})

      assert updated.data.type == "link_test"
      assert updated.metadata.order == 2
      assert updated.metadata.project == :test_schema
    end

    test "should update with binary ids", %{unit_1: unit_1, unit_2: unit_2} do
      {:ok, _link} = LinkManager.add_node(:test_schema, unit_1, unit_2, "link_test", %{})

      {:ok, updated} =
        LinkManager.update_node(
          :test_schema,
          "test_unit_arke_1",
          "test_unit_arke_2",
          "link_test",
          %{order: 3}
        )

      assert updated.metadata.order == 3
    end

    test "update a link that does not exist", %{unit_1: unit_1, unit_2: unit_2} do
      assert LinkManager.update_node(:test_schema, unit_1, unit_2, "link_test", %{}) ==
               {:error, [%{context: "link", message: "link not found"}]}
    end

    test "update with an unknown binary id" do
      assert LinkManager.update_node(:test_schema, "nope", "nope_either", "link_test", %{}) ==
               {:error, [%{context: "link", message: "invalid parameters"}]}
    end

    test "update with invalid parameters" do
      assert LinkManager.update_node(:test_schema, :not_a_unit, :not_a_unit, "link_test", %{}) ==
               {:error, [%{context: "link", message: "invalid parameters"}]}
    end

    test "should delete with %Unit{}", %{unit_1: unit_1, unit_2: unit_2} do
      {:ok, link} = LinkManager.add_node(:test_schema, unit_1, unit_2, "link_test", %{})

      assert LinkManager.delete_node(:test_schema, unit_1, unit_2, "link_test") == {:ok, nil}
      assert QueryManager.get_by(id: link.id, project: :test_schema) == nil
    end

    test "should delete with binary ids", %{unit_1: unit_1, unit_2: unit_2} do
      {:ok, link} = LinkManager.add_node(:test_schema, unit_1, unit_2, "link_test", %{})

      assert LinkManager.delete_node(
               :test_schema,
               "test_unit_arke_1",
               "test_unit_arke_2",
               "link_test"
             ) == {:ok, nil}

      assert QueryManager.get_by(id: link.id, project: :test_schema) == nil
    end

    test "delete a link that does not exist", %{unit_1: unit_1, unit_2: unit_2} do
      assert LinkManager.delete_node(:test_schema, unit_1, unit_2, "link_test") ==
               {:error, [%{context: "link", message: "link not found"}]}
    end

    test "delete with an unknown binary id" do
      assert LinkManager.delete_node(:test_schema, "nope", "nope_either", "link_test") ==
               {:error, [%{context: "link", message: "invalid parameters"}]}
    end

    test "delete with invalid parameters" do
      assert LinkManager.delete_node(:test_schema, :not_a_unit, :not_a_unit, "link_test") ==
               {:error, [%{context: "link", message: "invalid parameters"}]}
    end

    # add_node resolves arke_link from `project`, update_node and delete_node
    # resolve it from :arke_system. Both land on the same unit only because
    # manager lookups fall back to :arke_system. Pinned as it stands.
    test "a link created in the project is found by update and delete", %{
      unit_1: unit_1,
      unit_2: unit_2
    } do
      {:ok, _link} = LinkManager.add_node(:test_schema, unit_1, unit_2, "link_test", %{})

      assert {:ok, _} = LinkManager.update_node(:test_schema, unit_1, unit_2, "link_test", %{})
      assert {:ok, nil} = LinkManager.delete_node(:test_schema, unit_1, unit_2, "link_test")
    end
  end
end
