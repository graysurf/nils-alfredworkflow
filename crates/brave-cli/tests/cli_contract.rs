use std::path::PathBuf;
use std::process::{Command, Output};

use serde_json::Value;

fn run_cli(args: &[&str], envs: &[(&str, &str)]) -> Output {
    let mut cmd = Command::new(resolve_cli_path());
    cmd.args(args);
    for (key, value) in envs {
        cmd.env(key, value);
    }
    cmd.output().expect("run brave-cli")
}

#[test]
fn service_json_error_envelope_has_required_keys_and_no_secret_leak() {
    let secret = "brave-contract-secret";
    let output = run_cli(
        &["search", "--query", "   ", "--mode", "service-json"],
        &[("BRAVE_API_KEY", secret)],
    );
    assert_eq!(output.status.code(), Some(2));

    let json: Value = serde_json::from_slice(&output.stdout).expect("stdout should be json");
    assert_eq!(
        json.get("schema_version").and_then(Value::as_str),
        Some("v1")
    );
    assert_eq!(json.get("command").and_then(Value::as_str), Some("search"));
    assert_eq!(json.get("ok").and_then(Value::as_bool), Some(false));
    assert!(json.get("result").is_none());
    assert!(json.get("error").is_some());
    assert!(
        json.get("error")
            .and_then(|error| error.get("code"))
            .and_then(Value::as_str)
            .is_some()
    );
    assert!(
        json.get("error")
            .and_then(|error| error.get("message"))
            .and_then(Value::as_str)
            .is_some()
    );
    assert!(
        json.get("error")
            .and_then(|error| error.get("details"))
            .is_none()
    );

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(!stdout.contains(secret));
    assert!(!stderr.contains(secret));
}

#[test]
fn alfred_mode_keeps_stderr_error_behavior() {
    let output = run_cli(&["search", "--query", "   ", "--mode", "alfred"], &[]);
    assert_eq!(output.status.code(), Some(2));
    assert!(output.stdout.is_empty());
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("query must not be empty"),
        "alfred mode should keep non-enveloped stderr error"
    );
}

#[test]
fn query_mode_empty_input_returns_alfred_feedback_json() {
    let output = run_cli(&["query", "--input", "   ", "--mode", "alfred"], &[]);
    assert_eq!(output.status.code(), Some(0));
    assert!(
        output.stderr.is_empty(),
        "query empty-input should not use stderr"
    );

    let json: Value = serde_json::from_slice(&output.stdout).expect("stdout should be json");
    assert!(
        json.get("items")
            .and_then(Value::as_array)
            .is_some_and(|items| !items.is_empty()),
        "query mode should return at least one guidance item"
    );
}

fn resolve_cli_path() -> PathBuf {
    if let Some(path) = std::env::var_os("CARGO_BIN_EXE_brave-cli") {
        return PathBuf::from(path);
    }

    if let Ok(current_exe) = std::env::current_exe()
        && let Some(debug_dir) = current_exe.parent().and_then(|deps| deps.parent())
    {
        let candidate = debug_dir.join(format!("brave-cli{}", std::env::consts::EXE_SUFFIX));
        if candidate.exists() {
            return candidate;
        }
    }

    PathBuf::from(env!("CARGO_BIN_EXE_brave-cli"))
}
