use std::collections::HashMap;
use std::path::PathBuf;

use thiserror::Error;

pub const BANGUMI_API_KEY_ENV: &str = "BANGUMI_API_KEY";
pub const BANGUMI_MAX_RESULTS_ENV: &str = "BANGUMI_MAX_RESULTS";
pub const BANGUMI_TIMEOUT_MS_ENV: &str = "BANGUMI_TIMEOUT_MS";
pub const BANGUMI_USER_AGENT_ENV: &str = "BANGUMI_USER_AGENT";
pub const BANGUMI_CACHE_DIR_ENV: &str = "BANGUMI_CACHE_DIR";
pub const BANGUMI_IMAGE_CACHE_TTL_SECONDS_ENV: &str = "BANGUMI_IMAGE_CACHE_TTL_SECONDS";
pub const BANGUMI_IMAGE_CACHE_MAX_MB_ENV: &str = "BANGUMI_IMAGE_CACHE_MAX_MB";
pub const BANGUMI_API_FALLBACK_ENV: &str = "BANGUMI_API_FALLBACK";

const ALFRED_WORKFLOW_CACHE_ENV: &str = "alfred_workflow_cache";
const ALFRED_WORKFLOW_CACHE_ENV_UPPER: &str = "ALFRED_WORKFLOW_CACHE";
const XDG_CACHE_HOME_ENV: &str = "XDG_CACHE_HOME";
const HOME_ENV: &str = "HOME";

pub const DEFAULT_MAX_RESULTS: u8 = 10;
pub const DEFAULT_TIMEOUT_MS: u64 = 8_000;
pub const DEFAULT_IMAGE_CACHE_TTL_SECONDS: u64 = 86_400;
pub const DEFAULT_IMAGE_CACHE_MAX_MB: u64 = 128;
pub const DEFAULT_USER_AGENT: &str =
    "nils-bangumi-cli/1.1 (+https://github.com/graysurf/nils-alfredworkflow)";

const MIN_MAX_RESULTS: i32 = 1;
const MAX_MAX_RESULTS: i32 = 20;
const MIN_TIMEOUT_MS: i64 = 1_000;
const MAX_TIMEOUT_MS: i64 = 30_000;
const MIN_IMAGE_CACHE_TTL_SECONDS: i64 = 0;
const MAX_IMAGE_CACHE_TTL_SECONDS: i64 = 30 * 24 * 60 * 60;
const MIN_IMAGE_CACHE_MAX_MB: i64 = 8;
const MAX_IMAGE_CACHE_MAX_MB: i64 = 1_024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ApiFallbackPolicy {
    Auto,
    Never,
    Always,
}

impl ApiFallbackPolicy {
    fn parse(raw: &str) -> Option<Self> {
        match raw {
            "auto" => Some(Self::Auto),
            "never" => Some(Self::Never),
            "always" => Some(Self::Always),
            _ => None,
        }
    }
}

impl std::fmt::Display for ApiFallbackPolicy {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let value = match self {
            Self::Auto => "auto",
            Self::Never => "never",
            Self::Always => "always",
        };
        f.write_str(value)
    }
}

pub const DEFAULT_API_FALLBACK_POLICY: ApiFallbackPolicy = ApiFallbackPolicy::Auto;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeConfig {
    pub api_key: Option<String>,
    pub max_results: u8,
    pub timeout_ms: u64,
    pub user_agent: String,
    pub cache_dir: PathBuf,
    pub image_cache_ttl_seconds: u64,
    pub image_cache_max_bytes: u64,
    pub api_fallback: ApiFallbackPolicy,
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

        let max_results =
            parse_max_results(env_map.get(BANGUMI_MAX_RESULTS_ENV).map(String::as_str))?;
        let timeout_ms = parse_timeout_ms(env_map.get(BANGUMI_TIMEOUT_MS_ENV).map(String::as_str))?;
        let image_cache_ttl_seconds = parse_image_cache_ttl_seconds(
            env_map
                .get(BANGUMI_IMAGE_CACHE_TTL_SECONDS_ENV)
                .map(String::as_str),
        )?;
        let image_cache_max_mb = parse_image_cache_max_mb(
            env_map
                .get(BANGUMI_IMAGE_CACHE_MAX_MB_ENV)
                .map(String::as_str),
        )?;

        Ok(Self {
            api_key: resolve_api_key(&env_map),
            max_results,
            timeout_ms,
            user_agent: resolve_user_agent(&env_map),
            cache_dir: resolve_cache_dir(&env_map)?,
            image_cache_ttl_seconds,
            image_cache_max_bytes: image_cache_max_mb.saturating_mul(1024 * 1024),
            api_fallback: parse_api_fallback(
                env_map.get(BANGUMI_API_FALLBACK_ENV).map(String::as_str),
            )?,
        })
    }
}

