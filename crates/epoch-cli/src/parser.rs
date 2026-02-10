use chrono::{NaiveDate, NaiveDateTime, NaiveTime};
use thiserror::Error;

const SECONDS_THRESHOLD: u128 = 100_000_000_000;
const MILLISECONDS_THRESHOLD: u128 = 100_000_000_000_000;
const MICROSECONDS_THRESHOLD: u128 = 100_000_000_000_000_000;

const DATE_TIME_FORMATS: [&str; 6] = [
    "%Y-%m-%d %H:%M",
    "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%d %H:%M:%S%.f",
    "%Y-%m-%dT%H:%M",
    "%Y-%m-%dT%H:%M:%S",
    "%Y-%m-%dT%H:%M:%S%.f",
];

const TIME_ONLY_FORMATS: [&str; 3] = ["%H:%M", "%H:%M:%S", "%H:%M:%S%.f"];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EpochUnit {
    Seconds,
    Milliseconds,
    Microseconds,
    Nanoseconds,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EpochInput {
    pub value: i128,
    pub unit: EpochUnit,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum QueryInput {
    Empty,
    Epoch(EpochInput),
    DateTime(NaiveDateTime),
}

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum ParseError {
    #[error("unsupported query format: {0}")]
    UnsupportedQuery(String),
}

pub fn parse_query(raw_query: &str, today: NaiveDate) -> Result<QueryInput, ParseError> {
    let query = raw_query.trim();
    if query.is_empty() {
        return Ok(QueryInput::Empty);
    }

    if let Ok(epoch_value) = query.parse::<i128>() {
        return Ok(QueryInput::Epoch(EpochInput {
            value: epoch_value,
            unit: infer_epoch_unit(epoch_value),
        }));
    }

    if let Some(datetime) = parse_datetime(query, today) {
        return Ok(QueryInput::DateTime(datetime));
    }

    Err(ParseError::UnsupportedQuery(query.to_string()))
}

fn infer_epoch_unit(epoch_value: i128) -> EpochUnit {
    let magnitude = epoch_value.unsigned_abs();

    if magnitude < SECONDS_THRESHOLD {
        EpochUnit::Seconds
    } else if magnitude < MILLISECONDS_THRESHOLD {
        EpochUnit::Milliseconds
    } else if magnitude < MICROSECONDS_THRESHOLD {
        EpochUnit::Microseconds
    } else {
        EpochUnit::Nanoseconds
    }
}

fn parse_datetime(query: &str, today: NaiveDate) -> Option<NaiveDateTime> {
    for format in DATE_TIME_FORMATS {
        if let Ok(datetime) = NaiveDateTime::parse_from_str(query, format) {
            return Some(datetime);
        }
    }

    if let Ok(date) = NaiveDate::parse_from_str(query, "%Y-%m-%d") {
        return date.and_hms_opt(0, 0, 0);
    }

    for format in TIME_ONLY_FORMATS {
        if let Ok(time) = NaiveTime::parse_from_str(query, format) {
            return Some(today.and_time(time));
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture_today() -> NaiveDate {
        NaiveDate::from_ymd_opt(2026, 2, 10).expect("fixture date")
    }

    #[test]
    fn parse_empty_query_returns_empty_variant() {
        let parsed = parse_query("   ", fixture_today()).expect("empty query should parse");

        assert_eq!(parsed, QueryInput::Empty);
    }

    #[test]
    fn parse_epoch_query_infers_unit_from_magnitude() {
        let seconds = parse_query("99999999999", fixture_today()).expect("seconds parse");
        let milliseconds =
            parse_query("100000000000", fixture_today()).expect("milliseconds parse");
        let microseconds =
            parse_query("100000000000000", fixture_today()).expect("microseconds parse");
        let nanoseconds =
            parse_query("100000000000000000", fixture_today()).expect("nanoseconds parse");

        assert_eq!(
            seconds,
            QueryInput::Epoch(EpochInput {
                value: 99_999_999_999,
                unit: EpochUnit::Seconds,
            })
        );
        assert_eq!(
            milliseconds,
            QueryInput::Epoch(EpochInput {
                value: 100_000_000_000,
                unit: EpochUnit::Milliseconds,
            })
        );
        assert_eq!(
            microseconds,
            QueryInput::Epoch(EpochInput {
                value: 100_000_000_000_000,
                unit: EpochUnit::Microseconds,
            })
        );
        assert_eq!(
            nanoseconds,
            QueryInput::Epoch(EpochInput {
                value: 100_000_000_000_000_000,
                unit: EpochUnit::Nanoseconds,
            })
        );
    }

    #[test]
    fn parse_date_only_uses_local_midnight() {
        let parsed = parse_query("2026-02-10", fixture_today()).expect("date parse");

        assert_eq!(
            parsed,
            QueryInput::DateTime(
                NaiveDate::from_ymd_opt(2026, 2, 10)
                    .expect("date")
                    .and_hms_opt(0, 0, 0)
                    .expect("midnight"),
            )
        );
    }

    #[test]
    fn parse_datetime_supports_space_and_t_separator_with_subseconds() {
        let space = parse_query("2026-02-10 12:34:56.789", fixture_today()).expect("space parse");
        let t_sep = parse_query("2026-02-10T12:34:56.789", fixture_today()).expect("t parse");

        let expected = QueryInput::DateTime(
            NaiveDate::from_ymd_opt(2026, 2, 10)
                .expect("date")
                .and_hms_milli_opt(12, 34, 56, 789)
                .expect("time"),
        );

        assert_eq!(space, expected);
        assert_eq!(t_sep, expected);
    }

    #[test]
    fn parse_time_only_uses_today_date() {
        let parsed = parse_query("08:09:10.123", fixture_today()).expect("time parse");

        assert_eq!(
            parsed,
            QueryInput::DateTime(
                NaiveDate::from_ymd_opt(2026, 2, 10)
                    .expect("date")
                    .and_hms_milli_opt(8, 9, 10, 123)
                    .expect("time"),
            )
        );
    }

    #[test]
    fn parse_invalid_query_reports_user_error() {
        let error =
            parse_query("not-a-time", fixture_today()).expect_err("invalid query should fail");

        assert_eq!(
            error,
            ParseError::UnsupportedQuery("not-a-time".to_string())
        );
    }
}
