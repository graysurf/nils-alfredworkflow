use std::collections::HashMap;
use std::path::PathBuf;

pub const FX_TTL_SECS: u64 = 24 * 60 * 60;
pub const CRYPTO_TTL_SECS: u64 = 5 * 60;

pub const MARKET_CACHE_DIR_ENV: &str = "MARKET_CACHE_DIR";
const ALFRED_WORKFLOW_CACHE_ENV: &str = "alfred_workflow_cache";
const ALFRED_WORKFLOW_DATA_ENV: &str = "alfred_workflow_data";

pub const PROVIDER_TIMEOUT_SECS: u64 = 6;
pub const PROVIDER_RETRY_MAX_ATTEMPTS: usize = 3;
pub const PROVIDER_RETRY_BASE_BACKOFF_MS: u64 = 200;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeConfig {
    pub cache_dir: PathBuf,
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
        }
    }
}

fn resolve_cache_dir(env_map: &HashMap<String, String>) -> PathBuf {
    env_map
        .get(MARKET_CACHE_DIR_ENV)
        .or_else(|| env_map.get(ALFRED_WORKFLOW_CACHE_ENV))
        .or_else(|| env_map.get(ALFRED_WORKFLOW_DATA_ENV))
        .map(String::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::temp_dir().join("nils-market-cli"))
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
    fn config_defaults_use_temp_market_cache_dir() {
        let config = RuntimeConfig::from_pairs(Vec::<(String, String)>::new());
        assert!(config.cache_dir.ends_with("nils-market-cli"));
    }

    #[test]
    fn config_prefers_market_cache_dir_over_alfred_paths() {
        let config = RuntimeConfig::from_pairs(vec![
            (ALFRED_WORKFLOW_DATA_ENV, "/tmp/alfred-data"),
            (ALFRED_WORKFLOW_CACHE_ENV, "/tmp/alfred-cache"),
            (MARKET_CACHE_DIR_ENV, "/tmp/market-cache"),
        ]);

        assert_eq!(config.cache_dir, PathBuf::from("/tmp/market-cache"));
    }

    #[test]
    fn config_uses_alfred_workflow_cache_when_market_cache_dir_missing() {
        let config =
            RuntimeConfig::from_pairs(vec![(ALFRED_WORKFLOW_CACHE_ENV, "/tmp/alfred-cache")]);
        assert_eq!(config.cache_dir, PathBuf::from("/tmp/alfred-cache"));
    }

    #[test]
    fn config_uses_alfred_workflow_data_when_cache_env_missing() {
        let config =
            RuntimeConfig::from_pairs(vec![(ALFRED_WORKFLOW_DATA_ENV, "/tmp/alfred-data")]);
        assert_eq!(config.cache_dir, PathBuf::from("/tmp/alfred-data"));
    }

    #[test]
    fn config_retry_policy_backoff_is_deterministic() {
        let policy = RetryPolicy::default();

        assert_eq!(policy.backoff_for_attempt(1), 0);
        assert_eq!(policy.backoff_for_attempt(2), 200);
        assert_eq!(policy.backoff_for_attempt(3), 400);
    }
}
