use std::env;
use std::path::PathBuf;

use alfred_core::{Feedback, Item};
use memo_cli::output::format_item_id;
use memo_cli::storage::Storage;
use memo_cli::storage::repository;
use serde::Serialize;
use thiserror::Error;

pub const DB_INIT_TOKEN: &str = "db-init";
pub const ADD_TOKEN_PREFIX: &str = "add::";
pub const DEFAULT_SOURCE: &str = "alfred";
pub const DEFAULT_MAX_INPUT_BYTES: usize = 4096;
const MAX_INPUT_BYTES_LIMIT: usize = 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeConfig {
    pub db_path: PathBuf,
    pub source: String,
    pub require_confirm: bool,
    pub max_input_bytes: usize,
}

impl RuntimeConfig {
    pub fn from_env() -> Result<Self, AppError> {
        let db_path = resolve_db_path();
        let source = resolve_source()?;
        let require_confirm = resolve_require_confirm()?;
        let max_input_bytes = resolve_max_input_bytes()?;

        Ok(Self {
            db_path,
            source,
            require_confirm,
            max_input_bytes,
        })
    }
}

#[derive(Debug, Error)]
pub enum AppError {
    #[error("{0}")]
    User(String),
    #[error("{0}")]
    Runtime(String),
}

impl AppError {
    pub fn exit_code(&self) -> i32 {
        match self {
            AppError::User(_) => 2,
            AppError::Runtime(_) => 1,
        }
    }

