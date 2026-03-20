defmodule Arke.Errors.ArkeError do
  alias Arke.Utils.ErrorGenerator, as: Error
  defexception [:message, type: nil]

  def message(%{message: nil}), do: "message is required"

  def message(%{message: msg, type: nil}) when is_binary(msg) do
    {:error, [%{context: context, message: message}]} = Error.create(:arke, msg)
    "context: #{context}, message: #{message}"
  end

  def message(%{message: [%{context: context, message: message}]} = exception),
    do: "context: #{context}, message: #{message}"

  def message(%{message: errors} = exception) when is_list(errors) do
    formatted_errors =
      errors
      |> Enum.map(&format_error/1)
      |> Enum.join("\n")

    "Found multiple errors:\n" <> formatted_errors
  end

  defp format_error(%{context: context, message: message}) do
    "- context: #{context}, message: #{message}"
  end
end
