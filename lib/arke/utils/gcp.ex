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

defmodule Arke.Utils.Gcp do
  use Arke.Utils.FileStorage
  require Logger

  alias Arke.Utils.ErrorGenerator, as: Error
  alias Arke.Utils.Gcp.Auth
  @storage Application.get_env(:arke, :storage)
  @service_account @storage[:gcp][:service_account]
  @default_bucket @storage[:gcp][:default_bucket]

  def upload_file(file_name, file_data, opts \\ []) do
    bucket = opts[:bucket] || System.get_env("DEFAULT_BUCKET")

    query =
      [uploadType: "multipart"] ++
        if(opts[:public], do: [predefinedAcl: "publicread"], else: [])

    # Built here rather than through storage_objects_insert_iodata: google_gax
    # names the multipart fields with atoms, which tesla >= 1.21 rejects before
    # sending anything.
    body =
      Tesla.Multipart.new()
      |> Tesla.Multipart.add_field("metadata", Poison.encode!(%{name: file_name}),
        headers: [{"content-type", "application/json"}]
      )
      |> Tesla.Multipart.add_field("data", file_data,
        headers: [{"content-type", "application/octet-stream"}]
      )

    # Callers branch on {:error, _}: a failed upload must reach them, not crash.
    with {:ok, conn} <- get_connection() do
      conn
      |> Tesla.post(
        "https://storage.googleapis.com/upload/storage/v1/b/#{URI.encode(bucket, &URI.char_unreserved?/1)}/o",
        body,
        query: query
      )
      |> GoogleApi.Gax.Response.decode(struct: %GoogleApi.Storage.V1.Model.Object{})
    end
  end

  def get_file(file_path, opts \\ []) do
    bucket = opts[:bucket] || System.get_env("DEFAULT_BUCKET")

    with {:ok, conn} <- get_connection() do
      GoogleApi.Storage.V1.Api.Objects.storage_objects_get(
        conn,
        bucket,
        file_path
      )
    end
  end

  def get_public_url(%{data: %{name: name, path: path, extension: ext}} = unit, opts \\ []) do
    bucket = opts[:bucket] || System.get_env("DEFAULT_BUCKET")
    {:ok, %{signed_url: "https://storage.googleapis.com/#{bucket}/#{path}/#{name}",expiration: nil}}
  end

  def get_public_url(_unit, _opts), do: Error.create(:storage, "invalid unit")

  def delete_file(file_path, opts \\ []) do
    bucket = opts[:bucket] || System.get_env("DEFAULT_BUCKET")

    with {:ok, conn} <- get_connection() do
      GoogleApi.Storage.V1.Api.Objects.storage_objects_delete(
        conn,
        bucket,
        file_path
      )
    end
  end

  def get_bucket_file_signed_url(file_path, opts \\ []) do
    with {:ok, gcp_service_account} <- Auth.signer_email(opts),
         {:ok, conn} <- get_connection() do
      sign_url(conn, gcp_service_account, file_path, opts)
    else
      {:error, reason} ->
        Logger.warning("error on gcp signed url: #{inspect(reason)}")
        {:error, "error on signed url"}
    end
  end

  defp sign_url(conn, gcp_service_account, file_path, opts) do
    bucket = opts[:bucket] || System.get_env("DEFAULT_BUCKET")
    headers = [{"Content-Type", "application/json"}]

    url =
      "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/#{gcp_service_account}:signBlob"

    expires = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(1 * 3600)
    resource = "/#{bucket}/#{URI.encode(file_path)}"
    signature = ["GET", "", "", expires, resource] |> Enum.join("\n") |> Base.encode64()
    body = %{"payload" => signature} |> Poison.encode!()

    case Tesla.post(conn, url, body,
           headers: headers,
           opts: [adapter: [timeout: 5_000, connect_timeout: 8_000]]
         ) do
      {:ok, %{status: 200, body: result}} ->
        %{"signedBlob" => signed_blob} = Poison.decode!(result)

        qs =
          %{
            "GoogleAccessId" => gcp_service_account,
            "Expires" => expires,
            "Signature" => signed_blob
          }
          |> URI.encode_query()

        {:ok,
         %{
           signed_url: Enum.join(["https://storage.googleapis.com#{resource}", "?", qs]),
           expiration: expires
         }}

      {:ok, %{status: 403}} ->
        {:error, "Forbidden resource"}

      # Only status and body: the request env carries the bearer token.
      {:ok, %{status: status, body: body}} ->
        Logger.warning("error on gcp signed url: #{status} #{inspect(body)}")
        {:error, "error on signed url"}

      {:error, reason} ->
        Logger.warning("error on gcp signed url: #{inspect(reason)}")
        {:error, "error on signed url"}
    end
  end

  defp get_connection() do
    with {:ok, token} <- Auth.token() do
      {:ok, GoogleApi.Storage.V1.Connection.new(token)}
    end
  end
end
