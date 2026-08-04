defmodule Arke.Boundary.FileManagerTest do
  use ExUnit.Case, async: false

  alias Arke.Boundary.FileManager

  test "get_all/1 returns entries for the given project only" do
    now = System.os_time(:second)
    FileManager.add(:fm_a, :fm_proj, "url_a", now + 100)
    FileManager.add(:fm_b, :fm_proj, "url_b", now + 100)
    FileManager.add(:fm_c, :fm_other, "url_c", now + 100)

    entries = FileManager.get_all(:fm_proj)

    assert Enum.sort(Enum.map(entries, & &1.unit_id)) == [:fm_a, :fm_b]
    assert Enum.map(Enum.sort_by(entries, & &1.unit_id), & &1.signed_url) == ["url_a", "url_b"]
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
end
