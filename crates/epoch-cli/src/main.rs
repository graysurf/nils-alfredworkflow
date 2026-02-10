use chrono::{DateTime, Local, NaiveDate};
use clap::{Parser, Subcommand};

use epoch_cli::{
    clipboard,
    convert::{self, ConversionRow},
    error::AppError,
    feedback,
    parser::{self, QueryInput},
};

#[derive(Debug, Parser)]
#[command(author, version, about = "Epoch conversion workflow CLI")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Convert epoch/date-time values and print Alfred feedback JSON.
    Convert {
        /// Conversion query text.
        #[arg(long, default_value = "")]
        query: String,
    },
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
    run_with(cli, Local::now, clipboard::read_clipboard_text)
}

fn run_with<Now, ReadClipboard>(
    cli: Cli,
    now: Now,
    read_clipboard: ReadClipboard,
) -> Result<String, AppError>
where
    Now: Fn() -> DateTime<Local>,
    ReadClipboard: Fn() -> Option<String>,
{
    match cli.command {
        Commands::Convert { query } => {
            let now = now();
            let today = now.date_naive();
            let parsed = parser::parse_query(&query, today)?;
            let include_clipboard = matches!(parsed, QueryInput::Empty);

            let mut rows = rows_for_query(parsed, now)?;
            if include_clipboard {
                rows.extend(best_effort_clipboard_rows(read_clipboard(), today, now));
            }

            feedback::rows_to_feedback(&rows)
                .to_json()
                .map_err(|error| {
                    AppError::runtime(format!("failed to serialize feedback: {error}"))
                })
        }
    }
}

fn rows_for_query(
    parsed: QueryInput,
    now: DateTime<Local>,
) -> Result<Vec<ConversionRow>, AppError> {
    match parsed {
        QueryInput::Empty => convert::current_epoch_rows(now).map_err(AppError::from),
        QueryInput::Epoch(epoch) => convert::epoch_to_datetime_rows(epoch).map_err(AppError::from),
        QueryInput::DateTime(datetime) => {
            convert::datetime_to_epoch_rows(datetime).map_err(AppError::from)
        }
    }
}

fn best_effort_clipboard_rows(
    clipboard_text: Option<String>,
    today: NaiveDate,
    now: DateTime<Local>,
) -> Vec<ConversionRow> {
    let Some(clipboard_text) = clipboard_text else {
        return Vec::new();
    };

    let parsed = match parser::parse_query(&clipboard_text, today) {
        Ok(parsed) => parsed,
        Err(_) => return Vec::new(),
    };

    if matches!(parsed, QueryInput::Empty) {
        return Vec::new();
    }

    match rows_for_query(parsed, now) {
        Ok(rows) => convert::prefix_rows(rows, "(clipboard)"),
        Err(_) => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use chrono::{NaiveDate, TimeZone, Utc};
    use epoch_cli::error::ErrorKind;
    use serde_json::Value;

    use super::*;

    fn fixed_now() -> DateTime<Local> {
        DateTime::parse_from_rfc3339("2026-02-10T00:00:00+00:00")
            .expect("parse fixture")
            .with_timezone(&Local)
    }

    fn item_subtitles(json: &Value) -> Vec<&str> {
        json.get("items")
            .and_then(Value::as_array)
            .expect("items array")
            .iter()
            .filter_map(|item| item.get("subtitle").and_then(Value::as_str))
            .collect()
    }

    #[test]
    fn main_convert_epoch_query_outputs_local_formatted_row() {
        let cli = Cli::parse_from(["epoch-cli", "convert", "--query", "0"]);

        let output = run_with(cli, fixed_now, || None).expect("conversion should succeed");

        let json: Value = serde_json::from_str(&output).expect("output should be json");
        let items = json
            .get("items")
            .and_then(Value::as_array)
            .expect("items should be array");

        let formatted_item = items
            .iter()
            .find(|item| {
                item.get("subtitle").and_then(Value::as_str)
                    == Some("Local formatted (YYYY-MM-DD HH:MM:SS)")
            })
            .expect("formatted row should exist");

        let expected = Utc
            .timestamp_opt(0, 0)
            .single()
            .expect("epoch zero")
            .with_timezone(&Local)
            .format("%Y-%m-%d %H:%M:%S")
            .to_string();

        assert_eq!(
            formatted_item.get("title").and_then(Value::as_str),
            Some(expected.as_str())
        );
    }

    #[test]
    fn main_empty_query_includes_now_rows_and_clipboard_prefix_rows() {
        let cli = Cli::parse_from(["epoch-cli", "convert"]);

        let output = run_with(cli, fixed_now, || Some("1970-01-01".to_string()))
            .expect("empty query should succeed");

        let json: Value = serde_json::from_str(&output).expect("output should be json");
        let subtitles = item_subtitles(&json);

        assert!(subtitles.contains(&"Now epoch (s)"));
        assert!(subtitles.contains(&"Now epoch (ms)"));
        assert!(subtitles.contains(&"Now epoch (us)"));
        assert!(subtitles.contains(&"Now epoch (ns)"));
        assert!(
            subtitles
                .iter()
                .any(|subtitle| subtitle.starts_with("(clipboard) ")),
            "clipboard rows should be prefixed"
        );
    }

    #[test]
    fn main_invalid_query_returns_user_error() {
        let cli = Cli::parse_from(["epoch-cli", "convert", "--query", "invalid query"]);

        let error = run_with(cli, fixed_now, || None).expect_err("invalid query should fail");

        assert_eq!(error.kind, ErrorKind::User);
        assert_eq!(error.exit_code(), 2);
        assert_eq!(error.message, "unsupported query format: invalid query");
    }

    #[test]
    fn main_help_flag_is_supported() {
        let help = Cli::try_parse_from(["epoch-cli", "--help"])
            .expect_err("help should be surfaced by clap");

        assert_eq!(help.kind(), clap::error::ErrorKind::DisplayHelp);
    }

    #[test]
    fn best_effort_clipboard_rows_ignores_unparseable_content() {
        let rows = best_effort_clipboard_rows(
            Some("not a timestamp".to_string()),
            NaiveDate::from_ymd_opt(2026, 2, 10).expect("date"),
            fixed_now(),
        );

        assert!(rows.is_empty(), "invalid clipboard should be ignored");
    }
}
