use clap::{Parser, Subcommand};
use randomer_cli::{RandomerError, generate_feedback, list_formats_feedback, list_types_feedback};

#[derive(Debug, Parser)]
#[command(author, version, about = "Randomer workflow CLI")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// List supported formats as Alfred menu items.
    ListFormats {
        /// Optional case-insensitive filter against format keys.
        #[arg(long)]
        query: Option<String>,
    },
    /// List type keys for selector flow in rrv mode.
    ListTypes {
        /// Optional case-insensitive filter against format keys.
        #[arg(long)]
        query: Option<String>,
    },
    /// Generate values for a specific format.
    Generate {
        /// Target format key (case-insensitive).
        #[arg(long)]
        format: String,
        /// Number of values to generate.
        #[arg(long, default_value_t = 1)]
        count: usize,
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

    fn from_randomer(error: RandomerError) -> Self {
        match error {
            RandomerError::UnknownFormat(_) | RandomerError::InvalidCount(_) => {
                Self::user(error.to_string())
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
    let feedback = match cli.command {
        Commands::ListFormats { query } => list_formats_feedback(query.as_deref()),
        Commands::ListTypes { query } => list_types_feedback(query.as_deref()),
        Commands::Generate { format, count } => {
            generate_feedback(format.as_str(), count).map_err(AppError::from_randomer)?
        }
    };

    feedback
        .to_json()
        .map_err(|error| AppError::runtime(format!("failed to serialize Alfred feedback: {error}")))
}

#[cfg(test)]
mod tests {
    use serde_json::Value;

    use super::*;

    #[test]
    fn list_formats_outputs_alfred_json_items() {
        let cli = Cli::parse_from(["randomer-cli", "list-formats"]);
        let output = run(cli).expect("list-formats should succeed");
        let json: Value = serde_json::from_str(&output).expect("output should be JSON");
        let items = json
            .get("items")
            .and_then(Value::as_array)
            .expect("items should be present");

        assert_eq!(items.len(), 10);
        assert!(
            items
                .first()
                .and_then(|item| item.get("mods"))
                .and_then(|mods| mods.get("cmd"))
                .is_some()
        );
    }

    #[test]
    fn list_formats_applies_case_insensitive_contains_filter() {
        let cli = Cli::parse_from(["randomer-cli", "list-formats", "--query", "HE"]);
        let output = run(cli).expect("list-formats should succeed");
        let json: Value = serde_json::from_str(&output).expect("output should be JSON");
        let items = json
            .get("items")
            .and_then(Value::as_array)
            .expect("items should be present");

        assert_eq!(items.len(), 1);
        let subtitle = items[0]
            .get("subtitle")
            .and_then(Value::as_str)
            .expect("subtitle should exist");
        assert!(subtitle.contains("hex"));
    }

    #[test]
    fn generate_outputs_requested_count_for_known_format() {
        let cli = Cli::parse_from([
            "randomer-cli",
            "generate",
            "--format",
            "OtP",
            "--count",
            "4",
        ]);

        let output = run(cli).expect("generate should succeed");
        let json: Value = serde_json::from_str(&output).expect("output should be JSON");
        let items = json
            .get("items")
            .and_then(Value::as_array)
            .expect("items should be present");

        assert_eq!(items.len(), 4);
        assert!(items.iter().all(|item| {
            item.get("subtitle").and_then(Value::as_str) == Some("otp")
                && item.get("arg").and_then(Value::as_str)
                    == item.get("title").and_then(Value::as_str)
        }));
    }

    #[test]
    fn list_types_outputs_selector_items_with_format_args() {
        let cli = Cli::parse_from(["randomer-cli", "list-types", "--query", "in"]);
        let output = run(cli).expect("list-types should succeed");
        let json: Value = serde_json::from_str(&output).expect("output should be JSON");
        let items = json
            .get("items")
            .and_then(Value::as_array)
            .expect("items should be present");

        assert_eq!(items.len(), 1);
        assert_eq!(items[0].get("title").and_then(Value::as_str), Some("int"));
        assert_eq!(items[0].get("arg").and_then(Value::as_str), Some("int"));
        assert!(
            items[0]
                .get("subtitle")
                .and_then(Value::as_str)
                .is_some_and(|subtitle| subtitle.contains("show 10 values"))
        );
    }

    #[test]
    fn invalid_format_returns_user_error_kind_and_exit_code_2() {
        let cli = Cli::parse_from(["randomer-cli", "generate", "--format", "not-a-format"]);
        let error = run(cli).expect_err("unknown format should fail");

        assert_eq!(error.kind, ErrorKind::User);
        assert_eq!(error.exit_code(), 2);
        assert_eq!(error.message, "unknown format: not-a-format");
    }

    #[test]
    fn help_flag_is_supported() {
        let help = Cli::try_parse_from(["randomer-cli", "--help"])
            .expect_err("help should exit through clap");
        assert_eq!(help.kind(), clap::error::ErrorKind::DisplayHelp);
    }
}
