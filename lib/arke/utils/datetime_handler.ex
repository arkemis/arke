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
  Date/time helpers. ISO parsing and month shifting go through the Rust NIF
  (`Arke.Native.DateParser`), with a pure-Elixir fallback; the rest uses the
  stdlib.
  """
  alias Arke.Native.DateParser

  @datetime_msg "must be %DateTime{} | %NaiveDatetime{} | ~N[YYYY-MM-DDTHH:MM:SS] | ~N[YYYY-MM-DD HH:MM:SS] | ~U[YYYY-MM-DD HH:MM:SS]  format"
  @date_msg "must be %Date{} | ~D[YYYY-MM-DD] | iso8601 (YYYY-MM-DD) format"
  @time_msg "must be must be %Time{} |~T[HH:MM:SS] | iso8601 (HH:MM:SS) format"
  @general_msg " values must be %Date{} | ~D[YYYY-MM-DD]| %DateTime{} | %NaiveDateTime{} | ~N[YYYY-MM-DDTHH:MM:SS] | ~N[YYYY-MM-DD HH:MM:SS] | ~U[YYYY-MM-DD HH:MM:SS]"

  # ----- now / from_unix -----

  def now(:datetime), do: DateTime.utc_now() |> DateTime.truncate(:second)
  def now(:date), do: Date.utc_today()
  def now(:time), do: Time.utc_now() |> Time.truncate(:second)

  def from_unix(s, unit \\ :second), do: DateTime.from_unix!(s, unit)

  # ----- DATETIME -----

  def parse_datetime(value, only_value \\ false)
  def parse_datetime(value, true) when is_nil(value), do: value
  def parse_datetime(value, _only_value) when is_nil(value), do: {:ok, value}

  def parse_datetime(%DateTime{} = value, only_value),
    do: wrap(to_utc(value), only_value)

  def parse_datetime(%NaiveDateTime{} = value, only_value),
    do: wrap(DateTime.from_naive!(value, "Etc/UTC"), only_value)

  def parse_datetime(value, only_value) when is_binary(value) do
    case nif_parse_datetime(value) do
      {:ok, datetime} -> wrap(datetime, only_value)
      :error -> {:error, @datetime_msg}
      :fallback -> stdlib_parse_datetime(value, only_value)
    end
  end

  def parse_datetime(_value, _only_value), do: {:error, @datetime_msg}

  defp nif_parse_datetime(value) do
    case DateParser.parse_datetime(value) do
      {{y, m, d}, {h, mi, s, micro, prec}} ->
        with {:ok, date} <- Date.new(y, m, d),
             {:ok, time} <- Time.new(h, mi, s, {micro, prec}),
             {:ok, datetime} <- DateTime.new(date, time, "Etc/UTC") do
          {:ok, datetime}
        else
          _ -> :error
        end

      nil ->
        :error
    end
  rescue
    ErlangError -> :fallback
  end

  defp stdlib_parse_datetime(value, only_value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        wrap(to_utc(datetime), only_value)

      {:error, _} ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive} -> wrap(DateTime.from_naive!(naive, "Etc/UTC"), only_value)
          {:error, _} -> {:error, @datetime_msg}
        end
    end
  end

  def shift_datetime(datetime, opts) do
    case parse_datetime(datetime) do
      {:ok, value} -> do_shift(value, opts)
      {:error, msg} -> {:error, msg}
    end
  end

  def shift_datetime(opts), do: do_shift(now(:datetime), opts)

  # ----- DATE -----

  def parse_date(value, only_value \\ false)
  def parse_date(value, true) when is_nil(value), do: nil
  def parse_date(value, _only_value) when is_nil(value), do: {:ok, nil}

  def parse_date(%Date{} = value, only_value), do: wrap(value, only_value)

  def parse_date(value, only_value) when is_binary(value) do
    case nif_parse_date(value) do
      {:ok, date} -> wrap(date, only_value)
      :error -> {:error, @date_msg}
      :fallback -> stdlib_parse_date(value, only_value)
    end
  end

  def parse_date(_value, _only_value), do: {:error, @date_msg}

  defp nif_parse_date(value) do
    case DateParser.parse_date(value) do
      {y, m, d} ->
        case Date.new(y, m, d) do
          {:ok, date} -> {:ok, date}
          _ -> :error
        end

      nil ->
        :error
    end
  rescue
    ErlangError -> :fallback
  end

  defp stdlib_parse_date(value, only_value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> wrap(date, only_value)
      {:error, _} -> {:error, @date_msg}
    end
  end

  def shift_date(date, opts) do
    case parse_date(date) do
      {:ok, value} -> do_shift(value, opts)
      {:error, msg} -> {:error, msg}
    end
  end

  def shift_date(opts), do: do_shift(now(:date), opts)

  # ----- TIME -----

  def parse_time(value, only_value \\ false)
  def parse_time(value, true) when is_nil(value), do: nil
  def parse_time(value, _only_value) when is_nil(value), do: {:ok, nil}
  def parse_time(value, _only_value) when is_number(value), do: {:error, @time_msg}

  def parse_time(%Time{} = value, only_value), do: wrap(value, only_value)

  def parse_time(value, only_value) when is_binary(value) do
    case nif_parse_time(value) do
      {:ok, time} -> wrap(time, only_value)
      :error -> {:error, @time_msg}
      :fallback -> stdlib_parse_time(value, only_value)
    end
  end

  def parse_time(_value, _only_value), do: {:error, @time_msg}

  defp nif_parse_time(value) do
    case DateParser.parse_time(value) do
      {h, mi, s, micro, prec} ->
        case Time.new(h, mi, s, {micro, prec}) do
          {:ok, time} -> {:ok, time}
          _ -> :error
        end

      nil ->
        :error
    end
  rescue
    ErlangError -> :fallback
  end

  defp stdlib_parse_time(value, only_value) do
    case Time.from_iso8601(value) do
      {:ok, time} -> wrap(time, only_value)
      {:error, _} -> {:error, @time_msg}
    end
  end

  # ----- format / compare -----

  def format(value, format \\ "{ISO:Extended}"), do: {:ok, iso8601(value, format)}
  def format!(value, format \\ "{ISO:Extended}"), do: iso8601(value, format)

  def after?(a, b), do: compare(a, b, :gt)
  def before?(a, b), do: compare(a, b, :lt)

  # ----- helpers -----

  defp wrap(value, true), do: value
  defp wrap(value, false), do: {:ok, value}

  defp to_utc(%DateTime{time_zone: "Etc/UTC"} = dt), do: dt
  defp to_utc(%DateTime{} = dt), do: DateTime.shift_zone!(dt, "Etc/UTC")

  defp iso8601(%Date{} = v, fmt), do: Date.to_iso8601(v, iso_mode(fmt))
  defp iso8601(%Time{} = v, fmt), do: Time.to_iso8601(v, iso_mode(fmt))
  defp iso8601(%DateTime{} = v, fmt), do: DateTime.to_iso8601(v, iso_mode(fmt))
  defp iso8601(%NaiveDateTime{} = v, fmt), do: NaiveDateTime.to_iso8601(v, iso_mode(fmt))

  defp iso_mode(fmt) do
    if String.contains?(fmt, "Basic"), do: :basic, else: :extended
  end

  defp compare(%Time{} = a, %Time{} = b, want), do: Time.compare(a, b) == want
  defp compare(%Date{} = a, %Date{} = b, want), do: Date.compare(a, b) == want

  defp compare(a, b, want) do
    with {:ok, da} <- parse_datetime(a),
         {:ok, db} <- parse_datetime(b) do
      DateTime.compare(da, db) == want
    else
      _ -> @general_msg
    end
  end

  # ----- shift -----
  # months via NIF, the rest via stdlib

  defp do_shift(value, opts) do
    months = opt(opts, :years) * 12 + opt(opts, :months)
    days = opt(opts, :weeks) * 7 + opt(opts, :days)
    seconds = opt(opts, :hours) * 3600 + opt(opts, :minutes) * 60 + opt(opts, :seconds)
    micros = opt(opts, :microseconds) + opt(opts, :milliseconds) * 1000

    value
    |> add_months(months)
    |> add_delta(days, seconds, micros)
  end

  defp add_months(value, 0), do: value

  defp add_months(value, months) do
    {y, m, d} = ymd(value)

    {ny, nm, nd} =
      try do
        case DateParser.add_months(y, m, d, months) do
          {a, b, c} -> {a, b, c}
          nil -> add_months_stdlib(y, m, d, months)
        end
      rescue
        ErlangError -> add_months_stdlib(y, m, d, months)
      end

    put_ymd(value, ny, nm, nd)
  end

  defp add_months_stdlib(y, m, d, months) do
    total = y * 12 + (m - 1) + months
    ny = Integer.floor_div(total, 12)
    nm = Integer.mod(total, 12) + 1
    last = Date.days_in_month(Date.new!(ny, nm, 1))
    {ny, nm, min(d, last)}
  end

  defp add_delta(%Date{} = v, days, _seconds, _micros), do: Date.add(v, days)

  defp add_delta(v, days, seconds, micros) do
    v
    |> DateTime.add(days, :day)
    |> DateTime.add(seconds, :second)
    |> add_micros(micros)
  end

  # adding 0 µs would bump precision to 6; skip it
  defp add_micros(v, 0), do: v
  defp add_micros(v, micros), do: DateTime.add(v, micros, :microsecond)

  defp ymd(%Date{year: y, month: m, day: d}), do: {y, m, d}
  defp ymd(%DateTime{year: y, month: m, day: d}), do: {y, m, d}

  defp put_ymd(%Date{} = v, y, m, d), do: %{v | year: y, month: m, day: d}
  defp put_ymd(%DateTime{} = v, y, m, d), do: %{v | year: y, month: m, day: d}

  defp opt(opts, key), do: Keyword.get(opts, key, 0) || 0
end
