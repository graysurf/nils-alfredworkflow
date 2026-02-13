use std::path::Path;

use alfred_core::{Feedback, Item, ItemIcon, ItemModifier};

use crate::config::RuntimeConfig;
use crate::discovery::{discover_projects, filter_projects};
use crate::git::last_commit_summary;
use crate::usage_log::{UsageLog, parse_usage_timestamp};

const NO_PROJECTS_TITLE: &str = "No Git projects found";
const NO_PROJECTS_SUBTITLE: &str = "No matching or initialized Git repos found";
const NO_COMMIT_TEXT: &str = "No recent commits";
const NO_USAGE_TEXT: &str = "N/A";
const SHIFT_SUBTITLE: &str = "Open Project on GitHub";
const SHIFT_ICON_PATH: &str = "assets/icon-github.png";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScriptFilterMode {
    Open,
    Github,
}

pub fn build_script_filter_feedback(query: &str, config: &RuntimeConfig) -> Feedback {
    build_script_filter_feedback_with_mode(query, config, ScriptFilterMode::Open)
}

pub fn build_script_filter_feedback_with_mode(
    query: &str,
    config: &RuntimeConfig,
    mode: ScriptFilterMode,
) -> Feedback {
    let trimmed_query = query.trim();
    let discovered = discover_projects(&config.project_roots);
    let filtered = filter_projects(&discovered, trimmed_query);

    if filtered.is_empty() {
        return no_projects_feedback();
    }

    let usage_log = UsageLog::load(&config.usage_file);

    let mut ranked_items = filtered
        .into_iter()
        .map(|project| {
            let commit = last_commit_summary(&project.path);
            let last_used = usage_log.timestamp_for(&project.path, &project.name);
            let subtitle = subtitle_format(commit.as_deref(), last_used);
            let sort_key = parse_usage_timestamp(last_used);
            let path = project.path.to_string_lossy().to_string();

            let mut item = Item::new(&project.name)
                .with_arg(path.clone())
                .with_autocomplete(project.name.clone())
                .with_subtitle(subtitle)
                .with_mod(
                    "shift",
                    ItemModifier::new()
                        .with_arg(path.clone())
                        .with_valid(true)
                        .with_icon(ItemIcon::new(SHIFT_ICON_PATH))
                        .with_subtitle(SHIFT_SUBTITLE),
                )
                .with_variable("project_path", path);

            if mode == ScriptFilterMode::Github {
                item = item.with_icon(ItemIcon::new(SHIFT_ICON_PATH));
            }

            (sort_key, project.name, item)
        })
        .collect::<Vec<_>>();

    ranked_items.sort_by(|(left_sort, left_name, _), (right_sort, right_name, _)| {
        right_sort
            .cmp(left_sort)
            .then_with(|| left_name.cmp(right_name))
    });

    let max_items = if trimmed_query.is_empty() {
        config.max_results
    } else {
        usize::MAX
    };

    let items = ranked_items
        .into_iter()
        .take(max_items)
        .map(|(_, _, item)| item)
        .collect();

    Feedback::new(items)
}

pub fn subtitle_format(commit_summary: Option<&str>, usage_timestamp: Option<&str>) -> String {
    let commit_text = commit_summary
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(NO_COMMIT_TEXT);

    let usage_text = usage_timestamp
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(NO_USAGE_TEXT);

    format!("{commit_text} • {usage_text}")
}

pub fn no_projects_feedback() -> Feedback {
    Feedback::new(vec![
        Item::new(NO_PROJECTS_TITLE)
            .with_subtitle(NO_PROJECTS_SUBTITLE)
            .with_valid(false),
    ])
}

pub fn is_no_projects_feedback(payload: &Feedback) -> bool {
    payload
        .items
        .first()
        .map(|item| item.title == NO_PROJECTS_TITLE)
        .unwrap_or(false)
}

