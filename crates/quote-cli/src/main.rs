use clap::{Parser, Subcommand};

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

    fn from_refresh(error: RefreshError) -> Self {
        AppError::runtime(error.to_string())
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
        Commands::Feed { query } => {
            let config = load_config().map_err(AppError::from_config)?;
            let outcome = refresh_quotes(&config).map_err(AppError::from_refresh)?;

            let payload = feedback::quotes_to_feedback(
                &outcome.quotes,
                config.display_count,
                &query,
                outcome.refresh_error.as_deref(),
            );

            payload.to_json().map_err(|error| {
                AppError::runtime(format!("failed to serialize feedback: {error}"))
            })
        }
    }
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
}
