defmodule Arke.Core.GroupTest do
  use Arke.Test.RepoCase

  describe "Group CRUD" do
    test "create" do
      group_model = ArkeManager.get(:group, :arke_system)

      before_create = GroupManager.get(:group_test, :test_schema)

      QueryManager.create(:test_schema, group_model, %{id: "group_test", name: "group_test"})
      after_create = GroupManager.get(:group_test, :test_schema)

      assert before_create == nil

      assert after_create.arke_id == :group
      assert after_create.id == :group_test
    end

    test "create with arke_list registers the members in the manager" do
      group_model = ArkeManager.get(:group, :arke_system)

      QueryManager.create(:test_schema, group_model, %{
        id: "group_test_members",
        name: "group_test_members",
        arke_list: ["arke_test_support"]
      })

      members = GroupManager.get(:group_test_members, :test_schema).data.arke_list
      assert Enum.map(members, & &1.id) == [:arke_test_support]
    end

    test "update from a persisted unit keeps the manager's module and arke_list" do
      QueryManager.create(:test_schema, ArkeManager.get(:arke, :arke_system), %{
        id: "group_member",
        label: "Group Member"
      })

      QueryManager.create(:test_schema, ArkeManager.get(:group, :arke_system), %{
        id: "group_update",
        label: "Group",
        arke_list: ["group_member"]
      })

      old_group = GroupManager.get(:group_update, :test_schema)

      db_group =
        QueryManager.query(project: :test_schema, arke: :group)
        |> QueryManager.where(id: "group_update")
        |> QueryManager.one()

      {:ok, _} = QueryManager.update(db_group, %{label: "Renamed"})

      group = GroupManager.get(:group_update, :test_schema)
      assert group.data.label == "Renamed"
      assert group.__module__ == old_group.__module__
      assert Enum.map(group.data.arke_list, & &1.id) == [:group_member]
    end

    test "delete" do
      group_model = ArkeManager.get(:group, :arke_system)

      {:ok, unit} =
        QueryManager.create(:test_schema, group_model, %{
          id: "group_test_delete",
          name: "group_test"
        })

      before_delete = GroupManager.get(:group_test_delete, :test_schema)

      QueryManager.delete(:test_schema, unit)
      after_delete = GroupManager.get(:group_test_delete, :test_schema)

      assert before_delete.id == :group_test_delete

      assert after_delete == nil
    end
  end
end
