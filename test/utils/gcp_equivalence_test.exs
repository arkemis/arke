defmodule Arke.Utils.GcpEquivalenceTest do
  @moduledoc """
  Checks every storage request against the recording in
  `test/support/fixtures/gcs_requests.exs`, so the wire format cannot drift.

  Not async: the recorded requests resolve their bucket from `DEFAULT_BUCKET`.
  """
  use ExUnit.Case, async: false
  use Mimic

  alias Arke.Utils.Gcp
  alias Arke.Test.Gcp, as: TestGcp

  @bucket "probe-bucket"
  @simple_path "arke_file/f.png"
  # What Arke.Core.File.before_load/2 generates: "arke_file/<ISO datetime>",
  # so the object name contains spaces and colons.
  @dated_path "arke_file/2026-08-03 10:11:12.345678Z/my file.png"

  @cases [
    :upload_simple,
    :upload_dated_path,
    :upload_public,
    :upload_opts_bucket,
    :get_simple,
    :get_dated_path,
    :get_opts_bucket,
    :delete_simple,
    :delete_dated_path
  ]

  # The call that must reproduce each recorded fixture.
  defp call(:upload_simple), do: Gcp.upload_file(@simple_path, "BYTES")
  defp call(:upload_dated_path), do: Gcp.upload_file(@dated_path, "BYTES")
  defp call(:upload_public), do: Gcp.upload_file(@simple_path, "BYTES", public: true)
  defp call(:upload_opts_bucket), do: Gcp.upload_file(@simple_path, "BYTES", bucket: "opt-bucket")
  defp call(:get_simple), do: Gcp.get_file(@simple_path)
  defp call(:get_dated_path), do: Gcp.get_file(@dated_path)
  defp call(:get_opts_bucket), do: Gcp.get_file(@simple_path, bucket: "opt-bucket")
  defp call(:delete_simple), do: Gcp.delete_file(@simple_path)
  defp call(:delete_dated_path), do: Gcp.delete_file(@dated_path)

  setup do
    stub(Arke.Utils.Gcp.Auth, :token, fn -> {:ok, "test-token"} end)
    System.put_env("DEFAULT_BUCKET", @bucket)
    on_exit(fn -> System.delete_env("DEFAULT_BUCKET") end)

    {:ok, fixtures: TestGcp.request_fixtures()}
  end

  # Stubbing the adapter keeps the request steps in play, so the asserted
  # request is the one that actually goes out.
  defp respond(status, body) do
    pid = self()

    stub(Req.Finch, :run, fn request ->
      send(pid, {:request, request})
      {request, Req.Response.new(status: status, body: body)}
    end)
  end

  describe "storage requests" do
    setup do
      respond(200, ~s({"name":"recorded"}))
      :ok
    end

    for key <- @cases do
      test "#{key} matches the recorded request", %{fixtures: fixtures} do
        call(unquote(key))

        assert_received {:request, request}

        assert TestGcp.project_request(request) ==
                 fixtures |> Map.fetch!(unquote(key)) |> TestGcp.project_fixture()
      end
    end

    test "every recorded fixture is covered by a case", %{fixtures: fixtures} do
      assert MapSet.new(Map.keys(fixtures)) == MapSet.new(@cases)
    end
  end
end
