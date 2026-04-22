use std::path::Path;
use std::process::Command;

use crate::error::WorkflowError;

pub fn last_commit_summary(project_path: &Path) -> Option<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(project_path)
        .arg("log")
        .arg("-1")
        .arg("--pretty=format:%s (by %an, %ad)")
        .arg("--date=short")
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if stdout.is_empty() {
        None
    } else {
        Some(stdout)
    }
}

pub fn web_url_for_project(project_path: &Path) -> Result<String, WorkflowError> {
    if !project_path.exists() {
        return Err(WorkflowError::MissingPath(project_path.to_path_buf()));
    }
    if !project_path.is_dir() {
        return Err(WorkflowError::NotDirectory(project_path.to_path_buf()));
    }

    let output = Command::new("git")
        .arg("-C")
        .arg(project_path)
        .arg("remote")
        .arg("get-url")
        .arg("origin")
        .output()
        .map_err(|error| WorkflowError::GitCommand {
            path: project_path.to_path_buf(),
            message: error.to_string(),
        })?;

    if !output.status.success() {
        return Err(WorkflowError::MissingOrigin(project_path.to_path_buf()));
    }

    let remote_url = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if remote_url.is_empty() {
        return Err(WorkflowError::MissingOrigin(project_path.to_path_buf()));
    }

    normalize_remote(&remote_url)
}

