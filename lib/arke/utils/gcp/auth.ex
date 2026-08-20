# Copyright 2023 Arkemis S.r.l.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule Arke.Utils.Gcp.Auth do
  @moduledoc """
  Google credentials for `Arke.Utils.Gcp`.

  Resolves application default credentials, then either mints an OAuth access
  token (`token/0`) or signs a payload (`sign/2`).

  Credentials are resolved on every call, first hit wins:

    1. `config :arke, :gcp_credentials` — a JSON string, `{:system, "VAR"}`, or a
       decoded map
    2. `GOOGLE_APPLICATION_CREDENTIALS` — path to the key file
    3. `GOOGLE_APPLICATION_CREDENTIALS_JSON` — inline JSON
    4. `application_default_credentials.json` in the gcloud config dir
       (`$CLOUDSDK_CONFIG`, defaulting to `~/.config/gcloud`) — gcloud ADC
    5. the GCE metadata server

  Signing takes whichever of those is resolved. Sources 1-3 normally carry a
  private key and sign locally; the metadata server has none, so signing goes
  through the IAM Credentials API, which needs the account to hold
  `roles/iam.serviceAccountTokenCreator` on itself. gcloud ADC can sign the same
  way but cannot name the account it would sign as, so it additionally needs:

      config :arke, storage_signer_account: "signer@project.iam.gserviceaccount.com"

  and the developer to hold `roles/iam.serviceAccountTokenCreator` on it.
  """

  @token_url "https://www.googleapis.com/oauth2/v4/token"
  @scope "https://www.googleapis.com/auth/cloud-platform"
  @jwt_grant "urn:ietf:params:oauth:grant-type:jwt-bearer"
  @metadata_url "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
  @metadata_email_url "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email"
  @sign_blob_url "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts"

  @doc """
  An OAuth access token for the resolved credentials.
  """
  def token() do
    with {:ok, credentials} <- credentials() do
      request_token(credentials)
    end
  end

  @doc """
  Signs `payload` as `email`, returning the raw signature bytes — callers encode
  them as their url scheme requires.

  V4 signing embeds the signer in the payload, so the caller resolves it with
  `signer_email/0` and passes it back here: resolving it twice risks signing as
  one account under a url that names another.

  Service account credentials sign locally. Under Workload Identity there is no
  private key, so the IAM Credentials API signs on our behalf. gcloud user
  credentials can do the same, but cannot name the account they would be signing
  as, so they need `config :arke, :storage_signer_account`.
  """
  def sign(payload, email) do
    case credentials() do
      {:ok, %{"private_key" => pem}} ->
        {:ok, :public_key.sign(payload, :sha256, private_key(pem))}

      _ ->
        sign_blob(email, payload)
    end
  end

  @doc """
  The account signatures will be attributed to.

  V4 signing puts the signer inside the payload, so callers need it before they
  have anything to sign.
  """
  def signer_email() do
    case credentials() do
      {:ok, %{"client_email" => email}} ->
        {:ok, email}

      {:ok, :metadata} ->
        metadata_email()

      {:ok, _other} ->
        # A human's ADC cannot name itself, so it has to be told.
        case Application.get_env(:arke, :storage_signer_account) do
          nil -> {:error, :no_private_key}
          email -> {:ok, email}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Signing is idempotent and now sits behind a network hop, where it used to be
  # local cpu: a blip here breaks a download link, so this one call retries.
  defp sign_blob(email, payload) do
    with {:ok, token} <- token(),
         {:ok, %{status: 200, body: %{"signedBlob" => signature}}} <-
           request(
             method: :post,
             url: "#{@sign_blob_url}/#{email}:signBlob",
             headers: [{"authorization", "Bearer #{token}"}],
             json: %{payload: Base.encode64(payload)},
             retry: :transient
           ),
         {:ok, signature} <- Base.decode64(signature) do
      {:ok, signature}
    else
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      :error -> {:error, :invalid_signature}
      {:error, reason} -> {:error, reason}
    end
  end

  # Plain text, unlike every other metadata endpoint used here.
  defp metadata_email() do
    case request(url: @metadata_email_url, headers: [{"metadata-flavor", "Google"}]) do
      {:ok, %{status: 200, body: email}} -> {:ok, String.trim(email)}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp credentials() do
    cond do
      config = Application.get_env(:arke, :gcp_credentials) -> from_config(config)
      path = System.get_env("GOOGLE_APPLICATION_CREDENTIALS") -> path |> File.read!() |> decode()
      json = System.get_env("GOOGLE_APPLICATION_CREDENTIALS_JSON") -> decode(json)
      File.exists?(adc_file()) -> adc_file() |> File.read!() |> decode()
      true -> {:ok, :metadata}
    end
  end

  defp from_config({:system, var}), do: var |> System.fetch_env!() |> decode()
  defp from_config(json) when is_binary(json), do: decode(json)
  defp from_config(%{} = credentials), do: {:ok, credentials}

  defp adc_file() do
    gcloud_dir = System.get_env("CLOUDSDK_CONFIG") || Path.expand("~/.config/gcloud")
    Path.join(gcloud_dir, "application_default_credentials.json")
  end

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, %{} = credentials} -> {:ok, credentials}
      {:ok, other} -> {:error, "unexpected credentials: #{inspect(other)}"}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  defp request_token(%{"private_key" => _} = credentials) do
    post_token(form: [grant_type: @jwt_grant, assertion: jwt(credentials)])
  end

  defp request_token(%{"refresh_token" => token, "client_id" => id, "client_secret" => secret}) do
    post_token(
      form: [
        grant_type: "refresh_token",
        refresh_token: token,
        client_id: id,
        client_secret: secret
      ]
    )
  end

  defp request_token(:metadata) do
    [url: @metadata_url, headers: [{"metadata-flavor", "Google"}]]
    |> request()
    |> access_token()
  end

  defp request_token(credentials),
    do: {:error, "unsupported credentials: #{inspect(Map.keys(credentials))}"}

  defp post_token(opts) do
    [method: :post, url: @token_url]
    |> Keyword.merge(opts)
    |> request()
    |> access_token()
  end

  # Same defaults as the storage client: no retries, bounded call.
  defp request(opts) do
    Req.request([retry: false, receive_timeout: 5_000, connect_options: [timeout: 8_000]] ++ opts)
  end

  defp access_token({:ok, %{status: 200, body: %{"access_token" => token}}}), do: {:ok, token}
  defp access_token({:ok, %{status: status, body: body}}), do: {:error, {status, body}}
  defp access_token({:error, exception}), do: {:error, exception}

  # RS256 JWT bearer assertion: https://developers.google.com/identity/protocols/oauth2/service-account
  defp jwt(%{"private_key" => pem, "client_email" => email}) do
    iat = DateTime.utc_now() |> DateTime.to_unix()

    signing_input =
      Enum.map_join(
        [
          %{"alg" => "RS256", "typ" => "JWT"},
          %{
            "iss" => email,
            "scope" => @scope,
            "aud" => @token_url,
            "iat" => iat,
            "exp" => iat + 3600
          }
        ],
        ".",
        &(&1 |> Jason.encode!() |> Base.url_encode64(padding: false))
      )

    signature =
      signing_input
      |> :public_key.sign(:sha256, private_key(pem))
      |> Base.url_encode64(padding: false)

    "#{signing_input}.#{signature}"
  end

  defp private_key(pem) do
    pem |> :public_key.pem_decode() |> hd() |> :public_key.pem_entry_decode()
  end
end
