// Copyright 2023 Arkemis S.r.l.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// ISO8601 parsing + month arithmetic for Arke.Utils.DatetimeHandler.
// In: binary. Out: integer tuples (or nil). Elixir rebuilds the structs.

use chrono::{DateTime, Datelike, Months, NaiveDate, NaiveDateTime, NaiveTime, Timelike, Utc};

type DateTuple = (i32, u32, u32);
// h, mi, s, micro, precision (fractional digits, 0..6)
type TimeTuple = (u32, u32, u32, u32, u32);
// nested to fit rustler's tuple arity limit
type DateTimeTuple = (DateTuple, TimeTuple);

// fractional-second digits, capped at 6 — keeps the rebuilt struct's precision
fn frac_precision(s: &str) -> u32 {
    match s.find('.') {
        None => 0,
        Some(i) => {
            let n = s[i + 1..].bytes().take_while(u8::is_ascii_digit).count();
            n.min(6) as u32
        }
    }
}

#[rustler::nif]
fn parse_date(s: &str) -> Option<DateTuple> {
    let d = NaiveDate::parse_from_str(s.trim(), "%Y-%m-%d").ok()?;
    Some((d.year(), d.month(), d.day()))
}

#[rustler::nif]
fn parse_time(s: &str) -> Option<TimeTuple> {
    let s = s.trim();
    let t = NaiveTime::parse_from_str(s, "%H:%M:%S%.f")
        .or_else(|_| NaiveTime::parse_from_str(s, "%H:%M:%S"))
        .ok()?;
    Some((
        t.hour(),
        t.minute(),
        t.second(),
        t.nanosecond() / 1_000,
        frac_precision(s),
    ))
}

// offset-aware -> UTC; naive (T or space separated) assumed UTC
#[rustler::nif]
fn parse_datetime(s: &str) -> Option<DateTimeTuple> {
    let s = s.trim();

    let prec = frac_precision(s);

    if let Ok(dt) = DateTime::parse_from_rfc3339(s) {
        return Some(to_tuple(dt.with_timezone(&Utc).naive_utc(), prec));
    }

    for fmt in [
        "%Y-%m-%dT%H:%M:%S%.f",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d %H:%M:%S%.f",
        "%Y-%m-%d %H:%M:%S",
    ] {
        if let Ok(ndt) = NaiveDateTime::parse_from_str(s, fmt) {
            return Some(to_tuple(ndt, prec));
        }
    }

    None
}

// add months (signed), end-of-month clamped (Jan 31 + 1 -> Feb 28/29)
#[rustler::nif]
fn add_months(y: i32, m: u32, d: u32, months: i64) -> Option<DateTuple> {
    let date = NaiveDate::from_ymd_opt(y, m, d)?;
    let shifted = if months >= 0 {
        date.checked_add_months(Months::new(months as u32))?
    } else {
        date.checked_sub_months(Months::new(months.unsigned_abs() as u32))?
    };
    Some((shifted.year(), shifted.month(), shifted.day()))
}

fn to_tuple(ndt: NaiveDateTime, prec: u32) -> DateTimeTuple {
    (
        (ndt.year(), ndt.month(), ndt.day()),
        (
            ndt.hour(),
            ndt.minute(),
            ndt.second(),
            ndt.nanosecond() / 1_000,
            prec,
        ),
    )
}

rustler::init!("Elixir.Arke.Native.DateParser");

#[cfg(test)]
mod tests {
    use super::frac_precision;

    #[test]
    fn frac_precision_counts_capped_digits() {
        assert_eq!(frac_precision("12:00:00"), 0);
        assert_eq!(frac_precision("12:00:00.5"), 1);
        assert_eq!(frac_precision("12:00:00.123456"), 6);
        assert_eq!(frac_precision("12:00:00.1234567890"), 6);
        assert_eq!(frac_precision("2020-01-01T12:00:00.25+02:00"), 2);
    }
}
