use std::collections::HashMap;

use chrono::Utc;
use reqwest::blocking::Client;
use rust_decimal::Decimal;
use serde::Deserialize;

use crate::config::RetryPolicy;
use crate::model::MarketQuote;

use super::{ProviderError, execute_with_retry};

const ENDPOINT: &str = "https://api.frankfurter.dev/v1/latest";

pub fn fetch_fx_rate(
    client: &Client,
    base: &str,
    quote: &str,
    retry_policy: RetryPolicy,
) -> Result<MarketQuote, ProviderError> {
    execute_with_retry(
        "frankfurter",
        retry_policy,
        || fetch_once(client, base, quote),
        std::thread::sleep,
    )
}

fn fetch_once(client: &Client, base: &str, quote: &str) -> Result<MarketQuote, ProviderError> {
    let response = client
        .get(ENDPOINT)
        .query(&[("base", base), ("symbols", quote)])
        .send()
        .map_err(|error| ProviderError::Transport(error.to_string()))?;

    let status = response.status().as_u16();
    let body = response
        .text()
        .map_err(|error| ProviderError::Transport(error.to_string()))?;
    let unit_price = parse_fx_body(status, &body, quote)?;

    Ok(MarketQuote::new("frankfurter", unit_price, Utc::now()))
}

pub fn parse_fx_body(status: u16, body: &str, quote: &str) -> Result<Decimal, ProviderError> {
    if !(200..=299).contains(&status) {
        return Err(ProviderError::Http {
            status,
            message: extract_error_message(body).unwrap_or_else(|| format!("HTTP {status}")),
        });
    }

    let payload: FrankfurterResponse = serde_json::from_str(body)
        .map_err(|error| ProviderError::InvalidResponse(error.to_string()))?;
    let raw = payload
        .rates
        .get(quote)
        .ok_or_else(|| ProviderError::InvalidResponse(format!("missing rate for {quote}")))?;

    parse_decimal_value(raw).ok_or_else(|| {
        ProviderError::InvalidResponse(format!("invalid numeric rate for {quote}: {raw}"))
    })
}

fn extract_error_message(body: &str) -> Option<String> {
    let value = serde_json::from_str::<serde_json::Value>(body).ok()?;
    let candidates = [
        value.get("message").and_then(serde_json::Value::as_str),
        value.get("error").and_then(serde_json::Value::as_str),
        value
            .get("error")
            .and_then(|error| error.get("message"))
            .and_then(serde_json::Value::as_str),
    ];

    candidates
        .iter()
        .flatten()
        .map(|item| item.trim())
        .find(|item| !item.is_empty())
        .map(ToOwned::to_owned)
}

fn parse_decimal_value(value: &serde_json::Value) -> Option<Decimal> {
    match value {
        serde_json::Value::String(text) => text.parse::<Decimal>().ok(),
        serde_json::Value::Number(number) => number.to_string().parse::<Decimal>().ok(),
        _ => None,
    }
}

#[derive(Debug, Deserialize)]
struct FrankfurterResponse {
    #[serde(default)]
    rates: HashMap<String, serde_json::Value>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frankfurter_parse_success_body_extracts_rate() {
        let body = r#"{
            "amount": 1.0,
            "base": "USD",
            "date": "2026-02-10",
            "rates": { "TWD": 32.1234 }
        }"#;

        let rate = parse_fx_body(200, body, "TWD").expect("must parse");
        assert_eq!(rate.to_string(), "32.1234");
    }

    #[test]
    fn frankfurter_parse_rejects_missing_rate() {
        let body = r#"{"rates":{"JPY":150.1}}"#;
        let err = parse_fx_body(200, body, "TWD").expect_err("must fail");
        assert!(matches!(err, ProviderError::InvalidResponse(_)));
    }

    #[test]
    fn frankfurter_parse_surfaces_http_error_message() {
        let body = r#"{"message":"rate limit"}"#;
        let err = parse_fx_body(429, body, "TWD").expect_err("must fail");
        assert_eq!(
            err,
            ProviderError::Http {
                status: 429,
                message: "rate limit".to_string(),
            }
        );
    }
}
