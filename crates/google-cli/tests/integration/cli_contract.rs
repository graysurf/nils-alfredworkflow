use serde_json::Value;
use tempfile::tempdir;

use crate::common::TestHarness;

#[test]
fn service_json_success_envelope_has_required_keys() {
    let harness = TestHarness::new();
    let output = harness.run(
        &["--output", "json", "auth", "list"],
        &[("FAKE_GOG_STDOUT", r#"{"accounts":["me@example.com"]}"#)],
    );
    assert_eq!(output.status.code(), Some(0));

    let json: Value = serde_json::from_slice(&output.stdout).expect("stdout should be json");
    assert_eq!(
        json.get("schema_version").and_then(Value::as_str),
        Some("cli-envelope@v1")
    );
    assert_eq!(
        json.get("command").and_then(Value::as_str),
        Some("google.auth.list")
    );
    assert_eq!(json.get("ok").and_then(Value::as_bool), Some(true));
    assert!(
        json.get("result")
            .and_then(|value| value.get("accounts"))
            .and_then(Value::as_array)
            .is_some()
    );
}

#[test]
fn output_mode_invalid_value_is_rejected_by_clap() {
    let harness = TestHarness::new();
    let output = harness.run(&["--output", "yaml", "auth", "list"], &[]);
    // clap rejects with exit code 2 and prints usage on stderr.
    assert_eq!(output.status.code(), Some(2));
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("invalid value 'yaml'"),
        "expected clap rejection message, got: {stderr}"
    );
}

#[test]
fn native_drive_missing_token_returns_user_error_envelope() {
    let harness = TestHarness::new();
    let config_dir = tempdir().expect("tempdir");
    let config_dir_env = config_dir.path().display().to_string();
    let output = harness.run(
        &["--output", "json", "drive", "download", "file-id"],
        &[("GOOGLE_CLI_CONFIG_DIR", config_dir_env.as_str())],
    );
    assert_eq!(output.status.code(), Some(2));

    let json: Value = serde_json::from_slice(&output.stdout).expect("stdout should be json");
    assert_eq!(
        json.get("command").and_then(Value::as_str),
        Some("google.drive.download")
    );
    assert_eq!(json.get("ok").and_then(Value::as_bool), Some(false));
    assert_eq!(
        json.get("error")
            .and_then(|error| error.get("code"))
            .and_then(Value::as_str),
        Some("NILS_GOOGLE_005")
    );
}