fn resolve_api_key(env_map: &HashMap<String, String>) -> Option<String> {
    non_empty_env(env_map, BANGUMI_API_KEY_ENV)
}

fn resolve_user_agent(env_map: &HashMap<String, String>) -> String {
    non_empty_env(env_map, BANGUMI_USER_AGENT_ENV).unwrap_or_else(|| DEFAULT_USER_AGENT.to_string())
}

fn resolve_cache_dir(env_map: &HashMap<String, String>) -> Result<PathBuf, ConfigError> {
    if let Some(explicit) = non_empty_env(env_map, BANGUMI_CACHE_DIR_ENV) {
        return Ok(PathBuf::from(explicit));
    }

    if let Some(alfred_cache) = non_empty_env(env_map, ALFRED_WORKFLOW_CACHE_ENV)
        .or_else(|| non_empty_env(env_map, ALFRED_WORKFLOW_CACHE_ENV_UPPER))
    {
        return Ok(PathBuf::from(alfred_cache).join("bangumi-cli"));
    }

    if let Some(xdg_cache_home) = non_empty_env(env_map, XDG_CACHE_HOME_ENV) {
        return Ok(PathBuf::from(xdg_cache_home).join("nils-bangumi-cli"));
    }

    if let Some(home) = non_empty_env(env_map, HOME_ENV) {
        return Ok(PathBuf::from(home).join(".cache").join("nils-bangumi-cli"));
    }

    Err(ConfigError::MissingCacheHome)
}

fn parse_max_results(raw: Option<&str>) -> Result<u8, ConfigError> {
    let Some(value) = normalized(raw) else {
        return Ok(DEFAULT_MAX_RESULTS);
    };

    let parsed = value
        .parse::<i32>()
        .map_err(|_| ConfigError::InvalidMaxResults(value.to_string()))?;

    Ok(parsed.clamp(MIN_MAX_RESULTS, MAX_MAX_RESULTS) as u8)
}

fn parse_timeout_ms(raw: Option<&str>) -> Result<u64, ConfigError> {
    let Some(value) = normalized(raw) else {
        return Ok(DEFAULT_TIMEOUT_MS);
    };

    let parsed = value
        .parse::<i64>()
        .map_err(|_| ConfigError::InvalidTimeoutMs(value.to_string()))?;

    Ok(parsed.clamp(MIN_TIMEOUT_MS, MAX_TIMEOUT_MS) as u64)
}

fn parse_image_cache_ttl_seconds(raw: Option<&str>) -> Result<u64, ConfigError> {
    let Some(value) = normalized(raw) else {
        return Ok(DEFAULT_IMAGE_CACHE_TTL_SECONDS);
    };

    let parsed = value
        .parse::<i64>()
        .map_err(|_| ConfigError::InvalidImageCacheTtlSeconds(value.to_string()))?;

    Ok(parsed.clamp(MIN_IMAGE_CACHE_TTL_SECONDS, MAX_IMAGE_CACHE_TTL_SECONDS) as u64)
}

fn parse_image_cache_max_mb(raw: Option<&str>) -> Result<u64, ConfigError> {
    let Some(value) = normalized(raw) else {
        return Ok(DEFAULT_IMAGE_CACHE_MAX_MB);
    };

    let parsed = value
        .parse::<i64>()
        .map_err(|_| ConfigError::InvalidImageCacheMaxMb(value.to_string()))?;

    Ok(parsed.clamp(MIN_IMAGE_CACHE_MAX_MB, MAX_IMAGE_CACHE_MAX_MB) as u64)
}

fn parse_api_fallback(raw: Option<&str>) -> Result<ApiFallbackPolicy, ConfigError> {
    let Some(value) = normalized(raw) else {
        return Ok(DEFAULT_API_FALLBACK_POLICY);
    };

    ApiFallbackPolicy::parse(&value.to_ascii_lowercase())
        .ok_or_else(|| ConfigError::InvalidApiFallback(value.to_string()))
}

