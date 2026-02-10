use std::collections::HashMap;

use thiserror::Error;

const API_KEY_ENV: &str = "YOUTUBE_API_KEY";
const MAX_RESULTS_ENV: &str = "YOUTUBE_MAX_RESULTS";
const REGION_CODE_ENV: &str = "YOUTUBE_REGION_CODE";

const MIN_RESULTS: i32 = 1;
const MAX_RESULTS: i32 = 25;
pub const DEFAULT_MAX_RESULTS: u8 = 10;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeConfig {
    pub api_key: String,
    pub max_results: u8,
    pub region_code: Option<String>,
}

impl RuntimeConfig {
    pub fn from_env() -> Result<Self, ConfigError> {
        Self::from_pairs(std::env::vars())
    }

    fn from_pairs<I, K, V>(pairs: I) -> Result<Self, ConfigError>
    where
        I: IntoIterator<Item = (K, V)>,
        K: Into<String>,
        V: Into<String>,
    {
        let env_map: HashMap<String, String> = pairs
            .into_iter()
            .map(|(key, value)| (key.into(), value.into()))
            .collect();

        let api_key = env_map
            .get(API_KEY_ENV)
            .map(|value| value.trim())
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
            .ok_or(ConfigError::MissingApiKey)?;

        let max_results = parse_max_results(env_map.get(MAX_RESULTS_ENV).map(String::as_str))?;
        let region_code = parse_region_code(env_map.get(REGION_CODE_ENV).map(String::as_str))?;

        Ok(Self {
            api_key,
            max_results,
            region_code,
        })
    }
}

fn parse_max_results(raw: Option<&str>) -> Result<u8, ConfigError> {
    let Some(value) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(DEFAULT_MAX_RESULTS);
    };

    let parsed = value
        .parse::<i32>()
        .map_err(|_| ConfigError::InvalidMaxResults(value.to_string()))?;

    Ok(parsed.clamp(MIN_RESULTS, MAX_RESULTS) as u8)
}

fn parse_region_code(raw: Option<&str>) -> Result<Option<String>, ConfigError> {
    let Some(value) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(None);
    };

    let normalized = value.to_ascii_uppercase();
    let is_valid = normalized.len() == 2
        && normalized
            .chars()
            .all(|ch| ch.is_ascii_alphabetic() && ch.is_ascii_uppercase());

    if !is_valid {
        return Err(ConfigError::InvalidRegionCode(value.to_string()));
    }

    Ok(Some(normalized))
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ConfigError {
    #[error("missing YOUTUBE_API_KEY")]
    MissingApiKey,
    #[error("invalid YOUTUBE_MAX_RESULTS: {0}")]
    InvalidMaxResults(String),
    #[error("invalid YOUTUBE_REGION_CODE: {0} (expected 2-letter code)")]
    InvalidRegionCode(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_requires_youtube_api_key() {
        let err = RuntimeConfig::from_pairs(vec![("YOUTUBE_MAX_RESULTS", "10")])
            .expect_err("missing API key should fail");

        assert_eq!(err, ConfigError::MissingApiKey);
    }

    #[test]
    fn config_uses_default_max_results_when_missing() {
        let config = RuntimeConfig::from_pairs(vec![("YOUTUBE_API_KEY", "abc123")])
            .expect("config should parse");

        assert_eq!(config.max_results, DEFAULT_MAX_RESULTS);
    }

    #[test]
    fn config_clamps_max_results_into_supported_range() {
        let lower = RuntimeConfig::from_pairs(vec![
            ("YOUTUBE_API_KEY", "abc123"),
            ("YOUTUBE_MAX_RESULTS", "-5"),
        ])
        .expect("lower bound config should parse");
        assert_eq!(lower.max_results, 1);

        let upper = RuntimeConfig::from_pairs(vec![
            ("YOUTUBE_API_KEY", "abc123"),
            ("YOUTUBE_MAX_RESULTS", "100"),
        ])
        .expect("upper bound config should parse");
        assert_eq!(upper.max_results, 25);
    }

    #[test]
    fn config_normalizes_region_code_to_uppercase() {
        let config = RuntimeConfig::from_pairs(vec![
            ("YOUTUBE_API_KEY", "abc123"),
            ("YOUTUBE_REGION_CODE", " us "),
        ])
        .expect("config should parse");

        assert_eq!(config.region_code.as_deref(), Some("US"));
    }

    #[test]
    fn config_rejects_invalid_region_code_format() {
        let err = RuntimeConfig::from_pairs(vec![
            ("YOUTUBE_API_KEY", "abc123"),
            ("YOUTUBE_REGION_CODE", "u1"),
        ])
        .expect_err("invalid region should fail");

        assert_eq!(
            err,
            ConfigError::InvalidRegionCode("u1".to_string()),
            "should preserve invalid input in error"
        );
    }

    #[test]
    fn config_rejects_non_numeric_max_results() {
        let err = RuntimeConfig::from_pairs(vec![
            ("YOUTUBE_API_KEY", "abc123"),
            ("YOUTUBE_MAX_RESULTS", "abc"),
        ])
        .expect_err("invalid max results should fail");

        assert_eq!(
            err,
            ConfigError::InvalidMaxResults("abc".to_string()),
            "invalid max results should return precise error"
        );
    }
}
