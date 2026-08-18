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
  @moduledoc """
  Google Cloud Storage backend for `Arke.Utils.FileStorage`.

  Talks to the GCS JSON API over Req. The requests it builds are pinned by
  `test/support/fixtures/gcs_requests.exs`.
  """
  use Arke.Utils.FileStorage
  require Logger

  alias Arke.Utils.ErrorGenerator, as: Error
  alias Arke.Utils.Gcp.Auth

  @storage_base_url "https://storage.googleapis.com"

  def upload_file(file_name, file_data, opts) do
    params =
      [uploadType: "multipart"] ++
        if(opts[:public], do: [predefinedAcl: "publicread"], else: [])

    body = [
      metadata: {Jason.encode!(%{name: file_name}), content_type: "application/json"},
      data: {file_data, content_type: "application/octet-stream"}
    ]

    request(
      method: :post,
      url: "/upload/storage/v1/b/#{encode_segment(bucket(opts))}/o",
      params: params,
      form_multipart: body
    )
    |> handle_response(:json)
  end

  def get_file(file_path, opts) do
    request(method: :get, url: object_url(file_path, opts))
    |> handle_response(:json)
  end

  def get_public_url(%{data: %{name: name, path: path, extension: _ext}} = _unit, opts) do
    bucket = opts[:bucket] || System.get_env("DEFAULT_BUCKET")

    {:ok,
     %{signed_url: "https://storage.googleapis.com/#{bucket}/#{path}/#{name}", expiration: nil}}
  end

  def get_public_url(_unit, _opts), do: Error.create(:storage, "invalid unit")

  def delete_file(file_path, opts) do
    request(method: :delete, url: object_url(file_path, opts))
    |> handle_response(:raw)
  end

  @doc """
  A V2 signed url for the object.

  Signing is delegated to `Arke.Utils.Gcp.Auth.sign/1`, which uses the private
  key when the credentials carry one and the IAM Credentials API otherwise.
  """
  def get_bucket_file_signed_url(file_path, opts) do
    if opts[:service_account] do
      Logger.warning(
        "service_account option is ignored: urls are signed as the credentials' client_email"
      )
    end

    expires = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(1 * 3600)
    resource = "/#{bucket(opts)}/#{URI.encode(file_path)}"
    string_to_sign = ["GET", "", "", expires, resource] |> Enum.join("\n")

    case Auth.sign(string_to_sign) do
      {:ok, {client_email, signature}} ->
        qs =
          %{
            "GoogleAccessId" => client_email,
            "Expires" => expires,
            "Signature" => Base.encode64(signature)
          }
          |> URI.encode_query()

        {:ok,
         %{
           signed_url: Enum.join(["#{@storage_base_url}#{resource}", "?", qs]),
           expiration: expires
         }}

      {:error, reason} ->
        Logger.warning("error on gcp signed url: #{inspect(reason)}")
        {:error, "error on signed url"}
    end
  end

  # Req retries safe requests by default; keep every call one-shot and bounded.
  defp request(opts) do
    {:ok, token} = Auth.token()

    Req.request(
      [
        base_url: @storage_base_url,
        headers: [
          {"authorization", "Bearer #{token}"},
          {"x-goog-api-client", api_client()}
        ],
        retry: false,
        receive_timeout: 5_000,
        connect_options: [timeout: 8_000]
      ] ++ opts
    )
  end

  defp api_client(), do: "gl-elixir/#{System.version()} arke/#{Application.spec(:arke, :vsn)}"

  defp bucket(opts), do: opts[:bucket] || System.get_env("DEFAULT_BUCKET")

  defp object_url(file_path, opts),
    do: "/storage/v1/b/#{encode_segment(bucket(opts))}/o/#{encode_segment(file_path)}"

  defp encode_segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp handle_response({:error, reason}, _), do: {:error, reason}

  defp handle_response({:ok, %{status: status} = response}, _)
       when status < 200 or status >= 300,
       do: {:error, response}

  defp handle_response({:ok, response}, :raw), do: {:ok, response}
  defp handle_response({:ok, %{body: body}}, :json) when body in [nil, ""], do: {:ok, nil}
  # Req decodes the JSON body from the response content-type.
  defp handle_response({:ok, %{body: body}}, :json), do: {:ok, body}
end
