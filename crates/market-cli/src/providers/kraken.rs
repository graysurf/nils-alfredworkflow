use std::collections::HashMap;

use chrono::Utc;
use reqwest::blocking::Client;
use rust_decimal::Decimal;
use serde::Deserialize;

use crate::config::RetryPolicy;
use crate::model::MarketQuote;

use super::{ProviderError, execute_with_retry};

const ENDPOINT: &str = "https://api.kraken.com/0/public/Ticker";

pub fn fetch_crypto_spot(
    client: &Client,
    base: &str,
    quote: &str,
    retry_policy: RetryPolicy,
) -> Result<MarketQuote, ProviderError> {
    execute_with_retry(
        "kraken",
        retry_policy,
        || fetch_once(client, base, quote),
        std::thread::sleep,
    )
}

fn fetch_once(client: &Client, base: &str, quote: &str) -> Result<MarketQuote, ProviderError> {
    let pair = normalize_pair(base, quote)?;
    let response = client
        .get(ENDPOINT)
        .query(&[("pair", pair.as_str())])
        .send()
        .map_err(|error| ProviderError::Transport(error.to_string()))?;

    let status = response.status().as_u16();
    let body = response
        .text()
        .map_err(|error| ProviderError::Transport(error.to_string()))?;
    let unit_price = parse_ticker_body(status, &body)?;

    Ok(MarketQuote::new("kraken", unit_price, Utc::now()))
}

pub fn normalize_pair(base: &str, quote: &str) -> Result<String, ProviderError> {
    if !is_valid_symbol(base) || !is_valid_symbol(quote) {
        return Err(ProviderError::UnsupportedPair(format!("{base}/{quote}")));
    }

    let mapped_base = match base {
        "BTC" | "XBT" => "XBT",
        "ETH" => "ETH",
        "SOL" => "SOL",
        "LTC" => "LTC",
        other => other,
    };
    let mapped_quote = match quote {
        "BTC" | "XBT" => "XBT",
        "USD" => "USD",
        "EUR" => "EUR",
        "USDT" => "USDT",
        other => other,
    };

    Ok(format!("{mapped_base}{mapped_quote}"))
}

pub fn parse_ticker_body(status: u16, body: &str) -> Result<Decimal, ProviderError> {
    if !(200..=299).contains(&status) {
        return Err(ProviderError::Http {
            status,
            message: extract_error_message(body).unwrap_or_else(|| format!("HTTP {status}")),
        });
    }

    let payload: KrakenTickerResponse = serde_json::from_str(body)
        .map_err(|error| ProviderError::InvalidResponse(error.to_string()))?;
    if let Some(first_error) = payload.errors.first() {
        if first_error
            .to_ascii_lowercase()
            .contains("unknown asset pair")
        {
            return Err(ProviderError::UnsupportedPair(first_error.clone()));
        }

        return Err(ProviderError::Http {
            status: 400,
            message: first_error.clone(),
        });
    }

    let first_entry = payload
        .result
        .values()
        .next()
        .ok_or_else(|| ProviderError::InvalidResponse("missing kraken result".to_string()))?;
    let close = first_entry
        .close
        .first()
        .ok_or_else(|| ProviderError::InvalidResponse("missing kraken close price".to_string()))?;

    close
        .parse::<Decimal>()
        .map_err(|_| ProviderError::InvalidResponse("invalid kraken close price".to_string()))
}

fn is_valid_symbol(value: &str) -> bool {
    let len = value.len();
    (2..=10).contains(&len) && value.chars().all(|ch| ch.is_ascii_alphanumeric())
}

fn extract_error_message(body: &str) -> Option<String> {
    let value = serde_json::from_str::<serde_json::Value>(body).ok()?;
    let candidates = [
        value.get("message").and_then(serde_json::Value::as_str),
        value.get("error").and_then(serde_json::Value::as_str),
    ];

    candidates
        .iter()
        .flatten()
        .map(|item| item.trim())
        .find(|item| !item.is_empty())
        .map(ToOwned::to_owned)
}

#[derive(Debug, Deserialize)]
struct KrakenTickerResponse {
    #[serde(default, rename = "error")]
    errors: Vec<String>,
    #[serde(default)]
    result: HashMap<String, KrakenTickerResult>,
}

#[derive(Debug, Deserialize)]
struct KrakenTickerResult {
    #[serde(default, rename = "c")]
    close: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kraken_parse_ticker_body_extracts_close_price() {
        let body = r#"{
            "error": [],
            "result": {
                "XXBTZUSD": {
                    "c": ["67321.1", "0.1"]
                }
            }
        }"#;

        let price = parse_ticker_body(200, body).expect("must parse");
        assert_eq!(price.to_string(), "67321.1");
    }

    #[test]
    fn kraken_parse_ticker_body_returns_unsupported_pair() {
        let body = r#"{
            "error": ["EQuery:Unknown asset pair"]
        }"#;

        let err = parse_ticker_body(200, body).expect_err("must fail");
        assert_eq!(
            err,
            ProviderError::UnsupportedPair("EQuery:Unknown asset pair".to_string())
        );
    }

    #[test]
    fn kraken_parse_ticker_body_rejects_invalid_close() {
        let body = r#"{
            "error": [],
            "result": {"XXBTZUSD": {"c": ["not-number"]}}
        }"#;

        let err = parse_ticker_body(200, body).expect_err("must fail");
        assert!(matches!(err, ProviderError::InvalidResponse(_)));
    }

    #[test]
    fn crypto_pair_mapping_maps_btc_to_xbt() {
        let pair = normalize_pair("BTC", "USD").expect("must map");
        assert_eq!(pair, "XBTUSD");
    }

    #[test]
    fn crypto_pair_mapping_maps_eth_quote_btc() {
        let pair = normalize_pair("ETH", "BTC").expect("must map");
        assert_eq!(pair, "ETHXBT");
    }

    #[test]
    fn crypto_pair_mapping_rejects_invalid_symbols() {
        let err = normalize_pair("BTC-", "USD").expect_err("must fail");
        assert_eq!(err, ProviderError::UnsupportedPair("BTC-/USD".to_string()));
    }
}
