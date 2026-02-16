use std::collections::HashMap;
use std::path::PathBuf;

pub const WEATHER_CACHE_TTL_SECS: u64 = 30 * 60;

pub const WEATHER_CACHE_DIR_ENV: &str = "WEATHER_CACHE_DIR";
pub const WEATHER_CACHE_TTL_SECS_ENV: &str = "WEATHER_CACHE_TTL_SECS";
const ALFRED_WORKFLOW_CACHE_ENV: &str = "ALFRED_WORKFLOW_CACHE";
const ALFRED_WORKFLOW_DATA_ENV: &str = "ALFRED_WORKFLOW_DATA";
const HOME_ENV: &str = "HOME";

pub const PROVIDER_TIMEOUT_SECS: u64 = 3;
pub const PROVIDER_RETRY_MAX_ATTEMPTS: usize = 2;
pub const PROVIDER_RETRY_BASE_BACKOFF_MS: u64 = 200;
pub const MET_NO_USER_AGENT: &str =
    "nils-alfredworkflow/1.0 (+https://github.com/graysurf/nils-alfredworkflow)";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeConfig {
    pub cache_dir: PathBuf,
    pub cache_ttl_secs: u64,
}

impl RuntimeConfig {
    pub fn from_env() -> Self {
        Self::from_pairs(std::env::vars())
    }

    pub(crate) fn from_pairs<I, K, V>(pairs: I) -> Self
    where
        I: IntoIterator<Item = (K, V)>,
        K: Into<String>,
        V: Into<String>,
    {
        let map: HashMap<String, String> = pairs
            .into_iter()
            .map(|(k, v)| (k.into(), v.into()))
            .collect();
        Self {
            cache_dir: resolve_cache_dir(&map),
            cache_ttl_secs: resolve_cache_ttl_secs(&map),
        }
    }
}

fn resolve_cache_dir(env_map: &HashMap<String, String>) -> PathBuf {
    let home = env_map.get(HOME_ENV).map(String::as_str);
    env_map
        .get(WEATHER_CACHE_DIR_ENV)
        .or_else(|| env_map.get(ALFRED_WORKFLOW_CACHE_ENV))
        .or_else(|| env_map.get(ALFRED_WORKFLOW_DATA_ENV))
        .map(String::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| expand_home_path(value, home))
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::temp_dir().join("nils-weather-cli"))
}

fn expand_home_path(raw: &str, home: Option<&str>) -> String {
    let trimmed = raw.trim();
    let Some(home) = home.map(str::trim).filter(|value| !value.is_empty()) else {
        return trimmed.to_string();
    };

    let home = home.trim_end_matches('/');
    let mut expanded = trimmed.replace("$HOME", home);

    if expanded == "~" {
        expanded = home.to_string();
    } else if let Some(rest) = expanded.strip_prefix("~/") {
        expanded = format!("{home}/{rest}");
    }

    expanded
}

fn resolve_cache_ttl_secs(env_map: &HashMap<String, String>) -> u64 {
    env_map
        .get(WEATHER_CACHE_TTL_SECS_ENV)
        .map(String::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .and_then(|value| value.parse::<u64>().ok())
        .filter(|value| *value > 0)
        .unwrap_or(WEATHER_CACHE_TTL_SECS)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RetryPolicy {
    pub max_attempts: usize,
    pub base_backoff_ms: u64,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self {
            max_attempts: PROVIDER_RETRY_MAX_ATTEMPTS,
            base_backoff_ms: PROVIDER_RETRY_BASE_BACKOFF_MS,
        }
    }
}

impl RetryPolicy {
    pub fn backoff_for_attempt(self, attempt: usize) -> u64 {
        if attempt <= 1 {
            return 0;
        }

        let shift = (attempt - 2).min(8);
        self.base_backoff_ms.saturating_mul(1_u64 << shift)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_defaults_use_temp_weather_cache_dir() {
        let config = RuntimeConfig::from_pairs(Vec::<(String, String)>::new());
        assert!(config.cache_dir.ends_with("nils-weather-cli"));
        assert_eq!(config.cache_ttl_secs, WEATHER_CACHE_TTL_SECS);
    }

    #[test]
    fn config_prefers_weather_cache_dir_over_alfred_paths() {
        let config = RuntimeConfig::from_pairs(vec![
            (ALFRED_WORKFLOW_DATA_ENV, "/tmp/alfred-data"),
            (ALFRED_WORKFLOW_CACHE_ENV, "/tmp/alfred-cache"),
            (WEATHER_CACHE_DIR_ENV, "/tmp/weather-cache"),
        ]);

        assert_eq!(config.cache_dir, PathBuf::from("/tmp/weather-cache"));
    }

    #[test]
    fn config_expands_home_prefix_for_weather_cache_dir() {
        let config = RuntimeConfig::from_pairs(vec![
            (HOME_ENV, "/tmp/home"),
            (WEATHER_CACHE_DIR_ENV, "~/.cache/weather"),
        ]);

        assert_eq!(config.cache_dir, PathBuf::from("/tmp/home/.cache/weather"));
    }

    #[test]
    fn config_supports_cache_ttl_override() {
        let config = RuntimeConfig::from_pairs(vec![(WEATHER_CACHE_TTL_SECS_ENV, "900")]);
        assert_eq!(config.cache_ttl_secs, 900);
    }

    #[test]
    fn config_falls_back_when_cache_ttl_override_invalid() {
        let config = RuntimeConfig::from_pairs(vec![(WEATHER_CACHE_TTL_SECS_ENV, "abc")]);
        assert_eq!(config.cache_ttl_secs, WEATHER_CACHE_TTL_SECS);
    }

    #[test]
    fn config_retry_policy_backoff_is_deterministic() {
        let policy = RetryPolicy::default();

        assert_eq!(policy.backoff_for_attempt(1), 0);
        assert_eq!(policy.backoff_for_attempt(2), 200);
        assert_eq!(policy.backoff_for_attempt(3), 400);
    }
}
