defmodule Mix.Tasks.Arke.SeedProjectTest do
  use Arke.Test.RepoCase

  @moduletag :tmp_dir

  @project :seed_test

  # The task discovers arke's registry through `EX_DEP_ARKE_PATH`, so pointing it
  # at a tmp dir swaps the real registry for the fixture below. Managers are
  # already bootstrapped from the real registry (see `test_helper.exs`) and
  # manager lookups fall back to `:arke_system`, so `arke`, `group` and the
  # parameter types still resolve.
  setup %{tmp_dir: tmp_dir} do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Quiet)
    System.put_env("EX_DEP_ARKE_PATH", tmp_dir)

    on_exit(fn ->
      Mix.shell(shell)
      System.delete_env("EX_DEP_ARKE_PATH")
    end)

    :ok
  end

  describe "run/1" do
    test "seeds parameters, arkes, groups and their links", %{tmp_dir: tmp_dir} do
      write_registry(tmp_dir, ["seed_name", "seed_code"], ["seed_item"])
      seed()

      assert %Unit{arke_id: :string} = QueryManager.get_by(id: "seed_name", project: @project)

      assert %Unit{data: %{label: "Seed item"}} =
               QueryManager.get_by(id: "seed_item", project: @project)

      assert linked("parameter", "seed_item") == ["seed_code", "seed_name"]

      assert %Unit{data: %{arke_list: ["seed_item"]}} =
               QueryManager.get_by(id: "seed_group", project: @project)

      assert linked("group", "seed_group") == ["seed_item"]
    end

    test "re-seeding updates an arke's parameters and a group's arke_list", %{tmp_dir: tmp_dir} do
      write_registry(tmp_dir, ["seed_name", "seed_code"], ["seed_item"])
      seed()
      resolve_parameter_links("seed_item")

      # seed_code dropped, seed_extra added; seed_other joins the group
      write_registry(tmp_dir, ["seed_name", "seed_extra"], ["seed_item", "seed_other"])
      seed()

      assert linked("parameter", "seed_item") == ["seed_extra", "seed_name"]

      assert %Unit{data: %{arke_list: ["seed_item", "seed_other"]}} =
               QueryManager.get_by(id: "seed_group", project: @project)

      assert linked("group", "seed_group") == ["seed_item", "seed_other"]
    end

    test "rejects an unsupported format", %{tmp_dir: tmp_dir} do
      write_registry(tmp_dir, [], [])

      assert_raise Mix.Error, ~r/Invalid format: `xml`/, fn ->
        Mix.Tasks.Arke.SeedProject.run(["--project", to_string(@project), "--format", "xml"])
      end
    end
  end

  defp seed, do: Mix.Tasks.Arke.SeedProject.run(["--project", to_string(@project)])

  defp write_registry(tmp_dir, item_parameters, group_arke_list) do
    contents = %{
      parameter:
        Enum.map(["seed_name", "seed_code", "seed_extra"], fn id ->
          %{
            id: id,
            type: "string",
            label: String.capitalize(id),
            persistence: "arke_parameter"
          }
        end),
      arke: [
        %{
          id: "seed_item",
          label: "Seed item",
          parameters: Enum.map(item_parameters, &%{id: &1})
        },
        %{id: "seed_other", label: "Seed other", parameters: []}
      ],
      group: [%{id: "seed_group", label: "Seed group", arke_list: group_arke_list}]
    }

    dir = Path.join([tmp_dir, "lib", "registry", "shared"])
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "registry.json"), Jason.encode!(contents))
  end

  defp linked(type, parent) do
    QueryManager.filter_by(arke_id: :arke_link, project: @project)
    |> Enum.filter(&(&1.data.type == type and &1.data.parent_id == parent))
    |> Enum.map(& &1.data.child_id)
    |> Enum.sort()
  end

  # `arke_postgres` fills an arke's `parameters` from its links when it loads the
  # unit; the in-memory store doesn't, and the update path diffs against it.
  defp resolve_parameter_links(arke_id) do
    unit = QueryManager.get_by(id: arke_id, project: @project)

    parameters =
      Enum.map(linked("parameter", arke_id), &%{id: String.to_atom(&1), metadata: %{}})

    Arke.Test.Persistence.update(@project, Unit.update(unit, parameters: parameters))
  end
end
