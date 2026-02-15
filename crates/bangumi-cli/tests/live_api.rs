use std::process::Command;

use serde_json::Value;

fn live_api_key() -> String {
    std::env::var("BANGUMI_API_KEY")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .expect("set BANGUMI_API_KEY to run live API tests")
}

fn run_live(args: &[&str], api_key: &str) -> (i32, Value, String) {
    let output = Command::new(env!("CARGO_BIN_EXE_bangumi-cli"))
        .args(args)
        .env("BANGUMI_API_KEY", api_key)
        .env("BANGUMI_MAX_RESULTS", "3")
        .env("BANGUMI_TIMEOUT_MS", "15000")
        .output()
        .expect("run bangumi-cli live command");

    let status = output.status.code().unwrap_or(-1);
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let parsed = serde_json::from_str::<Value>(&stdout).expect("stdout should be JSON");
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    (status, parsed, stderr)
}

#[test]
#[ignore = "requires network and BANGUMI_API_KEY"]
fn live_api_query_uses_real_bangumi_key_and_returns_items_array() {
    let api_key = live_api_key();
    let (status, json, stderr) = run_live(&["query", "--input", "anime naruto"], &api_key);

    assert_eq!(status, 0, "query failed: {stderr}");
    assert!(
        json.get("items").and_then(Value::as_array).is_some(),
        "query output should contain items array"
    );
}

#[test]
#[ignore = "requires network and BANGUMI_API_KEY"]
fn live_api_search_command_works_with_explicit_type_and_key() {
    let api_key = live_api_key();
    let (status, json, stderr) = run_live(
        &["search", "--query", "cowboy bebop", "--type", "anime"],
        &api_key,
    );

    assert_eq!(status, 0, "search failed: {stderr}");
    let first_arg = json
        .pointer("/items/0/arg")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();

    if !first_arg.is_empty() {
        assert!(
            first_arg.starts_with("https://bgm.tv/subject/"),
            "first item URL should point to Bangumi subject page"
        );
    }
}
