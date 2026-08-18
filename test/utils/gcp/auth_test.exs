defmodule Arke.Utils.Gcp.AuthTest do
  # Not async: credentials are resolved from env vars and application config.
  use ExUnit.Case, async: false
  use Mimic

  alias Arke.Utils.Gcp.Auth
  alias Arke.Test.Gcp, as: TestGcp

  @token_url "https://www.googleapis.com/oauth2/v4/token"
  @jwt_grant "urn:ietf:params:oauth:grant-type:jwt-bearer"
  @metadata_email_url "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email"
  @sign_blob_host "iamcredentials.googleapis.com"
  @payload "GOOG4-RSA-SHA256\npayload to sign"

  setup :verify_on_exit!

  setup do
    # Nothing must leak in from the machine running the suite, including its
    # gcloud ADC file: CLOUDSDK_CONFIG points the lookup at an empty dir.
    for var <-
          ~w[GOOGLE_APPLICATION_CREDENTIALS GOOGLE_APPLICATION_CREDENTIALS_JSON CLOUDSDK_CONFIG] do
      previous = System.get_env(var)
      System.delete_env(var)

      on_exit(fn ->
        if previous, do: System.put_env(var, previous), else: System.delete_env(var)
      end)
    end

    System.put_env(
      "CLOUDSDK_CONFIG",
      Path.join(System.tmp_dir!(), "arke-gcloud-#{System.unique_integer([:positive])}")
    )

    on_exit(fn -> Application.delete_env(:arke, :gcp_credentials) end)
    :ok
  end

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

  # Signing under Workload Identity hits three endpoints; matching on the url
  # keeps the test independent of the order they are called in.
  defp stub_endpoints(handlers) do
    stub(Req.Finch, :run, fn request ->
      url = URI.to_string(request.url)

      case Enum.find(handlers, fn {match, _} -> String.contains?(url, match) end) do
        {_, {status, body, content_type}} ->
          send(self(), {:request, request})

          {request,
           Req.Response.new(
             status: status,
             headers: [{"content-type", content_type}],
             body: body
           )}

        nil ->
          flunk("unexpected request to #{url}")
      end
    end)
  end

  defp metadata_endpoints(extra) do
    [
      {"instance/service-accounts/default/token",
       {200, ~s({"access_token":"ya29.metadata"}), "application/json"}}
      | extra
    ]
  end

  defp service_account_json(account) do
    Jason.encode!(%{"private_key" => account.pem, "client_email" => account.email})
  end

  defp put_credentials_file(json) do
    path =
      Path.join(System.tmp_dir!(), "arke-credentials-#{System.unique_integer([:positive])}.json")

    File.write!(path, json)
    System.put_env("GOOGLE_APPLICATION_CREDENTIALS", path)
    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "token/0 with service account credentials" do
    setup do
      account = TestGcp.service_account()
      put_credentials_file(service_account_json(account))
      {:ok, account: account}
    end

    test "exchanges a self-signed RS256 JWT for an access token", %{account: account} do
      respond(200, ~s({"access_token":"ya29.token"}))

      assert Auth.token() == {:ok, "ya29.token"}

      assert_received {:request, request}
      assert URI.to_string(request.url) == @token_url

      params = request.body |> IO.iodata_to_binary() |> URI.decode_query()
      assert params["grant_type"] == @jwt_grant

      [header, claims, signature] = String.split(params["assertion"], ".")
      assert decode_part(header) == %{"alg" => "RS256", "typ" => "JWT"}

      claims = decode_part(claims)
      assert claims["iss"] == account.email
      assert claims["aud"] == @token_url
      assert claims["scope"] == "https://www.googleapis.com/auth/cloud-platform"
      assert claims["exp"] == claims["iat"] + 3600
      assert_in_delta claims["iat"], DateTime.utc_now() |> DateTime.to_unix(), 5

      assert :public_key.verify(
               "#{header}.#{claims_segment(params["assertion"])}",
               :sha256,
               Base.url_decode64!(signature, padding: false),
               account.public_key
             )
    end

    test "(error) surfaces a non-200 from the token endpoint" do
      respond(400, ~s({"error":"invalid_grant"}))

      assert {:error, {400, %{"error" => "invalid_grant"}}} = Auth.token()
    end

    test "sign/1 signs locally, making no request", %{account: account} do
      # Any request would raise: Req.Finch.run/1 has no stub in this test.
      assert {:ok, {email, signature}} = Auth.sign(@payload)
      assert email == account.email
      assert :public_key.verify(@payload, :sha256, signature, account.public_key)
    end
  end

  describe "token/0 with gcloud user credentials" do
    setup do
      System.put_env(
        "GOOGLE_APPLICATION_CREDENTIALS_JSON",
        Jason.encode!(%{
          "refresh_token" => "1//refresh",
          "client_id" => "id.apps.googleusercontent.com",
          "client_secret" => "secret"
        })
      )

      :ok
    end

    test "refreshes the token" do
      respond(200, ~s({"access_token":"ya29.refreshed"}))

      assert Auth.token() == {:ok, "ya29.refreshed"}

      assert_received {:request, request}
      assert URI.to_string(request.url) == @token_url

      params = request.body |> IO.iodata_to_binary() |> URI.decode_query()
      assert params["grant_type"] == "refresh_token"
      assert params["refresh_token"] == "1//refresh"
      assert params["client_secret"] == "secret"
    end

    test "(error) sign/1 has no private key and no configured signer" do
      assert Auth.sign(@payload) == {:error, :no_private_key}
    end

    test "sign/1 signs through IAM when a signer account is configured" do
      Application.put_env(
        :arke,
        :storage_signer_account,
        "configured@project.iam.gserviceaccount.com"
      )

      on_exit(fn -> Application.delete_env(:arke, :storage_signer_account) end)

      stub_endpoints([
        {@token_url, {200, ~s({"access_token":"ya29.refreshed"}), "application/json"}},
        {@sign_blob_host,
         {200, ~s({"signedBlob":"#{Base.encode64("iam signature")}"}), "application/json"}}
      ])

      assert Auth.sign(@payload) ==
               {:ok, {"configured@project.iam.gserviceaccount.com", "iam signature"}}

      # No metadata lookup: a human's ADC cannot name itself, hence the config.
      assert_received {:request, _token}
      assert_received {:request, sign}
      assert URI.to_string(sign.url) =~ "configured@project.iam.gserviceaccount.com:signBlob"
    end
  end

  describe "token/0 with no credentials" do
    test "falls back to the metadata server" do
      respond(200, ~s({"access_token":"ya29.metadata"}))

      assert Auth.token() == {:ok, "ya29.metadata"}

      assert_received {:request, request}

      assert URI.to_string(request.url) ==
               "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"

      assert Req.Request.get_header(request, "metadata-flavor") == ["Google"]
    end

    test "sign/1 signs through the IAM credentials API" do
      signature = "iam produced this"

      stub_endpoints(
        metadata_endpoints([
          {@metadata_email_url,
           {200, "arke-dev-app@project.iam.gserviceaccount.com\n", "text/plain"}},
          {@sign_blob_host,
           {200, ~s({"signedBlob":"#{Base.encode64(signature)}"}), "application/json"}}
        ])
      )

      assert Auth.sign(@payload) ==
               {:ok, {"arke-dev-app@project.iam.gserviceaccount.com", signature}}

      requests = collect_requests()
      sign = Enum.find(requests, &(URI.to_string(&1.url) =~ @sign_blob_host))

      assert sign.method == :post
      assert URI.to_string(sign.url) =~ "arke-dev-app@project.iam.gserviceaccount.com:signBlob"
      assert Req.Request.get_header(sign, "authorization") == ["Bearer ya29.metadata"]
      assert Jason.decode!(sign.body) == %{"payload" => Base.encode64(@payload)}
    end

    test "(error) surfaces a non-200 from signBlob" do
      stub_endpoints(
        metadata_endpoints([
          {@metadata_email_url,
           {200, "arke-dev-app@project.iam.gserviceaccount.com", "text/plain"}},
          {@sign_blob_host,
           {403, ~s({"error":{"status":"PERMISSION_DENIED"}}), "application/json"}}
        ])
      )

      assert {:error, {403, %{"error" => %{"status" => "PERMISSION_DENIED"}}}} =
               Auth.sign(@payload)
    end

    test "(error) surfaces a non-200 from the metadata email lookup" do
      stub_endpoints(metadata_endpoints([{@metadata_email_url, {404, "", "text/plain"}}]))

      assert {:error, {404, _}} = Auth.sign(@payload)
    end
  end

  describe "credential sources" do
    setup do
      account = TestGcp.service_account()
      # The env var must lose to application config.
      put_credentials_file(
        service_account_json(TestGcp.service_account("env@project.iam.gserviceaccount.com"))
      )

      {:ok, account: account}
    end

    test "config json wins over the env var", %{account: account} do
      Application.put_env(:arke, :gcp_credentials, service_account_json(account))
      assert {:ok, {email, _signature}} = Auth.sign(@payload)
      assert email == account.email
    end

    test "config accepts {:system, var}", %{account: account} do
      System.put_env("ARKE_TEST_CREDENTIALS", service_account_json(account))
      on_exit(fn -> System.delete_env("ARKE_TEST_CREDENTIALS") end)

      Application.put_env(:arke, :gcp_credentials, {:system, "ARKE_TEST_CREDENTIALS"})

      assert {:ok, {email, _signature}} = Auth.sign(@payload)
      assert email == account.email
    end

    test "config accepts a decoded map", %{account: account} do
      Application.put_env(:arke, :gcp_credentials, %{
        "private_key" => account.pem,
        "client_email" => account.email
      })

      assert {:ok, {email, _signature}} = Auth.sign(@payload)
      assert email == account.email
    end
  end

  # The deployed shape: credentials in the environment, no stubs anywhere, all
  # the way through to a signature GCS would accept.
  describe "signed urls from environment credentials" do
    setup do
      {:ok, account: TestGcp.service_account()}
    end

    test "GOOGLE_APPLICATION_CREDENTIALS signs the url", %{account: account} do
      put_credentials_file(service_account_json(account))
      assert_signs("dir/my file.png", account)
    end

    test "GOOGLE_APPLICATION_CREDENTIALS_JSON signs the url", %{account: account} do
      System.put_env("GOOGLE_APPLICATION_CREDENTIALS_JSON", service_account_json(account))
      assert_signs("dir/my file.png", account)
    end

    defp assert_signs(file_path, account) do
      assert {:ok, %{signed_url: signed_url}} =
               Arke.Utils.Gcp.get_bucket_file_signed_url(file_path, bucket: "my-bucket")

      %URI{path: resource, query: query} = URI.parse(signed_url)
      params = URI.decode_query(query)

      assert params["X-Goog-Credential"] =~ account.email

      assert :public_key.verify(
               TestGcp.v4_string_to_sign(params, account.email, resource),
               :sha256,
               Base.decode16!(params["X-Goog-Signature"], case: :lower),
               account.public_key
             )
    end
  end

  defp collect_requests(acc \\ []) do
    receive do
      {:request, request} -> collect_requests([request | acc])
    after
      0 -> acc
    end
  end

  defp decode_part(segment), do: segment |> Base.url_decode64!(padding: false) |> Jason.decode!()

  defp claims_segment(assertion), do: assertion |> String.split(".") |> Enum.at(1)
end
