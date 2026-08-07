defmodule Arke.Core.LinkTest do
  use Arke.Test.RepoCase

  defp create_units(_) do
    arke_model = ArkeManager.get(:arke, :arke_system)
    string_model = ArkeManager.get(:string, :arke_system)
    group_model = ArkeManager.get(:group, :arke_system)

    QueryManager.create(:test_schema, arke_model, %{id: "hook_arke", label: "Hook Arke"})

    QueryManager.create(:test_schema, string_model, %{
      id: "hook_string",
      label: "Hook String",
      max_length: 10
    })

    QueryManager.create(:test_schema, group_model, %{id: "hook_group", label: "Hook Group"})

    {:ok,
     arke: ArkeManager.get(:hook_arke, :test_schema),
     parameter: ParameterManager.get(:hook_string, :test_schema),
     group: GroupManager.get(:hook_group, :test_schema)}
  end

  defp arke_parameter_ids do
    ArkeManager.get(:hook_arke, :test_schema).data.parameters
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  defp group_arke_ids do
    GroupManager.get(:hook_group, :test_schema).data.arke_list
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  describe "on_create" do
    setup [:create_units]

    test "type parameter links the parameter to the arke", %{arke: arke, parameter: parameter} do
      refute :hook_string in arke_parameter_ids()

      {:ok, _link} = LinkManager.add_node(:test_schema, arke, parameter, "parameter", %{})

      assert :hook_string in arke_parameter_ids()
    end

    test "type group links the arke to the group", %{arke: arke, group: group} do
      refute :hook_arke in group_arke_ids()

      {:ok, _link} = LinkManager.add_node(:test_schema, group, arke, "group", %{})

      assert :hook_arke in group_arke_ids()
    end
  end

  describe "on_update" do
    setup [:create_units]

    test "type parameter pushes the link metadata onto the parameter", %{
      arke: arke,
      parameter: parameter
    } do
      {:ok, _link} = LinkManager.add_node(:test_schema, arke, parameter, "parameter", %{})

      assert ArkeManager.get_parameter(arke, :hook_string).data.max_length == 10

      {:ok, _link} =
        LinkManager.update_node(:test_schema, arke, parameter, "parameter", %{max_length: 4})

      updated = ArkeManager.get(:hook_arke, :test_schema)
      assert ArkeManager.get_parameter(updated, :hook_string).data.max_length == 4
    end

    test "any other type leaves the managers alone", %{arke: arke, parameter: parameter} do
      {:ok, _link} = LinkManager.add_node(:test_schema, arke, parameter, "custom", %{})
      before = arke_parameter_ids()

      {:ok, _link} =
        LinkManager.update_node(:test_schema, arke, parameter, "custom", %{max_length: 4})

      assert arke_parameter_ids() == before
    end
  end

  describe "on_delete" do
    setup [:create_units]

    test "type parameter unlinks the parameter from the arke", %{
      arke: arke,
      parameter: parameter
    } do
      {:ok, _link} = LinkManager.add_node(:test_schema, arke, parameter, "parameter", %{})
      assert :hook_string in arke_parameter_ids()

      {:ok, nil} = LinkManager.delete_node(:test_schema, arke, parameter, "parameter")

      refute :hook_string in arke_parameter_ids()

      assert ArkeManager.get_parameter(ArkeManager.get(:hook_arke, :test_schema), :hook_string) ==
               nil
    end

    test "type group unlinks the arke from the group", %{arke: arke, group: group} do
      {:ok, _link} = LinkManager.add_node(:test_schema, group, arke, "group", %{})
      assert :hook_arke in group_arke_ids()

      {:ok, nil} = LinkManager.delete_node(:test_schema, group, arke, "group")

      refute :hook_arke in group_arke_ids()
    end

    test "any other type leaves the managers alone", %{arke: arke, parameter: parameter} do
      {:ok, _link} = LinkManager.add_node(:test_schema, arke, parameter, "custom", %{})
      before = arke_parameter_ids()

      {:ok, nil} = LinkManager.delete_node(:test_schema, arke, parameter, "custom")

      assert arke_parameter_ids() == before
    end
  end
end
