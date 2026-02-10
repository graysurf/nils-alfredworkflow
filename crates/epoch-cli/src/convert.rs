use chrono::{DateTime, Local, LocalResult, NaiveDateTime, SecondsFormat, TimeZone, Utc};
use thiserror::Error;

use crate::parser::{EpochInput, EpochUnit};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConversionRow {
    pub label: String,
    pub value: String,
}

impl ConversionRow {
    pub fn new(label: impl Into<String>, value: impl Into<String>) -> Self {
        Self {
            label: label.into(),
            value: value.into(),
        }
    }
}

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum ConvertError {
    #[error("epoch value is out of supported range")]
    EpochOutOfRange,
    #[error("datetime is ambiguous in local timezone")]
    AmbiguousLocalDateTime,
    #[error("datetime does not exist in local timezone")]
    InvalidLocalDateTime,
    #[error("failed to calculate epoch value")]
    EpochCalculationOverflow,
}

pub fn epoch_to_datetime_rows(epoch: EpochInput) -> Result<Vec<ConversionRow>, ConvertError> {
    let utc_datetime = epoch_to_utc_datetime(epoch)?;
    let local_datetime = utc_datetime.with_timezone(&Local);

    Ok(vec![
        ConversionRow::new(
            "Local ISO-like",
            local_datetime.to_rfc3339_opts(SecondsFormat::AutoSi, false),
        ),
        ConversionRow::new(
            "UTC ISO-like",
            utc_datetime.to_rfc3339_opts(SecondsFormat::AutoSi, true),
        ),
        ConversionRow::new(
            "Local formatted (YYYY-MM-DD HH:MM:SS)",
            local_datetime.format("%Y-%m-%d %H:%M:%S").to_string(),
        ),
    ])
}

pub fn datetime_to_epoch_rows(datetime: NaiveDateTime) -> Result<Vec<ConversionRow>, ConvertError> {
    let local_datetime = match Local.from_local_datetime(&datetime) {
        LocalResult::Single(value) => value,
        LocalResult::Ambiguous(_, _) => return Err(ConvertError::AmbiguousLocalDateTime),
        LocalResult::None => return Err(ConvertError::InvalidLocalDateTime),
    };

    let utc_datetime = datetime.and_utc();

    let local_values = epoch_values(local_datetime.with_timezone(&Utc))?;
    let utc_values = epoch_values(utc_datetime)?;

    Ok(vec![
        ConversionRow::new("Local epoch (s)", local_values.seconds.to_string()),
        ConversionRow::new("Local epoch (ms)", local_values.milliseconds.to_string()),
        ConversionRow::new("Local epoch (us)", local_values.microseconds.to_string()),
        ConversionRow::new("Local epoch (ns)", local_values.nanoseconds.to_string()),
        ConversionRow::new("UTC epoch (s)", utc_values.seconds.to_string()),
        ConversionRow::new("UTC epoch (ms)", utc_values.milliseconds.to_string()),
        ConversionRow::new("UTC epoch (us)", utc_values.microseconds.to_string()),
        ConversionRow::new("UTC epoch (ns)", utc_values.nanoseconds.to_string()),
    ])
}

pub fn current_epoch_rows(now: DateTime<Local>) -> Result<Vec<ConversionRow>, ConvertError> {
    let now_values = epoch_values(now.with_timezone(&Utc))?;

    Ok(vec![
        ConversionRow::new("Now epoch (s)", now_values.seconds.to_string()),
        ConversionRow::new("Now epoch (ms)", now_values.milliseconds.to_string()),
        ConversionRow::new("Now epoch (us)", now_values.microseconds.to_string()),
        ConversionRow::new("Now epoch (ns)", now_values.nanoseconds.to_string()),
    ])
}

