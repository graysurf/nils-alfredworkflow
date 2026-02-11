use std::fs;
use std::process::{Command, Output};

use serde_json::Value;
use tempfile::tempdir;

const PLIST_TEMPLATE: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>readme</key>
  <string>placeholder</string>
</dict>
</plist>
"#;

fn run_cli(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_workflow-readme-cli"))
        .args(args)
        .output()
        .expect("run workflow-readme-cli")
}

fn setup_fixture() -> (tempfile::TempDir, String, String, String) {
    let temp = tempdir().expect("create temp dir");
    let workflow_root = temp.path().join("workflow");
    let stage_dir = temp.path().join("stage");
    let plist = temp.path().join("info.plist");

    fs::create_dir_all(&workflow_root).expect("create workflow root");
    fs::create_dir_all(&stage_dir).expect("create stage dir");
    fs::write(
        workflow_root.join("README.md"),
        "# Title\n\n![shot](./screenshot.png)\n\n| A | B |\n|---|---|\n| 1 | 2 |\n",
    )
    .expect("write readme");
    fs::write(workflow_root.join("screenshot.png"), b"png").expect("write screenshot");
    fs::write(&plist, PLIST_TEMPLATE).expect("write plist");

    (
        temp,
        workflow_root.to_string_lossy().to_string(),
        stage_dir.to_string_lossy().to_string(),
        plist.to_string_lossy().to_string(),
    )
}

#[test]
fn service_json_success_envelope_has_required_keys() {
    let (_temp, workflow_root, stage_dir, plist) = setup_fixture();
    let output = run_cli(&[
        "convert",
        "--workflow-root",
        &workflow_root,
        "--readme-source",
        "README.md",
        "--stage-dir",
        &stage_dir,
        "--plist",
        &plist,
        "--output",
        "json",
    ]);
    assert_eq!(output.status.code(), Some(0));

    let json: Value = serde_json::from_slice(&output.stdout).expect("stdout should be json");
    assert_eq!(
        json.get("schema_version").and_then(Value::as_str),
        Some("v1")
    );
    assert_eq!(
        json.get("command").and_then(Value::as_str),
        Some("workflow-readme.convert")
    );
    assert_eq!(json.get("ok").and_then(Value::as_bool), Some(true));
    assert!(
        json.get("result")
            .and_then(|result| result.get("copied_assets"))
            .and_then(Value::as_array)
            .is_some()
    );
}

#[test]
fn service_json_error_envelope_has_required_keys() {
    let (_temp, workflow_root, stage_dir, plist) = setup_fixture();
    let output = run_cli(&[
        "convert",
        "--workflow-root",
        &workflow_root,
        "--readme-source",
        "DOES_NOT_EXIST.md",
        "--stage-dir",
        &stage_dir,
        "--plist",
        &plist,
        "--output",
        "json",
    ]);
    assert_eq!(output.status.code(), Some(2));

    let json: Value = serde_json::from_slice(&output.stdout).expect("stdout should be json");
    assert_eq!(
        json.get("schema_version").and_then(Value::as_str),
        Some("v1")
    );
    assert_eq!(
        json.get("command").and_then(Value::as_str),
        Some("workflow-readme.convert")
    );
    assert_eq!(json.get("ok").and_then(Value::as_bool), Some(false));
    assert_eq!(
        json.get("error")
            .and_then(|error| error.get("code"))
            .and_then(Value::as_str),
        Some("user.readme_not_found")
    );
}

#[test]
fn json_conflict_returns_machine_readable_error() {
    let (_temp, workflow_root, stage_dir, plist) = setup_fixture();
    let output = run_cli(&[
        "convert",
        "--workflow-root",
        &workflow_root,
        "--readme-source",
        "README.md",
        "--stage-dir",
        &stage_dir,
        "--plist",
        &plist,
        "--json",
        "--output",
        "human",
    ]);
    assert_eq!(output.status.code(), Some(2));

    let json: Value = serde_json::from_slice(&output.stdout).expect("stdout should be json");
    assert_eq!(json.get("ok").and_then(Value::as_bool), Some(false));
    assert_eq!(
        json.get("error")
            .and_then(|error| error.get("code"))
            .and_then(Value::as_str),
        Some("user.output_mode_conflict")
    );
}
