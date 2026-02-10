use clap::{Parser, Subcommand};

use youtube_cli::{
    config::{ConfigError, RuntimeConfig},
    feedback,
    youtube_api::{self, VideoSearchResult, YouTubeApiError},
};

#[derive(Debug, Parser)]
#[command(author, version, about = "YouTube workflow CLI")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Search YouTube videos and print Alfred feedback JSON.
    Search {
        /// Search query text.
        #[arg(long)]
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

    fn from_youtube_api(error: YouTubeApiError) -> Self {
        match error {
            YouTubeApiError::Http { status, message } => {
                AppError::runtime(format!("youtube api error ({status}): {message}"))
            }
            YouTubeApiError::Transport { .. } => {
                AppError::runtime("youtube api request failed".to_string())
            }
            YouTubeApiError::InvalidResponse(_) => {
                AppError::runtime("invalid youtube api response".to_string())
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
    run_with(cli, RuntimeConfig::from_env, youtube_api::search_videos)
}

fn run_with<LoadConfig, SearchVideos>(
    cli: Cli,
    load_config: LoadConfig,
    search_videos: SearchVideos,
) -> Result<String, AppError>
where
    LoadConfig: Fn() -> Result<RuntimeConfig, ConfigError>,
    SearchVideos: Fn(&RuntimeConfig, &str) -> Result<Vec<VideoSearchResult>, YouTubeApiError>,
{
    match cli.command {
        Commands::Search { query } => {
            let query = query.trim();
            if query.is_empty() {
                return Err(AppError::user("query must not be empty"));
            }

            let config = load_config().map_err(AppError::from_config)?;
            let videos = search_videos(&config, query).map_err(AppError::from_youtube_api)?;

            let payload = feedback::videos_to_feedback(&videos);
            payload
                .to_json()
                .map_err(|err| AppError::runtime(format!("failed to serialize feedback: {err}")))
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::Value;

    use super::*;

    fn fixture_config() -> RuntimeConfig {
        RuntimeConfig {
            api_key: "demo-key".to_string(),
            max_results: 5,
            region_code: None,
        }
    }

    #[test]
    fn main_search_command_outputs_feedback_json_contract() {
        let cli = Cli::parse_from(["youtube-cli", "search", "--query", "rust"]);

        let output = run_with(
            cli,
            || Ok(fixture_config()),
            |_, _| {
                Ok(vec![VideoSearchResult {
                    video_id: "abc123".to_string(),
                    title: "Rust Tutorial".to_string(),
                    description: "Learn Rust quickly".to_string(),
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
            Some("Rust Tutorial")
        );
        assert_eq!(
            first_item.get("subtitle").and_then(Value::as_str),
            Some("Learn Rust quickly")
        );
        assert_eq!(
            first_item.get("arg").and_then(Value::as_str),
            Some("https://www.youtube.com/watch?v=abc123")
        );
    }

    #[test]
    fn main_rejects_empty_query_as_user_error() {
        let cli = Cli::parse_from(["youtube-cli", "search", "--query", "   "]);

        let err = run_with(
            cli,
            || Ok(fixture_config()),
            |_, _| Ok(Vec::<VideoSearchResult>::new()),
        )
        .expect_err("empty query should fail");

        assert_eq!(err.kind, ErrorKind::User);
        assert_eq!(err.message, "query must not be empty");
    }

    #[test]
    fn main_surfaces_config_errors_with_user_exit_kind() {
        let cli = Cli::parse_from(["youtube-cli", "search", "--query", "rust"]);

        let err = run_with(
            cli,
            || Err(ConfigError::MissingApiKey),
            |_, _| Ok(Vec::<VideoSearchResult>::new()),
        )
        .expect_err("missing config should fail");

        assert_eq!(err.kind, ErrorKind::User);
        assert_eq!(err.message, "missing YOUTUBE_API_KEY");
    }

    #[test]
    fn main_maps_api_failures_to_runtime_error_kind() {
        let cli = Cli::parse_from(["youtube-cli", "search", "--query", "rust"]);

        let err = run_with(
            cli,
            || Ok(fixture_config()),
            |_, _| {
                Err(YouTubeApiError::Http {
                    status: 403,
                    message: "invalid key".to_string(),
                })
            },
        )
        .expect_err("api errors should fail");

        assert_eq!(err.kind, ErrorKind::Runtime);
        assert_eq!(err.message, "youtube api error (403): invalid key");
    }

    #[test]
    fn main_help_flag_is_supported() {
        let help = Cli::try_parse_from(["youtube-cli", "--help"])
            .expect_err("help should exit through clap error");

        assert_eq!(help.kind(), clap::error::ErrorKind::DisplayHelp);
    }
}
