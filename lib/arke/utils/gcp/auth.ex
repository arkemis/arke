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
  Access tokens and the url signer for `Arke.Utils.Gcp`.

  Tokens come from Goth, which resolves `config :goth`, then
  `GOOGLE_APPLICATION_CREDENTIALS` / `GOOGLE_APPLICATION_CREDENTIALS_JSON`, then
  gcloud ADC, then the GCE/GKE metadata server: the last one is what Workload
  Identity uses, with no key anywhere.

  Urls are signed through the IAM Credentials `signBlob` API as
  `STORAGE_SERVICE_ACCOUNT` or, when unset, as the metadata server's account.
  The caller needs `iam.serviceAccounts.signBlob` on that account.

  Tokens are cached per node until shortly before they expire, and the metadata
  server's account email for the life of the node.
  """

  @metadata_email_url "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email"

  # Tokens change about hourly, so the global GC a :persistent_term update
  # triggers costs less than a process to own an ETS table.
  @cache {__MODULE__, :cache}
  # A token handed out this close to expiry could die mid-request.
  @expiry_margin 60
  @attempts 3

  @doc """
  An OAuth access token for the credentials Goth resolves.
  """
  def token(), do: cached(:token, fn -> fetch_token(@attempts) end)

  @doc """
  The account urls are signed as: `opts[:service_account]`, then
  `STORAGE_SERVICE_ACCOUNT`, then the metadata server's account.
  """
  def signer_email(opts \\ []) do
    case opts[:service_account] || System.get_env("STORAGE_SERVICE_ACCOUNT") do
      nil -> cached(:metadata_email, &metadata_email/0)
      email -> {:ok, email}
    end
  end

  @doc false
  def clear_cache(), do: :persistent_term.erase(@cache)

  # The GKE metadata server can be unreachable for the first seconds of a pod.
  defp fetch_token(attempts_left) do
    case goth_token() do
      {:ok, %{token: token, expires: expires}} ->
        {:ok, token, expires - @expiry_margin}

      {:error, _reason} when attempts_left > 1 ->
        Process.sleep(500 * (@attempts - attempts_left + 1))
        fetch_token(attempts_left - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Goth loads its config on first use and raises when it cannot, e.g. when
  # the metadata server is not up yet.
  defp goth_token() do
    Goth.Token.fetch([])
  rescue
    e -> {:error, e}
  end

  # Plain text, unlike the token endpoint.
  defp metadata_email() do
    case Tesla.get(@metadata_email_url,
           headers: [{"metadata-flavor", "Google"}],
           opts: [adapter: [timeout: 5_000, connect_timeout: 8_000]]
         ) do
      {:ok, %{status: 200, body: email}} -> signer_from_metadata(String.trim(email))
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Workload Identity without a bound Google service account answers with the
  # pool itself, which signBlob cannot sign as.
  defp signer_from_metadata(email) do
    if String.ends_with?(email, ".svc.id.goog") do
      {:error,
       "#{email} is a workload identity pool and cannot sign: " <>
         "bind a Google service account or set STORAGE_SERVICE_ACCOUNT"}
    else
      # The account is fixed for the life of the pod.
      {:ok, email, :infinity}
    end
  end

  # Expiries are unix seconds or :infinity, which sorts above every integer.
  defp cached(key, fetch) do
    now = System.os_time(:second)

    case :persistent_term.get(@cache, %{}) do
      %{^key => {value, expires_at}} when expires_at > now ->
        {:ok, value}

      _ ->
        with {:ok, value, expires_at} <- fetch.() do
          cache = :persistent_term.get(@cache, %{})
          :persistent_term.put(@cache, Map.put(cache, key, {value, expires_at}))
          {:ok, value}
        end
    end
  end
end
