use std::path::PathBuf;

use clap::{Parser, Subcommand, ValueEnum};
use serde_json::json;
use workflow_readme_cli::{AppError, ConvertRequest, convert};

#[derive(Debug, Parser)]
#[command(
    author,
    version,
    about = "Workflow README converter for Alfred plist readme"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Convert README markdown and inject readme content into plist.
    Convert {
        /// Workflow root directory that contains README and local image assets.
        #[arg(long)]
        workflow_root: PathBuf,
        /// Relative path to README from workflow root.
        #[arg(long)]
        readme_source: PathBuf,
        /// Stage directory where local image assets should be copied.
        #[arg(long)]
        stage_dir: PathBuf,
        /// Target plist file that will receive converted readme content.
        #[arg(long)]
        plist: PathBuf,
        /// Validate and render without writing files.
        #[arg(long, default_value_t = false)]
        dry_run: bool,
        /// Explicit output mode (`human`, `json`).
        #[arg(long, value_enum)]
        output: Option<OutputModeArg>,
        /// Legacy compatibility flag for JSON output mode.
        #[arg(long)]
        json: bool,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum OutputModeArg {
    Human,
    Json,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ConvertSummary {
    converted_readme_length: usize,
    copied_assets: Vec<String>,
    dry_run: bool,
}

const COMMAND_CONVERT: &str = "workflow-readme.convert";
const SCHEMA_VERSION_V1: &str = "v1";
const ERROR_CODE_USER_OUTPUT_MODE_CONFLICT: &str = "user.output_mode_conflict";

impl Cli {
    fn command_name(&self) -> &'static str {
        match self.command {
            Commands::Convert { .. } => COMMAND_CONVERT,
        }
    }

    fn output_mode_hint(&self) -> OutputModeArg {
        match &self.command {
            Commands::Convert { output, json, .. } => {
                if *json || output == &Some(OutputModeArg::Json) {
                    OutputModeArg::Json
                } else {
                    OutputModeArg::Human
                }
            }
        }
    }

    fn output_mode(&self) -> Result<OutputModeArg, AppError> {
        match &self.command {
            Commands::Convert { output, json, .. } => {
                if *json && output == &Some(OutputModeArg::Human) {
                    return Err(AppError::user(
                        ERROR_CODE_USER_OUTPUT_MODE_CONFLICT,
                        "conflicting output modes: --json cannot be combined with --output human",
                    ));
                }

                if *json {
                    Ok(OutputModeArg::Json)
                } else if let Some(mode) = output {
                    Ok(*mode)
                } else {
                    Ok(OutputModeArg::Human)
                }
            }
        }
    }
}

fn main() {
    let cli = Cli::parse();
    let command = cli.command_name();
    let output_mode_hint = cli.output_mode_hint();
    let output_mode = match cli.output_mode() {
        Ok(mode) => mode,
        Err(error) => {
            emit_error(command, output_mode_hint, &error);
            std::process::exit(error.exit_code());
        }
    };

    match run(cli) {
        Ok(summary) => emit_success(command, output_mode, &summary),
        Err(error) => {
            emit_error(command, output_mode, &error);
            std::process::exit(error.exit_code());
        }
    }
}

fn run(cli: Cli) -> Result<ConvertSummary, AppError> {
    match cli.command {
        Commands::Convert {
            workflow_root,
            readme_source,
            stage_dir,
            plist,
            dry_run,
            ..
        } => {
            let result = convert(&ConvertRequest {
                workflow_root,
                readme_source,
                stage_dir,
                plist,
                dry_run,
            })?;

            Ok(ConvertSummary {
                converted_readme_length: result.converted_readme.len(),
                copied_assets: result
                    .copied_assets
                    .iter()
                    .map(|path| path.to_string_lossy().to_string())
                    .collect(),
                dry_run,
            })
        }
    }
}

fn emit_success(command: &str, output_mode: OutputModeArg, summary: &ConvertSummary) {
    match output_mode {
        OutputModeArg::Human => {
            if summary.dry_run {
                println!(
                    "dry-run: converted {} bytes, detected {} local image asset(s)",
                    summary.converted_readme_length,
                    summary.copied_assets.len()
                );
            } else {
                println!(
                    "converted {} bytes, copied {} local image asset(s)",
                    summary.converted_readme_length,
                    summary.copied_assets.len()
                );
            }
        }
        OutputModeArg::Json => {
            let envelope = json!({
                "schema_version": SCHEMA_VERSION_V1,
                "command": command,
                "ok": true,
                "result": {
                    "converted_readme_length": summary.converted_readme_length,
                    "copied_assets": summary.copied_assets,
                    "dry_run": summary.dry_run,
                }
            });
            println!(
                "{}",
                serde_json::to_string(&envelope).expect("serialize success envelope")
            );
        }
    }
}

fn emit_error(command: &str, output_mode: OutputModeArg, error: &AppError) {
    match output_mode {
        OutputModeArg::Json => {
            let envelope = json!({
                "schema_version": SCHEMA_VERSION_V1,
                "command": command,
                "ok": false,
                "error": {
                    "code": error.code(),
                    "message": error.message(),
                    "details": {
                        "kind": error_kind_label(error),
                        "exit_code": error.exit_code(),
                    }
                }
            });
            println!(
                "{}",
                serde_json::to_string(&envelope).expect("serialize error envelope")
            );
        }
        OutputModeArg::Human => {
            eprintln!("error[{}]: {}", error.code(), error.message());
        }
    }
}

fn error_kind_label(error: &AppError) -> &'static str {
    match error.kind() {
        workflow_readme_cli::ErrorKind::User => "user",
        workflow_readme_cli::ErrorKind::Runtime => "runtime",
    }
}
