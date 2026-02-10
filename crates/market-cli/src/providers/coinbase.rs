use chrono::Utc;
use reqwest::blocking::Client;
use rust_decimal::Decimal;
use serde::Deserialize;

use crate::config::RetryPolicy;
use crate::model::MarketQuote;

use super::{ProviderError, execute_with_retry};

const ENDPOINT_PREFIX: &str = "https://api.coinbase.com/v2/prices";

pub fn fetch_crypto_spot(
    client: &Client,
    base: &str,
    quote: &str,
    retry_policy: RetryPolicy,
) -> Result<MarketQuote, ProviderError> {
    execute_with_retry(
        "coinbase",
        retry_policy,
        || fetch_once(client, base, quote),
        std::thread::sleep,
    )
}

fn fetch_once(client: &Client, base: &str, quote: &str) -> Result<MarketQuote, ProviderError> {
    let pair = format!("{base}-{quote}");
    let endpoint = format!("{ENDPOINT_PREFIX}/{pair}/spot");

    let response = client
        .get(endpoint)
        .send()
        .map_err(|error| ProviderError::Transport(error.to_string()))?;
    let status = response.status().as_u16();
    let body = response
        .text()
        .map_err(|error| ProviderError::Transport(error.to_string()))?;
    let unit_price = parse_spot_body(status, &body)?;

    Ok(MarketQuote::new("coinbase", unit_price, Utc::now()))
}

pub fn parse_spot_body(status: u16, body: &str) -> Result<Decimal, ProviderError> {
    if !(200..=299).contains(&status) {
        return Err(ProviderError::Http {
            status,
            message: extract_error_message(body).unwrap_or_else(|| format!("HTTP {status}")),
        });
    }

    let payload: CoinbaseSpotResponse = serde_json::from_str(body)
        .map_err(|error| ProviderError::InvalidResponse(error.to_string()))?;
    payload
        .data
        .amount
        .trim()
        .parse::<Decimal>()
        .map_err(|_| ProviderError::InvalidResponse("invalid coinbase amount".to_string()))
}

fn extract_error_message(body: &str) -> Option<String> {
    let value = serde_json::from_str::<serde_json::Value>(body).ok()?;
    let candidates = [
        value.get("message").and_then(serde_json::Value::as_str),
        value
            .get("errors")
            .and_then(|errors| errors.get(0))
            .and_then(|first| first.get("message"))
            .and_then(serde_json::Value::as_str),
        value
            .get("error")
            .and_then(|error| error.get("message"))
            .and_then(serde_json::Value::as_str),
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
struct CoinbaseSpotResponse {
    data: CoinbaseSpotData,
}

#[derive(Debug, Deserialize)]
struct CoinbaseSpotData {
    amount: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn coinbase_parse_spot_body_extracts_amount() {
        let body = r#"{
            "data": {
                "base": "BTC",
                "currency": "USD",
                "amount": "67321.1201"
            }
        }"#;

        let price = parse_spot_body(200, body).expect("must parse");
        assert_eq!(price.to_string(), "67321.1201");
    }

    #[test]
    fn coinbase_parse_spot_body_rejects_invalid_json() {
        let err = parse_spot_body(200, "not-json").expect_err("must fail");
        assert!(matches!(err, ProviderError::InvalidResponse(_)));
    }

    #[test]
    fn coinbase_parse_spot_body_surfaces_http_errors() {
        let body = r#"{"message":"Too many requests"}"#;
        let err = parse_spot_body(429, body).expect_err("must fail");
        assert_eq!(
            err,
            ProviderError::Http {
                status: 429,
                message: "Too many requests".to_string(),
            }
        );
    }
}
