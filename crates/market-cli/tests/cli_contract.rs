use std::process::{Command, Output};

use chrono::{TimeZone, Utc};
use market_cli::model::{
    CacheMetadata, CacheStatus, MarketKind, MarketQuote, MarketRequest, build_output,
};
use serde_json::Value;

fn run_cli(args: &[&str], envs: &[(&str, &str)]) -> Output {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_market-cli"));
    cmd.args(args);
    for (key, value) in envs {
        cmd.env(key, value);
    }
    cmd.output().expect("run market-cli")
}

#[test]
fn cli_contract_output_contains_required_fields_for_fx() {
    let request = MarketRequest::new(MarketKind::Fx, "USD", "TWD", "100").expect("request");
    let quote = MarketQuote::new(
        "frankfurter",
        rust_decimal::Decimal::new(321, 1),
        Utc.with_ymd_and_hms(2026, 2, 10, 12, 0, 0)
            .single()
            .expect("time"),
    );

    let output = build_output(
        &request,
        &quote,
        CacheMetadata {
            status: CacheStatus::Live,
            key: "fx-usd-twd".to_string(),
            ttl_secs: 86400,
            age_secs: 0,
        },
    );
    let value = serde_json::to_value(output).expect("json");

    for field in [
        "kind",
        "base",
        "quote",
        "amount",
        "unit_price",
        "converted",
        "provider",
        "fetched_at",
        "cache",
    ] {
        assert!(value.get(field).is_some(), "missing field: {field}");
    }
}

#[test]
fn cli_contract_cache_status_serializes_in_snake_case() {
    let request = MarketRequest::new(MarketKind::Crypto, "BTC", "USD", "0.5").expect("request");
    let quote = MarketQuote::new(
        "coinbase",
        rust_decimal::Decimal::new(68000, 0),
        Utc.with_ymd_and_hms(2026, 2, 10, 12, 0, 0)
            .single()
            .expect("time"),
    );

    let output = build_output(
        &request,
        &quote,
        CacheMetadata {
            status: CacheStatus::CacheStaleFallback,
            key: "crypto-btc-usd".to_string(),
            ttl_secs: 300,
            age_secs: 900,
        },
    );

    let value: Value = serde_json::to_value(output).expect("json");
    assert_eq!(
        value
            .get("cache")
            .and_then(|cache| cache.get("status"))
            .and_then(Value::as_str),
        Some("cache_stale_fallback")
    );
}

#[test]
fn cli_contract_amount_validation_rejects_zero() {
    let err = MarketRequest::new(MarketKind::Fx, "USD", "TWD", "0").expect_err("must fail");
    assert!(err.to_string().contains("amount must be positive"));
}

#[test]
fn service_json_error_envelope_has_required_keys() {
    let output = run_cli(
        &[
            "fx", "--base", "USD", "--quote", "TWD", "--amount", "0", "--json",
        ],
        &[("MARKET_TEST_SECRET", "unused")],
    );
    assert_eq!(output.status.code(), Some(2));

    let json: Value = serde_json::from_slice(&output.stdout).expect("stdout should be json");
    assert_eq!(
        json.get("schema_version").and_then(Value::as_str),
        Some("v1")
    );
    assert_eq!(
        json.get("command").and_then(Value::as_str),
        Some("market.fx")
    );
    assert_eq!(json.get("ok").and_then(Value::as_bool), Some(false));
    assert_eq!(
        json.get("error")
            .and_then(|error| error.get("code"))
            .and_then(Value::as_str),
        Some("user.invalid_input")
    );
    assert!(
        json.get("error")
            .and_then(|error| error.get("details"))
            .is_some()
    );
}

#[test]
fn service_json_error_envelope_redacts_secret_like_input() {
    let secret = "market-contract-secret-123";
    let amount = format!("token={secret}");
    let output = run_cli(
        &[
            "fx", "--base", "USD", "--quote", "TWD", "--amount", &amount, "--json",
        ],
        &[],
    );
    assert_eq!(output.status.code(), Some(2));

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(!stdout.contains(secret));
    assert!(!stderr.contains(secret));

    let json: Value = serde_json::from_slice(&output.stdout).expect("stdout should be json");
    assert_eq!(json.get("ok").and_then(Value::as_bool), Some(false));
    assert!(
        json.get("error")
            .and_then(|error| error.get("message"))
            .and_then(Value::as_str)
            .is_some()
    );
}
