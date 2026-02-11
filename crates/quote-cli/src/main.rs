use clap::{Parser, Subcommand, ValueEnum};
use serde::Serialize;
use serde_json::Value;

use quote_cli::{
    config::{ConfigError, RuntimeConfig},
    feedback,
    refresh::{self, RefreshError, RefreshOutcome},
    store::StorePaths,
    zenquotes,
};

#[derive(Debug, Parser)]
#[command(author, version, about = "Quote workflow CLI")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Build quote feed items and print Alfred feedback JSON.
    Feed {
        /// Optional query text for local cache filtering.
        #[arg(long, default_value = "")]
        query: String,
        /// Output mode: workflow-compatible Alfred JSON or service envelope JSON.
        #[arg(long, value_enum, default_value_t = OutputMode::Alfred)]
        mode: OutputMode,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
#[value(rename_all = "kebab-case")]
enum OutputMode {
    ServiceJson,
    Alfred,
}

impl Cli {
    fn command_name(&self) -> &'static str {
        match &self.command {
            Commands::Feed { .. } => "feed",
        }
    }

    fn output_mode(&self) -> OutputMode {
        match &self.command {
            Commands::Feed { mode, .. } => *mode,
        }
    }
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

    fn from_refresh(error: RefreshError) -> Self {
        AppError::runtime(error.to_string())
    }

    fn exit_code(&self) -> i32 {
        match self.kind {
            ErrorKind::User => 2,
            ErrorKind::Runtime => 1,
        }
    }

    fn code(&self) -> &'static str {
        match self.kind {
            ErrorKind::User => "quote.user",
            ErrorKind::Runtime => "quote.runtime",
        }
    }
}

fn main() {
    let cli = Cli::parse();
    let command = cli.command_name();
    let mode = cli.output_mode();

    match run(cli) {
        Ok(output) => {
            println!("{output}");
        }
        Err(error) => {
            match mode {
                OutputMode::ServiceJson => {
                    println!("{}", serialize_service_error(command, &error));
                }
                OutputMode::Alfred => {
                    eprintln!("error: {}", error.message);
                }
            }
            std::process::exit(error.exit_code());
        }
    }
}

fn run(cli: Cli) -> Result<String, AppError> {
    run_with(cli, RuntimeConfig::from_env, |config| {
        let paths = StorePaths::from_config(config);
        refresh::maybe_refresh(
            config,
            &paths,
            |count| zenquotes::fetch_quotes(count, 2),
            refresh::unix_now_secs,
        )
    })
}

fn run_with<LoadConfig, RefreshQuotes>(
    cli: Cli,
    load_config: LoadConfig,
    refresh_quotes: RefreshQuotes,
) -> Result<String, AppError>
where
    LoadConfig: Fn() -> Result<RuntimeConfig, ConfigError>,
    RefreshQuotes: Fn(&RuntimeConfig) -> Result<RefreshOutcome, RefreshError>,
{
    match cli.command {
        Commands::Feed { query, mode } => {
            let config = load_config().map_err(AppError::from_config)?;
            let outcome = refresh_quotes(&config).map_err(AppError::from_refresh)?;

            let payload = feedback::quotes_to_feedback(
                &outcome.quotes,
                config.display_count,
                &query,
                outcome.refresh_error.as_deref(),
            );

            render_feedback(mode, "feed", payload)
        }
    }
}

#[derive(Debug, Serialize)]
struct ServiceErrorEnvelope {
    code: &'static str,
    message: String,
    details: Option<Value>,
}

#[derive(Debug, Serialize)]
struct ServiceEnvelope {
    schema_version: &'static str,
    command: &'static str,
    ok: bool,
    result: Option<Value>,
    error: Option<ServiceErrorEnvelope>,
}

fn render_feedback(
    mode: OutputMode,
    command: &'static str,
    payload: alfred_core::Feedback,
) -> Result<String, AppError> {
    match mode {
        OutputMode::Alfred => payload
            .to_json()
            .map_err(|error| AppError::runtime(format!("failed to serialize feedback: {error}"))),
        OutputMode::ServiceJson => {
            let result = serde_json::to_value(payload).map_err(|error| {
                AppError::runtime(format!("failed to serialize feedback: {error}"))
            })?;
            serde_json::to_string(&ServiceEnvelope {
                schema_version: "v1",
                command,
                ok: true,
                result: Some(result),
                error: None,
            })
            .map_err(|error| {
                AppError::runtime(format!("failed to serialize service envelope: {error}"))
            })
        }
    }
}

fn serialize_service_error(command: &'static str, error: &AppError) -> String {
    let envelope = ServiceEnvelope {
        schema_version: "v1",
        command,
        ok: false,
        result: None,
        error: Some(ServiceErrorEnvelope {
            code: error.code(),
            message: error.message.clone(),
            details: None,
        }),
    };

    serde_json::to_string(&envelope).unwrap_or_else(|serialize_error| {
        serde_json::json!({
            "schema_version": "v1",
            "command": command,
            "ok": false,
            "result": Value::Null,
            "error": {
                "code": "internal.serialize",
                "message": format!("failed to serialize service error envelope: {serialize_error}"),
                "details": Value::Null,
            }
        })
        .to_string()
    })
}

