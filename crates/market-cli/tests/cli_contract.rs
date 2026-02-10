use chrono::{TimeZone, Utc};
use market_cli::model::{
    CacheMetadata, CacheStatus, MarketKind, MarketQuote, MarketRequest, build_output,
};
use serde_json::Value;

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
