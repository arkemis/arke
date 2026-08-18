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
  @default_ttl 3600

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
  A V4 signed url for the object.

  Signing is delegated to `Arke.Utils.Gcp.Auth.sign/1`, which uses the private
  key when the credentials carry one and the IAM Credentials API otherwise.
  """
  def get_bucket_file_signed_url(file_path, opts) do
    if opts[:service_account] do
      Logger.warning(
        "service_account option is ignored: urls are signed as the credentials' client_email"
      )
    end

    now = DateTime.utc_now()
    ttl = @default_ttl
    resource = "/#{escape_path(bucket(opts))}/#{escape_path(file_path)}"

    # The signer's email is part of what gets signed, so it is resolved before
    # the payload exists rather than read back off the signature.
    with {:ok, client_email} <- Auth.signer_email(),
         params <- signing_params(client_email, now, ttl),
         string_to_sign <- string_to_sign(resource, params, now),
         {:ok, {_email, signature}} <- Auth.sign(string_to_sign) do
      qs =
        params
        |> Map.put("X-Goog-Signature", Base.encode16(signature, case: :lower))
        |> URI.encode_query()

      {:ok,
       %{
         signed_url: Enum.join(["#{@storage_base_url}#{resource}", "?", qs]),
         expiration: DateTime.to_unix(now) + ttl
       }}
    else
      {:error, reason} ->
        Logger.warning("error on gcp signed url: #{inspect(reason)}")
        {:error, "error on signed url"}
    end
  end

  defp signing_params(client_email, now, ttl) do
    %{
      "X-Goog-Algorithm" => "GOOG4-RSA-SHA256",
      "X-Goog-Credential" => "#{client_email}/#{credential_scope(now)}",
      "X-Goog-Date" => goog_date(now),
      "X-Goog-Expires" => ttl,
      "X-Goog-SignedHeaders" => "host"
    }
  end

  # Every byte here has to match what the client will send, or GCS answers
  # SignatureDoesNotMatch with no indication of which byte differed.
  defp string_to_sign(resource, params, now) do
    canonical_request =
      Enum.join(
        [
          "GET",
          resource,
          canonical_query(params),
          "host:#{URI.parse(@storage_base_url).host}",
          "",
          "host",
          "UNSIGNED-PAYLOAD"
        ],
        "\n"
      )

    Enum.join(
      [
        "GOOG4-RSA-SHA256",
        goog_date(now),
        credential_scope(now),
        hex(:crypto.hash(:sha256, canonical_request))
      ],
      "\n"
    )
  end

  defp canonical_query(params) do
    params
    |> Enum.sort()
    |> Enum.map_join("&", fn {name, value} ->
      "#{escape(name)}=#{escape(to_string(value))}"
    end)
  end

  defp credential_scope(now), do: "#{Calendar.strftime(now, "%Y%m%d")}/auto/storage/goog4_request"

  defp goog_date(now), do: Calendar.strftime(now, "%Y%m%dT%H%M%SZ")

  defp escape(value), do: URI.encode(value, &URI.char_unreserved?/1)

  # Separators stay separators; everything inside a segment is escaped.
  defp escape_path(path), do: path |> String.split("/") |> Enum.map_join("/", &escape/1)

  defp hex(binary), do: Base.encode16(binary, case: :lower)

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
