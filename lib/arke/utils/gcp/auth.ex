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
  token (`token/0`) or returns the service account key to sign blobs with
  (`signer/0`).

  Credentials are resolved on every call, first hit wins:

    1. `config :arke, :gcp_credentials` — a JSON string, `{:system, "VAR"}`, or a
       decoded map
    2. `GOOGLE_APPLICATION_CREDENTIALS` — path to the key file
    3. `GOOGLE_APPLICATION_CREDENTIALS_JSON` — inline JSON
    4. `~/.config/gcloud/application_default_credentials.json` — gcloud ADC
    5. the GCE metadata server
  """

  @token_url "https://www.googleapis.com/oauth2/v4/token"
  @scope "https://www.googleapis.com/auth/cloud-platform"
  @jwt_grant "urn:ietf:params:oauth:grant-type:jwt-bearer"
  @metadata_url "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
  @adc_file "~/.config/gcloud/application_default_credentials.json"

  @doc """
  An OAuth access token for the resolved credentials.
  """
  def token() do
    with {:ok, credentials} <- credentials() do
      request_token(credentials)
    end
  end

  @doc """
  The service account able to sign blobs: `{client_email, private_key_pem}`.

  Only service account credentials carry a private key; metadata server and
  gcloud user credentials return `{:error, :no_private_key}`.
  """
  def signer() do
    case credentials() do
      {:ok, %{"private_key" => pem, "client_email" => email}} -> {:ok, {email, pem}}
      {:ok, _other} -> {:error, :no_private_key}
      {:error, reason} -> {:error, reason}
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

  defp adc_file(), do: Path.expand(@adc_file)

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

  @doc """
  Decodes a PEM private key into the term `:public_key.sign/3` expects.
  """
  def private_key(pem) do
    pem |> :public_key.pem_decode() |> hd() |> :public_key.pem_entry_decode()
  end
end