pub fn prefix_rows(rows: Vec<ConversionRow>, prefix: &str) -> Vec<ConversionRow> {
    rows.into_iter()
        .map(|row| ConversionRow::new(format!("{prefix} {}", row.label), row.value))
        .collect()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct EpochValues {
    seconds: i128,
    milliseconds: i128,
    microseconds: i128,
    nanoseconds: i128,
}

fn epoch_values(datetime: DateTime<Utc>) -> Result<EpochValues, ConvertError> {
    let seconds = i128::from(datetime.timestamp());
    let nanos_part = i128::from(datetime.timestamp_subsec_nanos());
    let nanoseconds = seconds
        .checked_mul(1_000_000_000)
        .and_then(|base| base.checked_add(nanos_part))
        .ok_or(ConvertError::EpochCalculationOverflow)?;

    Ok(EpochValues {
        seconds,
        milliseconds: nanoseconds.div_euclid(1_000_000),
        microseconds: nanoseconds.div_euclid(1_000),
        nanoseconds,
    })
}

fn epoch_to_utc_datetime(epoch: EpochInput) -> Result<DateTime<Utc>, ConvertError> {
    let (seconds, nanos) = match epoch.unit {
        EpochUnit::Seconds => (epoch.value, 0),
        EpochUnit::Milliseconds => {
            let seconds = epoch.value.div_euclid(1_000);
            let nanos = epoch.value.rem_euclid(1_000) * 1_000_000;
            (seconds, nanos)
        }
        EpochUnit::Microseconds => {
            let seconds = epoch.value.div_euclid(1_000_000);
            let nanos = epoch.value.rem_euclid(1_000_000) * 1_000;
            (seconds, nanos)
        }
        EpochUnit::Nanoseconds => {
            let seconds = epoch.value.div_euclid(1_000_000_000);
            let nanos = epoch.value.rem_euclid(1_000_000_000);
            (seconds, nanos)
        }
    };

    let seconds_i64 = i64::try_from(seconds).map_err(|_| ConvertError::EpochOutOfRange)?;
    let nanos_u32 = u32::try_from(nanos).map_err(|_| ConvertError::EpochOutOfRange)?;

    DateTime::<Utc>::from_timestamp(seconds_i64, nanos_u32).ok_or(ConvertError::EpochOutOfRange)
}

#[cfg(test)]
mod tests {
    use chrono::NaiveDate;

    use super::*;

    fn row_value<'a>(rows: &'a [ConversionRow], label: &str) -> &'a str {
        rows.iter()
            .find(|row| row.label == label)
            .map(|row| row.value.as_str())
            .expect("row should exist")
    }

    #[test]
    fn epoch_to_datetime_rows_include_formatted_local_row() {
        let rows = epoch_to_datetime_rows(EpochInput {
            value: 0,
            unit: EpochUnit::Seconds,
        })
        .expect("epoch conversion should succeed");

        assert_eq!(rows.len(), 3, "epoch conversion should return three rows");

        let expected_local = DateTime::<Utc>::from_timestamp(0, 0)
            .expect("epoch zero should be valid")
            .with_timezone(&Local)
            .format("%Y-%m-%d %H:%M:%S")
            .to_string();

        assert_eq!(
            row_value(&rows, "Local formatted (YYYY-MM-DD HH:MM:SS)"),
            expected_local
        );
        assert!(
            row_value(&rows, "Local ISO-like").contains('T'),
            "local ISO-like row should contain time separator"
        );
        assert!(
            row_value(&rows, "UTC ISO-like").ends_with('Z'),
            "utc row should end with Z"
        );
    }

    #[test]
    fn datetime_to_epoch_rows_include_local_and_utc_units() {
        let datetime = NaiveDate::from_ymd_opt(2024, 1, 2)
            .expect("date")
            .and_hms_opt(3, 4, 5)
            .expect("time");

        let rows = datetime_to_epoch_rows(datetime).expect("datetime conversion should succeed");

        assert_eq!(
            rows.len(),
            8,
            "datetime conversion should return eight rows"
        );

        let local_timestamp = match Local.from_local_datetime(&datetime) {
            LocalResult::Single(value) => value.timestamp(),
            LocalResult::Ambiguous(_, _) => panic!("fixture must not be ambiguous"),
            LocalResult::None => panic!("fixture must exist in local timezone"),
        };
        let utc_timestamp = datetime.and_utc().timestamp();

        assert_eq!(
            row_value(&rows, "Local epoch (s)"),
            local_timestamp.to_string()
        );
        assert_eq!(row_value(&rows, "UTC epoch (s)"), utc_timestamp.to_string());
        assert!(
            row_value(&rows, "Local epoch (ns)").parse::<i128>().is_ok(),
            "local ns row should be numeric"
        );
        assert!(
            row_value(&rows, "UTC epoch (ns)").parse::<i128>().is_ok(),
            "utc ns row should be numeric"
        );
    }

    #[test]
    fn current_epoch_rows_return_all_units() {
        let now = DateTime::parse_from_rfc3339("2026-02-10T00:00:00+00:00")
            .expect("parse fixed instant")
            .with_timezone(&Local);

        let rows = current_epoch_rows(now).expect("current rows should succeed");

        assert_eq!(rows.len(), 4);
        assert_eq!(row_value(&rows, "Now epoch (s)"), "1770681600");
        assert_eq!(row_value(&rows, "Now epoch (ms)"), "1770681600000");
        assert_eq!(row_value(&rows, "Now epoch (us)"), "1770681600000000");
        assert_eq!(row_value(&rows, "Now epoch (ns)"), "1770681600000000000");
    }

    #[test]
    fn prefix_rows_applies_clipboard_prefix() {
        let rows = vec![ConversionRow::new("UTC epoch (s)", "1")];

        let prefixed = prefix_rows(rows, "(clipboard)");

        assert_eq!(prefixed[0].label, "(clipboard) UTC epoch (s)");
        assert_eq!(prefixed[0].value, "1");
    }

    #[test]
    fn epoch_to_datetime_rejects_out_of_range_epoch() {
        let error = epoch_to_datetime_rows(EpochInput {
            value: i128::MAX,
            unit: EpochUnit::Nanoseconds,
        })
        .expect_err("range overflow should fail");

        assert_eq!(error, ConvertError::EpochOutOfRange);
    }
}
