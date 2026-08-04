defmodule Arke.Core.ArkeTest do
  use Arke.Test.RepoCase

  describe "Arke CRUD" do
    test "create Arke" do
      arke_model = ArkeManager.get(:arke, :arke_system)

      {:ok, unit_created} =
        QueryManager.create(:test_schema, arke_model, %{id: "test", label: "Test Arke"})

      assert unit_created.id == :test
      assert ArkeManager.get(:test, :test_schema).id == :test
    end

    test "create Arke (error) " do
      arke_model = ArkeManager.get(:arke, :arke_system)
      {:error, msg} = QueryManager.create(:test_schema, arke_model, %{id: 1234})
      assert List.first(msg)[:context] == "parameter_validation"
    end

    test "edit Arke" do
      arke_model = ArkeManager.get(:arke, :arke_system)
      QueryManager.create(:test_schema, arke_model, %{id: "test", label: "Test Arke"})

      old_arke = ArkeManager.get(:test, :test_schema)
      {:ok, edit_arke} = QueryManager.update(old_arke, %{label: "Test Arke modificato"})

      assert old_arke.id == edit_arke.id and
               String.downcase(edit_arke.data.label) == "test arke modificato"
    end

    test "edit Arke (error)" do
      arke_model = ArkeManager.get(:arke, :arke_system)
      QueryManager.create(:test_schema, arke_model, %{id: "test", label: "Test Arke"})

      old_arke = ArkeManager.get(:test, :test_schema)

      assert {:error, _msg} = QueryManager.update(old_arke, %{label: 1234})
      assert ArkeManager.get(:test, :test_schema) == old_arke
    end

    test "delete Arke" do
      arke_model = ArkeManager.get(:arke, :arke_system)
      QueryManager.create(:test_schema, arke_model, %{id: "test2", label: "Test Arke"})
      arke = ArkeManager.get(:test2, :test_schema)
      assert arke.id == :test2

      assert QueryManager.delete(:test_schema, arke) == {:ok, nil}

      assert ArkeManager.get(:test2, :test_schema) == nil
    end

    test "delete Arke (error)" do
      assert_raise FunctionClauseError, fn ->
        QueryManager.delete(:test_schema, QueryManager.get_by(id: "test2", project: :test_schema))
      end
    end
  end

  describe "check_base_parameters/2" do
    test "fills an empty parameter list with the table columns of the model" do
      unit = Unit.load(ArkeManager.get(:arke, :arke_system), %{id: "test_base", parameters: []})

      # arke_link is the model whose parameters carry persistence: table_column
      parameters =
        ArkeManager.get(:arke_link, :arke_system)
        |> Arke.Core.Arke.check_base_parameters(unit)
        |> Map.fetch!(:data)
        |> Map.fetch!(:parameters)
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert parameters == [:child_id, :metadata, :parent_id, :type]
    end

    test "leaves a non-empty parameter list untouched" do
      arke_model = ArkeManager.get(:arke, :arke_system)
      parameters = [%{id: :label, metadata: %{}}]
      unit = Unit.load(arke_model, %{id: "test_base", parameters: parameters})

      assert Arke.Core.Arke.check_base_parameters(arke_model, unit) == unit
      assert Enum.map(unit.data.parameters, & &1.id) == [:label]
    end
  end

  describe "handle_link_init/2" do
    test "wraps a binary id" do
      assert Arke.Core.Arke.handle_link_init("label", :parameters) ==
               %{id: :label, metadata: %{"parameter_id" => "parameters"}}
    end

    test "wraps an atom id" do
      assert Arke.Core.Arke.handle_link_init(:label, :parameters) ==
               %{id: :label, metadata: %{"parameter_id" => "parameters"}}
    end

    test "leaves anything else untouched" do
      already_wrapped = %{id: :label, metadata: %{"parameter_id" => "parameters"}}
      assert Arke.Core.Arke.handle_link_init(already_wrapped, :parameters) == already_wrapped
    end
  end
end
