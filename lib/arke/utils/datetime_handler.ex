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

defmodule Arke.Utils.DatetimeHandler do
  @moduledoc """
  Parsing, formatting and arithmetic helpers for the temporal parameter types.

  Every value handled here is UTC. Datetime strings are accepted either with an
  explicit offset or without one, in which case they are read as UTC.
  """

  @datetime_msg "must be %DateTime{} | %NaiveDatetime{} | ~N[YYYY-MM-DDTHH:MM:SS] | ~N[YYYY-MM-DD HH:MM:SS] | ~U[YYYY-MM-DD HH:MM:SS]  format"

  @date_msg "must be %Date{} | ~D[YYYY-MM-DD] | iso8601 (YYYY-MM-DD) format"

  @time_msg "must be must be %Time{} |~T[HH:MM:SS] | iso8601 (HH:MM:SS) format"
  @general_msg " values must be %Date{} | ~D[YYYY-MM-DD]| %DateTime{} | %NaiveDateTime{} | ~N[YYYY-MM-DDTHH:MM:SS] | ~N[YYYY-MM-DD HH:MM:SS] | ~U[YYYY-MM-DD HH:MM:SS]"

  @utc "Etc/UTC"
  @clock_units [:hours, :minutes, :seconds]

  def now(:datetime), do: DateTime.utc_now() |> DateTime.truncate(:second)
  def now(:date), do: Date.utc_today()
  def now(:time), do: Time.utc_now() |> Time.truncate(:second)

  # ----- DATETIME -----

  def from_unix(s, unit \\ :second), do: DateTime.from_unix!(s, unit)

  def parse_datetime(value, only_value \\ false)
  def parse_datetime(nil, true), do: nil
  def parse_datetime(nil, _only_value), do: {:ok, nil}

  def parse_datetime(%DateTime{} = value, only_value), do: wrap(value, only_value)

  def parse_datetime(%NaiveDateTime{} = value, only_value),
    do: wrap(DateTime.from_naive!(value, @utc), only_value)

  def parse_datetime(value, only_value) when is_binary(value) do
    case decode_datetime(value) do
      {:ok, datetime} -> wrap(datetime, only_value)
      :error -> {:error, @datetime_msg}
    end
  end

  def parse_datetime(_value, _only_value), do: {:error, @datetime_msg}

  def format(value, format \\ "{ISO:Extended}")

  def format(value, format) do
    case to_datetime(value) do
      {:ok, datetime} -> encode(datetime, format)
      :error -> {:error, @datetime_msg}
    end
  end

  def format!(value, format \\ "{ISO:Extended}") do
    case format(value, format) do
      {:ok, formatted} -> formatted
      {:error, msg} -> raise ArgumentError, message: msg
    end
  end

  def shift_datetime(datetime, opts) do
    case parse_datetime(datetime) do
      {:ok, value} -> shift_units(value, opts)
      {:error, msg} -> {:error, msg}
    end
  end

  def shift_datetime(opts), do: shift_datetime(now(:datetime), opts)

  # ----- DATE -----

  def parse_date(value, only_value \\ false)
  def parse_date(nil, true), do: nil
  def parse_date(nil, _only_value), do: {:ok, nil}

  def parse_date(%Date{} = value, only_value), do: wrap(value, only_value)

  def parse_date(value, only_value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> wrap(date, only_value)
      {:error, _} -> {:error, @date_msg}
    end
  end

  def parse_date(_value, _only_value), do: {:error, @date_msg}

  def shift_date(date, opts) do
    case parse_date(date) do
      {:ok, value} -> shift_calendar_units(value, opts)
      {:error, msg} -> {:error, msg}
    end
  end

  def shift_date(opts), do: shift_date(now(:date), opts)

  # ----- TIME -----

  def parse_time(value, only_value \\ false)
  def parse_time(nil, true), do: nil
  def parse_time(nil, _only_value), do: {:ok, nil}

  def parse_time(%Time{} = value, only_value), do: wrap(value, only_value)

  def parse_time(value, only_value) when is_binary(value) do
    case Time.from_iso8601(value) do
      {:ok, time} -> wrap(time, only_value)
      {:error, _} -> {:error, @time_msg}
    end
  end

  def parse_time(_value, _only_value), do: {:error, @time_msg}

  # ----- COMPARISON -----

  def after?(first_date, second_date) do
    case compare(first_date, second_date) do
      :error -> @general_msg
      result -> result == :gt
    end
  end

  def before?(first_date, second_date) do
    case compare(first_date, second_date) do
      :error -> @general_msg
      result -> result == :lt
    end
  end

  defp compare(first, second) do
    with {:ok, first} <- to_datetime(first),
         {:ok, second} <- to_datetime(second) do
      DateTime.compare(first, second)
    else
      _ -> :error
    end
  end

  defp wrap(value, true), do: value
  defp wrap(value, _only_value), do: {:ok, value}

  defp decode_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      {:error, _} ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive} -> {:ok, DateTime.from_naive!(naive, @utc)}
          {:error, _} -> :error
        end
    end
  end

  defp to_datetime(%DateTime{} = value), do: {:ok, value}
  defp to_datetime(%NaiveDateTime{} = value), do: {:ok, DateTime.from_naive!(value, @utc)}
  defp to_datetime(%Date{} = value), do: {:ok, DateTime.new!(value, ~T[00:00:00], @utc)}
  defp to_datetime(value) when is_binary(value), do: decode_datetime(value)
  defp to_datetime(_value), do: :error

  defp encode(datetime, "{ISO:Basic:Z}"), do: {:ok, DateTime.to_iso8601(datetime, :basic)}

  defp encode(datetime, "{ISO:Extended}") do
    formatted =
      datetime
      |> DateTime.to_iso8601(:extended)
      |> String.replace_suffix("Z", "+00:00")

    {:ok, formatted}
  end

  defp encode(_datetime, format),
    do: {:error, "unsupported datetime format #{inspect(format)}"}

  defp shift_units(datetime, opts) do
    shifted = shift_calendar_units(datetime, opts)

    case clock_seconds(opts) do
      nil -> shifted
      seconds -> shifted |> DateTime.add(seconds, :second) |> with_microsecond_precision()
    end
  end

  defp shift_calendar_units(value, opts) do
    value
    |> shift_years(Keyword.get(opts, :years, 0))
    |> shift_months(Keyword.get(opts, :months, 0))
    |> shift_days(Keyword.get(opts, :weeks, 0) * 7 + Keyword.get(opts, :days, 0))
  end

  defp clock_seconds(opts) do
    if Enum.any?(@clock_units, &Keyword.has_key?(opts, &1)) do
      Keyword.get(opts, :hours, 0) * 3600 + Keyword.get(opts, :minutes, 0) * 60 +
        Keyword.get(opts, :seconds, 0)
    else
      nil
    end
  end

  defp with_microsecond_precision(%DateTime{microsecond: {value, _precision}} = datetime),
    do: %{datetime | microsecond: {value, 6}}

  defp shift_days(value, 0), do: value
  defp shift_days(%Date{} = date, days), do: Date.add(date, days)

  defp shift_days(%DateTime{} = datetime, days),
    do: replace_date(datetime, Date.add(datetime, days))

  defp shift_years(value, 0), do: value

  defp shift_years(value, years) do
    %{year: year, month: month, day: day} = value
    target = year + years

    case Date.new(target, month, day) do
      {:ok, date} ->
        replace_date(value, date)

      {:error, _} ->
        last = days_in_month(target, month)
        replace_date(value, Date.new!(target, month, last) |> Date.add(day - last))
    end
  end

  defp shift_months(value, 0), do: value

  defp shift_months(value, months) do
    %{year: year, month: month, day: day} = value
    total = year * 12 + (month - 1) + months
    target_year = div(total, 12)
    target_month = rem(total, 12) + 1
    target_day = min(day, days_in_month(target_year, target_month))

    replace_date(value, Date.new!(target_year, target_month, target_day))
  end

  defp days_in_month(year, month), do: Date.days_in_month(Date.new!(year, month, 1))

  defp replace_date(%Date{}, date), do: date

  defp replace_date(%DateTime{} = datetime, date),
    do: %{datetime | year: date.year, month: date.month, day: date.day}
end
