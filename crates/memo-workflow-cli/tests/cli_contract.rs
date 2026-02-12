use std::process::Command;

use serde_json::Value;
use tempfile::tempdir;

fn bin() -> String {
    env!("CARGO_BIN_EXE_memo-workflow-cli").to_string()
}

#[test]
fn script_filter_returns_items_array() {
    let output = Command::new(bin())
        .args(["script-filter", "--query", "buy milk"])
        .output()
        .expect("script-filter should run");

    assert!(output.status.success(), "script-filter must exit 0");

    let payload: Value =
        serde_json::from_slice(&output.stdout).expect("script-filter stdout must be JSON");
    assert!(payload.get("items").and_then(Value::as_array).is_some());
}

#[test]
fn db_init_creates_database() {
    let dir = tempdir().expect("temp dir");
    let db = dir.path().join("memo.db");

    let output = Command::new(bin())
        .args(["db-init", "--db", db.to_str().expect("db path")])
        .output()
        .expect("db-init should run");

    assert!(output.status.success(), "db-init must exit 0");
    assert!(db.exists(), "db file should be created");
}

#[test]
fn add_writes_one_row() {
    let dir = tempdir().expect("temp dir");
    let db = dir.path().join("memo.db");

    let status = Command::new(bin())
        .args(["db-init", "--db", db.to_str().expect("db path")])
        .status()
        .expect("db-init should run");
    assert!(status.success(), "db-init should succeed");

    let output = Command::new(bin())
        .args([
            "add",
            "--db",
            db.to_str().expect("db path"),
            "--text",
            "buy milk",
            "--source",
            "alfred-test",
            "--mode",
            "json",
        ])
        .output()
        .expect("add should run");

    assert!(output.status.success(), "add must exit 0");

    let payload: Value = serde_json::from_slice(&output.stdout).expect("add stdout must be JSON");
    assert_eq!(payload.get("ok").and_then(Value::as_bool), Some(true));
    assert_eq!(
        payload
            .get("result")
            .and_then(|result| result.get("source"))
            .and_then(Value::as_str),
        Some("alfred-test")
    );
}

#[test]
fn add_rejects_empty_text() {
    let output = Command::new(bin())
        .args(["add", "--text", "   "])
        .output()
        .expect("add should run");

    assert_eq!(output.status.code(), Some(2));
}