pub fn project_arg(item: &Item) -> Option<&Path> {
    item.arg.as_deref().map(Path::new)
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::PathBuf;
    use std::process::Command;

    use tempfile::tempdir;

    use crate::config::RuntimeConfig;

    use super::*;

    #[test]
    fn subtitle_format_uses_commit_and_usage_fallbacks() {
        let full = subtitle_format(
            Some("feat: add quick open (by dev, 2025-01-01)"),
            Some("2025-01-02 03:04:05"),
        );
        assert_eq!(
            full,
            "feat: add quick open (by dev, 2025-01-01) • 2025-01-02 03:04:05"
        );

        let fallback = subtitle_format(None, None);
        assert_eq!(fallback, "No recent commits • N/A");
    }

    #[test]
    fn sort_order_prioritizes_recent_usage_timestamp() {
        let temp = tempdir().expect("create temp dir");
        let roots = temp.path().join("roots");
        let alpha = roots.join("alpha");
        let beta = roots.join("beta");

        init_repo(&alpha);
        init_repo(&beta);

        let usage_file = temp.path().join("usage.log");
        fs::write(
            &usage_file,
            format!(
                "{} | 2024-01-01 00:00:00\n{} | 2025-02-01 00:00:00\n",
                alpha.to_string_lossy(),
                beta.to_string_lossy()
            ),
        )
        .expect("write usage file");

        let config = RuntimeConfig {
            project_roots: vec![roots],
            usage_file,
            vscode_path: "code".to_string(),
            max_results: 10,
        };

        let feedback = build_script_filter_feedback("", &config);
        let titles: Vec<&str> = feedback
            .items
            .iter()
            .map(|item| item.title.as_str())
            .collect();

        assert_eq!(
            titles.first(),
            Some(&"beta"),
            "more recent usage should be first"
        );
        assert_eq!(titles.get(1), Some(&"alpha"), "older usage should be later");
    }

    #[test]
    fn no_projects_feedback_is_invalid_item() {
        let config = RuntimeConfig {
            project_roots: vec![PathBuf::from("/path/that/does/not/exist")],
            usage_file: PathBuf::from("/tmp/non-existent-usage.log"),
            vscode_path: "code".to_string(),
            max_results: 10,
        };

        let feedback = build_script_filter_feedback("", &config);
        assert_eq!(
            feedback.items.len(),
            1,
            "fallback should include exactly one item"
        );
        assert_eq!(feedback.items[0].title, NO_PROJECTS_TITLE);
        assert_eq!(
            feedback.items[0].valid,
            Some(false),
            "fallback item should be marked invalid"
        );
    }

    #[test]
    fn empty_query_respects_max_results_limit() {
        let temp = tempdir().expect("create temp dir");
        let roots = temp.path().join("roots");
        init_repo(&roots.join("alpha"));
        init_repo(&roots.join("beta"));
        init_repo(&roots.join("gamma"));

        let config = RuntimeConfig {
            project_roots: vec![roots],
            usage_file: temp.path().join("usage.log"),
            vscode_path: "code".to_string(),
            max_results: 2,
        };

        let feedback = build_script_filter_feedback("", &config);
        assert_eq!(
            feedback.items.len(),
            2,
            "empty query should be limited by max_results"
        );
    }

    #[test]
    fn non_empty_query_is_not_limited_by_max_results() {
        let temp = tempdir().expect("create temp dir");
        let roots = temp.path().join("roots");
        init_repo(&roots.join("alpha"));
        init_repo(&roots.join("beta"));
        init_repo(&roots.join("gamma"));

        let config = RuntimeConfig {
            project_roots: vec![roots],
            usage_file: temp.path().join("usage.log"),
            vscode_path: "code".to_string(),
            max_results: 1,
        };

        let feedback = build_script_filter_feedback("a", &config);
        assert_eq!(
            feedback.items.len(),
            3,
            "non-empty query should return all matched projects"
        );
    }

    #[test]
    fn shift_modifier_uses_github_icon() {
        let temp = tempdir().expect("create temp dir");
        let roots = temp.path().join("roots");
        let repo = roots.join("alpha");
        init_repo(&repo);

        let config = RuntimeConfig {
            project_roots: vec![roots],
            usage_file: temp.path().join("usage.log"),
            vscode_path: "code".to_string(),
            max_results: 10,
        };

        let feedback = build_script_filter_feedback("", &config);
        let first = feedback.items.first().expect("at least one project item");
        let shift = first
            .mods
            .as_ref()
            .and_then(|mods| mods.get("shift"))
            .expect("shift modifier should exist");
        let icon = shift
            .icon
            .as_ref()
            .expect("shift modifier icon should exist");

        assert_eq!(
            icon.path, SHIFT_ICON_PATH,
            "shift modifier should point to GitHub icon asset"
        );
    }

    #[test]
    fn github_mode_sets_primary_item_icon() {
        let temp = tempdir().expect("create temp dir");
        let roots = temp.path().join("roots");
        let repo = roots.join("alpha");
        init_repo(&repo);

        let config = RuntimeConfig {
            project_roots: vec![roots],
            usage_file: temp.path().join("usage.log"),
            vscode_path: "code".to_string(),
            max_results: 10,
        };

        let feedback =
            build_script_filter_feedback_with_mode("", &config, ScriptFilterMode::Github);
        let first = feedback.items.first().expect("at least one project item");
        let icon = first.icon.as_ref().expect("primary item icon should exist");

        assert_eq!(
            icon.path, SHIFT_ICON_PATH,
            "github mode should display GitHub icon on primary item"
        );
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

    #[test]
    fn max_results_limits_number_of_feedback_items() {
        let temp = tempdir().expect("create temp dir");
        let roots = temp.path().join("roots");
        let alpha = roots.join("alpha");
        let beta = roots.join("beta");
        let gamma = roots.join("gamma");

        init_repo(&alpha);
        init_repo(&beta);
        init_repo(&gamma);

        let config = RuntimeConfig {
            project_roots: vec![roots],
            usage_file: temp.path().join("usage.log"),
            vscode_path: "code".to_string(),
            max_results: 2,
        };

        let feedback = build_script_filter_feedback("", &config);
        assert_eq!(
            feedback.items.len(),
            2,
            "feedback should be capped by max_results"
        );
    }
}
