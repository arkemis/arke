defmodule Arke.Utils.GcpTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Arke.Utils.Gcp
  alias Arke.Utils.Gcp.Auth
  alias Arke.Test.Gcp, as: TestGcp

  @bucket "my-bucket"
  @file_path "dir/my file.png"
  @resource "/my-bucket/dir/my%20file.png"
  @token "test-token"

  setup :verify_on_exit!

  setup do
    stub(Auth, :token, fn -> {:ok, @token} end)
    :ok
  end

  # Stubbing the adapter keeps the request steps in play, so the asserted
  # request is the one that actually goes out.
  defp respond(status, body) do
    expect(Req.Finch, :run, fn request ->
      send(self(), {:request, request})

      response =
        Req.Response.new(
          status: status,
          headers: [{"content-type", "application/json"}],
          body: body
        )

      {request, response}
    end)
  end

  defp transport_error(reason) do
    expect(Req.Finch, :run, fn request -> {request, %Req.TransportError{reason: reason}} end)
  end

  describe "get_bucket_file_signed_url/2" do
    setup do
      account = TestGcp.service_account()

      stub(Auth, :signer_email, fn -> {:ok, account.email} end)

      stub(Auth, :sign, fn payload, _email ->
        {:ok, :public_key.sign(payload, :sha256, account.private_key)}
      end)

      {:ok, account: account}
    end

    test "signs a v4 canonical request", %{account: account} do
      assert {:ok, %{signed_url: signed_url, expiration: expires}} =
               Gcp.get_bucket_file_signed_url(@file_path, bucket: @bucket)

      assert_in_delta expires, DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(3600), 5

      %URI{host: host, path: path, query: query} = URI.parse(signed_url)
      assert host == "storage.googleapis.com"
      assert path == @resource

      params = URI.decode_query(query)
      day = params["X-Goog-Date"] |> String.slice(0, 8)

      assert params["X-Goog-Algorithm"] == "GOOG4-RSA-SHA256"
      assert params["X-Goog-Credential"] == "#{account.email}/#{day}/auto/storage/goog4_request"
      assert params["X-Goog-Expires"] == "3600"
      assert params["X-Goog-SignedHeaders"] == "host"
      assert params["X-Goog-Date"] =~ ~r/^\d{8}T\d{6}Z$/

      assert :public_key.verify(
               TestGcp.v4_string_to_sign(params, account.email, @resource),
               :sha256,
               Base.decode16!(params["X-Goog-Signature"], case: :lower),
               account.public_key
             )
    end

    test "percent-encodes the object path without touching the separators" do
      assert {:ok, %{signed_url: signed_url}} =
               Gcp.get_bucket_file_signed_url("dir/a?b c.png", bucket: @bucket)

      assert URI.parse(signed_url).path == "/my-bucket/dir/a%3Fb%20c.png"
    end

    test "performs no request" do
      # Any call would raise, since Req.Finch.run/1 has no stub here.
      assert {:ok, _} = Gcp.get_bucket_file_signed_url(@file_path, bucket: @bucket)
    end

    # The url embeds the signer, so a second resolution is both a wasted
    # metadata round trip and a chance to sign as someone else.
    test "resolves the signer once and signs as the account it embedded", %{account: account} do
      parent = self()

      stub(Auth, :signer_email, fn ->
        send(parent, :resolved)
        {:ok, account.email}
      end)

      stub(Auth, :sign, fn _payload, email ->
        send(parent, {:signed_as, email})
        {:ok, "sig"}
      end)

      assert {:ok, %{signed_url: signed_url}} =
               Gcp.get_bucket_file_signed_url(@file_path, bucket: @bucket)

      assert_received :resolved
      refute_received :resolved

      assert_received {:signed_as, email}

      assert URI.parse(signed_url).query |> URI.decode_query() |> Map.fetch!("X-Goog-Credential") =~
               email
    end
  end

  describe "get_bucket_file_signed_url/2 without a bucket" do
    setup do
      previous = System.get_env("DEFAULT_BUCKET")
      System.delete_env("DEFAULT_BUCKET")
      on_exit(fn -> if previous, do: System.put_env("DEFAULT_BUCKET", previous) end)
      :ok
    end

    # Legacy units carry no bucket, and this path renders a page: it degrades.
    test "(error) refuses to sign an unresolvable bucket" do
      assert {:error, message} = Gcp.get_bucket_file_signed_url(@file_path, [])
      assert is_binary(message)
    end
  end

  describe "get_bucket_file_signed_url/2 expiry" do
    setup do
      account = TestGcp.service_account()
      stub(Auth, :signer_email, fn -> {:ok, account.email} end)
      stub(Auth, :sign, fn _payload, _email -> {:ok, "signature"} end)
      on_exit(fn -> Application.delete_env(:arke, :signed_url_ttl) end)
      :ok
    end

    test "defaults to an hour" do
      assert expires_in(bucket: @bucket) == "3600"
    end

    test "takes the configured default" do
      Application.put_env(:arke, :signed_url_ttl, 1_800)
      assert expires_in(bucket: @bucket) == "1800"
    end

    test "the call overrides the configured default" do
      Application.put_env(:arke, :signed_url_ttl, 1_800)
      assert expires_in(bucket: @bucket, expires_in: 60) == "60"
    end

    test "expiration stays an absolute timestamp for the cache" do
      assert {:ok, %{expiration: expiration}} =
               Gcp.get_bucket_file_signed_url(@file_path, bucket: @bucket, expires_in: 60)

      assert_in_delta expiration, DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(60), 5
    end

    # Every error here reaches a caller that interpolates it into a log line.
    test "(error) rejects a ttl beyond the seven day ceiling" do
      assert {:error, message} =
               Gcp.get_bucket_file_signed_url(@file_path, bucket: @bucket, expires_in: 604_801)

      assert is_binary(message)
      assert message =~ "604800"
    end

    test "(error) rejects a ttl of zero or less" do
      for ttl <- [0, -60] do
        assert {:error, message} =
                 Gcp.get_bucket_file_signed_url(@file_path, bucket: @bucket, expires_in: ttl)

        assert is_binary(message)
      end
    end

    # A ttl read straight out of the environment arrives as a string, and
    # `"3600" > 604_800` is true in term order.
    test "(error) rejects a ttl that is not an integer" do
      Application.put_env(:arke, :signed_url_ttl, "3600")

      assert {:error, message} = Gcp.get_bucket_file_signed_url(@file_path, bucket: @bucket)
      assert is_binary(message)
    end

    defp expires_in(opts) do
      assert {:ok, %{signed_url: signed_url}} = Gcp.get_bucket_file_signed_url(@file_path, opts)

      signed_url
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()
      |> Map.fetch!("X-Goog-Expires")
    end
  end

  describe "get_bucket_file_signed_url/2 without a signing key" do
    test "(error) fails when the credentials carry no private key" do
      stub(Auth, :signer_email, fn -> {:error, :no_private_key} end)

      assert {:error, "error on signed url"} =
               Gcp.get_bucket_file_signed_url(@file_path, bucket: @bucket)
    end
  end

  describe "upload_file/3" do
    test "returns the decoded object on success" do
      respond(200, ~s({"name":"#{@file_path}"}))

      assert Gcp.upload_file(@file_path, "BYTES", bucket: @bucket) ==
               {:ok, %{"name" => @file_path}}
    end

    test "carries the bearer token and bounds the call" do
      respond(200, ~s({"name":"#{@file_path}"}))

      Gcp.upload_file(@file_path, "BYTES", bucket: @bucket)

      assert_received {:request, request}
      assert Req.Request.get_header(request, "authorization") == ["Bearer #{@token}"]
      assert request.options[:receive_timeout] == 5_000
      assert request.options[:connect_options] == [timeout: 8_000]
    end

    test "(error) returns the response on a non-2xx response" do
      respond(403, ~s({"error":"forbidden"}))

      assert {:error, %Req.Response{status: 403}} =
               Gcp.upload_file(@file_path, "BYTES", bucket: @bucket)
    end

    test "(error) returns the reason on a transport failure" do
      transport_error(:econnrefused)

      assert Gcp.upload_file(@file_path, "BYTES", bucket: @bucket) ==
               {:error, %Req.TransportError{reason: :econnrefused}}
    end
  end

  describe "get_file/2" do
    test "returns the decoded object on success" do
      respond(200, ~s({"name":"#{@file_path}","size":"5"}))

      assert Gcp.get_file(@file_path, bucket: @bucket) ==
               {:ok, %{"name" => @file_path, "size" => "5"}}
    end

    test "(error) returns the response on a non-2xx response" do
      respond(404, ~s({"error":"not found"}))
      assert {:error, %Req.Response{status: 404}} = Gcp.get_file(@file_path, bucket: @bucket)
    end
  end

  describe "delete_file/2" do
    test "returns the raw response on success" do
      respond(204, "")
      assert {:ok, %Req.Response{status: 204}} = Gcp.delete_file(@file_path, bucket: @bucket)
    end

    test "(error) returns the response on a non-2xx response" do
      respond(404, ~s({"error":"not found"}))
      assert {:error, %Req.Response{status: 404}} = Gcp.delete_file(@file_path, bucket: @bucket)
    end
  end

  describe "get_public_url/2" do
    # Builds a string, performs no I/O.
    test "builds a bucket url from the unit data" do
      unit = %{data: %{name: "f.png", path: "arke_file/2026", extension: ".png"}}

      assert Gcp.get_public_url(unit, bucket: @bucket) ==
               {:ok,
                %{
                  signed_url: "https://storage.googleapis.com/#{@bucket}/arke_file/2026/f.png",
                  expiration: nil
                }}
    end

    test "(error) rejects a unit without the expected data" do
      assert Gcp.get_public_url(%{data: %{}}) ==
               {:error, [%{context: "storage", message: "invalid unit"}]}
    end
  end

  describe "arities delegated from the behaviour reach the real implementation" do
    setup do
      System.put_env("DEFAULT_BUCKET", @bucket)
      on_exit(fn -> System.delete_env("DEFAULT_BUCKET") end)
    end

    test "upload_file/2 performs the request" do
      respond(200, ~s({"name":"#{@file_path}"}))

      assert {:ok, _} = Gcp.upload_file(@file_path, "BYTES")

      assert_received {:request, request}
      assert request.method == :post
    end

    test "delete_file/1 performs the request" do
      respond(204, "")

      assert {:ok, %Req.Response{status: 204}} = Gcp.delete_file(@file_path)

      assert_received {:request, request}
      assert request.method == :delete
    end

    test "get_file/1 performs the request" do
      respond(200, ~s({"name":"#{@file_path}"}))

      assert {:ok, _} = Gcp.get_file(@file_path)

      assert_received {:request, request}
      assert request.method == :get
    end
  end
end
