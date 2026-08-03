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

  # Stubbing the adapter rather than Req.request/1 keeps the request steps in
  # play, so the asserted request is the one that actually goes out.
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
      stub(Auth, :signer, fn -> {:ok, {account.email, account.pem}} end)
      {:ok, account: account}
    end

    test "signs the canonical GET string with the service account key", %{account: account} do
      assert {:ok, %{signed_url: signed_url, expiration: expires}} =
               Gcp.get_bucket_file_signed_url(@file_path, bucket: @bucket)

      assert_in_delta expires, DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(3600), 5

      %URI{host: host, path: path, query: query} = URI.parse(signed_url)
      assert host == "storage.googleapis.com"
      assert path == @resource

      params = URI.decode_query(query)
      assert params["GoogleAccessId"] == account.email
      assert params["Expires"] == to_string(expires)

      string_to_sign = Enum.join(["GET", "", "", expires, @resource], "\n")

      assert :public_key.verify(
               string_to_sign,
               :sha256,
               Base.decode64!(params["Signature"]),
               account.public_key
             )
    end

    test "performs no request" do
      # Any call would raise, since Req.Finch.run/1 has no stub here.
      assert {:ok, _} = Gcp.get_bucket_file_signed_url(@file_path, bucket: @bucket)
    end
  end

  describe "get_bucket_file_signed_url/2 without a signing key" do
    test "(error) fails when the credentials carry no private key" do
      stub(Auth, :signer, fn -> {:error, :no_private_key} end)

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
end
