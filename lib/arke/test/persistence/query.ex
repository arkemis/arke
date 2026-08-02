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

defmodule Arke.Test.Persistence.Query do
  @moduledoc false

  # Evaluates an `Arke.Core.Query` against a list of units, in memory. Operator
  # semantics mirror the `arke_postgres` adapter so that a suite running on
  # `Arke.Test.Persistence` and one running on Postgres agree. Unsupported
  # operators raise rather than silently matching everything.

  alias Arke.Core.Unit

  @spec run([Unit.t()], Arke.Core.Query.t()) :: [Unit.t()]
  def run(units, query) do
    units
    |> Enum.filter(&matches_all?(&1, Map.get(query, :filters) || []))
    |> order(Map.get(query, :orders) || [])
    |> distinct(Map.get(query, :distinct))
    |> drop(Map.get(query, :offset))
    |> take(Map.get(query, :limit))
  end

  defp matches_all?(unit, filters), do: Enum.all?(filters, &matches?(unit, &1))

  defp matches?(unit, %{logic: logic, negate: negate, base_filters: base_filters}) do
    result =
      case logic do
        :or -> Enum.any?(base_filters, &matches_base?(unit, &1))
        _ -> Enum.all?(base_filters, &matches_base?(unit, &1))
      end

    if negate, do: not result, else: result
  end

  defp matches_base?(unit, %{
         parameter: parameter,
         operator: operator,
         value: value,
         negate: negate
       }) do
    result = compare(value_of(unit, parameter), value, operator, multiple?(parameter))
    if negate, do: not result, else: result
  end

  defp multiple?(%{data: %{multiple: multiple}}), do: multiple == true
  defp multiple?(_), do: false

  defp value_of(unit, %{id: id}), do: value_of(unit, id)

  defp value_of(unit, id) when id in [:id, :arke_id, :metadata, :inserted_at, :updated_at],
    do: Map.get(unit, id)

  defp value_of(%Unit{} = unit, id), do: Unit.get_value(unit, id)

  # a `multiple` parameter holds a list; :eq asks whether the value is in it
  defp compare(actual, value, :eq, true) when is_list(actual), do: value in actual
  defp compare(actual, value, :eq, _), do: equal?(actual, value)
  defp compare(actual, _value, :isnull, _), do: is_nil(actual)

  defp compare(actual, value, :in, _) when is_list(value),
    do: Enum.any?(value, &equal?(actual, &1))

  defp compare(nil, _value, _operator, _), do: false

  defp compare(actual, value, :contains, _),
    do: String.contains?(to_string(actual), to_string(value))

  defp compare(actual, value, :icontains, _),
    do: String.contains?(downcase(actual), downcase(value))

  defp compare(actual, value, :startswith, _),
    do: String.starts_with?(to_string(actual), to_string(value))

  defp compare(actual, value, :istartswith, _),
    do: String.starts_with?(downcase(actual), downcase(value))

  defp compare(actual, value, :endswith, _),
    do: String.ends_with?(to_string(actual), to_string(value))

  defp compare(actual, value, :iendswith, _),
    do: String.ends_with?(downcase(actual), downcase(value))

  defp compare(actual, value, :lt, _), do: actual < value
  defp compare(actual, value, :lte, _), do: actual <= value
  defp compare(actual, value, :gt, _), do: actual > value
  defp compare(actual, value, :gte, _), do: actual >= value

  defp compare(_actual, _value, operator, _) do
    raise ArgumentError,
          "Arke.Test.Persistence does not implement the #{inspect(operator)} operator. " <>
            "Add it here and to the arke_postgres adapter's semantics."
  end

  # ids round-trip through the registry as both atoms and strings
  defp equal?(actual, value) when is_atom(actual) and is_binary(value),
    do: to_string(actual) == value

  defp equal?(actual, value) when is_binary(actual) and is_atom(value),
    do: actual == to_string(value)

  defp equal?(actual, value), do: actual == value

  defp downcase(value), do: value |> to_string() |> String.downcase()

  defp order(units, []), do: units

  defp order(units, orders) do
    Enum.sort(units, fn left, right ->
      Enum.reduce_while(orders, true, fn %{parameter: parameter, direction: direction}, _acc ->
        l = value_of(left, parameter)
        r = value_of(right, parameter)

        cond do
          l == r -> {:cont, true}
          direction == :desc -> {:halt, l > r}
          true -> {:halt, l < r}
        end
      end)
    end)
  end

  defp distinct(units, true), do: Enum.uniq(units)
  defp distinct(units, _), do: units

  defp drop(units, nil), do: units
  defp drop(units, offset), do: Enum.drop(units, offset)

  defp take(units, nil), do: units
  defp take(units, limit), do: Enum.take(units, limit)
end
