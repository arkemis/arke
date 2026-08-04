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

    test "update" do
      group_model = ArkeManager.get(:group, :arke_system)
      arke_model = ArkeManager.get(:arke, :arke_system)
      QueryManager.create(:test_schema, arke_model, %{id: "group_member", label: "Group Member"})

      {:ok, group} =
        QueryManager.create(:test_schema, group_model, %{
          id: "group_test_update",
          label: "Group"
        })

      {:ok, updated} = QueryManager.update(group, %{arke_list: ["group_member"]})

      assert Enum.map(updated.data.arke_list, & &1.id) == [:group_member]

      # Behaviour as it stands: `on_update` writes the arke_list, then the link
      # parameter handling creates a "group" link whose `on_create` appends the
      # same arke again. Pinned, not endorsed — the entry lands twice.
      assert GroupManager.get(:group_test_update, :test_schema).data.arke_list
             |> Enum.map(& &1.id)
             |> Enum.sort() == [:group_member, :group_member]
    end
  end

  describe "handle_link_init/2" do
    test "wraps a binary id" do
      assert Arke.Core.Group.handle_link_init("member", :arke_list) ==
               %{id: :member, metadata: %{"parameter_id" => "arke_list"}}
    end

    test "wraps an atom id" do
      assert Arke.Core.Group.handle_link_init(:member, :arke_list) ==
               %{id: :member, metadata: %{"parameter_id" => "arke_list"}}
    end

    test "leaves anything else untouched" do
      already_wrapped = %{id: :member, metadata: %{"parameter_id" => "arke_list"}}
      assert Arke.Core.Group.handle_link_init(already_wrapped, :arke_list) == already_wrapped
    end
  end
end
