use chrono_tz::Tz;
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TimezoneEntry {
    pub id: String,
    pub tz: Tz,
}

impl TimezoneEntry {
    pub fn new(id: impl Into<String>, tz: Tz) -> Self {
        Self { id: id.into(), tz }
    }
}

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum ParseError {
    #[error("invalid timezone list: provide at least one IANA timezone")]
    EmptyTimezoneList,
    #[error("invalid timezone: {0}")]
    InvalidTimezone(String),
}

pub fn parse_timezone_list(raw: &str) -> Result<Vec<TimezoneEntry>, ParseError> {
    let mut entries = Vec::new();

    for token in raw.split([',', '\n']) {
        let trimmed = token.trim();
        if trimmed.is_empty() {
            continue;
        }

        let tz = trimmed
            .parse::<Tz>()
            .map_err(|_| ParseError::InvalidTimezone(trimmed.to_string()))?;

        entries.push(TimezoneEntry::new(trimmed.to_string(), tz));
    }

    if entries.is_empty() && !raw.trim().is_empty() {
        return Err(ParseError::EmptyTimezoneList);
    }

    Ok(entries)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_timezone_list_preserves_comma_and_newline_order() {
        let parsed = parse_timezone_list("Asia/Taipei\nAmerica/New_York,Europe/London")
            .expect("timezone list should parse");

        assert_eq!(parsed.len(), 3);
        assert_eq!(parsed[0].id, "Asia/Taipei");
        assert_eq!(parsed[1].id, "America/New_York");
        assert_eq!(parsed[2].id, "Europe/London");
    }

    #[test]
    fn parse_timezone_list_ignores_empty_tokens() {
        let parsed = parse_timezone_list(",, Asia/Taipei,\n\nAmerica/New_York ,, ")
            .expect("timezone list should parse");

        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0].id, "Asia/Taipei");
        assert_eq!(parsed[1].id, "America/New_York");
    }

    #[test]
    fn parse_timezone_list_rejects_invalid_timezone() {
        let error = parse_timezone_list("Asia/Taipei,Mars/Olympus").expect_err("invalid timezone");

        assert_eq!(
            error,
            ParseError::InvalidTimezone("Mars/Olympus".to_string())
        );
    }

    #[test]
    fn parse_timezone_list_rejects_delimiters_only_input() {
        let error = parse_timezone_list(",\n , ").expect_err("empty list should fail");

        assert_eq!(error, ParseError::EmptyTimezoneList);
    }

    #[test]
    fn parse_timezone_list_allows_empty_input_as_no_entries() {
        let parsed = parse_timezone_list("   ").expect("empty input is allowed");

        assert!(parsed.is_empty());
    }
}