fn normalized(raw: Option<&str>) -> Option<String> {
    raw.map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn non_empty_env(env_map: &HashMap<String, String>, key: &str) -> Option<String> {
    normalized(env_map.get(key).map(String::as_str))
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ConfigError {
    #[error("invalid BANGUMI_MAX_RESULTS: {0}")]
    InvalidMaxResults(String),
    #[error("invalid BANGUMI_TIMEOUT_MS: {0}")]
    InvalidTimeoutMs(String),
    #[error("invalid BANGUMI_IMAGE_CACHE_TTL_SECONDS: {0}")]
    InvalidImageCacheTtlSeconds(String),
    #[error("invalid BANGUMI_IMAGE_CACHE_MAX_MB: {0}")]
    InvalidImageCacheMaxMb(String),
    #[error("invalid BANGUMI_API_FALLBACK: {0} (expected auto, never, or always)")]
    InvalidApiFallback(String),
    #[error(
        "unable to resolve cache directory (set BANGUMI_CACHE_DIR, alfred_workflow_cache, XDG_CACHE_HOME, or HOME)"
    )]
    MissingCacheHome,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_uses_defaults_when_optional_env_missing() {
        let config =
            RuntimeConfig::from_pairs(vec![(HOME_ENV, "/tmp/home")]).expect("config should parse");

        assert_eq!(config.api_key, None);
        assert_eq!(config.max_results, DEFAULT_MAX_RESULTS);
        assert_eq!(config.timeout_ms, DEFAULT_TIMEOUT_MS);
        assert_eq!(config.user_agent, DEFAULT_USER_AGENT);
        assert_eq!(
            config.cache_dir,
            PathBuf::from("/tmp/home")
                .join(".cache")
                .join("nils-bangumi-cli")
        );
        assert_eq!(
            config.image_cache_ttl_seconds,
            DEFAULT_IMAGE_CACHE_TTL_SECONDS
        );
        assert_eq!(
            config.image_cache_max_bytes,
            DEFAULT_IMAGE_CACHE_MAX_MB * 1024 * 1024
        );
        assert_eq!(config.api_fallback, DEFAULT_API_FALLBACK_POLICY);
    }

    #[test]
    fn config_clamps_max_results_and_timeout_ranges() {
        let config = RuntimeConfig::from_pairs(vec![
            (HOME_ENV, "/tmp/home"),
            (BANGUMI_MAX_RESULTS_ENV, "200"),
            (BANGUMI_TIMEOUT_MS_ENV, "100"),
            (BANGUMI_IMAGE_CACHE_TTL_SECONDS_ENV, "-1"),
            (BANGUMI_IMAGE_CACHE_MAX_MB_ENV, "99999"),
        ])
        .expect("config should parse");

        assert_eq!(config.max_results, MAX_MAX_RESULTS as u8);
        assert_eq!(config.timeout_ms, MIN_TIMEOUT_MS as u64);
        assert_eq!(
            config.image_cache_ttl_seconds,
            MIN_IMAGE_CACHE_TTL_SECONDS as u64
        );
        assert_eq!(
            config.image_cache_max_bytes,
            (MAX_IMAGE_CACHE_MAX_MB as u64) * 1024 * 1024
        );
    }

    #[test]
    fn config_rejects_invalid_numeric_fields() {
        let err = RuntimeConfig::from_pairs(vec![
            (HOME_ENV, "/tmp/home"),
            (BANGUMI_MAX_RESULTS_ENV, "abc"),
        ])
        .expect_err("invalid max results should fail");
        assert_eq!(err, ConfigError::InvalidMaxResults("abc".to_string()));

        let err =
            RuntimeConfig::from_pairs(vec![(HOME_ENV, "/tmp/home"), (BANGUMI_TIMEOUT_MS_ENV, "x")])
                .expect_err("invalid timeout should fail");
        assert_eq!(err, ConfigError::InvalidTimeoutMs("x".to_string()));

        let err = RuntimeConfig::from_pairs(vec![
            (HOME_ENV, "/tmp/home"),
            (BANGUMI_IMAGE_CACHE_TTL_SECONDS_ENV, "x"),
        ])
        .expect_err("invalid ttl should fail");
        assert_eq!(
            err,
            ConfigError::InvalidImageCacheTtlSeconds("x".to_string())
        );

        let err = RuntimeConfig::from_pairs(vec![
            (HOME_ENV, "/tmp/home"),
            (BANGUMI_IMAGE_CACHE_MAX_MB_ENV, "x"),
        ])
        .expect_err("invalid max mb should fail");
        assert_eq!(err, ConfigError::InvalidImageCacheMaxMb("x".to_string()));
    }

    #[test]
    fn config_parses_api_fallback_policy_values() {
        let auto =
            RuntimeConfig::from_pairs(vec![(HOME_ENV, "/tmp/home")]).expect("config should parse");
        assert_eq!(auto.api_fallback, ApiFallbackPolicy::Auto);

        let never = RuntimeConfig::from_pairs(vec![
            (HOME_ENV, "/tmp/home"),
            (BANGUMI_API_FALLBACK_ENV, "never"),
        ])
        .expect("config should parse");
        assert_eq!(never.api_fallback, ApiFallbackPolicy::Never);

        let always = RuntimeConfig::from_pairs(vec![
            (HOME_ENV, "/tmp/home"),
            (BANGUMI_API_FALLBACK_ENV, "Always"),
        ])
        .expect("config should parse");
        assert_eq!(always.api_fallback, ApiFallbackPolicy::Always);

        let err = RuntimeConfig::from_pairs(vec![
            (HOME_ENV, "/tmp/home"),
            (BANGUMI_API_FALLBACK_ENV, "sometimes"),
        ])
        .expect_err("invalid fallback policy should fail");
        assert_eq!(
            err,
            ConfigError::InvalidApiFallback("sometimes".to_string())
        );
    }

    #[test]
    fn api_key_precedence_prefers_workflow_value_over_inherited_key() {
        let config = RuntimeConfig::from_pairs(vec![
            (HOME_ENV, "/tmp/home"),
            (BANGUMI_API_KEY_ENV, "workflow-key"),
        ])
        .expect("config should parse");

        assert_eq!(config.api_key.as_deref(), Some("workflow-key"));
    }

    #[test]
    fn api_key_precedence_returns_none_when_workflow_value_is_blank() {
        let config =
            RuntimeConfig::from_pairs(vec![(HOME_ENV, "/tmp/home"), (BANGUMI_API_KEY_ENV, "   ")])
                .expect("config should parse");

        assert_eq!(config.api_key, None);
    }

    #[test]
    fn cache_dir_resolution_prefers_explicit_bangumi_cache_dir() {
        let config = RuntimeConfig::from_pairs(vec![
            (HOME_ENV, "/tmp/home"),
            (ALFRED_WORKFLOW_CACHE_ENV, "/tmp/alfred-cache"),
            (BANGUMI_CACHE_DIR_ENV, "/tmp/bangumi-cache"),
        ])
        .expect("config should parse");

        assert_eq!(config.cache_dir, PathBuf::from("/tmp/bangumi-cache"));
    }

    #[test]
    fn cache_dir_resolution_uses_alfred_workflow_cache_subdir_when_available() {
        let config = RuntimeConfig::from_pairs(vec![
            (HOME_ENV, "/tmp/home"),
            (ALFRED_WORKFLOW_CACHE_ENV, "/tmp/alfred-cache"),
        ])
        .expect("config should parse");

        assert_eq!(
            config.cache_dir,
            PathBuf::from("/tmp/alfred-cache").join("bangumi-cli")
        );
    }

    #[test]
    fn cache_dir_resolution_supports_uppercase_alfred_workflow_cache_alias() {
        let config = RuntimeConfig::from_pairs(vec![
            (HOME_ENV, "/tmp/home"),
            (ALFRED_WORKFLOW_CACHE_ENV_UPPER, "/tmp/alfred-cache"),
        ])
        .expect("config should parse");

        assert_eq!(
            config.cache_dir,
            PathBuf::from("/tmp/alfred-cache").join("bangumi-cli")
        );
    }

    #[test]
    fn cache_dir_resolution_falls_back_to_xdg_cache_home_then_home_cache() {
        let xdg = RuntimeConfig::from_pairs(vec![
            (HOME_ENV, "/tmp/home"),
            (XDG_CACHE_HOME_ENV, "/tmp/xdg-cache"),
        ])
        .expect("config should parse");
        assert_eq!(
            xdg.cache_dir,
            PathBuf::from("/tmp/xdg-cache/nils-bangumi-cli")
        );

        let home =
            RuntimeConfig::from_pairs(vec![(HOME_ENV, "/tmp/home")]).expect("config should parse");
        assert_eq!(
            home.cache_dir,
            PathBuf::from("/tmp/home/.cache/nils-bangumi-cli")
        );
    }

    #[test]
    fn cache_dir_resolution_requires_any_cache_home_source() {
        let err = RuntimeConfig::from_pairs(Vec::<(String, String)>::new())
            .expect_err("missing cache home should fail");

        assert_eq!(err, ConfigError::MissingCacheHome);
    }
}
