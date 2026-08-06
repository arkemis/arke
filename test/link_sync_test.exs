defmodule Arke.LinkSyncTest do
  @moduledoc """
  Phase 0 of PLAN-transactions: link-parameter sync failures must surface as
  `{:error, _}` from create/update instead of being swallowed.
  """
  use Arke.Test.RepoCase

  @project :test_schema

  defp support_arke, do: ArkeManager.get(:arke_test_support, :arke_system)

  defp create_unit(id, args) do
    base = [id: id, enum_integer_support: [1]]
    QueryManager.create(@project, support_arke(), Keyword.merge(base, args))
  end

  defp create_target(id) do
    {:ok, unit} =
      create_unit(id, string_support: "target-#{id}", enum_string_support: "first")

    unit
  end

  test "create with a link to an existing unit succeeds and writes the link" do
    create_target("link_target")

    assert {:ok, unit} =
             create_unit("link_source",
               string_support: "source",
               enum_string_support: "second",
               link_support: "link_target"
             )

    link =
      QueryManager.query(project: @project, arke: :arke_link)
      |> QueryManager.filter(:parent_id, :eq, "link_source", false)
      |> QueryManager.filter(:child_id, :eq, "link_target", false)
      |> QueryManager.one()

    assert link != nil
    assert Unit.get_value(unit, :link_support) == "link_target"
  end

  test "create with a link to a missing unit returns {:error, _}" do
    assert {:error, _} = create_unit("bad_link_source", link_support: "does_not_exist")
  end

  test "update that flips a link to a missing unit returns {:error, _}" do
    create_target("upd_target")

    {:ok, unit} =
      create_unit("upd_source",
        string_support: "source",
        enum_string_support: "second",
        link_support: "upd_target"
      )

    assert {:error, _} = QueryManager.update(unit, link_support: "does_not_exist")
  end

  test "create with a multiple link where one target is missing returns {:error, _}" do
    create_target("multi_target")

    assert {:error, _} =
             create_unit("multi_source",
               string_support: "source",
               enum_string_support: "second",
               multi_link_support: ["multi_target", "does_not_exist"]
             )
  end
end
