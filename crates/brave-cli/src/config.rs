use std::collections::HashMap;

use thiserror::Error;

const API_KEY_ENV: &str = "BRAVE_API_KEY";
const COUNT_ENV: &str = "BRAVE_MAX_RESULTS";
const SAFESEARCH_ENV: &str = "BRAVE_SAFESEARCH";
const COUNTRY_ENV: &str = "BRAVE_COUNTRY";

const MIN_COUNT: i32 = 1;
const MAX_COUNT: i32 = 20;
pub const DEFAULT_COUNT: u8 = 10;
pub const DEFAULT_SAFESEARCH: SafeSearch = SafeSearch::Off;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SafeSearch {
    Strict,
    Moderate,
    Off,
}

impl SafeSearch {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Strict => "strict",
            Self::Moderate => "moderate",
            Self::Off => "off",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeConfig {
    pub api_key: String,
    pub count: u8,
    pub safesearch: SafeSearch,
    pub country: Option<String>,
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

        let count = parse_count(env_map.get(COUNT_ENV).map(String::as_str))?;
        let safesearch = parse_safesearch(env_map.get(SAFESEARCH_ENV).map(String::as_str))?;
        let country = parse_country(env_map.get(COUNTRY_ENV).map(String::as_str))?;

        Ok(Self {
            api_key,
            count,
            safesearch,
            country,
        })
    }
}

fn parse_count(raw: Option<&str>) -> Result<u8, ConfigError> {
    let Some(value) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(DEFAULT_COUNT);
    };

    let parsed = value
        .parse::<i32>()
        .map_err(|_| ConfigError::InvalidCount(value.to_string()))?;

    Ok(parsed.clamp(MIN_COUNT, MAX_COUNT) as u8)
}

fn parse_safesearch(raw: Option<&str>) -> Result<SafeSearch, ConfigError> {
    let Some(value) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(DEFAULT_SAFESEARCH);
    };

    match value.to_ascii_lowercase().as_str() {
        "strict" => Ok(SafeSearch::Strict),
        "moderate" => Ok(SafeSearch::Moderate),
        "off" => Ok(SafeSearch::Off),
        _ => Err(ConfigError::InvalidSafeSearch(value.to_string())),
    }
}

fn parse_country(raw: Option<&str>) -> Result<Option<String>, ConfigError> {
    let Some(value) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(None);
    };

    let normalized = value.to_ascii_uppercase();
    let is_valid = normalized.len() == 2
        && normalized
            .chars()
            .all(|ch| ch.is_ascii_alphabetic() && ch.is_ascii_uppercase());

    if !is_valid {
        return Err(ConfigError::InvalidCountry(value.to_string()));
    }

    Ok(Some(normalized))
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ConfigError {
    #[error("missing BRAVE_API_KEY")]
    MissingApiKey,
    #[error("invalid BRAVE_MAX_RESULTS: {0}")]
    InvalidCount(String),
    #[error("invalid BRAVE_SAFESEARCH: {0} (expected strict|moderate|off)")]
    InvalidSafeSearch(String),
    #[error("invalid BRAVE_COUNTRY: {0} (expected 2-letter code)")]
    InvalidCountry(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_requires_brave_api_key() {
        let err = RuntimeConfig::from_pairs(vec![("BRAVE_MAX_RESULTS", "10")])
            .expect_err("missing API key should fail");

        assert_eq!(err, ConfigError::MissingApiKey);
    }

    #[test]
    fn config_uses_defaults_when_optional_values_are_missing() {
        let config = RuntimeConfig::from_pairs(vec![("BRAVE_API_KEY", "abc123")])
            .expect("config should parse");

        assert_eq!(config.count, DEFAULT_COUNT);
        assert_eq!(config.safesearch, DEFAULT_SAFESEARCH);
        assert_eq!(config.country, None);
    }

    #[test]
    fn config_clamps_count_into_supported_range() {
        let lower = RuntimeConfig::from_pairs(vec![
            ("BRAVE_API_KEY", "abc123"),
            ("BRAVE_MAX_RESULTS", "-5"),
        ])
        .expect("lower bound config should parse");
        assert_eq!(lower.count, 1);

        let upper = RuntimeConfig::from_pairs(vec![
            ("BRAVE_API_KEY", "abc123"),
            ("BRAVE_MAX_RESULTS", "100"),
        ])
        .expect("upper bound config should parse");
        assert_eq!(upper.count, 20);
    }

    #[test]
    fn config_rejects_non_numeric_count() {
        let err = RuntimeConfig::from_pairs(vec![
            ("BRAVE_API_KEY", "abc123"),
            ("BRAVE_MAX_RESULTS", "abc"),
        ])
        .expect_err("invalid count should fail");

        assert_eq!(err, ConfigError::InvalidCount("abc".to_string()));
    }

    #[test]
    fn config_parses_safesearch_case_insensitively() {
        let strict = RuntimeConfig::from_pairs(vec![
            ("BRAVE_API_KEY", "abc123"),
            ("BRAVE_SAFESEARCH", " strict "),
        ])
        .expect("strict should parse");

        let off = RuntimeConfig::from_pairs(vec![
            ("BRAVE_API_KEY", "abc123"),
            ("BRAVE_SAFESEARCH", "OFF"),
        ])
        .expect("off should parse");

        assert_eq!(strict.safesearch, SafeSearch::Strict);
        assert_eq!(off.safesearch, SafeSearch::Off);
    }

    #[test]
    fn config_rejects_invalid_safesearch() {
        let err = RuntimeConfig::from_pairs(vec![
            ("BRAVE_API_KEY", "abc123"),
            ("BRAVE_SAFESEARCH", "safe"),
        ])
        .expect_err("invalid safe search should fail");

        assert_eq!(err, ConfigError::InvalidSafeSearch("safe".to_string()));
    }

    #[test]
    fn config_normalizes_country_to_uppercase() {
        let config =
            RuntimeConfig::from_pairs(vec![("BRAVE_API_KEY", "abc123"), ("BRAVE_COUNTRY", " us ")])
                .expect("country should parse");

        assert_eq!(config.country.as_deref(), Some("US"));
    }

    #[test]
    fn config_rejects_invalid_country_format() {
        let err =
            RuntimeConfig::from_pairs(vec![("BRAVE_API_KEY", "abc123"), ("BRAVE_COUNTRY", "u1")])
                .expect_err("invalid country should fail");

        assert_eq!(err, ConfigError::InvalidCountry("u1".to_string()));
    }
}
