use std::collections::HashMap;

use thiserror::Error;

const CLIENT_ID_ENV: &str = "SPOTIFY_CLIENT_ID";
const CLIENT_SECRET_ENV: &str = "SPOTIFY_CLIENT_SECRET";
const MAX_RESULTS_ENV: &str = "SPOTIFY_MAX_RESULTS";
const MARKET_ENV: &str = "SPOTIFY_MARKET";

const MIN_RESULTS: i32 = 1;
const MAX_RESULTS: i32 = 50;
pub const DEFAULT_MAX_RESULTS: u8 = 10;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeConfig {
    pub client_id: String,
    pub client_secret: String,
    pub max_results: u8,
    pub market: Option<String>,
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

        let client_id = env_map
            .get(CLIENT_ID_ENV)
            .map(|value| value.trim())
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
            .ok_or(ConfigError::MissingClientId)?;

        let client_secret = env_map
            .get(CLIENT_SECRET_ENV)
            .map(|value| value.trim())
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
            .ok_or(ConfigError::MissingClientSecret)?;

        let max_results = parse_max_results(env_map.get(MAX_RESULTS_ENV).map(String::as_str))?;
        let market = parse_market(env_map.get(MARKET_ENV).map(String::as_str))?;

        Ok(Self {
            client_id,
            client_secret,
            max_results,
            market,
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

fn parse_market(raw: Option<&str>) -> Result<Option<String>, ConfigError> {
    let Some(value) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(None);
    };

    let normalized = value.to_ascii_uppercase();
    let is_valid = normalized.len() == 2
        && normalized
            .chars()
            .all(|ch| ch.is_ascii_alphabetic() && ch.is_ascii_uppercase());

    if !is_valid {
        return Err(ConfigError::InvalidMarket(value.to_string()));
    }

    Ok(Some(normalized))
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ConfigError {
    #[error("missing SPOTIFY_CLIENT_ID")]
    MissingClientId,
    #[error("missing SPOTIFY_CLIENT_SECRET")]
    MissingClientSecret,
    #[error("invalid SPOTIFY_MAX_RESULTS: {0}")]
    InvalidMaxResults(String),
    #[error("invalid SPOTIFY_MARKET: {0} (expected 2-letter code)")]
    InvalidMarket(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_requires_spotify_client_id() {
        let err = RuntimeConfig::from_pairs(vec![("SPOTIFY_CLIENT_SECRET", "demo-secret")])
            .expect_err("missing client id should fail");

        assert_eq!(err, ConfigError::MissingClientId);
    }

    #[test]
    fn config_requires_spotify_client_secret() {
        let err = RuntimeConfig::from_pairs(vec![("SPOTIFY_CLIENT_ID", "demo-client")])
            .expect_err("missing client secret should fail");

        assert_eq!(err, ConfigError::MissingClientSecret);
    }

    #[test]
    fn config_uses_default_max_results_when_missing() {
        let config = RuntimeConfig::from_pairs(vec![
            ("SPOTIFY_CLIENT_ID", "demo-client"),
            ("SPOTIFY_CLIENT_SECRET", "demo-secret"),
        ])
        .expect("config should parse");

        assert_eq!(config.max_results, DEFAULT_MAX_RESULTS);
    }

    #[test]
    fn config_clamps_max_results_into_supported_range() {
        let lower = RuntimeConfig::from_pairs(vec![
            ("SPOTIFY_CLIENT_ID", "demo-client"),
            ("SPOTIFY_CLIENT_SECRET", "demo-secret"),
            ("SPOTIFY_MAX_RESULTS", "-8"),
        ])
        .expect("lower bound config should parse");
        assert_eq!(lower.max_results, 1);

        let upper = RuntimeConfig::from_pairs(vec![
            ("SPOTIFY_CLIENT_ID", "demo-client"),
            ("SPOTIFY_CLIENT_SECRET", "demo-secret"),
            ("SPOTIFY_MAX_RESULTS", "999"),
        ])
        .expect("upper bound config should parse");
        assert_eq!(upper.max_results, 50);
    }

    #[test]
    fn config_rejects_non_numeric_max_results() {
        let err = RuntimeConfig::from_pairs(vec![
            ("SPOTIFY_CLIENT_ID", "demo-client"),
            ("SPOTIFY_CLIENT_SECRET", "demo-secret"),
            ("SPOTIFY_MAX_RESULTS", "ten"),
        ])
        .expect_err("invalid max results should fail");

        assert_eq!(err, ConfigError::InvalidMaxResults("ten".to_string()));
    }

    #[test]
    fn config_normalizes_market_to_uppercase() {
        let config = RuntimeConfig::from_pairs(vec![
            ("SPOTIFY_CLIENT_ID", "demo-client"),
            ("SPOTIFY_CLIENT_SECRET", "demo-secret"),
            ("SPOTIFY_MARKET", " tw "),
        ])
        .expect("config should parse");

        assert_eq!(config.market.as_deref(), Some("TW"));
    }

    #[test]
    fn config_rejects_invalid_market_format() {
        let err = RuntimeConfig::from_pairs(vec![
            ("SPOTIFY_CLIENT_ID", "demo-client"),
            ("SPOTIFY_CLIENT_SECRET", "demo-secret"),
            ("SPOTIFY_MARKET", "u1"),
        ])
        .expect_err("invalid market should fail");

        assert_eq!(err, ConfigError::InvalidMarket("u1".to_string()));
    }
}
