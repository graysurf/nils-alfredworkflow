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
fn script_filter_empty_query_includes_db_init_row() {
    let dir = tempdir().expect("temp dir");
    let db = dir.path().join("memo.db");

    let output = Command::new(bin())
        .args(["script-filter", "--query", ""])
        .env("MEMO_DB_PATH", db.to_str().expect("db path"))
        .output()
        .expect("script-filter should run");

    assert!(output.status.success(), "script-filter must exit 0");

    let payload: Value =
        serde_json::from_slice(&output.stdout).expect("script-filter stdout must be JSON");
    let has_db_init = payload
        .get("items")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .any(|item| item.get("arg").and_then(Value::as_str) == Some("db-init"))
        })
        .unwrap_or(false);

    assert!(has_db_init, "empty query should include db-init action row");
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

#[test]
fn list_returns_latest_first() {
    let dir = tempdir().expect("temp dir");
    let db = dir.path().join("memo.db");
    let db_path = db.to_str().expect("db path");

    let first = Command::new(bin())
        .args(["add", "--db", db_path, "--text", "first memo"])
        .output()
        .expect("first add should run");
    assert!(first.status.success(), "first add should succeed");

    let second = Command::new(bin())
        .args(["add", "--db", db_path, "--text", "second memo"])
        .output()
        .expect("second add should run");
    assert!(second.status.success(), "second add should succeed");

    let list = Command::new(bin())
        .args(["list", "--db", db_path, "--limit", "2", "--mode", "json"])
        .output()
        .expect("list should run");
    assert!(list.status.success(), "list should exit 0");

    let payload: Value = serde_json::from_slice(&list.stdout).expect("list stdout must be JSON");
    let rows = payload
        .get("result")
        .and_then(Value::as_array)
        .expect("result must be an array");
    assert_eq!(rows.len(), 2, "list should return two rows");

    let first_preview = rows[0]
        .get("text_preview")
        .and_then(Value::as_str)
        .unwrap_or_default();
    assert!(
        first_preview.contains("second memo"),
        "newest row should be listed first"
    );
}
