use std::path::PathBuf;
use std::process::{Command, Output};

use serde_json::Value;

fn run_cli(args: &[&str], envs: &[(&str, &str)]) -> Output {
    let mut cmd = Command::new(resolve_cli_path());
    cmd.args(args);
    for (key, value) in envs {
        cmd.env(key, value);
    }
    cmd.output().expect("run epoch-cli")
}

#[test]
fn service_json_success_envelope_has_required_keys() {
    let output = run_cli(&["convert", "--query", "0", "--output", "json"], &[]);
    assert_eq!(output.status.code(), Some(0));

    let json: Value = serde_json::from_slice(&output.stdout).expect("stdout should be json");
    assert_eq!(
        json.get("schema_version").and_then(Value::as_str),
        Some("cli-envelope@v1")
    );
    assert_eq!(json.get("command").and_then(Value::as_str), Some("convert"));
    assert_eq!(json.get("ok").and_then(Value::as_bool), Some(true));
    assert!(json.get("error").is_none());
    assert!(
        json.get("result")
            .and_then(|result| result.get("items"))
            .and_then(Value::as_array)
            .is_some()
    );
}

#[test]
fn service_json_error_envelope_has_required_keys_and_no_secret_leak() {
    let secret = "epoch-contract-secret";
    let output = run_cli(
        &["convert", "--query", "invalid query", "--output", "json"],
        &[("EPOCH_TEST_SECRET", secret)],
    );
    assert_eq!(output.status.code(), Some(2));

    let json: Value = serde_json::from_slice(&output.stdout).expect("stdout should be json");
    assert_eq!(json.get("ok").and_then(Value::as_bool), Some(false));
    assert!(
        json.get("error")
            .and_then(|error| error.get("code"))
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

fn resolve_cli_path() -> PathBuf {
    if let Some(path) = std::env::var_os("CARGO_BIN_EXE_epoch-cli") {
        return PathBuf::from(path);
    }

    if let Ok(current_exe) = std::env::current_exe()
        && let Some(debug_dir) = current_exe.parent().and_then(|deps| deps.parent())
    {
        let candidate = debug_dir.join(format!("epoch-cli{}", std::env::consts::EXE_SUFFIX));
        if candidate.exists() {
            return candidate;
        }
    }

    PathBuf::from(env!("CARGO_BIN_EXE_epoch-cli"))
}
