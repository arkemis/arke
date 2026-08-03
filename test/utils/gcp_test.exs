defmodule Arke.Utils.GcpTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Arke.Utils.Gcp

  @service_account "signer@project.iam.gserviceaccount.com"
  @bucket "my-bucket"
  @file_path "dir/my file.png"
  @resource "/my-bucket/dir/my%20file.png"
  @signed_blob "c2lnbmF0dXJl"
  @token "test-token"

  setup :verify_on_exit!

  setup do
    stub(Goth.Token, :fetch, fn _ -> {:ok, %{token: @token}} end)
    :ok
  end

  defp sign(opts \\ []),
    do: Gcp.get_bucket_file_signed_url(@file_path, [bucket: @bucket] ++ opts)

  # Stubbing the adapter rather than Tesla.post/4 keeps the middleware stack in
  # play, so the asserted env is the request as it actually goes out.
  defp respond(status, body) do
    expect(Tesla.Adapter.Httpc, :call, fn env, _opts ->
      send(self(), {:request, env})
      {:ok, %{env | status: status, body: body}}
    end)
  end

  describe "get_bucket_file_signed_url/2 request" do
    setup do
      respond(200, ~s({"signedBlob":"#{@signed_blob}"}))
      :ok
    end

    test "targets the signBlob endpoint of the given service account" do
      sign(service_account: @service_account)

      assert_received {:request, env}

      assert env.url ==
               "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/#{@service_account}:signBlob"
    end

    test "carries the bearer token applied by the connection middleware" do
      sign(service_account: @service_account)

      assert_received {:request, env}
      assert {"Content-Type", "application/json"} in env.headers
      assert {"authorization", "Bearer #{@token}"} in env.headers
    end

    test "sends the canonical GET signature for the bucket resource" do
      {:ok, %{expiration: expires}} = sign(service_account: @service_account)

      assert_received {:request, env}
      assert %{"payload" => payload} = Poison.decode!(env.body)
      assert Base.decode64!(payload) == Enum.join(["GET", "", "", expires, @resource], "\n")
    end
  end

  describe "get_bucket_file_signed_url/2 response" do
    test "builds the signed url out of the returned blob" do
      respond(200, ~s({"signedBlob":"#{@signed_blob}"}))

      assert {:ok, %{signed_url: signed_url, expiration: expires}} =
               sign(service_account: @service_account)

      assert_in_delta expires, DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(3600), 5

      %URI{host: host, path: path, query: query} = URI.parse(signed_url)
      assert host == "storage.googleapis.com"
      assert path == @resource

      assert URI.decode_query(query) == %{
               "GoogleAccessId" => @service_account,
               "Expires" => to_string(expires),
               "Signature" => @signed_blob
             }
    end

    test "maps 403 to a forbidden error" do
      respond(403, ~s({"error":"nope"}))
      assert {:error, "Forbidden resource"} = sign()
    end

    test "maps any other status to a generic error" do
      respond(500, ~s({"error":"boom"}))
      assert {:error, "error on signed url"} = sign()
    end
  end
end
