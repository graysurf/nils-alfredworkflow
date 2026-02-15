use std::collections::{HashMap, HashSet};

use thiserror::Error;
use workflow_common::parse_ordered_list_with;

const LANGUAGE_ENV: &str = "WIKI_LANGUAGE";
const LANGUAGE_OPTIONS_ENV: &str = "WIKI_LANGUAGE_OPTIONS";
const MAX_RESULTS_ENV: &str = "WIKI_MAX_RESULTS";

const MIN_RESULTS: i32 = 1;
const MAX_RESULTS: i32 = 20;
pub const DEFAULT_MAX_RESULTS: u8 = 10;
pub const DEFAULT_LANGUAGE: &str = "en";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeConfig {
    pub language: String,
    pub language_options: Vec<String>,
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
        let language_options = parse_language_options(
            env_map.get(LANGUAGE_OPTIONS_ENV).map(String::as_str),
            &language,
        )?;
        let max_results = parse_max_results(env_map.get(MAX_RESULTS_ENV).map(String::as_str))?;

        Ok(Self {
            language,
            language_options,
            max_results,
        })
    }
}

fn parse_language(raw: Option<&str>) -> Result<String, ConfigError> {
    let Some(value) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(DEFAULT_LANGUAGE.to_string());
    };

    parse_language_code(value).ok_or_else(|| ConfigError::InvalidLanguage(value.to_string()))
}

fn parse_language_options(
    raw: Option<&str>,
    default_language: &str,
) -> Result<Vec<String>, ConfigError> {
    let Some(value) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(vec![default_language.to_string()]);
    };

    let mut seen = HashSet::new();
    let options = parse_ordered_list_with(value, |token| {
        let normalized = parse_language_code(token)
            .ok_or_else(|| ConfigError::InvalidLanguageOptions(token.to_string()))?;
        if !seen.insert(normalized.clone()) {
            return Ok(None);
        }

        Ok(Some(normalized))
    })?;

    if options.is_empty() {
        return Err(ConfigError::InvalidLanguageOptions(value.to_string()));
    }

    Ok(options)
}

fn parse_language_code(raw: &str) -> Option<String> {
    let normalized = raw.trim().to_ascii_lowercase();
    let valid_len = (2..=12).contains(&normalized.len());
    let valid_chars = normalized.chars().all(|ch| ch.is_ascii_lowercase());

    if !valid_len || !valid_chars {
        return None;
    }

    Some(normalized)
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
    #[error(
        "invalid WIKI_LANGUAGE_OPTIONS token: {0} (expected comma/newline list of lowercase letters, length 2..12)"
    )]
    InvalidLanguageOptions(String),
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
        assert_eq!(config.language_options, vec![DEFAULT_LANGUAGE.to_string()]);
        assert_eq!(config.max_results, DEFAULT_MAX_RESULTS);
    }

    #[test]
    fn config_normalizes_language_to_lowercase() {
        let config = RuntimeConfig::from_pairs(vec![("WIKI_LANGUAGE", " EN ")])
            .expect("language should parse and normalize");

        assert_eq!(config.language, "en");
    }

    #[test]
    fn config_parses_language_options_with_order_and_dedup() {
        let config = RuntimeConfig::from_pairs(vec![
            ("WIKI_LANGUAGE", "en"),
            ("WIKI_LANGUAGE_OPTIONS", "zh,en,zh,ja"),
        ])
        .expect("language options should parse");

        assert_eq!(config.language, "en");
        assert_eq!(config.language_options, vec!["zh", "en", "ja"]);
    }

    #[test]
    fn config_rejects_invalid_language_options_token() {
        let err = RuntimeConfig::from_pairs(vec![("WIKI_LANGUAGE_OPTIONS", "en,EN-US!")])
            .expect_err("invalid language option should fail");

        assert_eq!(
            err,
            ConfigError::InvalidLanguageOptions("EN-US!".to_string())
        );
    }

    #[test]
    fn config_rejects_delimiters_only_language_options_input() {
        let err = RuntimeConfig::from_pairs(vec![("WIKI_LANGUAGE_OPTIONS", ", \n ,,")])
            .expect_err("delimiter-only options should fail");

        assert_eq!(
            err,
            ConfigError::InvalidLanguageOptions(", \n ,,".to_string())
        );
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
