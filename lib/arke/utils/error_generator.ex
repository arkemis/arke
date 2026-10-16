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

defmodule Arke.Utils.ErrorGenerator do
  @moduledoc """
  Documentation for `Arke.Utils.ErrorGenerator`
  """

  @doc """
  Create standardized errors

  ## Parameters
    - context => string => the context where the error has been generated
    - errors => list | string => the error itself; a `{label, message, code}` tuple sets a per-error code
    - opts => keyword => `code:` a stable key (e.g. for translations) added to errors without one

  ## Example
      iex> Arke.Utils.ErrorGenerator.create(:auth, "login error")

  ## Return
       {:error , [%{context: "context_value", message: "message_value"}, ...]}
  """

  @type error() :: %{
          required(:context) => String.t(),
          required(:message) => String.t(),
          optional(:code) => String.t()
        }
  @type t() :: {:error, [error()]}

  @spec create(context :: String.t(), errors :: list() | String.t(), opts :: keyword()) :: t()
  def create(context, errors, opts \\ [])

  def create(context, errors, opts) when is_list(errors) or is_binary(errors) do
    {:error, context |> create_map(errors) |> put_code(opts[:code])}
  end

  def create(context, errors, opts) when is_atom(errors) do
    create(context, Atom.to_string(errors), opts)
  end

  def create(_context, _errors, _opts), do: create(:error_generator, "invalid attribute format")

  defp put_code(errors, nil), do: errors
  defp put_code(errors, code), do: Enum.map(errors, &Map.put_new(&1, :code, code))

  defp create_map(_context, _errors, error_list \\ [])

  defp create_map(context, [{message, values, code} | t], error_list) do
    [error] = create_map(context, [{message, values}])
    create_map(context, t, error_list ++ [Map.put(error, :code, code)])
  end

  defp create_map(context, [{message, values} = _h | t] = _errors, error_list)
       when is_list(values) do
    create_map(
      context,
      t,
      error_list ++
        [%{context: to_string(context), message: "#{message}: #{Enum.join(values, ", ")}"}]
    )
  end

  defp create_map(context, errors, error_list) when is_binary(errors) do
    create_map(context, [], error_list ++ [%{context: to_string(context), message: errors}])
  end

  defp create_map(context, [{message, values} | t] = _errors, error_list) do
    create_map(
      context,
      t,
      error_list ++ [%{context: to_string(context), message: "#{message}: #{values}"}]
    )
  end

  defp create_map(_context, [], error_list) do
    error_list
  end

  defp create_map(context, errors, error_list) when is_list(errors) do
    errors_from_list =
      Enum.map(errors, fn v -> %{context: to_string(context), message: to_string(v)} end)

    create_map(context, [], error_list ++ errors_from_list)
  end
end
