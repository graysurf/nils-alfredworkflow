use std::collections::HashMap;
use std::path::PathBuf;

use thiserror::Error;

const DICT_MODE_ENV: &str = "CAMBRIDGE_DICT_MODE";
const MAX_RESULTS_ENV: &str = "CAMBRIDGE_MAX_RESULTS";
const TIMEOUT_MS_ENV: &str = "CAMBRIDGE_TIMEOUT_MS";
const HEADLESS_ENV: &str = "CAMBRIDGE_HEADLESS";
const NODE_BIN_ENV: &str = "CAMBRIDGE_NODE_BIN";
const SCRAPER_SCRIPT_ENV: &str = "CAMBRIDGE_SCRAPER_SCRIPT";
const HOME_ENV: &str = "HOME";

const MIN_RESULTS: i32 = 1;
const MAX_RESULTS: i32 = 20;
const MIN_TIMEOUT_MS: i64 = 1_000;
const MAX_TIMEOUT_MS: i64 = 60_000;

pub const DEFAULT_MAX_RESULTS: u8 = 10;
pub const DEFAULT_TIMEOUT_MS: u64 = 12_000;
pub const DEFAULT_HEADLESS: bool = true;
pub const DEFAULT_NODE_BIN: &str = "node";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DictionaryMode {
    English,
    EnglishChineseTraditional,
}

impl DictionaryMode {
    pub const fn as_str(self) -> &'static str {
        match self {
            DictionaryMode::English => "english",
            DictionaryMode::EnglishChineseTraditional => "english-chinese-traditional",
        }
    }

    fn parse(value: &str) -> Option<Self> {
        match value {
            "english" => Some(DictionaryMode::English),
            "english-chinese-traditional" => Some(DictionaryMode::EnglishChineseTraditional),
            _ => None,
        }
    }
}

impl std::fmt::Display for DictionaryMode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

pub const DEFAULT_DICT_MODE: DictionaryMode = DictionaryMode::English;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeConfig {
    pub dict_mode: DictionaryMode,
    pub max_results: u8,
    pub timeout_ms: u64,
    pub headless: bool,
    pub node_bin: String,
    pub scraper_script: PathBuf,
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
        let home = env_map.get(HOME_ENV).map(String::as_str);

        Ok(Self {
            dict_mode: parse_dict_mode(env_map.get(DICT_MODE_ENV).map(String::as_str))?,
            max_results: parse_max_results(env_map.get(MAX_RESULTS_ENV).map(String::as_str))?,
            timeout_ms: parse_timeout_ms(env_map.get(TIMEOUT_MS_ENV).map(String::as_str))?,
            headless: parse_headless(env_map.get(HEADLESS_ENV).map(String::as_str))?,
            node_bin: parse_node_bin(env_map.get(NODE_BIN_ENV).map(String::as_str), home),
            scraper_script: parse_scraper_script(
                env_map.get(SCRAPER_SCRIPT_ENV).map(String::as_str),
                home,
            )?,
        })
    }
}

fn parse_dict_mode(raw: Option<&str>) -> Result<DictionaryMode, ConfigError> {
    let Some(value) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(DEFAULT_DICT_MODE);
    };

    let normalized = value.to_ascii_lowercase();
    DictionaryMode::parse(&normalized)
        .ok_or_else(|| ConfigError::InvalidDictMode(value.to_string()))
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

fn parse_timeout_ms(raw: Option<&str>) -> Result<u64, ConfigError> {
    let Some(value) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(DEFAULT_TIMEOUT_MS);
    };

    let parsed = value
        .parse::<i64>()
        .map_err(|_| ConfigError::InvalidTimeoutMs(value.to_string()))?;

    Ok(parsed.clamp(MIN_TIMEOUT_MS, MAX_TIMEOUT_MS) as u64)
}

fn parse_headless(raw: Option<&str>) -> Result<bool, ConfigError> {
    let Some(value) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(DEFAULT_HEADLESS);
    };

    match value.to_ascii_lowercase().as_str() {
        "1" | "true" | "t" | "yes" | "y" | "on" => Ok(true),
        "0" | "false" | "f" | "no" | "n" | "off" => Ok(false),
        _ => Err(ConfigError::InvalidHeadless(value.to_string())),
    }
}

fn parse_node_bin(raw: Option<&str>, home: Option<&str>) -> String {
    raw.map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| expand_home_path(value, home))
        .unwrap_or_else(|| DEFAULT_NODE_BIN.to_string())
}

