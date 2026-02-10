use std::collections::HashMap;
use std::path::PathBuf;

use thiserror::Error;

const DISPLAY_COUNT_ENV: &str = "QUOTE_DISPLAY_COUNT";
const REFRESH_INTERVAL_ENV: &str = "QUOTE_REFRESH_INTERVAL";
const FETCH_COUNT_ENV: &str = "QUOTE_FETCH_COUNT";
const MAX_ENTRIES_ENV: &str = "QUOTE_MAX_ENTRIES";
const ALFRED_WORKFLOW_DATA_ENV: &str = "alfred_workflow_data";
const QUOTE_DATA_DIR_ENV: &str = "QUOTE_DATA_DIR";

const DISPLAY_MIN: i32 = 1;
const DISPLAY_MAX: i32 = 20;
const FETCH_MIN: i32 = 1;
const FETCH_MAX: i32 = 20;
const MAX_ENTRIES_MIN: i32 = 1;
const MAX_ENTRIES_MAX: i32 = 1000;

pub const DEFAULT_DISPLAY_COUNT: usize = 3;
pub const DEFAULT_REFRESH_INTERVAL_SECS: u64 = 3600;
pub const DEFAULT_REFRESH_INTERVAL_TEXT: &str = "1h";
pub const DEFAULT_FETCH_COUNT: usize = 5;
pub const DEFAULT_MAX_ENTRIES: usize = 100;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeConfig {
    pub display_count: usize,
    pub refresh_interval_secs: u64,
    pub fetch_count: usize,
    pub max_entries: usize,
    pub data_dir: PathBuf,
}

impl RuntimeConfig {
    pub fn from_env() -> Result<Self, ConfigError> {
        Self::from_pairs(std::env::vars())
    }

    pub(crate) fn from_pairs<I, K, V>(pairs: I) -> Result<Self, ConfigError>
    where
        I: IntoIterator<Item = (K, V)>,
        K: Into<String>,
        V: Into<String>,
    {
        let env_map: HashMap<String, String> = pairs
            .into_iter()
            .map(|(key, value)| (key.into(), value.into()))
            .collect();

        Ok(Self {
            display_count: parse_clamped_count(
                env_map.get(DISPLAY_COUNT_ENV).map(String::as_str),
                DEFAULT_DISPLAY_COUNT,
                DISPLAY_MIN,
                DISPLAY_MAX,
                DISPLAY_COUNT_ENV,
            )?,
            refresh_interval_secs: parse_refresh_interval(
                env_map.get(REFRESH_INTERVAL_ENV).map(String::as_str),
            )?,
            fetch_count: parse_clamped_count(
                env_map.get(FETCH_COUNT_ENV).map(String::as_str),
                DEFAULT_FETCH_COUNT,
                FETCH_MIN,
                FETCH_MAX,
                FETCH_COUNT_ENV,
            )?,
            max_entries: parse_clamped_count(
                env_map.get(MAX_ENTRIES_ENV).map(String::as_str),
                DEFAULT_MAX_ENTRIES,
                MAX_ENTRIES_MIN,
                MAX_ENTRIES_MAX,
                MAX_ENTRIES_ENV,
            )?,
            data_dir: parse_data_dir(&env_map),
        })
    }

    pub fn quotes_file(&self) -> PathBuf {
        self.data_dir.join("quotes.txt")
    }

    pub fn timestamp_file(&self) -> PathBuf {
        self.data_dir.join("quotes.timestamp")
    }
}

fn parse_data_dir(env_map: &HashMap<String, String>) -> PathBuf {
    let selected = env_map
        .get(QUOTE_DATA_DIR_ENV)
        .or_else(|| env_map.get(ALFRED_WORKFLOW_DATA_ENV))
        .map(String::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from);

    selected.unwrap_or_else(|| std::env::temp_dir().join("nils-quote-feed"))
}

fn parse_clamped_count(
    raw: Option<&str>,
    default: usize,
    min: i32,
    max: i32,
    field_name: &'static str,
) -> Result<usize, ConfigError> {
    let Some(value) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(default);
    };

    let parsed = value
        .parse::<i32>()
        .map_err(|_| ConfigError::InvalidCount {
            field: field_name,
            value: value.to_string(),
        })?;

    Ok(parsed.clamp(min, max) as usize)
}

