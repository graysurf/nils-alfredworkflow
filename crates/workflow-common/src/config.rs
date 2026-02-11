use std::env;
use std::path::PathBuf;

use crate::output_contract::OutputMode;

pub const DEFAULT_PROJECT_DIRS: &str = "$HOME/Project,$HOME/.config";
pub const DEFAULT_USAGE_FILE: &str = "$HOME/.config/zsh/cache/.alfred_project_usage.log";
pub const DEFAULT_VSCODE_PATH: &str =
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code";
pub const DEFAULT_OPEN_PROJECT_MAX_RESULTS: usize = 30;
pub const DEFAULT_OUTPUT_MODE: OutputMode = OutputMode::AlfredJson;
pub const OUTPUT_MODE_ENV: &str = "WORKFLOW_OUTPUT_MODE";

const PROJECT_DIRS_ENV: &str = "PROJECT_DIRS";
const USAGE_FILE_ENV: &str = "USAGE_FILE";
const VSCODE_PATH_ENV: &str = "VSCODE_PATH";
const OPEN_PROJECT_MAX_RESULTS_ENV: &str = "OPEN_PROJECT_MAX_RESULTS";
const OPEN_PROJECT_MAX_RESULTS_MIN: usize = 1;
const OPEN_PROJECT_MAX_RESULTS_MAX: usize = 200;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeConfig {
    pub project_roots: Vec<PathBuf>,
    pub usage_file: PathBuf,
    pub vscode_path: String,
    pub max_results: usize,
}

impl RuntimeConfig {
    pub fn from_env() -> Self {
        let home = env::var("HOME").unwrap_or_default();
        let project_dirs =
            env::var(PROJECT_DIRS_ENV).unwrap_or_else(|_| DEFAULT_PROJECT_DIRS.to_string());
        let usage_file =
            env::var(USAGE_FILE_ENV).unwrap_or_else(|_| DEFAULT_USAGE_FILE.to_string());
        let vscode_path =
            env::var(VSCODE_PATH_ENV).unwrap_or_else(|_| DEFAULT_VSCODE_PATH.to_string());
        let max_results = env::var(OPEN_PROJECT_MAX_RESULTS_ENV)
            .unwrap_or_else(|_| DEFAULT_OPEN_PROJECT_MAX_RESULTS.to_string());

        Self::from_values(
            &home,
            &project_dirs,
            &usage_file,
            &vscode_path,
            &max_results,
        )
    }

    pub fn from_values(
        home: &str,
        project_dirs: &str,
        usage_file: &str,
        vscode_path: &str,
        max_results: &str,
    ) -> Self {
        let project_roots = parse_project_dirs(project_dirs, home);
        let usage_file = PathBuf::from(expand_home_tokens(usage_file, home));
        let max_results = parse_max_results(max_results);

        Self {
            project_roots,
            usage_file,
            vscode_path: vscode_path.to_string(),
            max_results,
        }
    }
}

fn parse_max_results(raw: &str) -> usize {
    raw.trim()
        .parse::<usize>()
        .ok()
        .map(|value| value.clamp(OPEN_PROJECT_MAX_RESULTS_MIN, OPEN_PROJECT_MAX_RESULTS_MAX))
        .unwrap_or(DEFAULT_OPEN_PROJECT_MAX_RESULTS)
}

pub fn parse_project_dirs(raw: &str, home: &str) -> Vec<PathBuf> {
    raw.split(',')
        .map(str::trim)
        .filter(|entry| !entry.is_empty())
        .map(|entry| PathBuf::from(expand_home_tokens(entry, home)))
        .collect()
}

pub fn expand_home_tokens(raw: &str, home: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return String::new();
    }

    let mut expanded = trimmed.replace("$HOME", home);

    if expanded == "~" {
        expanded = home.to_string();
    } else if let Some(rest) = expanded.strip_prefix("~/") {
        expanded = format!("{home}/{rest}");
    }

    expanded
}

pub fn parse_output_mode_env(raw: Option<&str>) -> OutputMode {
    raw.and_then(OutputMode::parse)
        .unwrap_or(DEFAULT_OUTPUT_MODE)
}

pub fn output_mode_from_env() -> OutputMode {
    parse_output_mode_env(env::var(OUTPUT_MODE_ENV).ok().as_deref())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn expands_home_tokens_for_usage_file() {
        let path = expand_home_tokens("$HOME/.usage.log", "/Users/tester");
        assert_eq!(path, "/Users/tester/.usage.log");

        let path = expand_home_tokens("~/projects", "/Users/tester");
        assert_eq!(path, "/Users/tester/projects");
    }

    #[test]
    fn parses_multiple_project_dirs() {
        let dirs = parse_project_dirs("$HOME/One, ~/Two ,/tmp/Three", "/Users/tester");
        assert_eq!(dirs.len(), 3);
        assert_eq!(dirs[0], PathBuf::from("/Users/tester/One"));
        assert_eq!(dirs[1], PathBuf::from("/Users/tester/Two"));
        assert_eq!(dirs[2], PathBuf::from("/tmp/Three"));
    }

    #[test]
    fn open_project_max_results_uses_default_and_clamps() {
        let default_config = RuntimeConfig::from_values(
            "/Users/tester",
            "$HOME/One",
            "$HOME/.usage.log",
            "code",
            "",
        );
        assert_eq!(default_config.max_results, DEFAULT_OPEN_PROJECT_MAX_RESULTS);

        let clamped_low = RuntimeConfig::from_values(
            "/Users/tester",
            "$HOME/One",
            "$HOME/.usage.log",
            "code",
            "0",
        );
        assert_eq!(clamped_low.max_results, OPEN_PROJECT_MAX_RESULTS_MIN);

        let clamped_high = RuntimeConfig::from_values(
            "/Users/tester",
            "$HOME/One",
            "$HOME/.usage.log",
            "code",
            "9999",
        );
        assert_eq!(clamped_high.max_results, OPEN_PROJECT_MAX_RESULTS_MAX);
    }

    #[test]
    fn output_mode_defaults_to_alfred_json() {
        assert_eq!(parse_output_mode_env(None), OutputMode::AlfredJson);
        assert_eq!(
            parse_output_mode_env(Some("invalid")),
            OutputMode::AlfredJson
        );
    }

    #[test]
    fn output_mode_env_parser_accepts_known_values() {
        assert_eq!(parse_output_mode_env(Some("human")), OutputMode::Human);
        assert_eq!(parse_output_mode_env(Some("json")), OutputMode::Json);
        assert_eq!(
            parse_output_mode_env(Some("alfred-json")),
            OutputMode::AlfredJson
        );
    }
}
