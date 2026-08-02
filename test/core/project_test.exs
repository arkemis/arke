defmodule Arke.Core.ProjectTest do
  use Arke.Test.RepoCase

  describe "Project" do
    test "create" do
      project = ArkeManager.get(:arke_project, :arke_system)

      {:ok, unit} =
        QueryManager.create(:arke_system, project, %{
          id: "project_to_delete",
          name: "project_to_delete",
          description: "project to delete",
          type: "postgres_schema",
          label: "Project to delete"
        })

      assert unit.id == :project_to_delete
      assert unit.data.type == "postgres_schema"
      assert unit.arke_id == :arke_project
    end

    test "create (error)" do
      project = ArkeManager.get(:arke_project, :arke_system)

      assert QueryManager.create(:arke_system, project, %{
               id: "invalid_project",
               name: "invalid_project",
               description: "invalid project",
               type: "postgres_schema"
             }) == {:error, [%{context: "parameter_validation", message: "label: is required"}]}
    end

    test "delete" do
      project = ArkeManager.get(:arke_project, :arke_system)

      {:ok, unit} =
        QueryManager.create(:arke_system, project, %{
          id: "project_to_delete",
          name: "project_to_delete",
          description: "project to delete",
          type: "postgres_schema",
          label: "Project to delete"
        })

      assert QueryManager.get_by(id: "project_to_delete", project: :arke_system) != nil
      assert QueryManager.delete(:arke_system, unit) == {:ok, nil}
      assert QueryManager.get_by(id: "project_to_delete", project: :arke_system) == nil
    end
  end
end
