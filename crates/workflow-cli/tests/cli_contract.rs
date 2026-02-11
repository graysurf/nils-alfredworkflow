use std::fs;
use std::process::{Command, Output};

use serde_json::Value;

fn run_cli(args: &[&str], envs: &[(&str, &str)]) -> Output {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_workflow-cli"));
    cmd.args(args);
    for (key, value) in envs {
        cmd.env(key, value);
    }
    cmd.output().expect("run workflow-cli")
}

fn init_repo(path: &std::path::Path) {
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
fn script_filter_json_mode_returns_success_envelope() {
    let temp = tempfile::tempdir().expect("temp dir");
    let root = temp.path().join("projects");
    init_repo(&root.join("alpha"));

    let project_dirs = root.to_string_lossy().to_string();
    let usage_file = temp.path().join("usage.log").to_string_lossy().to_string();

    let output = run_cli(
        &["script-filter", "--query", "", "--output", "json"],
        &[
            ("PROJECT_DIRS", project_dirs.as_str()),
            ("USAGE_FILE", usage_file.as_str()),
            ("VSCODE_PATH", "code"),
        ],
    );
    assert_eq!(output.status.code(), Some(0));

    let json: Value = serde_json::from_slice(&output.stdout).expect("stdout should be json");
    assert_eq!(
        json.get("schema_version").and_then(Value::as_str),
        Some("v1")
    );
    assert_eq!(
        json.get("command").and_then(Value::as_str),
        Some("workflow.script-filter")
    );
    assert_eq!(json.get("ok").and_then(Value::as_bool), Some(true));
    assert!(
        json.get("result")
            .and_then(|result| result.get("items"))
            .and_then(Value::as_array)
            .is_some()
    );
}

#[test]
fn script_filter_json_conflict_returns_machine_readable_error() {
    let output = run_cli(
        &[
            "script-filter",
            "--query",
            "alpha",
            "--json",
            "--output",
            "human",
        ],
        &[],
    );
    assert_eq!(output.status.code(), Some(2));

    let json: Value = serde_json::from_slice(&output.stdout).expect("stdout should be json");
    assert_eq!(json.get("ok").and_then(Value::as_bool), Some(false));
    assert_eq!(
        json.get("error")
            .and_then(|error| error.get("code"))
            .and_then(Value::as_str),
        Some("user.output_mode_conflict")
    );
    assert!(
        json.get("error")
            .and_then(|error| error.get("details"))
            .is_some()
    );
}

#[test]
fn human_error_output_redacts_secret_like_path_value() {
    let secret = "workflow-secret-456";
    let missing_path = format!("/tmp/token={secret}");
    let output = run_cli(&["record-usage", "--path", &missing_path], &[]);
    assert_eq!(output.status.code(), Some(2));

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(!stdout.contains(secret));
    assert!(!stderr.contains(secret));
}
