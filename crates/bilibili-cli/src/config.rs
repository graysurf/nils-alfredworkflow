use std::collections::HashMap;

use thiserror::Error;

pub const BILIBILI_UID_ENV: &str = "BILIBILI_UID";
pub const BILIBILI_MAX_RESULTS_ENV: &str = "BILIBILI_MAX_RESULTS";
pub const BILIBILI_TIMEOUT_MS_ENV: &str = "BILIBILI_TIMEOUT_MS";
pub const BILIBILI_USER_AGENT_ENV: &str = "BILIBILI_USER_AGENT";

const MIN_MAX_RESULTS: i32 = 1;
const MAX_MAX_RESULTS: i32 = 20;
const MIN_TIMEOUT_MS: i64 = 1_000;
const MAX_TIMEOUT_MS: i64 = 30_000;

pub const DEFAULT_MAX_RESULTS: u8 = 10;
pub const DEFAULT_TIMEOUT_MS: u64 = 8_000;
pub const DEFAULT_USER_AGENT: &str =
    "nils-bilibili-cli/1.1 (+https://github.com/graysurf/nils-alfredworkflow)";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeConfig {
    pub uid: Option<String>,
    pub max_results: u8,
    pub timeout_ms: u64,
    pub user_agent: String,
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

        let uid = non_empty(env_map.get(BILIBILI_UID_ENV).map(String::as_str));
        let max_results =
            parse_max_results(env_map.get(BILIBILI_MAX_RESULTS_ENV).map(String::as_str))?;
        let timeout_ms =
            parse_timeout_ms(env_map.get(BILIBILI_TIMEOUT_MS_ENV).map(String::as_str))?;
        let user_agent = non_empty(env_map.get(BILIBILI_USER_AGENT_ENV).map(String::as_str))
            .unwrap_or_else(|| DEFAULT_USER_AGENT.to_string());

        Ok(Self {
            uid,
            max_results,
            timeout_ms,
            user_agent,
        })
    }
}

fn parse_max_results(raw: Option<&str>) -> Result<u8, ConfigError> {
    let Some(value) = non_empty(raw) else {
        return Ok(DEFAULT_MAX_RESULTS);
    };

    let parsed = value
        .parse::<i32>()
        .map_err(|_| ConfigError::InvalidMaxResults(value))?;

    Ok(parsed.clamp(MIN_MAX_RESULTS, MAX_MAX_RESULTS) as u8)
}

fn parse_timeout_ms(raw: Option<&str>) -> Result<u64, ConfigError> {
    let Some(value) = non_empty(raw) else {
        return Ok(DEFAULT_TIMEOUT_MS);
    };

    let parsed = value
        .parse::<i64>()
        .map_err(|_| ConfigError::InvalidTimeoutMs(value))?;

    Ok(parsed.clamp(MIN_TIMEOUT_MS, MAX_TIMEOUT_MS) as u64)
}

fn non_empty(raw: Option<&str>) -> Option<String> {
    raw.map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ConfigError {
    #[error("invalid BILIBILI_MAX_RESULTS: {0}")]
    InvalidMaxResults(String),
    #[error("invalid BILIBILI_TIMEOUT_MS: {0}")]
    InvalidTimeoutMs(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_uses_defaults_when_optional_values_are_missing() {
        let config = RuntimeConfig::from_pairs(Vec::<(String, String)>::new())
            .expect("config should parse with defaults");

        assert_eq!(config.uid, None);
        assert_eq!(config.max_results, DEFAULT_MAX_RESULTS);
        assert_eq!(config.timeout_ms, DEFAULT_TIMEOUT_MS);
        assert_eq!(config.user_agent, DEFAULT_USER_AGENT);
    }

    #[test]
    fn config_uses_trimmed_uid_when_present() {
        let config = RuntimeConfig::from_pairs(vec![(BILIBILI_UID_ENV, "  123456 ")])
            .expect("uid should parse");

        assert_eq!(config.uid.as_deref(), Some("123456"));
    }

    #[test]
    fn config_clamps_max_results_into_supported_range() {
        let lower = RuntimeConfig::from_pairs(vec![(BILIBILI_MAX_RESULTS_ENV, "-5")])
            .expect("lower bound config should parse");
        assert_eq!(lower.max_results, 1);

        let upper = RuntimeConfig::from_pairs(vec![(BILIBILI_MAX_RESULTS_ENV, "999")])
            .expect("upper bound config should parse");
        assert_eq!(upper.max_results, 20);
    }

    #[test]
    fn config_clamps_timeout_ms_into_supported_range() {
        let lower = RuntimeConfig::from_pairs(vec![(BILIBILI_TIMEOUT_MS_ENV, "300")])
            .expect("lower bound timeout should parse");
        assert_eq!(lower.timeout_ms, 1000);

        let upper = RuntimeConfig::from_pairs(vec![(BILIBILI_TIMEOUT_MS_ENV, "999999")])
            .expect("upper bound timeout should parse");
        assert_eq!(upper.timeout_ms, 30000);
    }

    #[test]
    fn config_rejects_non_numeric_max_results() {
        let err = RuntimeConfig::from_pairs(vec![(BILIBILI_MAX_RESULTS_ENV, "abc")])
            .expect_err("invalid max results should fail");

        assert_eq!(err, ConfigError::InvalidMaxResults("abc".to_string()));
    }

    #[test]
    fn config_rejects_non_numeric_timeout_ms() {
        let err = RuntimeConfig::from_pairs(vec![(BILIBILI_TIMEOUT_MS_ENV, "oops")])
            .expect_err("invalid timeout should fail");

        assert_eq!(err, ConfigError::InvalidTimeoutMs("oops".to_string()));
    }
}