#[cfg(test)]
mod tests {
    use serde_json::Value;

    use super::*;

    fn fixture_config() -> RuntimeConfig {
        RuntimeConfig {
            display_count: 3,
            refresh_interval_secs: 3600,
            fetch_count: 5,
            max_entries: 100,
            data_dir: std::env::temp_dir().join("quote-cli-test"),
        }
    }

    #[test]
    fn main_feed_command_outputs_feedback_json_contract() {
        let cli = Cli::parse_from(["quote-cli", "feed", "--query", ""]);

        let output = run_with(
            cli,
            || Ok(fixture_config()),
            |_| {
                Ok(RefreshOutcome {
                    quotes: vec!["\"stay hungry\" — steve jobs".to_string()],
                    refresh_error: None,
                })
            },
        )
        .expect("feed should succeed");

        let json: Value = serde_json::from_str(&output).expect("output should be JSON");
        let first = json
            .get("items")
            .and_then(Value::as_array)
            .and_then(|items| items.first())
            .expect("first item should exist");

        assert_eq!(
            first.get("title").and_then(Value::as_str),
            Some("stay hungry")
        );
        assert_eq!(
            first.get("subtitle").and_then(Value::as_str),
            Some("steve jobs")
        );
        assert_eq!(
            first.get("arg").and_then(Value::as_str),
            Some("stay hungry")
        );
        assert_eq!(first.get("valid").and_then(Value::as_bool), Some(true));
    }

    #[test]
    fn main_feed_service_json_mode_wraps_result_in_v1_envelope() {
        let cli = Cli::parse_from(["quote-cli", "feed", "--mode", "service-json"]);

        let output = run_with(
            cli,
            || Ok(fixture_config()),
            |_| {
                Ok(RefreshOutcome {
                    quotes: vec!["\"stay hungry\" — steve jobs".to_string()],
                    refresh_error: None,
                })
            },
        )
        .expect("feed should succeed");

        let json: Value = serde_json::from_str(&output).expect("output must be JSON");
        assert_eq!(
            json.get("schema_version").and_then(Value::as_str),
            Some("v1")
        );
        assert_eq!(json.get("command").and_then(Value::as_str), Some("feed"));
        assert_eq!(json.get("ok").and_then(Value::as_bool), Some(true));
        assert!(
            json.get("result")
                .and_then(|result| result.get("items"))
                .and_then(Value::as_array)
                .is_some()
        );
    }

    #[test]
    fn main_maps_config_failures_to_user_error() {
        let cli = Cli::parse_from(["quote-cli", "feed"]);

        let err = run_with(
            cli,
            || Err(ConfigError::InvalidRefreshInterval("90x".to_string())),
            |_| unreachable!("refresh should not run when config fails"),
        )
        .expect_err("invalid config should fail");

        assert_eq!(err.kind, ErrorKind::User);
        assert_eq!(err.exit_code(), 2);
        assert!(err.message.contains("invalid QUOTE_REFRESH_INTERVAL"));
    }

    #[test]
    fn main_maps_refresh_storage_failures_to_runtime_error() {
        let cli = Cli::parse_from(["quote-cli", "feed"]);

        let err = run_with(
            cli,
            || Ok(fixture_config()),
            |_| {
                Err(RefreshError::Storage(std::io::Error::other(
                    "disk is read-only",
                )))
            },
        )
        .expect_err("storage errors should fail");

        assert_eq!(err.kind, ErrorKind::Runtime);
        assert_eq!(err.exit_code(), 1);
        assert!(err.message.contains("quote storage operation failed"));
    }

    #[test]
    fn main_help_flag_is_supported() {
        let help = Cli::try_parse_from(["quote-cli", "--help"])
            .expect_err("help should be handled by clap");

        assert_eq!(help.kind(), clap::error::ErrorKind::DisplayHelp);
    }

    #[test]
    fn main_service_error_envelope_has_required_error_fields() {
        let payload = serialize_service_error(
            "feed",
            &AppError::user("invalid QUOTE_REFRESH_INTERVAL: bad"),
        );
        let json: Value = serde_json::from_str(&payload).expect("service error should be json");

        assert_eq!(
            json.get("schema_version").and_then(Value::as_str),
            Some("v1")
        );
        assert_eq!(json.get("command").and_then(Value::as_str), Some("feed"));
        assert_eq!(json.get("ok").and_then(Value::as_bool), Some(false));
        assert!(json.get("result").is_some());
        assert_eq!(
            json.get("error")
                .and_then(|error| error.get("code"))
                .and_then(Value::as_str),
            Some("quote.user")
        );
        assert!(
            json.get("error")
                .and_then(|error| error.get("details"))
                .is_some()
        );
    }
}
