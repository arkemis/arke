defmodule Arke.Boundary.GroupManagerTest do
  use Arke.Test.RepoCase

  alias Arke.LinkManager

  describe "GroupManager" do
    test "link arke to group" do
      # Create arke
      arke_model = ArkeManager.get(:arke, :arke_system)
      arke_data = [id: :test_arke_group, label: "Arke test"]
      arke_unit = ArkeManager.create(Unit.load(arke_model, arke_data), :test_schema)

      # Create group
      group_model = ArkeManager.get(:group, :arke_system)
      group_data = [id: "group_test", name: "group_test"]
      group_unit = GroupManager.create(Unit.load(group_model, group_data), :test_schema)

      {:ok, link_unit} =
        LinkManager.add_node(
          :test_schema,
          group_unit,
          arke_unit,
          "group"
        )

      assert link_unit.data.type == "group"
      assert link_unit.data.parent_id == "group_test"
      assert link_unit.data.child_id == "test_arke_group"
    end

    test "get_groups_by_arke/1 (‰Arke.Core.Unit{})" do
      # Create arke
      arke_model = ArkeManager.get(:arke, :arke_system)
      arke_data = [id: :test_arke_group, label: "Arke test"]
      arke_unit = ArkeManager.create(Unit.load(arke_model, arke_data), :test_schema)

      # Create group
      group_model = ArkeManager.get(:group, :arke_system)
      group_data = [id: "group_test", name: "group_test"]
      group_unit = GroupManager.create(Unit.load(group_model, group_data), :test_schema)

      LinkManager.add_node(:test_schema, group_unit, arke_unit, "group")

      arke_list = GroupManager.get_groups_by_arke(arke_unit)

      assert is_list(arke_list) == true
      assert List.first(arke_list).id == :group_test
    end

    test "get_groups_by_arke/2 (atoms)" do
      # Create arke
      arke_model = ArkeManager.get(:arke, :arke_system)
      arke_data = [id: :test_arke_group, label: "Arke test"]
      arke_unit = Unit.load(arke_model, arke_data)
      ArkeManager.create(arke_unit, :test_schema)

      # Create group
      group_model = ArkeManager.get(:group, :arke_system)
      group_data = [id: "group_test", name: "group_test"]
      group_unit = Unit.load(group_model, group_data)
      GroupManager.create(group_unit, :test_schema)

      LinkManager.add_node(:test_schema, group_unit, arke_unit, "group")

      arke_list = GroupManager.get_groups_by_arke(:test_arke_group, :test_schema)

      assert is_list(arke_list) == true
      assert length(arke_list) > 0
      assert List.first(List.first(arke_list).data.arke_list).id == :test_arke_group
    end

    test "get_parameters/1 (‰Arke.Core.Unit{})" do
      # Create arke, with a parameter of its own
      arke_model = ArkeManager.get(:arke, :arke_system)
      arke_data = [id: :test_arke_group, label: "Arke test"]
      arke_unit = ArkeManager.create(Unit.load(arke_model, arke_data), :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke_unit,
        ParameterManager.get(:name, :arke_system),
        "parameter",
        %{}
      )

      # Create group
      group_model = ArkeManager.get(:group, :arke_system)
      group_data = [id: "group_test", name: "group_test"]
      group_unit = GroupManager.create(Unit.load(group_model, group_data), :test_schema)

      LinkManager.add_node(:test_schema, group_unit, arke_unit, "group")

      parameters = GroupManager.get_parameters(GroupManager.get(:group_test, :test_schema))
      name_parameter = Enum.find(parameters, fn el -> el.id == :name end)

      assert is_list(parameters) == true
      assert name_parameter.arke_id == :string
      assert name_parameter.data.format == "attribute"
    end

    test "get_parameters/1 (atoms)" do
      # Create arke, with a parameter of its own
      arke_model = ArkeManager.get(:arke, :arke_system)
      arke_data = [id: :test_arke_group, label: "Arke test"]
      arke_unit = ArkeManager.create(Unit.load(arke_model, arke_data), :test_schema)

      LinkManager.add_node(
        :test_schema,
        arke_unit,
        ParameterManager.get(:name, :arke_system),
        "parameter",
        %{}
      )

      # Create group
      group_model = ArkeManager.get(:group, :arke_system)
      group_data = [id: "group_test", name: "group_test"]
      group_unit = GroupManager.create(Unit.load(group_model, group_data), :test_schema)

      LinkManager.add_node(:test_schema, group_unit, arke_unit, "group")

      parameters = GroupManager.get_parameters(:group_test, :test_schema)
      name_parameter = Enum.find(parameters, fn el -> el.id == :name end)

      assert is_list(parameters) == true
      assert name_parameter.arke_id == :string
      assert name_parameter.data.format == "attribute"
    end
  end

  describe "GroupManager error paths" do
    setup do
      arke_model = ArkeManager.get(:arke, :arke_system)
      arke_data = [id: :test_arke_group, label: "Arke test"]
      arke_unit = ArkeManager.create(Unit.load(arke_model, arke_data), :test_schema)

      group_model = ArkeManager.get(:group, :arke_system)
      group_data = [id: "group_test", label: "group_test"]
      group_unit = GroupManager.create(Unit.load(group_model, group_data), :test_schema)

      LinkManager.add_node(:test_schema, group_unit, arke_unit, "group")

      {:ok, arke: arke_unit, group: GroupManager.get(:group_test, :test_schema)}
    end

    test "get_arke_list/1 on something that is not a unit" do
      assert GroupManager.get_arke_list(%{}) ==
               {:error, [%{context: "group", message: "invalid unit"}]}
    end

    test "get_arke_list/1 on an arke that is no longer registered", %{group: group} do
      ArkeManager.remove(:test_arke_group, :test_schema)

      # the skip branch keys off {:error, msg}, but ArkeManager.get/2 returns
      # nil for an unknown id. Pinned, not endorsed.
      assert_raise FunctionClauseError, fn -> GroupManager.get_arke_list(group) end
    end

    test "get_arke/3 finds a linked arke", %{group: group} do
      assert GroupManager.get_arke(group, :test_arke_group).id == :test_arke_group

      assert GroupManager.get_arke(:group_test, :test_schema, "test_arke_group").id ==
               :test_arke_group
    end

    test "get_arke/3 on an arke that is not in the group", %{group: group} do
      assert GroupManager.get_arke(group, :arke) == nil
    end

    test "get_arke/3 on an unknown group" do
      # same nil-instead-of-{:error, msg} mismatch: get/2 returns nil, which
      # get_arke_list/1 answers with an error tuple that Enum.find cannot walk
      assert_raise Protocol.UndefinedError, fn ->
        GroupManager.get_arke(:not_a_group, :test_schema, :arke)
      end
    end

    test "get_arke/3 passes a unit through", %{arke: arke} do
      assert GroupManager.get_arke(:not_a_group, :test_schema, arke) == arke
    end

    test "remove/2 on an unknown group" do
      assert GroupManager.remove(:not_a_group, :test_schema) ==
               {:error, "not_a_group doesn't exist in project: test_schema"}
    end

    test "get/2 on a nil id" do
      assert GroupManager.get(nil, :test_schema) == nil
    end
  end
end
