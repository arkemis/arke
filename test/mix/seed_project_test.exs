defmodule Mix.Tasks.Arke.SeedProjectTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Arke.SeedProject

  # deps/ as Hex lays it out: the arke* glob matches both packages
  setup do
    root = Path.join(System.tmp_dir!(), "arke_seed_#{System.unique_integer([:positive])}")

    write = fn dep, data ->
      dir = Path.join([root, "deps", dep, "lib", "registry", "system"])
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "#{dep}.json"), Jason.encode!(data))
    end

    write.("arke", %{
      parameter: [%{id: "core_param"}],
      arke: [%{id: "core_arke"}],
      link: [%{type: "parameter", parent: "core_arke", child: "core_param"}]
    })

    write.("arke_auth", %{parameter: [%{id: "auth_param"}]})

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "core_registry_data/2 returns each unit and link once", %{root: root} do
    data =
      File.cd!(root, fn ->
        SeedProject.core_registry_data("json", [{:arke_auth, "~> 0.6"}, {:jason, "~> 1.0"}])
      end)

    assert data.parameter |> Enum.map(& &1.id) |> Enum.sort() == ["auth_param", "core_param"]
    assert Enum.map(data.arke, & &1.id) == ["core_arke"]
    assert length(data.link) == 1
  end
end
