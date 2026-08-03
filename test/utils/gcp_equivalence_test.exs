defmodule Arke.Utils.GcpEquivalenceTest do
  @moduledoc """
  Proves the Req implementation issues the same requests as the
  `google_api_storage` one it replaces.

  The baseline could not be captured live: `google_gax 0.4.1` is broken under the
  locked tesla 1.21 — it passes `DecompressResponse` without the now-required
  `:max_body_size` and uses atom multipart field names, both rejected by the
  1.17+ security fixes. So the expected requests were recorded once under tesla
  1.16.0, the last working version, into
  `test/support/fixtures/gcs_requests.exs`.

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

  # Stubbing the adapter rather than Req.request/1 keeps the request steps in
  # play, so the asserted request is the one that actually goes out.
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
      test "#{key} matches the recorded google_api_storage request", %{fixtures: fixtures} do
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
