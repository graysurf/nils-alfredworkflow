use std::collections::BTreeMap;
use std::ffi::OsStr;
use std::path::{Path, PathBuf};

use walkdir::WalkDir;

pub const MAX_SCAN_DEPTH: usize = 3;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Project {
    pub name: String,
    pub path: PathBuf,
}

impl Project {
    pub fn new(path: PathBuf) -> Option<Self> {
        let name = path.file_name()?.to_string_lossy().trim().to_string();
        if name.is_empty() {
            return None;
        }

        Some(Self { name, path })
    }
}

pub fn discover_projects(roots: &[PathBuf]) -> Vec<Project> {
    let mut projects = BTreeMap::<String, Project>::new();

    for root in roots {
        if !root.is_dir() {
            continue;
        }

        // Git repo root depth = 3 means `.git` appears at depth 4 from base root.
        let walker = WalkDir::new(root)
            .follow_links(true)
            .max_depth(MAX_SCAN_DEPTH + 1)
            .into_iter();

        for entry in walker {
            let entry = match entry {
                Ok(entry) => entry,
                Err(_) => continue,
            };

            if !entry.file_type().is_dir() || entry.file_name() != OsStr::new(".git") {
                continue;
            }

            let Some(project_path) = entry.path().parent() else {
                continue;
            };

            if let Some(project) = Project::new(project_path.to_path_buf()) {
                let key = normalize_path_key(&project.path);
                projects.insert(key, project);
            }
        }
    }

    projects.into_values().collect()
}

pub fn filter_projects(projects: &[Project], query: &str) -> Vec<Project> {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return projects.to_vec();
    }

    projects
        .iter()
        .filter(|project| project.name.contains(trimmed))
        .cloned()
        .collect()
}

fn normalize_path_key(path: &Path) -> String {
    path.to_string_lossy().to_string()
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::process::Command;

    use tempfile::tempdir;

    use super::*;

    #[test]
    fn project_scan_discovers_multiple_roots_and_skips_missing() {
        let temp = tempdir().expect("create temp dir");
        let root_a = temp.path().join("root-a");
        let root_b = temp.path().join("root-b");
        fs::create_dir_all(&root_a).expect("create root a");
        fs::create_dir_all(&root_b).expect("create root b");

        init_git_repo(&root_a.join("alpha"));
        init_git_repo(&root_b.join("nested/inner/bravo"));

        let roots = vec![
            root_a,
            root_b,
            temp.path().join("missing-root"),
            temp.path().join("not-a-dir.txt"),
        ];

        fs::write(&roots[3], "not a dir").expect("write file path");

        let projects = discover_projects(&roots);
        let names: Vec<&str> = projects
            .iter()
            .map(|project| project.name.as_str())
            .collect();

        assert_eq!(
            projects.len(),
            2,
            "should discover only git repos under valid roots"
        );
        assert!(
            names.contains(&"alpha"),
            "expected alpha repo to be discovered"
        );
        assert!(
            names.contains(&"bravo"),
            "expected bravo repo to be discovered"
        );
    }

    #[test]
    fn query_filter_handles_empty_and_non_empty_queries() {
        let projects = vec![
            Project {
                name: "alpha-api".to_string(),
                path: PathBuf::from("/tmp/alpha-api"),
            },
            Project {
                name: "beta-service".to_string(),
                path: PathBuf::from("/tmp/beta-service"),
            },
        ];

        let all = filter_projects(&projects, "   ");
        assert_eq!(all.len(), 2, "empty query should keep all projects");

        let filtered = filter_projects(&projects, "api");
        assert_eq!(
            filtered.len(),
            1,
            "non-empty query should perform substring filtering"
        );
        assert_eq!(filtered[0].name, "alpha-api");
    }

    fn init_git_repo(path: &Path) {
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
