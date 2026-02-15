use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::config::RuntimeConfig;
use crate::input::SubjectType;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScraperBridgeRequest {
    pub keyword: String,
    pub subject_type: String,
    pub max_results: u8,
}

impl ScraperBridgeRequest {
    pub fn new(keyword: impl Into<String>, subject_type: SubjectType, max_results: u8) -> Self {
        Self {
            keyword: keyword.into(),
            subject_type: subject_type.as_str().to_string(),
            max_results,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScraperBridgeErrorInfo {
    pub code: String,
    pub message: String,
    pub retryable: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScraperBridgeResponse {
    pub ok: bool,
    pub items: Vec<ScraperBridgeItem>,
    pub error: Option<ScraperBridgeErrorInfo>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScraperBridgeItem {
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub url: Option<String>,
}

pub fn run_scraper_bridge(
    _config: &RuntimeConfig,
    _request: &ScraperBridgeRequest,
) -> Result<ScraperBridgeResponse, ScraperBridgeError> {
    Err(ScraperBridgeError::DisabledByDefault)
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ScraperBridgeError {
    #[error("scraper bridge is disabled by default")]
    DisabledByDefault,
    #[error("scraper bridge payload is invalid: {0}")]
    InvalidPayload(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scraper_bridge_request_serializes_subject_type_contract() {
        let request = ScraperBridgeRequest::new("naruto", SubjectType::Anime, 10);

        let json = serde_json::to_string(&request).expect("request should serialize");
        assert!(json.contains("\"subject_type\":\"anime\""));
    }

    #[test]
    fn scraper_bridge_stub_stays_disabled_by_default() {
        let config = RuntimeConfig {
            api_key: None,
            max_results: 10,
            timeout_ms: 8_000,
            user_agent: "ua".to_string(),
            cache_dir: std::path::PathBuf::from("/tmp/bangumi-cli-cache"),
            image_cache_ttl_seconds: 60,
            image_cache_max_bytes: 128 * 1024 * 1024,
            api_fallback: crate::config::ApiFallbackPolicy::Auto,
        };

        let request = ScraperBridgeRequest::new("naruto", SubjectType::Anime, 10);
        let err = run_scraper_bridge(&config, &request).expect_err("bridge should be disabled");

        assert_eq!(err, ScraperBridgeError::DisabledByDefault);
    }
}