fn parse_scraper_script(raw: Option<&str>, home: Option<&str>) -> Result<PathBuf, ConfigError> {
    let value = raw
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or(ConfigError::MissingScraperScript)?;

    let expanded = expand_home_path(value, home);
    let path = PathBuf::from(&expanded);
    if !path.is_file() {
        return Err(ConfigError::ScraperScriptNotFound(expanded));
    }

    Ok(path)
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

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ConfigError {
    #[error("invalid CAMBRIDGE_DICT_MODE: {0} (expected english or english-chinese-traditional)")]
    InvalidDictMode(String),
    #[error("invalid CAMBRIDGE_MAX_RESULTS: {0}")]
    InvalidMaxResults(String),
    #[error("invalid CAMBRIDGE_TIMEOUT_MS: {0}")]
    InvalidTimeoutMs(String),
    #[error("invalid CAMBRIDGE_HEADLESS: {0} (expected one of: true/false, yes/no, on/off, 1/0)")]
    InvalidHeadless(String),
    #[error("missing CAMBRIDGE_SCRAPER_SCRIPT")]
    MissingScraperScript,
    #[error("CAMBRIDGE_SCRAPER_SCRIPT not found: {0}")]
    ScraperScriptNotFound(String),
}

#[cfg(test)]
mod tests {
    use std::fs;

    use tempfile::tempdir;

    use super::*;

    fn fixture_script() -> (tempfile::TempDir, String) {
        let dir = tempdir().expect("create temp dir");
        let script_path = dir.path().join("cambridge_scraper.mjs");
        fs::write(&script_path, "console.log('{}');").expect("write temp script");
        (dir, script_path.to_string_lossy().into_owned())
    }

    #[test]
    fn config_uses_defaults_for_optional_values() {
        let (_dir, script_path) = fixture_script();
        let config = RuntimeConfig::from_pairs(vec![(SCRAPER_SCRIPT_ENV, script_path.as_str())])
            .expect("config should parse");

        assert_eq!(config.dict_mode, DEFAULT_DICT_MODE);
        assert_eq!(config.max_results, DEFAULT_MAX_RESULTS);
        assert_eq!(config.timeout_ms, DEFAULT_TIMEOUT_MS);
        assert_eq!(config.headless, DEFAULT_HEADLESS);
        assert_eq!(config.node_bin, DEFAULT_NODE_BIN);
    }

    #[test]
    fn config_parses_supported_dict_modes() {
        let (_dir, script_path) = fixture_script();
        let english = RuntimeConfig::from_pairs(vec![
            (DICT_MODE_ENV, " english "),
            (SCRAPER_SCRIPT_ENV, script_path.as_str()),
        ])
        .expect("english mode should parse");
        assert_eq!(english.dict_mode, DictionaryMode::English);

        let traditional = RuntimeConfig::from_pairs(vec![
            (DICT_MODE_ENV, "ENGLISH-CHINESE-TRADITIONAL"),
            (SCRAPER_SCRIPT_ENV, script_path.as_str()),
        ])
        .expect("traditional mode should parse");
        assert_eq!(
            traditional.dict_mode,
            DictionaryMode::EnglishChineseTraditional
        );
    }

    #[test]
    fn config_rejects_invalid_dict_mode() {
        let (_dir, script_path) = fixture_script();
        let err = RuntimeConfig::from_pairs(vec![
            (DICT_MODE_ENV, "zh-tw"),
            (SCRAPER_SCRIPT_ENV, script_path.as_str()),
        ])
        .expect_err("invalid mode should fail");

        assert_eq!(err, ConfigError::InvalidDictMode("zh-tw".to_string()));
    }

    #[test]
    fn config_clamps_max_results_into_supported_range() {
        let (_dir, script_path) = fixture_script();
        let lower = RuntimeConfig::from_pairs(vec![
            (MAX_RESULTS_ENV, "-9"),
            (SCRAPER_SCRIPT_ENV, script_path.as_str()),
        ])
        .expect("lower bound should parse");
        assert_eq!(lower.max_results, 1);

        let upper = RuntimeConfig::from_pairs(vec![
            (MAX_RESULTS_ENV, "99"),
            (SCRAPER_SCRIPT_ENV, script_path.as_str()),
        ])
        .expect("upper bound should parse");
        assert_eq!(upper.max_results, 20);
    }

    #[test]
    fn config_clamps_timeout_ms_into_supported_range() {
        let (_dir, script_path) = fixture_script();
        let lower = RuntimeConfig::from_pairs(vec![
            (TIMEOUT_MS_ENV, "500"),
            (SCRAPER_SCRIPT_ENV, script_path.as_str()),
        ])
        .expect("lower timeout should parse");
        assert_eq!(lower.timeout_ms, 1_000);

        let upper = RuntimeConfig::from_pairs(vec![
            (TIMEOUT_MS_ENV, "999999"),
            (SCRAPER_SCRIPT_ENV, script_path.as_str()),
        ])
        .expect("upper timeout should parse");
        assert_eq!(upper.timeout_ms, 60_000);
    }

    #[test]
    fn config_parses_common_headless_bool_strings() {
        let (_dir, script_path) = fixture_script();

        for raw in ["1", "true", "YES", "On", "t"] {
            let config = RuntimeConfig::from_pairs(vec![
                (HEADLESS_ENV, raw),
                (SCRAPER_SCRIPT_ENV, script_path.as_str()),
            ])
            .expect("truthy value should parse");
            assert!(config.headless, "{raw} should parse as true");
        }

        for raw in ["0", "false", "NO", "off", "F"] {
            let config = RuntimeConfig::from_pairs(vec![
                (HEADLESS_ENV, raw),
                (SCRAPER_SCRIPT_ENV, script_path.as_str()),
            ])
            .expect("falsy value should parse");
            assert!(!config.headless, "{raw} should parse as false");
        }
    }

    #[test]
    fn config_rejects_invalid_headless_value() {
        let (_dir, script_path) = fixture_script();
        let err = RuntimeConfig::from_pairs(vec![
            (HEADLESS_ENV, "maybe"),
            (SCRAPER_SCRIPT_ENV, script_path.as_str()),
        ])
        .expect_err("invalid bool should fail");

        assert_eq!(err, ConfigError::InvalidHeadless("maybe".to_string()));
    }

    #[test]
    fn config_uses_default_node_bin_for_blank_value() {
        let (_dir, script_path) = fixture_script();
        let config = RuntimeConfig::from_pairs(vec![
            (NODE_BIN_ENV, " "),
            (SCRAPER_SCRIPT_ENV, script_path.as_str()),
        ])
        .expect("blank node bin should fall back to default");

        assert_eq!(config.node_bin, DEFAULT_NODE_BIN);
    }

    #[test]
    fn config_expands_home_prefix_for_node_bin() {
        let (_dir, script_path) = fixture_script();
        let config = RuntimeConfig::from_pairs(vec![
            (HOME_ENV, "/tmp/home"),
            (NODE_BIN_ENV, "~/.local/bin/node"),
            (SCRAPER_SCRIPT_ENV, script_path.as_str()),
        ])
        .expect("node bin should parse");

        assert_eq!(config.node_bin, "/tmp/home/.local/bin/node");
    }

    #[test]
    fn config_requires_scraper_script_path() {
        let err = RuntimeConfig::from_pairs(Vec::<(String, String)>::new())
            .expect_err("missing script should fail");

        assert_eq!(err, ConfigError::MissingScraperScript);
    }

    #[test]
    fn config_rejects_missing_scraper_script_file() {
        let err = RuntimeConfig::from_pairs(vec![(SCRAPER_SCRIPT_ENV, "/tmp/no-such-script.mjs")])
            .expect_err("unknown script path should fail");

        assert_eq!(
            err,
            ConfigError::ScraperScriptNotFound("/tmp/no-such-script.mjs".to_string())
        );
    }

    #[test]
    fn config_expands_home_prefix_for_scraper_script_path() {
        let home = tempdir().expect("create home dir");
        let script_path = home.path().join(".cambridge").join("scraper.mjs");
        fs::create_dir_all(script_path.parent().expect("script parent")).expect("create dir");
        fs::write(&script_path, "console.log('{}');").expect("write script");

        let config = RuntimeConfig::from_pairs(vec![
            (HOME_ENV, home.path().to_string_lossy().as_ref()),
            (SCRAPER_SCRIPT_ENV, "~/.cambridge/scraper.mjs"),
        ])
        .expect("scraper script should parse");

        assert_eq!(config.scraper_script, script_path);
    }
}
