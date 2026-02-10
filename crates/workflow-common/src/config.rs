use std::env;
use std::path::PathBuf;

pub const DEFAULT_PROJECT_DIRS: &str = "$HOME/Project,$HOME/.config";
pub const DEFAULT_USAGE_FILE: &str = "$HOME/.config/zsh/cache/.alfred_project_usage.log";
pub const DEFAULT_VSCODE_PATH: &str =
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code";

const PROJECT_DIRS_ENV: &str = "PROJECT_DIRS";
const USAGE_FILE_ENV: &str = "USAGE_FILE";
const VSCODE_PATH_ENV: &str = "VSCODE_PATH";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeConfig {
    pub project_roots: Vec<PathBuf>,
    pub usage_file: PathBuf,
    pub vscode_path: String,
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

        Self::from_values(&home, &project_dirs, &usage_file, &vscode_path)
    }

    pub fn from_values(
        home: &str,
        project_dirs: &str,
        usage_file: &str,
        vscode_path: &str,
    ) -> Self {
        let project_roots = parse_project_dirs(project_dirs, home);
        let usage_file = PathBuf::from(expand_home_tokens(usage_file, home));

        Self {
            project_roots,
            usage_file,
            vscode_path: vscode_path.to_string(),
        }
    }
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
}
