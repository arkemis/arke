defmodule Arke.Utils.DatetimeHandlerTest do
  use ExUnit.Case, async: true
  alias Arke.Utils.DatetimeHandler, as: D

  describe "parse_date/2" do
    test "valid iso date" do
      assert D.parse_date("2020-01-31") == {:ok, ~D[2020-01-31]}
      assert D.parse_date("2020-01-31", true) == ~D[2020-01-31]
    end

    test "passthrough for %Date{}" do
      assert D.parse_date(~D[1993-11-15]) == {:ok, ~D[1993-11-15]}
    end

    test "nil" do
      assert D.parse_date(nil) == {:ok, nil}
      assert D.parse_date(nil, true) == nil
    end

    test "invalid -> error" do
      assert {:error, _} = D.parse_date("31-01-1999")
      assert {:error, _} = D.parse_date("not a date")
      assert {:error, _} = D.parse_date("2020-13-40")
    end
  end

  describe "parse_time/2" do
    test "no fraction keeps precision 0 (struct equality with Timex path)" do
      assert D.parse_time("23:59:12") == {:ok, ~T[23:59:12]}
    end

    test "microsecond fraction" do
      assert D.parse_time("06:45:15.123456") == {:ok, ~T[06:45:15.123456]}
    end

    test "invalid -> error" do
      assert {:error, _} = D.parse_time("25:00:00")
      assert {:error, _} = D.parse_time("nope")
    end
  end

  describe "parse_datetime/2" do
    test "naive space-separated, assumed UTC, precision 0" do
      assert D.parse_datetime("1999-01-31 23:59:12") == {:ok, ~U[1999-01-31 23:59:12Z]}
    end

    test "Z suffix" do
      assert D.parse_datetime("2020-01-01T12:00:00Z") == {:ok, ~U[2020-01-01 12:00:00Z]}
    end

    test "offset normalized to UTC" do
      assert D.parse_datetime("2020-01-01T12:00:00+02:00") == {:ok, ~U[2020-01-01 10:00:00Z]}
    end

    test "fractional seconds preserved" do
      assert D.parse_datetime("2020-01-01T12:00:00.500000Z") ==
               {:ok, ~U[2020-01-01 12:00:00.500000Z]}
    end

    test "passthrough for %DateTime{} / %NaiveDateTime{}" do
      assert D.parse_datetime(~U[2000-01-31 23:59:12Z]) == {:ok, ~U[2000-01-31 23:59:12Z]}
      assert D.parse_datetime(~N[2000-01-31 23:59:12]) == {:ok, ~U[2000-01-31 23:59:12Z]}
    end

    test "invalid -> error" do
      assert {:error, _} = D.parse_datetime("not a date")
      assert {:error, _} = D.parse_datetime("2020-13-01 00:00:00")
    end
  end

  # parse the same ISO string with NIF and with the stdlib, compare
  describe "randomized: NIF == Elixir stdlib parser" do
    test "datetime" do
      for _ <- 1..2000 do
        iso = DateTime.to_iso8601(rand_datetime())
        {:ok, expected, _offset} = DateTime.from_iso8601(iso)
        assert D.parse_datetime(iso) == {:ok, expected}
      end
    end

    test "date" do
      for _ <- 1..2000 do
        iso =
          Date.to_iso8601(
            Date.new!(Enum.random(1970..2100), Enum.random(1..12), Enum.random(1..28))
          )

        {:ok, expected} = Date.from_iso8601(iso)
        assert D.parse_date(iso) == {:ok, expected}
      end
    end

    test "time incl. precision" do
      for _ <- 1..2000 do
        iso = Time.to_iso8601(rand_time())
        {:ok, expected} = Time.from_iso8601(iso)
        assert D.parse_time(iso) == {:ok, expected}
      end
    end
  end

  describe "now / from_unix / format / compare (stdlib, no Timex)" do
    test "now" do
      assert %DateTime{microsecond: {0, 0}} = D.now(:datetime)
      assert %Date{} = D.now(:date)
      assert %Time{microsecond: {0, 0}} = D.now(:time)
    end

    test "from_unix -> UTC" do
      assert D.from_unix(0) == ~U[1970-01-01 00:00:00Z]
    end

    test "format extended/basic" do
      assert D.format(~U[2020-01-02 03:04:05Z]) == {:ok, "2020-01-02T03:04:05Z"}
      assert D.format(~U[2020-01-02 03:04:05Z], "{ISO:Basic:Z}") == {:ok, "20200102T030405Z"}
      assert D.format!(~D[2020-01-02]) == "2020-01-02"
    end

    test "after?/before?" do
      assert D.after?(~U[2020-01-02 00:00:00Z], ~U[2020-01-01 00:00:00Z])
      refute D.before?(~U[2020-01-02 00:00:00Z], ~U[2020-01-01 00:00:00Z])
      assert D.before?(~D[2020-01-01], ~D[2020-01-02])
    end
  end

  describe "shift (NIF calendar math + stdlib deltas)" do
    test "month add with end-of-month clamp" do
      assert D.shift_datetime(~U[2020-01-31 00:00:00Z], months: 1) == ~U[2020-02-29 00:00:00Z]
      assert D.shift_datetime(~U[2021-01-31 00:00:00Z], months: 1) == ~U[2021-02-28 00:00:00Z]
    end

    test "years/days/hours mix" do
      assert D.shift_datetime(~U[2020-01-01 00:00:00Z], years: 1, days: 2, hours: 3) ==
               ~U[2021-01-03 03:00:00Z]
    end

    test "negative shift" do
      assert D.shift_datetime(~U[2020-03-31 00:00:00Z], months: -1) == ~U[2020-02-29 00:00:00Z]
    end

    test "shift_date" do
      assert D.shift_date(~D[2020-01-31], months: 1) == ~D[2020-02-29]
      assert D.shift_date(~D[2020-01-01], weeks: 1) == ~D[2020-01-08]
    end

    test "NIF == stdlib month math (randomized)" do
      for _ <- 1..2000 do
        y = Enum.random(1970..2100)
        m = Enum.random(1..12)
        d = Enum.random(1..28)
        n = Enum.random(-48..48)
        base = ~U[2000-01-01 00:00:00Z]
        from_nif = D.shift_datetime(%{base | year: y, month: m, day: d}, months: n)
        # same math in plain Elixir
        total = y * 12 + (m - 1) + n
        ey = Integer.floor_div(total, 12)
        em = Integer.mod(total, 12) + 1
        ed = min(d, Date.days_in_month(Date.new!(ey, em, 1)))
        assert {from_nif.year, from_nif.month, from_nif.day} == {ey, em, ed}
      end
    end
  end

  defp rand_time do
    prec = Enum.random(0..6)
    micro = if prec == 0, do: 0, else: Enum.random(0..999_999)
    Time.new!(Enum.random(0..23), Enum.random(0..59), Enum.random(0..59), {micro, prec})
  end

  defp rand_datetime do
    date = Date.new!(Enum.random(1970..2100), Enum.random(1..12), Enum.random(1..28))
    DateTime.new!(date, rand_time(), "Etc/UTC")
  end
end
