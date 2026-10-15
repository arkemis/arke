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

    test "edit Arke keeps the manager's parameters and module" do
      arke_model = ArkeManager.get(:arke, :arke_system)
      QueryManager.create(:test_schema, arke_model, %{id: "test", label: "Test Arke"})

      old_arke = ArkeManager.get(:test, :test_schema)
      assert old_arke.data.parameters != []

      # A unit loaded from persistence, as arke_server does, has no parameters or module.
      db_arke =
        QueryManager.query(project: :test_schema, arke: :arke)
        |> QueryManager.where(id: "test")
        |> QueryManager.one()

      {:ok, _} = QueryManager.update(db_arke, %{label: "Renamed", active: false})

      arke = ArkeManager.get(:test, :test_schema)
      assert arke.data.label == "Renamed"
      assert arke.data.active == false
      assert arke.data.parameters == old_arke.data.parameters
      assert arke.__module__ == old_arke.__module__
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
end
