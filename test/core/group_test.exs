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

    test "update" do
      group_model = ArkeManager.get(:group, :arke_system)

      QueryManager.create(:test_schema, group_model, %{id: "group_test_edit", name: "group_test"})
      before_update = GroupManager.get(:group_test_edit, :test_schema)
      QueryManager.update(before_update, %{label: "edit_label"})
      updated_group = GroupManager.get(:group_test_edit, :test_schema)

      assert before_update.data.label == nil
      assert updated_group.data.label == "edit_label"
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