/// Normalize a git remote URL to its canonical web URL.
///
/// Assumes `https://<host>/<path>` mirrors the clone URL — the standard layout for
/// GitHub, GitLab (including subgroups), Gitea, Bitbucket, Codeberg, and Gogs.
/// `github.com` is the single strict case (path must be exactly `owner/repo`);
/// every other host accepts two or more path segments to allow GitLab-style subgroups.
pub fn normalize_remote(remote_url: &str) -> Result<String, WorkflowError> {
    let parsed = parse_remote_url(remote_url)
        .ok_or_else(|| WorkflowError::UnsupportedRemote(remote_url.to_string()))?;
    build_web_url(&parsed, remote_url)
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ParsedRemote {
    host: String,
    path: String,
}

fn parse_remote_url(remote_url: &str) -> Option<ParsedRemote> {
    let trimmed = remote_url.trim();
    if trimmed.is_empty() {
        return None;
    }

    if let Some(rest) = trimmed.strip_prefix("git@") {
        let (host, path) = rest.split_once(':')?;
        return build_parsed(host, path);
    }

    if let Some(rest) = trimmed.strip_prefix("ssh://git@") {
        let (host_part, path) = rest.split_once('/')?;
        let host = host_part.split(':').next().unwrap_or(host_part);
        return build_parsed(host, path);
    }

    if let Some(rest) = trimmed.strip_prefix("https://") {
        let (host, path) = rest.split_once('/')?;
        return build_parsed(host, path);
    }

    None
}

fn build_parsed(host: &str, path: &str) -> Option<ParsedRemote> {
    let host = host.trim();
    let path = trim_repo_suffix(path);
    if host.is_empty() || path.is_empty() {
        return None;
    }
    Some(ParsedRemote {
        host: host.to_ascii_lowercase(),
        path,
    })
}

fn trim_repo_suffix(raw: &str) -> String {
    raw.trim()
        .trim_end_matches('/')
        .trim_end_matches(".git")
        .trim_end_matches('/')
        .to_string()
}

fn build_web_url(parsed: &ParsedRemote, raw_url: &str) -> Result<String, WorkflowError> {
    let segment_count = parsed
        .path
        .split('/')
        .filter(|segment| !segment.is_empty())
        .count();

    if segment_count < 2 {
        return Err(WorkflowError::UnsupportedRemote(raw_url.to_string()));
    }
    if parsed.host == "github.com" && segment_count != 2 {
        return Err(WorkflowError::UnsupportedRemote(raw_url.to_string()));
    }

    Ok(format!("https://{}/{}", parsed.host, parsed.path))
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::process::Command;

    use tempfile::tempdir;

    use super::*;

    #[test]
    fn github_remote_normalizes_ssh_and_https_formats() {
        let ssh =
            normalize_remote("git@github.com:owner/repo.git").expect("ssh remote should normalize");
        assert_eq!(ssh, "https://github.com/owner/repo");

        let ssh_url = normalize_remote("ssh://git@github.com/owner/repo.git")
            .expect("ssh url remote should normalize");
        assert_eq!(ssh_url, "https://github.com/owner/repo");

        let https = normalize_remote("https://github.com/owner/repo.git")
            .expect("https remote should normalize");
        assert_eq!(https, "https://github.com/owner/repo");

        let https_no_suffix =
            normalize_remote("https://github.com/owner/repo").expect("suffix-less remote");
        assert_eq!(https_no_suffix, "https://github.com/owner/repo");
    }

    #[test]
    fn github_remote_rejects_subgroup_path() {
        let err = normalize_remote("git@github.com:owner/group/repo.git")
            .expect_err("github paths must be exactly 2 segments");
        assert!(matches!(err, WorkflowError::UnsupportedRemote(_)));
    }

    #[test]
    fn gitlab_ssh_with_subgroup_resolves() {
        let url = normalize_remote("git@gitlab.com:gitlab-org/gitlab-foss/scripts.git")
            .expect("gitlab subgroup should resolve");
        assert_eq!(url, "https://gitlab.com/gitlab-org/gitlab-foss/scripts");
    }

    #[test]
    fn gitlab_ssh_two_segment_path_resolves() {
        let url = normalize_remote("git@gitlab.com:gitlab-org/gitlab.git")
            .expect("two-segment gitlab path should resolve");
        assert_eq!(url, "https://gitlab.com/gitlab-org/gitlab");
    }

    #[test]
    fn gitlab_https_with_subgroup_resolves() {
        let url = normalize_remote("https://gitlab.com/gitlab-org/gitlab-foss/scripts.git")
            .expect("https gitlab subgroup should resolve");
        assert_eq!(url, "https://gitlab.com/gitlab-org/gitlab-foss/scripts");
    }

    #[test]
    fn gitlab_ssh_url_with_port_resolves() {
        let url = normalize_remote("ssh://git@gitlab.com:2222/gitlab-org/gitlab.git")
            .expect("ssh url with port should resolve");
        assert_eq!(url, "https://gitlab.com/gitlab-org/gitlab");
    }

    #[test]
    fn self_hosted_host_resolves_without_configuration() {
        let url = normalize_remote("git@git.example.com:team/platform/service.git")
            .expect("self-hosted host should resolve without any whitelist");
        assert_eq!(url, "https://git.example.com/team/platform/service");
    }

    #[test]
    fn host_match_is_case_insensitive() {
        let url = normalize_remote("git@GitLab.COM:gitlab-org/gitlab.git")
            .expect("host comparison should ignore case");
        assert_eq!(url, "https://gitlab.com/gitlab-org/gitlab");
    }

    #[test]
    fn single_segment_path_returns_unsupported_remote() {
        let err = normalize_remote("git@gitlab.com:solo.git")
            .expect_err("one-segment path is not a repo");
        assert!(matches!(err, WorkflowError::UnsupportedRemote(_)));
    }

    #[test]
    fn malformed_remote_returns_unsupported_remote() {
        let err = normalize_remote("not a remote").expect_err("garbage input should fail");
        assert!(matches!(err, WorkflowError::UnsupportedRemote(_)));
    }

    #[test]
    fn web_url_reports_missing_origin_when_no_remote() {
        let temp = tempdir().expect("create temp dir");
        let repo = temp.path().join("repo");
        fs::create_dir_all(&repo).expect("create repo dir");

        let status = Command::new("git")
            .arg("init")
            .arg("-q")
            .arg(&repo)
            .status()
            .expect("run git init");
        assert!(status.success(), "git init should succeed");

        let err = web_url_for_project(&repo).expect_err("missing origin should fail");
        assert!(
            matches!(err, WorkflowError::MissingOrigin(_)),
            "expected missing origin error"
        );
    }
}
