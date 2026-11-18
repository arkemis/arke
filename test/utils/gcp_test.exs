defmodule Arke.Utils.GcpTest do
  # Not async: the token cache is per node and the signer comes from the env.
  use ExUnit.Case, async: false
  use Mimic

  alias Arke.Utils.Gcp
  alias Arke.Utils.Gcp.Auth

  @service_account "signer@project.iam.gserviceaccount.com"
  @bucket "my-bucket"
  @file_path "dir/my file.png"
  @resource "/my-bucket/dir/my%20file.png"
  @signed_blob "c2lnbmF0dXJl"
  @token "test-token"
  @metadata_email_url "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email"

  setup :verify_on_exit!

  setup do
    stub(Goth.Token, :fetch, fn _ -> {:ok, goth_token(@token)} end)

    previous = System.get_env("STORAGE_SERVICE_ACCOUNT")
    System.delete_env("STORAGE_SERVICE_ACCOUNT")
    Auth.clear_cache()

    on_exit(fn ->
      if previous, do: System.put_env("STORAGE_SERVICE_ACCOUNT", previous)
      Auth.clear_cache()
    end)

    :ok
  end

  defp goth_token(token, expires_in \\ 3600),
    do: %Goth.Token{token: token, expires: System.os_time(:second) + expires_in}

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
      assert {:error, "Forbidden resource"} = sign(service_account: @service_account)
    end

    test "maps any other status to a generic error" do
      respond(500, ~s({"error":"boom"}))
      assert {:error, "error on signed url"} = sign(service_account: @service_account)
    end

    test "maps a transport error to a generic error" do
      expect(Tesla.Adapter.Httpc, :call, fn _env, _opts -> {:error, :timeout} end)
      assert {:error, "error on signed url"} = sign(service_account: @service_account)
    end
  end

  describe "get_bucket_file_signed_url/2 signer" do
    test "STORAGE_SERVICE_ACCOUNT names the signer" do
      System.put_env("STORAGE_SERVICE_ACCOUNT", @service_account)
      respond(200, ~s({"signedBlob":"#{@signed_blob}"}))

      assert {:ok, _} = sign()

      assert_received {:request, env}
      assert env.url =~ "serviceAccounts/#{@service_account}:signBlob"
    end

    test "without it, signs as the metadata server's account, looked up once" do
      stub(Tesla.Adapter.Httpc, :call, fn env, _opts ->
        send(self(), {:request, env})

        case env.url do
          @metadata_email_url ->
            {:ok, %{env | status: 200, body: "pod@project.iam.gserviceaccount.com\n"}}

          _ ->
            {:ok, %{env | status: 200, body: ~s({"signedBlob":"#{@signed_blob}"})}}
        end
      end)

      assert {:ok, %{signed_url: url}} = sign()
      assert {:ok, _} = sign()

      assert URI.decode_query(URI.parse(url).query)["GoogleAccessId"] ==
               "pod@project.iam.gserviceaccount.com"

      assert_received {:request, %{url: @metadata_email_url} = metadata}
      assert {"metadata-flavor", "Google"} in metadata.headers
      refute_received {:request, %{url: @metadata_email_url}}
    end

    test "(error) a workload identity pool cannot be the signer" do
      expect(Tesla.Adapter.Httpc, :call, fn env, _opts ->
        {:ok, %{env | status: 200, body: "project.svc.id.goog"}}
      end)

      assert {:error, "error on signed url"} = sign()
    end
  end

  describe "access token" do
    test "is fetched once and reused until shortly before it expires" do
      expect(Goth.Token, :fetch, fn _ -> {:ok, goth_token("ya29.cached")} end)
      respond(200, ~s({"signedBlob":"#{@signed_blob}"}))
      respond(200, ~s({"signedBlob":"#{@signed_blob}"}))

      assert {:ok, _} = sign(service_account: @service_account)
      assert {:ok, _} = sign(service_account: @service_account)

      assert_received {:request, env}
      assert {"authorization", "Bearer ya29.cached"} in env.headers
    end

    test "a token about to expire is fetched again" do
      expect(Goth.Token, :fetch, 2, fn _ -> {:ok, goth_token("ya29.short", 30)} end)
      respond(200, ~s({"signedBlob":"#{@signed_blob}"}))
      respond(200, ~s({"signedBlob":"#{@signed_blob}"}))

      assert {:ok, _} = sign(service_account: @service_account)
      assert {:ok, _} = sign(service_account: @service_account)
    end

    test "a transient failure is retried" do
      expect(Goth.Token, :fetch, fn _ -> {:error, %RuntimeError{message: "not ready"}} end)
      expect(Goth.Token, :fetch, fn _ -> {:ok, goth_token(@token)} end)
      respond(200, ~s({"signedBlob":"#{@signed_blob}"}))

      assert {:ok, _} = sign(service_account: @service_account)
    end

    test "(error) a lasting failure is returned, not raised" do
      stub(Goth.Token, :fetch, fn _ -> raise "no credentials" end)

      # Any request would raise: the Httpc adapter has no stub in this test.
      assert {:error, %RuntimeError{message: "no credentials"}} =
               Gcp.upload_file(@file_path, "data", bucket: @bucket)
    end
  end

  describe "upload_file/3" do
    test "sends the object as a multipart upload" do
      respond(200, ~s({"name":"#{@file_path}","bucket":"#{@bucket}"}))

      assert {:ok, %GoogleApi.Storage.V1.Model.Object{name: @file_path}} =
               Gcp.upload_file(@file_path, "data", bucket: @bucket, public: true)

      assert_received {:request, env}
      assert env.method == :post
      assert env.url == "https://storage.googleapis.com/upload/storage/v1/b/my-bucket/o"
      assert env.query == [uploadType: "multipart", predefinedAcl: "publicread"]
      assert {"authorization", "Bearer #{@token}"} in env.headers

      body = env.body |> Tesla.Multipart.body() |> Enum.join()
      assert body =~ ~s(name="metadata")
      assert body =~ ~s({"name":"#{@file_path}"})
      assert body =~ ~s(name="data")
      assert body =~ "application/octet-stream"
    end

    test "(error) returns a failed upload instead of raising" do
      respond(403, ~s({"error":"forbidden"}))

      assert {:error, %Tesla.Env{status: 403}} =
               Gcp.upload_file(@file_path, "data", bucket: @bucket)
    end
  end
end
