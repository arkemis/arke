defmodule Arke.Utils.DatetimeHandlerTest do
  use ExUnit.Case, async: true

  alias Arke.Utils.DatetimeHandler, as: DatetimeHandler

  @datetime_msg "must be %DateTime{} | %NaiveDatetime{} | ~N[YYYY-MM-DDTHH:MM:SS] | ~N[YYYY-MM-DD HH:MM:SS] | ~U[YYYY-MM-DD HH:MM:SS]  format"
  @date_msg "must be %Date{} | ~D[YYYY-MM-DD] | iso8601 (YYYY-MM-DD) format"
  @time_msg "must be must be %Time{} |~T[HH:MM:SS] | iso8601 (HH:MM:SS) format"
  @general_msg " values must be %Date{} | ~D[YYYY-MM-DD]| %DateTime{} | %NaiveDateTime{} | ~N[YYYY-MM-DDTHH:MM:SS] | ~N[YYYY-MM-DD HH:MM:SS] | ~U[YYYY-MM-DD HH:MM:SS]"

  describe "now/1" do
    test "returns a second-precision UTC datetime" do
      now = DatetimeHandler.now(:datetime)
      assert %DateTime{} = now
      assert now.microsecond == {0, 0}
      assert now.time_zone == "Etc/UTC"
    end

    test "returns a date" do
      assert %Date{} = DatetimeHandler.now(:date)
    end

    test "returns a second-precision time" do
      assert DatetimeHandler.now(:time).microsecond == {0, 0}
    end
  end

  describe "from_unix/2" do
    test "converts epoch seconds" do
      assert DatetimeHandler.from_unix(0) == ~U[1970-01-01 00:00:00Z]
      assert DatetimeHandler.from_unix(1_700_000_000) == ~U[2023-11-14 22:13:20Z]
    end

    test "honours an explicit unit" do
      assert DatetimeHandler.from_unix(1_700_000_000_000, :millisecond) ==
               ~U[2023-11-14 22:13:20.000Z]
    end
  end

  describe "parse_datetime/2" do
    test "handles nil in both modes" do
      assert DatetimeHandler.parse_datetime(nil, false) == {:ok, nil}
      assert DatetimeHandler.parse_datetime(nil, true) == nil
    end

    test "accepts a DateTime in both modes" do
      assert DatetimeHandler.parse_datetime(~U[2024-03-05 10:20:30Z], false) ==
               {:ok, ~U[2024-03-05 10:20:30Z]}

      assert DatetimeHandler.parse_datetime(~U[2024-03-05 10:20:30Z], true) ==
               ~U[2024-03-05 10:20:30Z]
    end

    test "promotes a NaiveDateTime to UTC" do
      assert DatetimeHandler.parse_datetime(~N[2024-03-05 10:20:30], false) ==
               {:ok, ~U[2024-03-05 10:20:30Z]}
    end

    test "preserves sub-second precision" do
      assert DatetimeHandler.parse_datetime(~N[2024-03-05 10:20:30.500], false) ==
               {:ok, ~U[2024-03-05 10:20:30.500Z]}
    end

    test "accepts a zulu string" do
      assert DatetimeHandler.parse_datetime("2024-03-05T10:20:30Z") ==
               {:ok, ~U[2024-03-05 10:20:30Z]}
    end

    test "normalises a non-UTC offset" do
      assert DatetimeHandler.parse_datetime("2024-03-05T10:20:30+02:00") ==
               {:ok, ~U[2024-03-05 08:20:30Z]}
    end

    test "accepts a space separator" do
      assert DatetimeHandler.parse_datetime("2024-03-05 10:20:30") ==
               {:ok, ~U[2024-03-05 10:20:30Z]}
    end

    test "accepts a zone-less string" do
      assert DatetimeHandler.parse_datetime("2024-03-05T10:20:30") ==
               {:ok, ~U[2024-03-05 10:20:30Z]}
    end

    test "accepts fractional seconds" do
      assert DatetimeHandler.parse_datetime("2024-03-05T10:20:30.123Z") ==
               {:ok, ~U[2024-03-05 10:20:30.123Z]}
    end

    test "rejects date-only, garbage, empty and numbers" do
      assert DatetimeHandler.parse_datetime("2024-03-05") == {:error, @datetime_msg}
      assert DatetimeHandler.parse_datetime("garbage") == {:error, @datetime_msg}
      assert DatetimeHandler.parse_datetime("") == {:error, @datetime_msg}
      assert DatetimeHandler.parse_datetime(12_345) == {:error, @datetime_msg}
      assert DatetimeHandler.parse_datetime(~D[2024-03-05]) == {:error, @datetime_msg}
    end

    test "reports errors as a tuple even when only_value is true" do
      assert DatetimeHandler.parse_datetime("garbage", true) == {:error, @datetime_msg}
    end
  end

  describe "parse_date/2" do
    test "handles nil in both modes" do
      assert DatetimeHandler.parse_date(nil, false) == {:ok, nil}
      assert DatetimeHandler.parse_date(nil, true) == nil
    end

    test "accepts a Date in both modes" do
      assert DatetimeHandler.parse_date(~D[2024-03-05], false) == {:ok, ~D[2024-03-05]}
      assert DatetimeHandler.parse_date(~D[2024-03-05], true) == ~D[2024-03-05]
    end

    test "accepts a zero-padded iso8601 date" do
      assert DatetimeHandler.parse_date("2024-03-05") == {:ok, ~D[2024-03-05]}
    end

    test "rejects unpadded dates, datetime strings and DateTime structs" do
      assert DatetimeHandler.parse_date("2024-3-5") == {:error, @date_msg}
      assert DatetimeHandler.parse_date("2024-03-05T10:20:30Z") == {:error, @date_msg}
      assert DatetimeHandler.parse_date(~U[2024-03-05 10:20:30Z]) == {:error, @date_msg}
      assert DatetimeHandler.parse_date("garbage") == {:error, @date_msg}
    end
  end

  describe "parse_time/2" do
    test "handles nil in both modes" do
      assert DatetimeHandler.parse_time(nil, false) == {:ok, nil}
      assert DatetimeHandler.parse_time(nil, true) == nil
    end

    test "accepts a Time in both modes" do
      assert DatetimeHandler.parse_time(~T[10:20:30], false) == {:ok, ~T[10:20:30]}
      assert DatetimeHandler.parse_time(~T[10:20:30], true) == ~T[10:20:30]
    end

    test "preserves sub-second precision" do
      assert DatetimeHandler.parse_time(~T[10:20:30.250], false) == {:ok, ~T[10:20:30.250]}
    end

    test "accepts an iso8601 time" do
      assert DatetimeHandler.parse_time("10:20:30") == {:ok, ~T[10:20:30]}
    end

    test "rejects times without seconds, numbers and garbage" do
      assert DatetimeHandler.parse_time("10:20") == {:error, @time_msg}
      assert DatetimeHandler.parse_time(123) == {:error, @time_msg}
      assert DatetimeHandler.parse_time("garbage") == {:error, @time_msg}
    end
  end

  describe "format/2 and format!/2" do
    @dt ~U[2024-03-05 10:20:30Z]

    test "defaults to an extended iso8601 string with a numeric offset" do
      assert DatetimeHandler.format(@dt) == {:ok, "2024-03-05T10:20:30+00:00"}
    end

    test "renders the basic zulu format" do
      assert DatetimeHandler.format(@dt, "{ISO:Basic:Z}") == {:ok, "20240305T102030Z"}
    end

    test "returns a bare string from the bang variant" do
      assert DatetimeHandler.format!(@dt, "{ISO:Basic:Z}") == "20240305T102030Z"
    end

    test "zero-fills the time component of a Date" do
      assert DatetimeHandler.format(~D[2024-03-05], "{ISO:Basic:Z}") == {:ok, "20240305T000000Z"}
    end

    test "formats a NaiveDateTime" do
      assert DatetimeHandler.format(~N[2024-03-05 10:20:30], "{ISO:Basic:Z}") ==
               {:ok, "20240305T102030Z"}
    end
  end

  describe "shift_datetime/2 month arithmetic" do
    test "clamps to the last valid day of the target month" do
      assert DatetimeHandler.shift_datetime(~U[2024-01-31 00:00:00Z], months: 1) ==
               ~U[2024-02-29 00:00:00Z]

      assert DatetimeHandler.shift_datetime(~U[2024-05-31 00:00:00Z], months: 1) ==
               ~U[2024-06-30 00:00:00Z]
    end

    test "clamps when shifting backwards" do
      assert DatetimeHandler.shift_datetime(~U[2024-03-31 00:00:00Z], months: -1) ==
               ~U[2024-02-29 00:00:00Z]
    end

    test "carries across year boundaries" do
      assert DatetimeHandler.shift_datetime(~U[2024-12-31 00:00:00Z], months: 1) ==
               ~U[2025-01-31 00:00:00Z]

      assert DatetimeHandler.shift_datetime(~U[2024-01-31 00:00:00Z], months: 13) ==
               ~U[2025-02-28 00:00:00Z]
    end

    test "is a no-op for a zero shift" do
      assert DatetimeHandler.shift_datetime(~U[2024-01-31 00:00:00Z], months: 0) ==
               ~U[2024-01-31 00:00:00Z]
    end
  end

  describe "shift_datetime/2 year arithmetic" do
    test "overflows a leap day into March rather than clamping" do
      assert DatetimeHandler.shift_datetime(~U[2024-02-29 00:00:00Z], years: 1) ==
               ~U[2025-03-01 00:00:00Z]

      assert DatetimeHandler.shift_datetime(~U[2024-02-29 00:00:00Z], years: -1) ==
               ~U[2023-03-01 00:00:00Z]
    end

    test "disagrees with the equivalent month shift on a leap day" do
      assert DatetimeHandler.shift_datetime(~U[2024-02-29 00:00:00Z], months: 12) ==
               ~U[2025-02-28 00:00:00Z]
    end

    test "leaves a non-leap date untouched" do
      assert DatetimeHandler.shift_datetime(~U[2023-02-28 00:00:00Z], years: 1) ==
               ~U[2024-02-28 00:00:00Z]
    end
  end

  describe "shift_datetime/2 day and clock arithmetic" do
    test "shifts by weeks and days" do
      assert DatetimeHandler.shift_datetime(~U[2024-03-05 10:20:30Z], weeks: 2) ==
               ~U[2024-03-19 10:20:30Z]

      assert DatetimeHandler.shift_datetime(~U[2024-03-05 10:20:30Z], days: 1) ==
               ~U[2024-03-06 10:20:30Z]
    end

    test "shifts backwards across month boundaries" do
      assert DatetimeHandler.shift_datetime(~U[2024-03-01 00:00:00Z], days: -1) ==
               ~U[2024-02-29 00:00:00Z]

      assert DatetimeHandler.shift_datetime(~U[2024-01-01 00:00:00Z], weeks: -1) ==
               ~U[2023-12-25 00:00:00Z]
    end

    test "shifts by hours and seconds" do
      assert DatetimeHandler.shift_datetime(~U[2024-03-05 10:20:30Z], hours: 5) ==
               ~U[2024-03-05 15:20:30.000000Z]

      assert DatetimeHandler.shift_datetime(~U[2024-03-05 10:20:30Z], seconds: 90) ==
               ~U[2024-03-05 10:22:00.000000Z]
    end

    test "applies combined units" do
      assert DatetimeHandler.shift_datetime(~U[2024-03-05 10:20:30Z], months: 1, days: 2) ==
               ~U[2024-04-07 10:20:30Z]
    end
  end

  describe "shift_datetime/2 precision" do
    test "keeps second precision for calendar units" do
      base = ~U[2024-03-05 10:20:30Z]
      assert DatetimeHandler.shift_datetime(base, days: 1).microsecond == {0, 0}
      assert DatetimeHandler.shift_datetime(base, weeks: 1).microsecond == {0, 0}
      assert DatetimeHandler.shift_datetime(base, months: 1).microsecond == {0, 0}
    end

    test "widens to microsecond precision for clock units" do
      base = ~U[2024-03-05 10:20:30Z]
      assert DatetimeHandler.shift_datetime(base, hours: 5).microsecond == {0, 6}
      assert DatetimeHandler.shift_datetime(base, minutes: 1).microsecond == {0, 6}
    end
  end

  describe "shift_datetime with non-struct input" do
    test "parses a string before shifting" do
      assert DatetimeHandler.shift_datetime("2024-01-31T00:00:00Z", months: 1) ==
               ~U[2024-02-29 00:00:00Z]
    end

    test "propagates a parse error instead of shifting" do
      assert DatetimeHandler.shift_datetime("garbage", days: 1) == {:error, @datetime_msg}
    end

    test "shifts relative to now when given only options" do
      assert %DateTime{} = DatetimeHandler.shift_datetime(weeks: 2)
    end
  end

  describe "shift_date/2" do
    test "clamps to the last valid day of the target month" do
      assert DatetimeHandler.shift_date(~D[2024-01-31], months: 1) == ~D[2024-02-29]
    end

    test "overflows a leap day into March" do
      assert DatetimeHandler.shift_date(~D[2024-02-29], years: 1) == ~D[2025-03-01]
    end

    test "shifts by weeks" do
      assert DatetimeHandler.shift_date(~D[2024-03-05], weeks: 2) == ~D[2024-03-19]
    end

    test "parses a string before shifting" do
      assert DatetimeHandler.shift_date("2024-01-31", days: 1) == ~D[2024-02-01]
    end

    test "shifts relative to today when given only options" do
      assert %Date{} = DatetimeHandler.shift_date(days: 1)
    end
  end

  describe "after?/2 and before?/2" do
    @earlier ~U[2024-03-05 10:20:30Z]
    @later ~U[2024-03-06 10:20:30Z]

    test "orders two datetimes" do
      assert DatetimeHandler.after?(@later, @earlier) == true
      assert DatetimeHandler.after?(@earlier, @later) == false
      assert DatetimeHandler.before?(@earlier, @later) == true
    end

    test "treats equal datetimes as neither after nor before" do
      assert DatetimeHandler.after?(@earlier, @earlier) == false
      assert DatetimeHandler.before?(@earlier, @earlier) == false
    end

    test "orders dates and naive datetimes" do
      assert DatetimeHandler.after?(~D[2024-03-06], ~D[2024-03-05]) == true
      assert DatetimeHandler.after?(~N[2024-03-06 00:00:00], ~N[2024-03-05 00:00:00]) == true
    end

    test "compares a datetime against a date" do
      assert DatetimeHandler.after?(@earlier, ~D[2024-03-05]) == true
    end

    test "returns a bare message string for invalid input" do
      assert DatetimeHandler.after?("garbage", @earlier) == @general_msg
      assert DatetimeHandler.after?(nil, nil) == @general_msg
      assert DatetimeHandler.before?(nil, nil) == @general_msg
    end
  end
end
