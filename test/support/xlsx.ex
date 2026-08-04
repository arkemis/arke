defmodule Arke.Test.Xlsx do
  @moduledoc """
  Builds a minimal `.xlsx` on disk so the import path can be driven without a
  binary fixture in the repo.

  Cells are written as inline strings whose text lives in `<v>`: that is where
  Xlsxir reads it from, rather than the `<is><t>` an Excel-written file uses.
  """

  @spec write([[term()]], Path.t()) :: Path.t()
  def write(rows, path) do
    {:ok, {_name, zip}} =
      :zip.create(
        ~c"test.xlsx",
        [
          {~c"xl/workbook.xml", workbook()},
          {~c"xl/worksheets/sheet1.xml", sheet(rows)}
        ],
        [:memory]
      )

    File.write!(path, zip)
    path
  end

  defp workbook do
    ~s(<?xml version="1.0"?><workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>)
  end

  defp sheet(rows) do
    body =
      rows
      |> Enum.with_index(1)
      |> Enum.map_join(fn {row, r} ->
        cells = row |> Enum.with_index() |> Enum.map_join(&cell(&1, r))
        ~s(<row r="#{r}">#{cells}</row>)
      end)

    ~s(<?xml version="1.0"?><worksheet><sheetData>#{body}</sheetData></worksheet>)
  end

  defp cell({nil, c}, r), do: ~s(<c r="#{column(c)}#{r}"/>)

  defp cell({value, c}, r) when is_number(value),
    do: ~s(<c r="#{column(c)}#{r}"><v>#{value}</v></c>)

  defp cell({value, c}, r),
    do: ~s(<c r="#{column(c)}#{r}" t="inlineStr"><v>#{value}</v></c>)

  defp column(index) when index < 26, do: <<?A + index>>
end