    pub fn message(&self) -> &str {
        match self {
            AppError::User(message) | AppError::Runtime(message) => message,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct AddResult {
    pub item_id: String,
    pub created_at: String,
    pub source: String,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct InitResult {
    pub db_path: String,
}

pub fn build_script_filter(query: &str, config: &RuntimeConfig) -> Feedback {
    let normalized = query.trim();
    if normalized.is_empty() {
        return build_empty_query_feedback(config);
    }

    if normalized.len() > config.max_input_bytes {
        return Feedback::new(vec![
            Item::new("Input exceeds MEMO_MAX_INPUT_BYTES")
                .with_subtitle(format!(
                    "Current {} bytes, limit {} bytes.",
                    normalized.len(),
                    config.max_input_bytes
                ))
                .with_valid(false),
        ]);
    }

    let preview = truncate_title(normalized, 64);
    let add_token = build_add_token(normalized);

    if config.require_confirm {
        return Feedback::new(vec![
            Item::new(format!("Preview: {preview}"))
                .with_subtitle("Confirmation required. Choose the row below to save.")
                .with_valid(false),
            Item::new("Confirm add memo")
                .with_subtitle(format!(
                    "Source: {} | DB: {}",
                    config.source,
                    config.db_path.display()
                ))
                .with_arg(add_token)
                .with_valid(true),
        ]);
    }

    Feedback::new(vec![
        Item::new(format!("Add memo: {preview}"))
            .with_subtitle(format!(
                "Press Enter to save ({}/{} bytes).",
                normalized.len(),
                config.max_input_bytes
            ))
            .with_arg(add_token)
            .with_valid(true),
    ])
}

pub fn execute_db_init(
    db_override: Option<PathBuf>,
    config: &RuntimeConfig,
) -> Result<InitResult, AppError> {
    let db_path = db_override.unwrap_or_else(|| config.db_path.clone());
    let storage = Storage::new(db_path.clone());
    storage
        .init()
        .map_err(|error| AppError::Runtime(error.message().to_string()))?;

    Ok(InitResult {
        db_path: db_path.display().to_string(),
    })
}

pub fn execute_add(
    text: &str,
    source_override: Option<&str>,
    db_override: Option<PathBuf>,
    config: &RuntimeConfig,
) -> Result<AddResult, AppError> {
    let normalized_text = text.trim();
    if normalized_text.is_empty() {
        return Err(AppError::User(
            "add requires a non-empty memo text".to_string(),
        ));
    }

    if normalized_text.len() > config.max_input_bytes {
        return Err(AppError::User(format!(
            "memo text exceeds MEMO_MAX_INPUT_BYTES: {} > {}",
            normalized_text.len(),
            config.max_input_bytes
        )));
    }

    let source = source_override
        .map(str::trim)
        .unwrap_or(config.source.as_str())
        .to_string();
    if source.is_empty() {
        return Err(AppError::User("MEMO_SOURCE must be non-empty".to_string()));
    }

    let db_path = db_override.unwrap_or_else(|| config.db_path.clone());
    let storage = Storage::new(db_path);
    storage
        .init()
        .map_err(|error| AppError::Runtime(error.message().to_string()))?;

    let added = storage
        .with_transaction(|tx| repository::add_item(tx, normalized_text, &source, None))
        .map_err(|error| AppError::Runtime(error.message().to_string()))?;

    Ok(AddResult {
        item_id: format_item_id(added.item_id),
        created_at: added.created_at,
        source: added.source,
        text: added.text,
    })
}

pub fn parse_add_token(arg: &str) -> Option<String> {
    arg.strip_prefix(ADD_TOKEN_PREFIX).map(str::to_string)
}

pub fn build_add_token(text: &str) -> String {
    format!("{ADD_TOKEN_PREFIX}{text}")
}

fn build_empty_query_feedback(config: &RuntimeConfig) -> Feedback {
    Feedback::new(vec![
        Item::new("Type memo text after keyword")
            .with_subtitle(format!(
                "Max {} bytes. Current source: {}.",
                config.max_input_bytes, config.source
            ))
            .with_valid(false),
        Item::new("Initialize memo database")
            .with_subtitle(format!(
                "Create/open SQLite at {}",
                config.db_path.display()
            ))
            .with_arg(DB_INIT_TOKEN)
            .with_valid(true),
    ])
}

fn truncate_title(input: &str, max_chars: usize) -> String {
    let count = input.chars().count();
    if count <= max_chars {
        return input.to_string();
    }

    let mut value = input.chars().take(max_chars).collect::<String>();
    value.push('…');
    value
}

fn resolve_db_path() -> PathBuf {
    if let Some(path) = non_empty_env("MEMO_DB_PATH") {
        return PathBuf::from(path);
    }

    for env_key in [
        "alfred_workflow_data",
        "ALFRED_WORKFLOW_DATA",
        "alfred_workflow_cache",
        "ALFRED_WORKFLOW_CACHE",
    ] {
        if let Some(path) = non_empty_env(env_key) {
            return PathBuf::from(path).join("memo.db");
        }
    }

    default_memo_db_path()
}

fn default_memo_db_path() -> PathBuf {
    if let Some(data_home) = env::var_os("XDG_DATA_HOME") {
        return PathBuf::from(data_home).join("nils-cli").join("memo.db");
    }

    if let Some(home) = env::var_os("HOME") {
        return PathBuf::from(home)
            .join(".local")
            .join("share")
            .join("nils-cli")
            .join("memo.db");
    }

    PathBuf::from("memo.db")
}

fn resolve_source() -> Result<String, AppError> {
    let source = non_empty_env("MEMO_SOURCE").unwrap_or_else(|| DEFAULT_SOURCE.to_string());
    let source = source.trim();

    if source.is_empty() {
        return Err(AppError::User("MEMO_SOURCE must be non-empty".to_string()));
    }

    Ok(source.to_string())
}

fn resolve_require_confirm() -> Result<bool, AppError> {
    let raw = non_empty_env("MEMO_REQUIRE_CONFIRM").unwrap_or_else(|| "0".to_string());
    parse_bool(&raw).ok_or_else(|| {
        AppError::User(
            "invalid MEMO_REQUIRE_CONFIRM: expected one of 1/0/true/false/yes/no/on/off"
                .to_string(),
        )
    })
}

fn resolve_max_input_bytes() -> Result<usize, AppError> {
    let raw = non_empty_env("MEMO_MAX_INPUT_BYTES")
        .unwrap_or_else(|| DEFAULT_MAX_INPUT_BYTES.to_string());

    let parsed = raw.parse::<usize>().map_err(|_| {
        AppError::User(format!(
            "invalid MEMO_MAX_INPUT_BYTES: {raw} (must be integer in range 1..={MAX_INPUT_BYTES_LIMIT})"
        ))
    })?;

    if !(1..=MAX_INPUT_BYTES_LIMIT).contains(&parsed) {
        return Err(AppError::User(format!(
            "invalid MEMO_MAX_INPUT_BYTES: {parsed} (must be integer in range 1..={MAX_INPUT_BYTES_LIMIT})"
        )));
    }

    Ok(parsed)
}

fn non_empty_env(key: &str) -> Option<String> {
    let value = env::var(key).ok()?;
    let value = value.trim();
    if value.is_empty() {
        return None;
    }
    Some(value.to_string())
}

fn parse_bool(raw: &str) -> Option<bool> {
    match raw.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Some(true),
        "0" | "false" | "no" | "off" => Some(false),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_config() -> RuntimeConfig {
        RuntimeConfig {
            db_path: PathBuf::from("/tmp/memo-test.db"),
            source: "alfred".to_string(),
            require_confirm: false,
            max_input_bytes: 4096,
        }
    }

    #[test]
    fn add_token_roundtrip() {
        let token = build_add_token("buy milk");
        assert_eq!(parse_add_token(&token).as_deref(), Some("buy milk"));
    }

    #[test]
    fn script_filter_returns_db_init_on_empty_query() {
        let feedback = build_script_filter("", &test_config());

        assert_eq!(feedback.items.len(), 2);
        assert_eq!(feedback.items[1].arg.as_deref(), Some(DB_INIT_TOKEN));
        assert_eq!(feedback.items[1].valid, Some(true));
    }

    #[test]
    fn script_filter_returns_add_action_for_non_empty_query() {
        let feedback = build_script_filter("buy milk", &test_config());

        assert_eq!(feedback.items.len(), 1);
        assert!(
            feedback.items[0]
                .arg
                .as_deref()
                .expect("arg")
                .starts_with(ADD_TOKEN_PREFIX)
        );
        assert_eq!(feedback.items[0].valid, Some(true));
    }

    #[test]
    fn script_filter_enforces_max_input_bytes() {
        let mut config = test_config();
        config.max_input_bytes = 4;

        let feedback = build_script_filter("12345", &config);
        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].valid, Some(false));
    }

    #[test]
    fn parse_bool_supports_expected_values() {
        assert_eq!(parse_bool("true"), Some(true));
        assert_eq!(parse_bool("1"), Some(true));
        assert_eq!(parse_bool("false"), Some(false));
        assert_eq!(parse_bool("0"), Some(false));
        assert_eq!(parse_bool("unknown"), None);
    }
}
