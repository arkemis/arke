defmodule Arke.Boundary.ArkeTest do
  use Arke.Test.RepoCase

  describe "ArkeManager" do
    test "get_all/0" do
      all = ArkeManager.get_all()

      assert all != []
      assert Enum.all?(all, fn {id, project} -> is_atom(id) and project == :arke_system end)
      assert {:arke, :arke_system} in all
    end

    test "get_all/1" do
      assert is_list(ArkeManager.get_all(:invalid_project)) == true and
               ArkeManager.get_all(:invalid_project) == []
    end

    test "get/2" do
      assert ArkeManager.get(:arke, :arke_system).id == :arke and
               ArkeManager.get(:arke, :arke_system).metadata.project == :arke_system
    end

    test "get/2 (error)" do
      assert ArkeManager.get(:not_valid, :arke_system) == nil
    end

    test "create/1 " do
      data = [id: "arke_test", label: "Arke test"]
      arke = ArkeManager.get(:arke, :arke_system)
      unit = Unit.load(arke, data)
      assert %Arke.Core.Unit{} = ArkeManager.create(unit)

      assert %Arke.Core.Unit{} = ArkeManager.get(:arke_test, :arke_system)
    end

    test "create/2 " do
      data = [id: :arke_test_create, label: "Arke test"]
      arke = ArkeManager.get(:arke, :arke_system)
      unit = Unit.load(arke, data)
      assert %Arke.Core.Unit{} = ArkeManager.create(unit, :another_project)

      assert %Arke.Core.Unit{} = ArkeManager.get(:arke_test_create, :another_project)
      assert ArkeManager.get(:not_exist, :arke_system) == nil
    end

    test "get_parameters/0" do
      arke = ArkeManager.get(:arke, :arke_system)
      assert length(ArkeManager.get_parameters(arke)) > 0
    end

    test "get_parameter/3" do
      arke = ArkeManager.get(:arke, :arke_system)
      assert %Arke.Core.Unit{} = ArkeManager.get_parameter(arke, "label")
      assert %Arke.Core.Unit{} = ArkeManager.get_parameter(arke, :metadata)
      assert %Arke.Core.Unit{} = ArkeManager.get_parameter(:arke, :arke_system, :active)
      assert nil == ArkeManager.get_parameter(arke, :not_a_parameter)
    end
  end
end
