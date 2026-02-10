use std::path::{Path, PathBuf};

use clap::{Parser, Subcommand, ValueEnum};
use workflow_common::{
    RuntimeConfig, ScriptFilterMode, WorkflowError, build_script_filter_feedback_with_mode,
    github_url_for_project, record_usage,
};

#[derive(Debug, Parser)]
#[command(author, version, about = "Shared Alfred workflow CLI")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Render Alfred script-filter JSON.
    ScriptFilter {
        /// Input query from Alfred.
        #[arg(long, short, default_value = "")]
        query: String,
        /// Display mode for icon treatment.
        #[arg(long, value_enum, default_value_t = ScriptFilterModeArg::Open)]
        mode: ScriptFilterModeArg,
    },
    /// Record usage timestamp for a selected project path.
    RecordUsage {
        /// Selected project path.
        #[arg(long)]
        path: PathBuf,
    },
    /// Resolve project origin URL to a canonical GitHub URL.
    GithubUrl {
        /// Selected project path.
        #[arg(long)]
        path: PathBuf,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum ScriptFilterModeArg {
    Open,
    Github,
}

impl From<ScriptFilterModeArg> for ScriptFilterMode {
    fn from(value: ScriptFilterModeArg) -> Self {
        match value {
            ScriptFilterModeArg::Open => ScriptFilterMode::Open,
            ScriptFilterModeArg::Github => ScriptFilterMode::Github,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ErrorKind {
    User,
    Runtime,
}

#[derive(Debug)]
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
        Ok(stdout) => {
            println!("{stdout}");
        }
        Err(err) => {
            eprintln!("error: {}", err.message);
            std::process::exit(err.exit_code());
        }
    }
}

fn run(cli: Cli) -> Result<String, AppError> {
    let config = RuntimeConfig::from_env();
    run_with_config(cli, &config)
}

fn run_with_config(cli: Cli, config: &RuntimeConfig) -> Result<String, AppError> {
    match cli.command {
        Commands::ScriptFilter { query, mode } => {
            let feedback = build_script_filter_feedback_with_mode(&query, config, mode.into());
            feedback.to_json().map_err(|error| {
                AppError::runtime(format!("failed to serialize Alfred feedback: {error}"))
            })
        }
        Commands::RecordUsage { path } => {
            validate_project_path(&path)?;
            record_usage(&path, &config.usage_file).map_err(map_workflow_error)?;
            Ok(path.to_string_lossy().to_string())
        }
        Commands::GithubUrl { path } => {
            validate_project_path(&path)?;
            github_url_for_project(&path).map_err(map_workflow_error)
        }
    }
}

fn validate_project_path(path: &Path) -> Result<(), AppError> {
    if !path.exists() {
        return Err(AppError::user(format!(
            "path does not exist: {}",
            path.to_string_lossy()
        )));
    }

    if !path.is_dir() {
        return Err(AppError::user(format!(
            "path is not a directory: {}",
            path.to_string_lossy()
        )));
    }

    Ok(())
}

fn map_workflow_error(error: WorkflowError) -> AppError {
    match error {
        WorkflowError::MissingPath(path) => {
            AppError::user(format!("path does not exist: {}", path.to_string_lossy()))
        }
        WorkflowError::NotDirectory(path) => AppError::user(format!(
            "path is not a directory: {}",
            path.to_string_lossy()
        )),
        WorkflowError::MissingOrigin(path) => AppError::runtime(format!(
            "no remote 'origin' found in {}",
            path.to_string_lossy()
        )),
        WorkflowError::UnsupportedRemote(remote) => {
            AppError::runtime(format!("unsupported remote URL format: {remote}"))
        }
        WorkflowError::GitCommand { path, message } => AppError::runtime(format!(
            "failed to execute git in {}: {message}",
            path.to_string_lossy()
        )),
        WorkflowError::UsageWrite { path, source } => AppError::runtime(format!(
            "failed to persist usage log at {}: {source}",
            path.to_string_lossy()
        )),
    }
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::Path;
    use std::process::Command;

    use tempfile::tempdir;

    use super::*;

    #[test]
    fn script_filter_command_outputs_json_contract() {
        let temp = tempdir().expect("create temp dir");
        let root = temp.path().join("projects");
        let repo = root.join("alpha");
        init_repo(&repo);

        let config = RuntimeConfig {
            project_roots: vec![root],
            usage_file: temp.path().join("usage.log"),
            vscode_path: "code".to_string(),
        };

        let output = run_with_config(
            Cli {
                command: Commands::ScriptFilter {
                    query: String::new(),
                    mode: ScriptFilterModeArg::Open,
                },
            },
            &config,
        )
        .expect("script-filter should succeed");

        let json: serde_json::Value =
            serde_json::from_str(&output).expect("script-filter output should be valid JSON");
        assert!(
            json.get("items").is_some(),
            "JSON output should contain items field"
        );
    }

    #[test]
    fn action_commands_output_plain_values() {
        let temp = tempdir().expect("create temp dir");
        let root = temp.path().join("projects");
        let repo = root.join("alpha");
        init_repo(&repo);

        let status = Command::new("git")
            .arg("-C")
            .arg(&repo)
            .args(["remote", "add", "origin", "git@github.com:owner/repo.git"])
            .status()
            .expect("set git remote");
        assert!(status.success(), "git remote add should succeed");

        let config = RuntimeConfig {
            project_roots: vec![root],
            usage_file: temp.path().join("usage.log"),
            vscode_path: "code".to_string(),
        };

        let recorded = run_with_config(
            Cli {
                command: Commands::RecordUsage { path: repo.clone() },
            },
            &config,
        )
        .expect("record-usage should succeed");
        assert_eq!(
            recorded,
            repo.to_string_lossy(),
            "record-usage should output plain path"
        );

        let github_url = run_with_config(
            Cli {
                command: Commands::GithubUrl { path: repo.clone() },
            },
            &config,
        )
        .expect("github-url should succeed");
        assert_eq!(
            github_url, "https://github.com/owner/repo",
            "github-url should output canonical URL only"
        );
    }

    #[test]
    fn action_commands_report_user_error_for_invalid_path() {
        let temp = tempdir().expect("create temp dir");
        let config = RuntimeConfig {
            project_roots: vec![temp.path().join("projects")],
            usage_file: temp.path().join("usage.log"),
            vscode_path: "code".to_string(),
        };

        let missing = temp.path().join("missing-project");
        let err = run_with_config(
            Cli {
                command: Commands::RecordUsage {
                    path: missing.clone(),
                },
            },
            &config,
        )
        .expect_err("missing project should produce user error");

        assert_eq!(
            err.kind,
            ErrorKind::User,
            "missing path should be treated as user error"
        );
        assert!(
            err.message.contains(missing.to_string_lossy().as_ref()),
            "error message should include offending path"
        );
    }

    #[test]
    fn script_filter_github_mode_sets_primary_item_icon() {
        let temp = tempdir().expect("create temp dir");
        let root = temp.path().join("projects");
        let repo = root.join("alpha");
        init_repo(&repo);

        let config = RuntimeConfig {
            project_roots: vec![root],
            usage_file: temp.path().join("usage.log"),
            vscode_path: "code".to_string(),
        };

        let output = run_with_config(
            Cli {
                command: Commands::ScriptFilter {
                    query: String::new(),
                    mode: ScriptFilterModeArg::Github,
                },
            },
            &config,
        )
        .expect("script-filter should succeed");

        let json: serde_json::Value =
            serde_json::from_str(&output).expect("script-filter output should be valid JSON");
        let icon_path = json
            .get("items")
            .and_then(|items| items.get(0))
            .and_then(|item| item.get("icon"))
            .and_then(|icon| icon.get("path"))
            .and_then(|path| path.as_str())
            .expect("github mode should include primary icon path");

        assert_eq!(icon_path, "assets/icon-github.png");
    }

    fn init_repo(path: &Path) {
        fs::create_dir_all(path).expect("create repo dir");
        let status = Command::new("git")
            .arg("init")
            .arg("-q")
            .arg(path)
            .status()
            .expect("run git init");
        assert!(status.success(), "git init should succeed");
    }
}
