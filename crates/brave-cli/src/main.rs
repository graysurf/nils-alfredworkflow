use clap::{Parser, Subcommand, ValueEnum};
use serde::Serialize;
use serde_json::Value;

use brave_cli::{
    brave_api::{self, BraveApiError, WebSearchResult},
    config::{ConfigError, RuntimeConfig},
    feedback,
};

#[derive(Debug, Parser)]
#[command(author, version, about = "Brave search workflow CLI")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Search Brave web results and print Alfred feedback JSON.
    Search {
        /// Search query text.
        #[arg(long)]
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
            Commands::Search { .. } => "search",
        }
    }

    fn output_mode(&self) -> OutputMode {
        match &self.command {
            Commands::Search { mode, .. } => *mode,
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

    fn from_brave_api(error: BraveApiError) -> Self {
        match error {
            BraveApiError::Http { status, message } => {
                AppError::runtime(format!("brave api error ({status}): {message}"))
            }
            BraveApiError::Transport { .. } => AppError::runtime("brave api request failed"),
            BraveApiError::InvalidResponse(_) => AppError::runtime("invalid brave api response"),
        }
    }

    fn exit_code(&self) -> i32 {
        match self.kind {
            ErrorKind::User => 2,
            ErrorKind::Runtime => 1,
        }
    }

    fn code(&self) -> &'static str {
        match self.kind {
            ErrorKind::User => "brave.user",
            ErrorKind::Runtime => "brave.runtime",
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
    run_with(cli, RuntimeConfig::from_env, brave_api::search_web)
}

fn run_with<LoadConfig, SearchWeb>(
    cli: Cli,
    load_config: LoadConfig,
    search_web: SearchWeb,
) -> Result<String, AppError>
where
    LoadConfig: Fn() -> Result<RuntimeConfig, ConfigError>,
    SearchWeb: Fn(&RuntimeConfig, &str) -> Result<Vec<WebSearchResult>, BraveApiError>,
{
    match cli.command {
        Commands::Search { query, mode } => {
            let query = query.trim();
            if query.is_empty() {
                return Err(AppError::user("query must not be empty"));
            }

            let config = load_config().map_err(AppError::from_config)?;
            let results = search_web(&config, query).map_err(AppError::from_brave_api)?;

            let payload = feedback::search_results_to_feedback(&results);
            render_feedback(mode, "search", payload)
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
            .map_err(|err| AppError::runtime(format!("failed to serialize feedback: {err}"))),
        OutputMode::ServiceJson => {
            let result = serde_json::to_value(payload)
                .map_err(|err| AppError::runtime(format!("failed to serialize feedback: {err}")))?;
            serde_json::to_string(&ServiceEnvelope {
                schema_version: "v1",
                command,
                ok: true,
                result: Some(result),
                error: None,
            })
            .map_err(|err| {
                AppError::runtime(format!("failed to serialize service envelope: {err}"))
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

    use brave_cli::config::SafeSearch;

    use super::*;

    fn fixture_config() -> RuntimeConfig {
        RuntimeConfig {
            api_key: "demo-key".to_string(),
            count: 5,
            safesearch: SafeSearch::Moderate,
            country: None,
        }
    }

    #[test]
    fn main_search_command_outputs_feedback_json_contract() {
        let cli = Cli::parse_from(["brave-cli", "search", "--query", "rust"]);

        let output = run_with(
            cli,
            || Ok(fixture_config()),
            |_, _| {
                Ok(vec![WebSearchResult {
                    title: "Rust Language".to_string(),
                    url: "https://www.rust-lang.org/".to_string(),
                    description: "Build reliable software".to_string(),
                }])
            },
        )
        .expect("search should succeed");

        let json: Value = serde_json::from_str(&output).expect("output must be JSON");
        let first_item = json
            .get("items")
            .and_then(|items| items.get(0))
            .expect("first item should exist");

        assert_eq!(
            first_item.get("title").and_then(Value::as_str),
            Some("Rust Language")
        );
        assert_eq!(
            first_item.get("subtitle").and_then(Value::as_str),
            Some("Build reliable software")
        );
        assert_eq!(
            first_item.get("arg").and_then(Value::as_str),
            Some("https://www.rust-lang.org/")
        );
    }

    #[test]
    fn main_search_service_json_mode_wraps_result_in_v1_envelope() {
        let cli = Cli::parse_from([
            "brave-cli",
            "search",
            "--query",
            "rust",
            "--mode",
            "service-json",
        ]);

        let output = run_with(
            cli,
            || Ok(fixture_config()),
            |_, _| {
                Ok(vec![WebSearchResult {
                    title: "Rust Language".to_string(),
                    url: "https://www.rust-lang.org/".to_string(),
                    description: "Build reliable software".to_string(),
                }])
            },
        )
        .expect("search should succeed");

        let json: Value = serde_json::from_str(&output).expect("output must be JSON");
        assert_eq!(
            json.get("schema_version").and_then(Value::as_str),
            Some("v1")
        );
        assert_eq!(json.get("command").and_then(Value::as_str), Some("search"));
        assert_eq!(json.get("ok").and_then(Value::as_bool), Some(true));
        assert!(json.get("error").is_some());
        assert!(
            json.get("result")
                .and_then(|result| result.get("items"))
                .and_then(Value::as_array)
                .is_some()
        );
    }

    #[test]
    fn main_rejects_empty_query_as_user_error() {
        let cli = Cli::parse_from(["brave-cli", "search", "--query", "   "]);

        let err = run_with(cli, || Ok(fixture_config()), |_, _| Ok(Vec::new()))
            .expect_err("empty query should fail");

        assert_eq!(err.kind, ErrorKind::User);
        assert_eq!(err.message, "query must not be empty");
        assert_eq!(err.exit_code(), 2);
    }

    #[test]
    fn main_surfaces_config_errors_with_user_exit_kind() {
        let cli = Cli::parse_from(["brave-cli", "search", "--query", "rust"]);

        let err = run_with(
            cli,
            || Err(ConfigError::MissingApiKey),
            |_, _| Ok(Vec::new()),
        )
        .expect_err("missing config should fail");

        assert_eq!(err.kind, ErrorKind::User);
        assert_eq!(err.message, "missing BRAVE_API_KEY");
        assert_eq!(err.exit_code(), 2);
    }

    #[test]
    fn main_maps_http_api_failures_to_runtime_error_kind() {
        let cli = Cli::parse_from(["brave-cli", "search", "--query", "rust"]);

        let err = run_with(
            cli,
            || Ok(fixture_config()),
            |_, _| {
                Err(BraveApiError::Http {
                    status: 429,
                    message: "rate limit exceeded".to_string(),
                })
            },
        )
        .expect_err("api errors should fail");

        assert_eq!(err.kind, ErrorKind::Runtime);
        assert_eq!(err.message, "brave api error (429): rate limit exceeded");
        assert_eq!(err.exit_code(), 1);
    }

    #[test]
    fn main_maps_invalid_response_failures_to_runtime_error_kind() {
        let cli = Cli::parse_from(["brave-cli", "search", "--query", "rust"]);

        let err = run_with(
            cli,
            || Ok(fixture_config()),
            |_, _| {
                Err(BraveApiError::InvalidResponse(
                    serde_json::from_str::<serde_json::Value>("not-json")
                        .expect_err("fixture must produce parse error"),
                ))
            },
        )
        .expect_err("invalid response should fail");

        assert_eq!(err.kind, ErrorKind::Runtime);
        assert_eq!(err.message, "invalid brave api response");
        assert_eq!(err.exit_code(), 1);
    }

    #[test]
    fn main_help_flag_is_supported() {
        let help = Cli::try_parse_from(["brave-cli", "--help"])
            .expect_err("help should exit through clap error");

        assert_eq!(help.kind(), clap::error::ErrorKind::DisplayHelp);
    }

    #[test]
    fn main_service_error_envelope_has_required_error_fields() {
        let payload = serialize_service_error("search", &AppError::user("query must not be empty"));
        let json: Value = serde_json::from_str(&payload).expect("service error should be json");

        assert_eq!(
            json.get("schema_version").and_then(Value::as_str),
            Some("v1")
        );
        assert_eq!(json.get("command").and_then(Value::as_str), Some("search"));
        assert_eq!(json.get("ok").and_then(Value::as_bool), Some(false));
        assert!(json.get("result").is_some());
        assert_eq!(
            json.get("error")
                .and_then(|error| error.get("code"))
                .and_then(Value::as_str),
            Some("brave.user")
        );
        assert_eq!(
            json.get("error")
                .and_then(|error| error.get("message"))
                .and_then(Value::as_str),
            Some("query must not be empty")
        );
        assert!(
            json.get("error")
                .and_then(|error| error.get("details"))
                .is_some()
        );
    }
}
