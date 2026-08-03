defmodule Arke.Test.Gcp do
  @moduledoc """
  Helpers for comparing what `Arke.Utils.Gcp` puts on the wire against the
  requests the archived `google_api_storage` client used to produce.

  `project_request/1` (a `%Req.Request{}` as it reaches the adapter) and
  `project_fixture/1` (a recorded request) reduce both sides to the same shape,
  so the recording stays exactly as captured.
  """

  @fixtures_path "test/support/fixtures/gcs_requests.exs"

  # Headers that describe the client or the transport rather than the request:
  # `x-goog-api-client` and `user-agent` name the library that built it, and the
  # recording negotiated compression (`gzip, deflate, identity`) where Req asks
  # for none.
  @ignored_headers ["x-goog-api-client", "user-agent", "accept-encoding"]

  @doc """
  A throwaway service account: a PKCS#8 private key as Google hands it out,
  plus the public key to verify signatures with.
  """
  def service_account(email \\ "signer@project.iam.gserviceaccount.com") do
    key = :public_key.generate_key({:rsa, 2048, 65537})

    %{
      email: email,
      pem: :public_key.pem_encode([:public_key.pem_entry_encode(:PrivateKeyInfo, key)]),
      public_key: {:RSAPublicKey, elem(key, 2), elem(key, 3)}
    }
  end

  @doc """
  The requests `google_api_storage` produced, recorded under tesla 1.16.0 — the
  last version where that stack worked.
  """
  def request_fixtures() do
    {fixtures, _} = Code.eval_file(@fixtures_path)
    fixtures
  end

  @doc """
  Reduce a `%Req.Request{}` to the parts that must match the recording.
  """
  def project_request(request) do
    %{
      method: request.method,
      url: request.url |> struct(query: nil) |> URI.to_string(),
      query: URI.decode_query(request.url.query || ""),
      headers: request |> Req.get_headers_list() |> reject_framing_headers() |> normalize_headers(),
      body: project_request_body(request)
    }
  end

  # Tesla's adapter derived the multipart content-type (with a random boundary)
  # and the content-length from the body after the middleware stack, so the
  # recording has neither. Both restate what the compared body already says.
  defp reject_framing_headers(headers) do
    Enum.reject(headers, fn {name, value} ->
      String.downcase(name) == "content-length" or
        (String.downcase(name) == "content-type" and
           String.starts_with?(value, "multipart/form-data"))
    end)
  end

  @doc """
  Reduce a recorded request to the same shape as `project_request/1`.
  """
  def project_fixture(fixture) do
    %{
      method: fixture.method,
      url: fixture.url,
      query: Map.new(fixture.query, fn {k, v} -> {to_string(k), to_string(v)} end),
      headers: normalize_headers(fixture.headers),
      body: project_fixture_body(fixture.body)
    }
  end

  defp normalize_headers(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
    |> Enum.reject(fn {k, _} -> k in @ignored_headers end)
    |> Enum.sort()
  end

  # Req hands the adapter an already encoded multipart body, so parse it back
  # into parts; the boundary is random and carries no meaning.
  defp project_request_body(request) do
    case Req.Request.get_header(request, "content-type") do
      ["multipart/form-data; boundary=" <> boundary] ->
        %{kind: :multipart, parts: parse_parts(request.body, boundary)}

      _ ->
        %{kind: :raw, body: blank_to_nil(request.body)}
    end
  end

  defp parse_parts(body, boundary) do
    body
    |> IO.iodata_to_binary()
    |> String.split("--" <> boundary)
    # the leading empty string and the trailing "--\r\n" footer
    |> Enum.slice(1..-2//1)
    |> Enum.map(&parse_part/1)
  end

  defp parse_part("\r\n" <> part) do
    [head, body] = String.split(part, "\r\n\r\n", parts: 2)

    {[{_, disposition}], headers} =
      head
      |> String.split("\r\n")
      |> Enum.map(fn line ->
        [name, value] = String.split(line, ": ", parts: 2)
        {name, value}
      end)
      |> Enum.split_with(fn {name, _} -> name == "content-disposition" end)

    %{
      name: part_name(disposition),
      headers: normalize_headers(headers),
      body: String.replace_suffix(body, "\r\n", "")
    }
  end

  defp part_name(disposition) do
    [_, name] = Regex.run(~r/name="([^"]*)"/, disposition)
    name
  end

  defp project_fixture_body(%{kind: :multipart, parts: parts}) do
    parts =
      Enum.map(parts, fn part ->
        %{
          name: to_string(part.dispositions[:name]),
          headers: normalize_headers(part.headers),
          body: part.body
        }
      end)

    %{kind: :multipart, parts: parts}
  end

  defp project_fixture_body(%{kind: :raw, body: body}),
    do: %{kind: :raw, body: blank_to_nil(body)}

  # google_api_storage sent an empty string where Req sends no body at all;
  # neither puts bytes on the wire.
  defp blank_to_nil(body) when body in [nil, ""], do: nil
  defp blank_to_nil(body), do: body
end
