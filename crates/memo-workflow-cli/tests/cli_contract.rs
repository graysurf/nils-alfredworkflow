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

    let has_db_path_info = payload
        .get("items")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .any(|item| item.get("title").and_then(Value::as_str) == Some("Memo database path"))
        })
        .unwrap_or(false);

    assert!(
        !has_db_path_info,
        "empty query without db should not show db path info row"
    );
}

#[test]
fn script_filter_empty_query_with_existing_db_shows_db_path_row_without_db_init() {
    let dir = tempdir().expect("temp dir");
    let db = dir.path().join("memo.db");
    let db_path = db.to_str().expect("db path");

    let init = Command::new(bin())
        .args(["db-init", "--db", db_path])
        .output()
        .expect("db-init should run");
    assert!(init.status.success(), "db-init must exit 0");

    let output = Command::new(bin())
        .args(["script-filter", "--query", ""])
        .env("MEMO_DB_PATH", db_path)
        .output()
        .expect("script-filter should run");
    assert!(output.status.success(), "script-filter must exit 0");

    let payload: Value =
        serde_json::from_slice(&output.stdout).expect("script-filter stdout must be JSON");
    let items = payload
        .get("items")
        .and_then(Value::as_array)
        .expect("items array");

    let has_db_init = items
        .iter()
        .any(|item| item.get("arg").and_then(Value::as_str) == Some("db-init"));
    assert!(
        !has_db_init,
        "empty query with existing db should not include db-init action row"
    );

    let db_path_subtitle = format!("Using SQLite at {db_path}");
    let has_db_path_info = items.iter().any(|item| {
        item.get("title").and_then(Value::as_str) == Some("Memo database path")
            && item.get("subtitle").and_then(Value::as_str) == Some(db_path_subtitle.as_str())
    });
    assert!(
        has_db_path_info,
        "empty query with existing db should show db path info row"
    );
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

#[test]
fn update_mutates_existing_item() {
    let dir = tempdir().expect("temp dir");
    let db = dir.path().join("memo.db");
    let db_path = db.to_str().expect("db path");

    let add = Command::new(bin())
        .args(["add", "--db", db_path, "--text", "before", "--mode", "json"])
        .output()
        .expect("add should run");
    assert!(add.status.success(), "add should succeed");
    let add_payload: Value = serde_json::from_slice(&add.stdout).expect("add json");
    let item_id = add_payload
        .get("result")
        .and_then(|result| result.get("item_id"))
        .and_then(Value::as_str)
        .expect("item id")
        .to_string();

    let update = Command::new(bin())
        .args([
            "update",
            "--db",
            db_path,
            "--item-id",
            &item_id,
            "--text",
            "after",
            "--mode",
            "json",
        ])
        .output()
        .expect("update should run");
    assert!(update.status.success(), "update should succeed");
    let update_payload: Value = serde_json::from_slice(&update.stdout).expect("update json");
    assert_eq!(
        update_payload.get("ok").and_then(Value::as_bool),
        Some(true)
    );
    assert_eq!(
        update_payload
            .get("result")
            .and_then(|result| result.get("text"))
            .and_then(Value::as_str),
        Some("after")
    );
}

#[test]
fn delete_removes_existing_item() {
    let dir = tempdir().expect("temp dir");
    let db = dir.path().join("memo.db");
    let db_path = db.to_str().expect("db path");

    let add = Command::new(bin())
        .args([
            "add",
            "--db",
            db_path,
            "--text",
            "to delete",
            "--mode",
            "json",
        ])
        .output()
        .expect("add should run");
    assert!(add.status.success(), "add should succeed");
    let add_payload: Value = serde_json::from_slice(&add.stdout).expect("add json");
    let item_id = add_payload
        .get("result")
        .and_then(|result| result.get("item_id"))
        .and_then(Value::as_str)
        .expect("item id")
        .to_string();

    let delete = Command::new(bin())
        .args([
            "delete",
            "--db",
            db_path,
            "--item-id",
            &item_id,
            "--mode",
            "json",
        ])
        .output()
        .expect("delete should run");
    assert!(delete.status.success(), "delete should succeed");

    let list = Command::new(bin())
        .args(["list", "--db", db_path, "--mode", "json"])
        .output()
        .expect("list should run");
    assert!(list.status.success(), "list should succeed");
    let list_payload: Value = serde_json::from_slice(&list.stdout).expect("list json");
    let rows = list_payload
        .get("result")
        .and_then(Value::as_array)
        .expect("list rows");
    assert!(
        rows.iter().all(|row| {
            row.get("item_id")
                .and_then(Value::as_str)
                .map(|id| id != item_id)
                .unwrap_or(true)
        }),
        "deleted item should not appear in list"
    );
}

#[test]
fn action_token_crud_roundtrip_with_isolated_db() {
    let dir = tempdir().expect("temp dir");
    let db = dir.path().join("memo.db");
    let db_path = db.to_str().expect("db path");

    let add = Command::new(bin())
        .args([
            "action",
            "--token",
            "add::first memo",
            "--db",
            db_path,
            "--mode",
            "json",
        ])
        .output()
        .expect("action add should run");
    assert!(add.status.success(), "action add should succeed");
    let add_payload: Value = serde_json::from_slice(&add.stdout).expect("add json");
    let item_id = add_payload
        .get("result")
        .and_then(|result| result.get("item_id"))
        .and_then(Value::as_str)
        .expect("item id")
        .to_string();

    let update_token = format!("update::{item_id}::updated memo");
    let update = Command::new(bin())
        .args([
            "action",
            "--token",
            &update_token,
            "--db",
            db_path,
            "--mode",
            "json",
        ])
        .output()
        .expect("action update should run");
    assert!(update.status.success(), "action update should succeed");

    let delete_token = format!("delete::{item_id}");
    let delete = Command::new(bin())
        .args([
            "action",
            "--token",
            &delete_token,
            "--db",
            db_path,
            "--mode",
            "json",
        ])
        .output()
        .expect("action delete should run");
    assert!(delete.status.success(), "action delete should succeed");
}

#[test]
fn script_filter_exposes_update_delete_intents() {
    let output_update = Command::new(bin())
        .args([
            "script-filter",
            "--query",
            "update itm_00000001 revised text",
        ])
        .output()
        .expect("script-filter update should run");
    assert!(
        output_update.status.success(),
        "script-filter update must exit 0"
    );
    let update_payload: Value =
        serde_json::from_slice(&output_update.stdout).expect("update payload json");
    let update_arg = update_payload
        .get("items")
        .and_then(Value::as_array)
        .and_then(|items| items.first())
        .and_then(|item| item.get("arg"))
        .and_then(Value::as_str)
        .unwrap_or_default();
    assert!(
        update_arg.starts_with("update::"),
        "update intent should produce update token"
    );

    let output_delete = Command::new(bin())
        .args(["script-filter", "--query", "delete itm_00000001"])
        .output()
        .expect("script-filter delete should run");
    assert!(
        output_delete.status.success(),
        "script-filter delete must exit 0"
    );
    let delete_payload: Value =
        serde_json::from_slice(&output_delete.stdout).expect("delete payload json");
    let delete_arg = delete_payload
        .get("items")
        .and_then(Value::as_array)
        .and_then(|items| items.first())
        .and_then(|item| item.get("arg"))
        .and_then(Value::as_str)
        .unwrap_or_default();
    assert!(
        delete_arg.starts_with("delete::"),
        "delete intent should produce delete token"
    );
}

#[test]
fn update_delete_invalid_item_id_returns_usage_error() {
    let update = Command::new(bin())
        .args([
            "update",
            "--item-id",
            "bad",
            "--text",
            "updated",
            "--mode",
            "json",
        ])
        .output()
        .expect("update should run");
    assert_eq!(update.status.code(), Some(2));

    let delete = Command::new(bin())
        .args(["delete", "--item-id", "bad", "--mode", "json"])
        .output()
        .expect("delete should run");
    assert_eq!(delete.status.code(), Some(2));
}
