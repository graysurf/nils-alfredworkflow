use chrono::{DateTime, Offset, Utc};

use crate::parser::TimezoneEntry;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConversionRow {
    pub timezone_id: String,
    pub title: String,
    pub subtitle: String,
    pub arg: String,
}

impl ConversionRow {
    pub fn new(
        timezone_id: impl Into<String>,
        title: impl Into<String>,
        subtitle: impl Into<String>,
        arg: impl Into<String>,
    ) -> Self {
        Self {
            timezone_id: timezone_id.into(),
            title: title.into(),
            subtitle: subtitle.into(),
            arg: arg.into(),
        }
    }
}

pub fn now_rows(now: DateTime<Utc>, zones: &[TimezoneEntry]) -> Vec<ConversionRow> {
    zones
        .iter()
        .map(|zone| {
            let local = now.with_timezone(&zone.tz);
            let formatted = local.format("%Y-%m-%d %H:%M:%S").to_string();
            let offset = format_utc_offset(local.offset().fix().local_minus_utc());

            ConversionRow::new(
                zone.id.clone(),
                formatted.clone(),
                format!("{} ({})", zone.id, offset),
                format!("{} {} {}", zone.id, formatted, offset),
            )
        })
        .collect()
}

fn format_utc_offset(total_seconds: i32) -> String {
    let sign = if total_seconds >= 0 { '+' } else { '-' };
    let abs = total_seconds.abs();
    let hours = abs / 3_600;
    let minutes = (abs % 3_600) / 60;

    format!("UTC{sign}{hours:02}:{minutes:02}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::parse_timezone_list;

    #[test]
    fn now_rows_preserves_input_order() {
        let zones = parse_timezone_list("Asia/Taipei,America/New_York,Europe/London")
            .expect("zones should parse");
        let now = DateTime::parse_from_rfc3339("2026-02-10T12:00:00+00:00")
            .expect("fixed now")
            .with_timezone(&Utc);

        let rows = now_rows(now, &zones);

        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].timezone_id, "Asia/Taipei");
        assert_eq!(rows[1].timezone_id, "America/New_York");
        assert_eq!(rows[2].timezone_id, "Europe/London");
    }

    #[test]
    fn now_rows_contains_offset_in_subtitle_and_copy_arg() {
        let zones = parse_timezone_list("Asia/Taipei").expect("zone should parse");
        let now = DateTime::parse_from_rfc3339("2026-02-10T12:00:00+00:00")
            .expect("fixed now")
            .with_timezone(&Utc);

        let rows = now_rows(now, &zones);

        assert_eq!(rows.len(), 1);
        assert!(rows[0].subtitle.contains("Asia/Taipei"));
        assert!(rows[0].subtitle.contains("UTC+08:00"));
        assert!(rows[0].arg.contains("Asia/Taipei"));
        assert!(rows[0].arg.contains("UTC+08:00"));
    }

    #[test]
    fn format_utc_offset_formats_positive_and_negative_offsets() {
        assert_eq!(format_utc_offset(28_800), "UTC+08:00");
        assert_eq!(format_utc_offset(-18_000), "UTC-05:00");
        assert_eq!(format_utc_offset(0), "UTC+00:00");
    }
}
