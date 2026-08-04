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

    test "get_parameter/3 on an unknown arke" do
      # `get/2` returns nil for an unknown id, which no clause of the case
      # handles. Pinned, not endorsed.
      assert_raise CaseClauseError, fn ->
        ArkeManager.get_parameter(:not_an_arke, :arke_system, :label)
      end
    end

    test "get_parameter/3 passes a parameter struct through" do
      parameter = ParameterManager.get(:label, :arke_system)
      assert ArkeManager.get_parameter(:arke, :arke_system, parameter) == parameter
    end
  end

  describe "ArkeManager.update_parameter/4" do
    setup do
      arke_model = ArkeManager.get(:arke, :arke_system)

      arke =
        ArkeManager.create(Unit.load(arke_model, id: :test_update_p, label: "P"), :test_schema)

      for parameter_id <- [:name, :label] do
        LinkManager.add_node(
          :test_schema,
          arke,
          ParameterManager.get(parameter_id, :arke_system),
          "parameter",
          %{}
        )
      end

      :ok
    end

    test "overrides the parameter metadata" do
      assert %Arke.Core.Unit{} =
               ArkeManager.update_parameter(:test_update_p, :name, :test_schema, %{
                 max_length: 3
               })

      arke = ArkeManager.get(:test_update_p, :test_schema)
      assert ArkeManager.get_parameter(arke, :name).data.max_length == 3
    end

    test "accepts the parameter id as a string" do
      assert %Arke.Core.Unit{} =
               ArkeManager.update_parameter(:test_update_p, "name", :test_schema, %{
                 max_length: 4
               })

      arke = ArkeManager.get(:test_update_p, :test_schema)
      assert ArkeManager.get_parameter(arke, :name).data.max_length == 4
    end

    test "on an unknown arke" do
      assert ArkeManager.update_parameter(:not_an_arke, :name, :test_schema, %{}) ==
               {:error, [%{context: "unit", message: "unit not_an_arke not found"}]}
    end

    test "leaves the other parameters alone" do
      before = ArkeManager.get_parameter(ArkeManager.get(:test_update_p, :test_schema), :label)
      ArkeManager.update_parameter(:test_update_p, :name, :test_schema, %{max_length: 3})

      after_update =
        ArkeManager.get_parameter(ArkeManager.get(:test_update_p, :test_schema), :label)

      assert after_update.data == before.data
    end
  end

  describe "ArkeManager links" do
    test "add_link on an unknown arke" do
      assert ArkeManager.add_link(:not_an_arke, :test_schema, :parameters, :label, %{}) ==
               {:error, "not_an_arke doesn't exist in project: test_schema"}
    end

    test "remove_link on an unknown arke" do
      assert ArkeManager.remove_link(:not_an_arke, :test_schema, :parameters, :label) ==
               {:error, "not_an_arke doesn't exist in project: test_schema"}
    end

    test "remove_link drops the child from the parameter list" do
      arke_model = ArkeManager.get(:arke, :arke_system)
      arke = ArkeManager.create(Unit.load(arke_model, id: :test_unlink, label: "U"), :test_schema)
      ArkeManager.add_link(arke, :parameters, :name, %{})

      assert :name in Enum.map(ArkeManager.get_link(arke, :parameters), & &1.id)

      ArkeManager.remove_link(:test_unlink, :test_schema, :parameters, :name)

      refute :name in Enum.map(
               ArkeManager.get_link(:test_unlink, :test_schema, :parameters),
               & &1.id
             )
    end

    test "get_link on an unknown arke" do
      assert ArkeManager.get_link(:not_an_arke, :test_schema, :parameters) ==
               {:error, "not_an_arke doesn't exist in project: test_schema"}
    end
  end

  describe "ArkeManager.remove/2" do
    test "on an unknown arke" do
      assert ArkeManager.remove(:not_an_arke, :test_schema) ==
               {:error, "not_an_arke doesn't exist in project: test_schema"}
    end
  end
end
