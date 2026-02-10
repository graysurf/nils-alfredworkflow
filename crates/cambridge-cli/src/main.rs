use clap::{Parser, Subcommand};

use cambridge_cli::{
    config::{ConfigError, RuntimeConfig},
    feedback,
    scraper_bridge::{self, BridgeError, ScraperResponse, ScraperStage},
    token::{self, QueryToken},
};

#[derive(Debug, Parser)]
#[command(author, version, about = "Cambridge dictionary workflow CLI")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Query Cambridge dictionary and print Alfred feedback JSON.
    Query {
        /// Query text from Alfred script filter.
        #[arg(long)]
        input: String,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ErrorKind {
    User,
    Runtime,
}

#[derive(Debug, PartialEq, Eq)]
struct AppError {
    kind: ErrorKind,
    message: String,
}

impl AppError {
    fn user(message: impl Into<String>) -> Self {
        Self {
            kind: ErrorKind::User,
            message: message.into(),
        }
    }

    fn runtime(message: impl Into<String>) -> Self {
        Self {
            kind: ErrorKind::Runtime,
            message: message.into(),
        }
    }

    fn from_config(error: ConfigError) -> Self {
        AppError::user(error.to_string())
    }

    fn from_bridge(error: BridgeError) -> Self {
        match error {
            BridgeError::Spawn { program, .. } => AppError::runtime(format!(
                "failed to run CAMBRIDGE_NODE_BIN `{program}`; install Node.js or fix CAMBRIDGE_NODE_BIN"
            )),
            BridgeError::Timeout { timeout_ms } => AppError::runtime(format!(
                "cambridge scraper timed out after {timeout_ms}ms; adjust CAMBRIDGE_TIMEOUT_MS and retry"
            )),
            BridgeError::NonZeroExit { code, stderr } => AppError::runtime(format!(
                "cambridge scraper exited with code {}: {stderr}",
                code.map_or_else(|| "unknown".to_string(), |value| value.to_string())
            )),
            BridgeError::InvalidJson(_) => {
                AppError::runtime("cambridge scraper returned invalid JSON")
            }
            BridgeError::UnsupportedStage(stage) => AppError::runtime(format!(
                "cambridge scraper returned unsupported stage: {stage}"
            )),
            BridgeError::StageMismatch { expected, actual } => AppError::runtime(format!(
                "cambridge scraper stage mismatch: expected {expected}, got {actual}"
            )),
            BridgeError::InvalidUtf8Stdout => {
                AppError::runtime("cambridge scraper stdout is not valid UTF-8")
            }
            BridgeError::Wait { .. }
            | BridgeError::ReadStdout { .. }
            | BridgeError::ReadStderr { .. } => {
                AppError::runtime("cambridge scraper process failed")
            }
        }
    }

    fn exit_code(&self) -> i32 {
        match self.kind {
            ErrorKind::User => 2,
            ErrorKind::Runtime => 1,
        }
    }
}

fn main() {
    let cli = Cli::parse();

    match run(cli) {
        Ok(output) => {
            println!("{output}");
        }
        Err(error) => {
            eprintln!("error: {}", error.message);
            std::process::exit(error.exit_code());
        }
    }
}

fn run(cli: Cli) -> Result<String, AppError> {
    run_with(cli, RuntimeConfig::from_env, scraper_bridge::run_scraper)
}

fn run_with<LoadConfig, RunScraper>(
    cli: Cli,
    load_config: LoadConfig,
    run_scraper: RunScraper,
) -> Result<String, AppError>
where
    LoadConfig: Fn() -> Result<RuntimeConfig, ConfigError>,
    RunScraper: Fn(&RuntimeConfig, ScraperStage, &str) -> Result<ScraperResponse, BridgeError>,
{
    match cli.command {
        Commands::Query { input } => {
            let feedback = match token::parse_query_token(&input) {
                QueryToken::Empty => feedback::empty_input_feedback(),
                QueryToken::DefineMissingEntry => feedback::missing_define_target_feedback(),
                QueryToken::Suggest { query } => {
                    let config = load_config().map_err(AppError::from_config)?;
                    let response = run_scraper(&config, ScraperStage::Suggest, &query)
                        .map_err(AppError::from_bridge)?;
                    feedback::suggest_feedback(&response)
                }
                QueryToken::Define { entry } => {
                    let config = load_config().map_err(AppError::from_config)?;
                    let response = run_scraper(&config, ScraperStage::Define, &entry)
                        .map_err(AppError::from_bridge)?;
                    feedback::define_feedback(&response, &entry, config.dict_mode)
                }
            };

            feedback.to_json().map_err(|error| {
                AppError::runtime(format!("failed to serialize feedback: {error}"))
            })
        }
    }
}

#[cfg(test)]
mod tests {
    use std::cell::Cell;
    use std::io;
    use std::path::PathBuf;

    use serde_json::Value;

    use super::*;
    use cambridge_cli::config::DictionaryMode;
    use cambridge_cli::scraper_bridge::{DefinitionLine, Entry, ScraperErrorInfo};

    fn fixture_config() -> RuntimeConfig {
        RuntimeConfig {
            dict_mode: DictionaryMode::EnglishChineseTraditional,
            max_results: 10,
            timeout_ms: 12_000,
            headless: true,
            node_bin: "node".to_string(),
            scraper_script: PathBuf::from("/tmp/cambridge_scraper.mjs"),
        }
    }

    fn fixture_suggest_response() -> ScraperResponse {
        ScraperResponse {
            ok: true,
            stage: ScraperStage::Suggest,
            items: vec![cambridge_cli::scraper_bridge::SuggestItem {
                word: "open".to_string(),
                subtitle: Some("verb".to_string()),
                url: None,
            }],
            entry: None,
            error: None,
        }
    }

    fn fixture_define_response() -> ScraperResponse {
        ScraperResponse {
            ok: true,
            stage: ScraperStage::Define,
            items: Vec::new(),
            entry: Some(Entry {
                headword: "open".to_string(),
                part_of_speech: Some("verb".to_string()),
                phonetics: None,
                url: Some("https://example.com/open".to_string()),
                definitions: vec![DefinitionLine {
                    text: "to move to an open position".to_string(),
                    part_of_speech: Some("verb".to_string()),
                }],
            }),
            error: None,
        }
    }

    #[test]
    fn main_query_empty_input_returns_guidance_without_runtime_dependencies() {
        let cli = Cli::parse_from(["cambridge-cli", "query", "--input", "   "]);
        let config_called = Cell::new(false);
        let bridge_called = Cell::new(false);

        let output = run_with(
            cli,
            || {
                config_called.set(true);
                Ok(fixture_config())
            },
            |_, _, _| {
                bridge_called.set(true);
                Ok(fixture_suggest_response())
            },
        )
        .expect("empty input should succeed");

        let json: Value = serde_json::from_str(&output).expect("output should be json");
        let item = json
            .get("items")
            .and_then(Value::as_array)
            .and_then(|items| items.first())
            .expect("feedback should contain one item");

        assert_eq!(
            item.get("title").and_then(Value::as_str),
            Some("Type a word to search Cambridge")
        );
        assert_eq!(item.get("valid").and_then(Value::as_bool), Some(false));
        assert!(!config_called.get(), "config should not be loaded");
        assert!(!bridge_called.get(), "bridge should not be called");
    }

    #[test]
    fn main_query_suggest_mode_maps_scraper_items_to_autocomplete_rows() {
        let cli = Cli::parse_from(["cambridge-cli", "query", "--input", "open"]);
        let output = run_with(
            cli,
            || Ok(fixture_config()),
            |_, stage, term| {
                assert_eq!(stage, ScraperStage::Suggest);
                assert_eq!(term, "open");
                Ok(fixture_suggest_response())
            },
        )
        .expect("suggest query should succeed");

        let json: Value = serde_json::from_str(&output).expect("output should be json");
        let item = json
            .get("items")
            .and_then(Value::as_array)
            .and_then(|items| items.first())
            .expect("first suggest item should exist");

        assert_eq!(item.get("title").and_then(Value::as_str), Some("open"));
        assert_eq!(item.get("valid").and_then(Value::as_bool), Some(false));
        assert_eq!(
            item.get("autocomplete").and_then(Value::as_str),
            Some("def::open")
        );
    }

    #[test]
    fn main_query_define_mode_maps_definition_rows_with_url_arg() {
        let cli = Cli::parse_from(["cambridge-cli", "query", "--input", "def::open"]);
        let output = run_with(
            cli,
            || Ok(fixture_config()),
            |_, stage, term| {
                assert_eq!(stage, ScraperStage::Define);
                assert_eq!(term, "open");
                Ok(fixture_define_response())
            },
        )
        .expect("define query should succeed");

        let json: Value = serde_json::from_str(&output).expect("output should be json");
        let items = json
            .get("items")
            .and_then(Value::as_array)
            .expect("items should be array");

        assert_eq!(items.len(), 2);
        assert_eq!(items[0].get("valid").and_then(Value::as_bool), Some(false));
        assert_eq!(items[1].get("valid").and_then(Value::as_bool), Some(true));
        assert_eq!(
            items[1].get("arg").and_then(Value::as_str),
            Some("https://example.com/open")
        );
    }

    #[test]
    fn main_maps_config_errors_to_user_exit_kind() {
        let cli = Cli::parse_from(["cambridge-cli", "query", "--input", "open"]);
        let err = run_with(
            cli,
            || Err(ConfigError::MissingScraperScript),
            |_, _, _| Ok(fixture_suggest_response()),
        )
        .expect_err("config error should fail");

        assert_eq!(err.kind, ErrorKind::User);
        assert_eq!(err.exit_code(), 2);
        assert_eq!(err.message, "missing CAMBRIDGE_SCRAPER_SCRIPT");
    }

    #[test]
    fn main_maps_bridge_spawn_failures_to_runtime_error() {
        let cli = Cli::parse_from(["cambridge-cli", "query", "--input", "open"]);
        let err = run_with(
            cli,
            || Ok(fixture_config()),
            |_, _, _| {
                Err(BridgeError::Spawn {
                    program: "/missing/node".to_string(),
                    source: io::Error::new(io::ErrorKind::NotFound, "missing binary"),
                })
            },
        )
        .expect_err("spawn failure should fail");

        assert_eq!(err.kind, ErrorKind::Runtime);
        assert_eq!(err.exit_code(), 1);
        assert!(err.message.contains("CAMBRIDGE_NODE_BIN"));
    }

    #[test]
    fn main_maps_bridge_timeout_to_runtime_error() {
        let cli = Cli::parse_from(["cambridge-cli", "query", "--input", "open"]);
        let err = run_with(
            cli,
            || Ok(fixture_config()),
            |_, _, _| Err(BridgeError::Timeout { timeout_ms: 12_000 }),
        )
        .expect_err("timeout should fail");

        assert_eq!(err.kind, ErrorKind::Runtime);
        assert_eq!(err.exit_code(), 1);
        assert!(err.message.contains("CAMBRIDGE_TIMEOUT_MS"));
    }

    #[test]
    fn main_maps_bridge_non_zero_exit_to_runtime_error() {
        let cli = Cli::parse_from(["cambridge-cli", "query", "--input", "open"]);
        let err = run_with(
            cli,
            || Ok(fixture_config()),
            |_, _, _| {
                Err(BridgeError::NonZeroExit {
                    code: Some(7),
                    stderr: "failed to scrape".to_string(),
                })
            },
        )
        .expect_err("non-zero exit should fail");

        assert_eq!(err.kind, ErrorKind::Runtime);
        assert_eq!(err.exit_code(), 1);
        assert!(err.message.contains("failed to scrape"));
    }

    #[test]
    fn main_help_flag_is_supported() {
        let help = Cli::try_parse_from(["cambridge-cli", "--help"])
            .expect_err("help should be surfaced by clap");

        assert_eq!(help.kind(), clap::error::ErrorKind::DisplayHelp);
    }

    #[test]
    fn main_suggest_error_payload_returns_non_crashing_feedback() {
        let cli = Cli::parse_from(["cambridge-cli", "query", "--input", "open"]);
        let output = run_with(
            cli,
            || Ok(fixture_config()),
            |_, _, _| {
                Ok(ScraperResponse {
                    ok: false,
                    stage: ScraperStage::Suggest,
                    items: Vec::new(),
                    entry: None,
                    error: Some(ScraperErrorInfo {
                        code: Some("blocked".to_string()),
                        message: "Cloudflare challenge".to_string(),
                        hint: Some("Try again later".to_string()),
                    }),
                })
            },
        )
        .expect("scraper contract error should still return feedback json");

        let json: Value = serde_json::from_str(&output).expect("output should be json");
        let item = json
            .get("items")
            .and_then(Value::as_array)
            .and_then(|items| items.first())
            .expect("item should exist");
        assert_eq!(item.get("valid").and_then(Value::as_bool), Some(false));
        assert_eq!(
            item.get("title").and_then(Value::as_str),
            Some("Cambridge suggestions unavailable")
        );
    }
}
