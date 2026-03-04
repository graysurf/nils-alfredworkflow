use std::collections::HashSet;

use workflow_common::parse_ordered_list_with;

pub mod cache;
pub mod config;
pub mod error;
pub mod expression;
pub mod model;
pub mod providers;
pub mod service;

use crate::model::{ValidationError, normalize_crypto_symbol, normalize_fx_symbol};

const DEFAULT_FAVORITE_SYMBOLS: [&str; 3] = ["BTC", "ETH", "JPY"];

pub fn parse_favorites_list(
    raw: Option<&str>,
    default_fiat: &str,
) -> Result<Vec<String>, ValidationError> {
    let fallback = default_favorites(default_fiat)?;

    let Some(value) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(fallback);
    };
    let expanded = value.replace("\\n", "\n");

    let mut seen = HashSet::new();
    let parsed = parse_ordered_list_with(&expanded, |token| {
        let normalized = normalize_crypto_symbol(token, "favorite")?;
        if !seen.insert(normalized.clone()) {
            return Ok(None);
        }

        Ok(Some(normalized))
    })?;

    if parsed.is_empty() {
        return Ok(fallback);
    }

    Ok(parsed)
}

fn default_favorites(default_fiat: &str) -> Result<Vec<String>, ValidationError> {
    let default_fiat = normalize_fx_symbol(default_fiat, "default_fiat")?;
    let mut seen = HashSet::new();
    let mut defaults = Vec::new();

    for symbol in [
        DEFAULT_FAVORITE_SYMBOLS[0].to_string(),
        DEFAULT_FAVORITE_SYMBOLS[1].to_string(),
        default_fiat,
        DEFAULT_FAVORITE_SYMBOLS[2].to_string(),
    ] {
        if seen.insert(symbol.clone()) {
            defaults.push(symbol);
        }
    }

    Ok(defaults)
}
