use std::collections::HashMap;

use thiserror::Error;

const LANGUAGE_ENV: &str = "WIKI_LANGUAGE";
const MAX_RESULTS_ENV: &str = "WIKI_MAX_RESULTS";

const MIN_RESULTS: i32 = 1;
const MAX_RESULTS: i32 = 20;
pub const DEFAULT_MAX_RESULTS: u8 = 10;
pub const DEFAULT_LANGUAGE: &str = "en";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeConfig {
    pub language: String,
    pub max_results: u8,
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

        let language = parse_language(env_map.get(LANGUAGE_ENV).map(String::as_str))?;
        let max_results = parse_max_results(env_map.get(MAX_RESULTS_ENV).map(String::as_str))?;

        Ok(Self {
            language,
            max_results,
        })
    }
}

fn parse_language(raw: Option<&str>) -> Result<String, ConfigError> {
    let Some(value) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(DEFAULT_LANGUAGE.to_string());
    };

    let normalized = value.to_ascii_lowercase();
    let valid_len = (2..=12).contains(&normalized.len());
    let valid_chars = normalized.chars().all(|ch| ch.is_ascii_lowercase());

    if !valid_len || !valid_chars {
        return Err(ConfigError::InvalidLanguage(value.to_string()));
    }

    Ok(normalized)
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

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ConfigError {
    #[error("invalid WIKI_LANGUAGE: {0} (expected lowercase letters, length 2..12)")]
    InvalidLanguage(String),
    #[error("invalid WIKI_MAX_RESULTS: {0}")]
    InvalidMaxResults(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_uses_defaults_when_optional_values_are_missing() {
        let config = RuntimeConfig::from_pairs(Vec::<(String, String)>::new())
            .expect("config should parse with defaults");

        assert_eq!(config.language, DEFAULT_LANGUAGE);
        assert_eq!(config.max_results, DEFAULT_MAX_RESULTS);
    }

    #[test]
    fn config_normalizes_language_to_lowercase() {
        let config = RuntimeConfig::from_pairs(vec![("WIKI_LANGUAGE", " EN ")])
            .expect("language should parse and normalize");

        assert_eq!(config.language, "en");
    }

    #[test]
    fn config_rejects_invalid_language_format() {
        let err = RuntimeConfig::from_pairs(vec![("WIKI_LANGUAGE", "EN-US!")])
            .expect_err("invalid language should fail");

        assert_eq!(err, ConfigError::InvalidLanguage("EN-US!".to_string()));
    }

    #[test]
    fn config_clamps_max_results_into_supported_range() {
        let lower = RuntimeConfig::from_pairs(vec![("WIKI_MAX_RESULTS", "-5")])
            .expect("lower bound config should parse");
        assert_eq!(lower.max_results, 1);

        let upper = RuntimeConfig::from_pairs(vec![("WIKI_MAX_RESULTS", "999")])
            .expect("upper bound config should parse");
        assert_eq!(upper.max_results, 20);
    }

    #[test]
    fn config_rejects_non_numeric_max_results() {
        let err = RuntimeConfig::from_pairs(vec![("WIKI_MAX_RESULTS", "abc")])
            .expect_err("invalid max results should fail");

        assert_eq!(err, ConfigError::InvalidMaxResults("abc".to_string()));
    }
}
