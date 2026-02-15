use std::process::{Command, Output};

use serde_json::Value;

fn run_cli(args: &[&str], envs: &[(&str, &str)]) -> Output {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_bilibili-cli"));
    cmd.args(args);
    for (key, value) in envs {
        cmd.env(key, value);
    }
    cmd.output().expect("run bilibili-cli")
}

#[test]
fn service_json_error_envelope_has_required_keys_and_no_secret_leak() {
    let secret = "bilibili-contract-secret";
    let output = run_cli(
        &["query", "--input", "   ", "--mode", "service-json"],
        &[("BILIBILI_UID", secret)],
    );
    assert_eq!(output.status.code(), Some(2));

    let json: Value = serde_json::from_slice(&output.stdout).expect("stdout should be json");
    assert_eq!(
        json.get("schema_version").and_then(Value::as_str),
        Some("v1")
    );
    assert_eq!(json.get("command").and_then(Value::as_str), Some("query"));
    assert_eq!(json.get("ok").and_then(Value::as_bool), Some(false));
    assert!(json.get("result").is_some());
    assert!(
        json.get("error")
            .and_then(|error| error.get("code"))
            .and_then(Value::as_str)
            .is_some()
    );

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(!stdout.contains(secret));
    assert!(!stderr.contains(secret));
}

#[test]
fn alfred_mode_keeps_stderr_error_behavior() {
    let output = run_cli(&["query", "--input", "   ", "--mode", "alfred"], &[]);
    assert_eq!(output.status.code(), Some(2));
    assert!(output.stdout.is_empty());
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("query must not be empty"),
        "alfred mode should keep non-enveloped stderr error"
    );
}
