use chrono::{DateTime, Utc};
use clap::{Parser, Subcommand};

use timezone_cli::{
    convert,
    error::AppError,
    feedback, local_tz,
    parser::{self, TimezoneEntry},
};

#[derive(Debug, Parser)]
#[command(author, version, about = "Multi-timezone workflow CLI")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Render current time rows for query/config timezone list.
    Now {
        /// Query timezone list (comma/newline separated IANA IDs).
        #[arg(long, default_value = "")]
        query: String,
        /// Configured fallback timezone list when query is empty.
        #[arg(long = "config-zones", default_value = "")]
        config_zones: String,
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
    run_with(cli, Utc::now, local_tz::detect_local_timezone)
}

fn run_with<Now, DetectLocal>(
    cli: Cli,
    now: Now,
    detect_local: DetectLocal,
) -> Result<String, AppError>
where
    Now: Fn() -> DateTime<Utc>,
    DetectLocal: Fn() -> local_tz::LocalTimezone,
{
    match cli.command {
        Commands::Now {
            query,
            config_zones,
        } => {
            let zones = resolve_zones(&query, &config_zones, detect_local)?;
            let rows = convert::now_rows(now(), &zones);
            feedback::rows_to_feedback(&rows)
                .to_json()
                .map_err(|error| {
                    AppError::runtime(format!("failed to serialize timezone feedback: {error}"))
                })
        }
    }
}

fn resolve_zones<DetectLocal>(
    query: &str,
    config_zones: &str,
    detect_local: DetectLocal,
) -> Result<Vec<TimezoneEntry>, AppError>
where
    DetectLocal: Fn() -> local_tz::LocalTimezone,
{
    if !query.trim().is_empty() {
        return parser::parse_timezone_list(query).map_err(AppError::from);
    }

    if !config_zones.trim().is_empty() {
        return parser::parse_timezone_list(config_zones).map_err(AppError::from);
    }

    let local = detect_local();
    Ok(vec![TimezoneEntry::new(local.id, local.tz)])
}

#[cfg(test)]
mod tests {
    use chrono_tz::Tz;
    use serde_json::Value;
    use timezone_cli::{error::ErrorKind, local_tz::LocalTimezoneSource};

    use super::*;

    fn fixed_now() -> DateTime<Utc> {
        DateTime::parse_from_rfc3339("2026-02-10T12:00:00+00:00")
            .expect("parse fixed now")
            .with_timezone(&Utc)
    }

    fn fixed_local(id: &str) -> local_tz::LocalTimezone {
        let tz = id.parse::<Tz>().expect("valid timezone fixture");
        local_tz::LocalTimezone {
            id: id.to_string(),
            tz,
            source: LocalTimezoneSource::Override,
            trace: vec!["test fixture".to_string()],
        }
    }

    fn item_uids(json: &Value) -> Vec<&str> {
        json.get("items")
            .and_then(Value::as_array)
            .expect("items array")
            .iter()
            .filter_map(|item| item.get("uid").and_then(Value::as_str))
            .collect()
    }

    #[test]
    fn order_preserved_for_config_list() {
        let cli = Cli::parse_from([
            "timezone-cli",
            "now",
            "--query",
            "",
            "--config-zones",
            "Asia/Taipei\nAmerica/New_York,Europe/London",
        ]);

        let output = run_with(cli, fixed_now, || fixed_local("UTC")).expect("run should pass");
        let json: Value = serde_json::from_str(&output).expect("json output");

        assert_eq!(
            item_uids(&json),
            vec!["Asia/Taipei", "America/New_York", "Europe/London"]
        );
    }

    #[test]
    fn query_overrides_config_list() {
        let cli = Cli::parse_from([
            "timezone-cli",
            "now",
            "--query",
            "Europe/London,Asia/Tokyo",
            "--config-zones",
            "Asia/Taipei,America/New_York",
        ]);

        let output = run_with(cli, fixed_now, || fixed_local("UTC")).expect("run should pass");
        let json: Value = serde_json::from_str(&output).expect("json output");

        assert_eq!(item_uids(&json), vec!["Europe/London", "Asia/Tokyo"]);
    }

    #[test]
    fn empty_query_and_config_uses_detected_local_timezone() {
        let cli = Cli::parse_from(["timezone-cli", "now", "--query", "", "--config-zones", ""]);

        let output = run_with(cli, fixed_now, || fixed_local("Asia/Taipei"))
            .expect("local fallback should pass");
        let json: Value = serde_json::from_str(&output).expect("json output");

        assert_eq!(item_uids(&json), vec!["Asia/Taipei"]);
    }

    #[test]
    fn invalid_timezone_returns_user_error() {
        let cli = Cli::parse_from([
            "timezone-cli",
            "now",
            "--query",
            "Mars/Olympus",
            "--config-zones",
            "",
        ]);

        let error = run_with(cli, fixed_now, || fixed_local("UTC")).expect_err("invalid input");

        assert_eq!(error.kind, ErrorKind::User);
        assert_eq!(error.exit_code(), 2);
        assert!(error.message.contains("invalid timezone"));
    }

    #[test]
    fn help_flag_is_supported() {
        let help = Cli::try_parse_from(["timezone-cli", "--help"])
            .expect_err("help should be surfaced by clap");

        assert_eq!(help.kind(), clap::error::ErrorKind::DisplayHelp);
    }
}
