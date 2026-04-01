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

  alias Arke.Utils.ErrorGenerator, as: Error
  @storage Application.get_env(:arke, :storage)
  @service_account @storage[:gcp][:service_account]
  @default_bucket @storage[:gcp][:default_bucket]

  def upload_file(file_name, file_data, opts \\ []) do
    bucket = opts[:bucket] || System.get_env("DEFAULT_BUCKET")
    optional_metadata = if opts[:public], do: [predefinedAcl: "publicread"], else: []
    conn = get_connection()

    {:ok, object} =
      GoogleApi.Storage.V1.Api.Objects.storage_objects_insert_iodata(
        conn,
        bucket,
        "multipart",
        %{name: file_name},
        file_data,
        optional_metadata
      )
  end

  def get_file(file_path, opts \\ []) do
    bucket = opts[:bucket] || System.get_env("DEFAULT_BUCKET")
    conn = get_connection()

    GoogleApi.Storage.V1.Api.Objects.storage_objects_get(
      conn,
      bucket,
      file_path
    )
  end

  def get_public_url(%{data: %{name: name, path: path, extension: ext}} = unit, opts \\ []) do
    bucket = opts[:bucket] || System.get_env("DEFAULT_BUCKET")
    {:ok, %{signed_url: "https://storage.googleapis.com/#{bucket}/#{path}/#{name}",expiration: nil}}
  end

  def get_public_url(_unit, _opts), do: Error.create(:storage, "invalid unit")

  def delete_file(file_path, opts \\ []) do
    bucket = opts[:bucket] || System.get_env("DEFAULT_BUCKET")
    conn = get_connection()

    GoogleApi.Storage.V1.Api.Objects.storage_objects_delete(
      conn,
      bucket,
      file_path
    )
  end

  def get_bucket_file_signed_url(file_path, opts \\ []) do
    gcp_service_account = opts[:service_account] || System.get_env("STORAGE_SERVICE_ACCOUNT")
    bucket = opts[:bucket] || System.get_env("DEFAULT_BUCKET")

    %Tesla.Client{pre: [{Tesla.Middleware.Headers, :call, [auth_headers]}]} = get_connection()
    headers = [{"Content-Type", "application/json"}] ++ auth_headers

    url =
      "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/#{gcp_service_account}:signBlob"

    expires = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(1 * 3600)
    resource = "/#{bucket}/#{URI.encode(file_path)}"
    signature = ["GET", "", "", expires, resource] |> Enum.join("\n") |> Base.encode64()
    body = %{"payload" => signature} |> Poison.encode!()

    case HTTPoison.post(url, body, headers) do
      {:ok, %{status_code: 200, body: result}} ->
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

      {:ok, %{status_code: 403} = err} ->
        {:error, "Forbidden resource"}

      {:ok, e} ->
        IO.inspect(e)
        {:error, "error on signed url"}
    end
  end

  defp get_connection() do
    {:ok, token} = Goth.Token.fetch([])
    GoogleApi.Storage.V1.Connection.new(token.token)
  end
end