fn parse_refresh_interval(raw: Option<&str>) -> Result<u64, ConfigError> {
    let Some(value) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(DEFAULT_REFRESH_INTERVAL_SECS);
    };

    if value.len() < 2 {
        return Err(ConfigError::InvalidRefreshInterval(value.to_string()));
    }

    let (digits, unit) = value.split_at(value.len() - 1);
    if digits.is_empty() || !digits.chars().all(|ch| ch.is_ascii_digit()) {
        return Err(ConfigError::InvalidRefreshInterval(value.to_string()));
    }

    let amount = digits
        .parse::<u64>()
        .map_err(|_| ConfigError::InvalidRefreshInterval(value.to_string()))?;
    if amount == 0 {
        return Err(ConfigError::InvalidRefreshInterval(value.to_string()));
    }

    let multiplier = match unit {
        "s" => 1,
        "m" => 60,
        "h" => 3600,
        _ => return Err(ConfigError::InvalidRefreshInterval(value.to_string())),
    };

    amount
        .checked_mul(multiplier)
        .ok_or_else(|| ConfigError::InvalidRefreshInterval(value.to_string()))
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ConfigError {
    #[error("invalid {field}: {value}")]
    InvalidCount { field: &'static str, value: String },
    #[error("invalid {REFRESH_INTERVAL_ENV}: {0} (expected <positive-int><s|m|h>)")]
    InvalidRefreshInterval(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_defaults_apply_when_values_missing() {
        let config = RuntimeConfig::from_pairs(Vec::<(String, String)>::new())
            .expect("defaults should parse");

        assert_eq!(config.display_count, DEFAULT_DISPLAY_COUNT);
        assert_eq!(config.refresh_interval_secs, DEFAULT_REFRESH_INTERVAL_SECS);
        assert_eq!(config.fetch_count, DEFAULT_FETCH_COUNT);
        assert_eq!(config.max_entries, DEFAULT_MAX_ENTRIES);
        assert!(
            config.data_dir.ends_with("nils-quote-feed"),
            "default data dir should fall back to temp location"
        );
    }

    #[test]
    fn config_prefers_alfred_workflow_data_path() {
        let config =
            RuntimeConfig::from_pairs(vec![(ALFRED_WORKFLOW_DATA_ENV, "/tmp/alfred-quote-feed")])
                .expect("alfred data dir should parse");

        assert_eq!(config.data_dir, PathBuf::from("/tmp/alfred-quote-feed"));
    }

    #[test]
    fn config_prefers_explicit_quote_data_dir_over_alfred_data_path() {
        let config = RuntimeConfig::from_pairs(vec![
            (ALFRED_WORKFLOW_DATA_ENV, "/tmp/alfred-quote-feed"),
            (QUOTE_DATA_DIR_ENV, "/tmp/custom-quote-feed"),
        ])
        .expect("explicit quote data dir should parse");

        assert_eq!(config.data_dir, PathBuf::from("/tmp/custom-quote-feed"));
    }

    #[test]
    fn config_clamps_numeric_values_into_ranges() {
        let config = RuntimeConfig::from_pairs(vec![
            (DISPLAY_COUNT_ENV, "999"),
            (FETCH_COUNT_ENV, "0"),
            (MAX_ENTRIES_ENV, "99999"),
        ])
        .expect("values should parse and clamp");

        assert_eq!(config.display_count, DISPLAY_MAX as usize);
        assert_eq!(config.fetch_count, FETCH_MIN as usize);
        assert_eq!(config.max_entries, MAX_ENTRIES_MAX as usize);
    }

    #[test]
    fn config_rejects_non_numeric_count_values() {
        let err = RuntimeConfig::from_pairs(vec![(DISPLAY_COUNT_ENV, "abc")])
            .expect_err("non-numeric display count should fail");

        assert_eq!(
            err,
            ConfigError::InvalidCount {
                field: DISPLAY_COUNT_ENV,
                value: "abc".to_string(),
            }
        );
    }

    #[test]
    fn duration_parser_accepts_s_m_h_suffixes() {
        let sec = RuntimeConfig::from_pairs(vec![(REFRESH_INTERVAL_ENV, "45s")])
            .expect("seconds should parse");
        assert_eq!(sec.refresh_interval_secs, 45);

        let min = RuntimeConfig::from_pairs(vec![(REFRESH_INTERVAL_ENV, "30m")])
            .expect("minutes should parse");
        assert_eq!(min.refresh_interval_secs, 1800);

        let hour = RuntimeConfig::from_pairs(vec![(REFRESH_INTERVAL_ENV, "2h")])
            .expect("hours should parse");
        assert_eq!(hour.refresh_interval_secs, 7200);
    }

    #[test]
    fn duration_parser_rejects_invalid_interval_formats() {
        for invalid in ["0s", "90x", "h", "1", "-1h"] {
            let err = RuntimeConfig::from_pairs(vec![(REFRESH_INTERVAL_ENV, invalid)])
                .expect_err("invalid interval should fail");
            assert_eq!(
                err,
                ConfigError::InvalidRefreshInterval(invalid.to_string())
            );
        }
    }
}
