defmodule Arke.Boundary.FileManagerTest do
  # RepoCase for the sandbox: the cache is a named ETS table, so entries would
  # otherwise outlive the test that added them.
  use Arke.Test.RepoCase

  alias Arke.Boundary.FileManager

  defp live, do: System.os_time(:second) + 100

  test "get_all/1 returns entries for the given project only" do
    now = System.os_time(:second)
    FileManager.add(:fm_a, :fm_proj, "url_a", now + 100)
    FileManager.add(:fm_b, :fm_proj, "url_b", now + 100)
    FileManager.add(:fm_c, :fm_other, "url_c", now + 100)

    entries = FileManager.get_all(:fm_proj)

    assert Enum.sort(Enum.map(entries, & &1.unit_id)) == [:fm_a, :fm_b]
    assert Enum.map(Enum.sort_by(entries, & &1.unit_id), & &1.signed_url) == ["url_a", "url_b"]
  end

  test "get_all/1 on a project with nothing cached" do
    assert FileManager.get_all(:fm_empty) == []
  end

  test "cleanup purges expired entries and keeps live ones" do
    now = System.os_time(:second)
    FileManager.add(:fm_expired, :fm_cleanup, "old", now - 10)
    FileManager.add(:fm_live, :fm_cleanup, "new", now + 100)

    send(FileManager, :cleanup)
    :sys.get_state(FileManager)

    assert FileManager.get(:fm_expired, :fm_cleanup) == nil
    assert FileManager.get(:fm_live, :fm_cleanup).signed_url == "new"
  end

  test "cleanup with nothing to purge" do
    FileManager.add(:fm_live, :fm_cleanup, "new", live())

    send(FileManager, :cleanup)
    :sys.get_state(FileManager)

    assert FileManager.get(:fm_live, :fm_cleanup).signed_url == "new"
  end

  test "add/2 and remove/1 take a unit" do
    unit = %{id: :fm_unit, metadata: %{project: :fm_proj}}
    expiration = live()

    assert FileManager.add(unit, %{signed_url: "url", expiration: expiration}) == :ok
    assert FileManager.get(:fm_unit, :fm_proj) == %{signed_url: "url", expiration: expiration}

    assert FileManager.remove(unit) == :ok
    assert FileManager.get(:fm_unit, :fm_proj) == nil
  end

  test "remove/2 on something that was never cached" do
    assert FileManager.remove(:fm_never, :fm_proj) == :ok
  end

  test "get/2 accepts a string id" do
    FileManager.add(:fm_string, :fm_proj, "url", live())

    assert FileManager.get("fm_string", :fm_proj).signed_url == "url"
  end

  test "get/2 on a string that is not an existing atom" do
    assert FileManager.get("fm_no_such_atom_anywhere", :fm_proj) == nil
  end

  test "reset/0 empties the cache" do
    FileManager.add(:fm_reset, :fm_proj, "url", live())

    assert FileManager.reset() == :ok
    assert FileManager.get(:fm_reset, :fm_proj) == nil
  end
end
