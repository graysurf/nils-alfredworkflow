use thiserror::Error;

pub const SUGGEST_ENDPOINT: &str = "https://suggestqueries.google.com/complete/search";
pub const DEFAULT_SUGGEST_MAX_RESULTS: u8 = 8;
const SUGGEST_OUTPUT: &str = "chrome";
const SUGGEST_IE: &str = "utf8";
const SUGGEST_OE: &str = "utf8";

pub fn fetch_suggestions(query: &str, max_results: u8) -> Result<Vec<String>, GoogleSuggestError> {
    let client = reqwest::blocking::Client::new();
    let params = vec![
        ("output".to_string(), SUGGEST_OUTPUT.to_string()),
        ("ie".to_string(), SUGGEST_IE.to_string()),
        ("oe".to_string(), SUGGEST_OE.to_string()),
        ("q".to_string(), query.to_string()),
    ];

    let response = client
        .get(SUGGEST_ENDPOINT)
        .query(&params)
        .send()
        .map_err(|source| GoogleSuggestError::Transport { source })?;
    let body = response
        .text()
        .map_err(|source| GoogleSuggestError::Transport { source })?;

    parse_suggestions_response(&body, query, max_results)
}

pub fn parse_suggestions_response(
    body: &str,
    query: &str,
    max_results: u8,
) -> Result<Vec<String>, GoogleSuggestError> {
    let payload: serde_json::Value =
        serde_json::from_str(body).map_err(GoogleSuggestError::InvalidResponse)?;
    let Some(rows) = payload.get(1).and_then(serde_json::Value::as_array) else {
        return Ok(Vec::new());
    };

    let query_trimmed = query.trim();
    let mut normalized: Vec<String> = Vec::new();
    for row in rows {
        let Some(text) = row
            .as_str()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        else {
            continue;
        };

        if text.eq_ignore_ascii_case(query_trimmed) {
            continue;
        }
        if normalized
            .iter()
            .any(|existing| existing.eq_ignore_ascii_case(text))
        {
            continue;
        }
        normalized.push(text.to_string());
    }

    let cap = usize::from(max_results.max(1));
    if normalized.len() > cap {
        normalized.truncate(cap);
    }

    Ok(normalized)
}

#[derive(Debug, Error)]
pub enum GoogleSuggestError {
    #[error("google suggest request failed")]
    Transport {
        #[source]
        source: reqwest::Error,
    },
    #[error("invalid google suggest response")]
    InvalidResponse(#[source] serde_json::Error),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_suggestions_response_normalizes_and_deduplicates_items() {
        let body =
            r#"["rust",["rust","rust language"," Rust language ","rust book","rust book",""]]"#;

        let parsed = parse_suggestions_response(body, "rust", 8).expect("response should parse");
        assert_eq!(
            parsed,
            vec!["rust language".to_string(), "rust book".to_string()]
        );
    }

    #[test]
    fn parse_suggestions_response_limits_results() {
        let body = r#"["rust",["rust language","rust book","rust cli"]]"#;

        let parsed = parse_suggestions_response(body, "rust", 2).expect("response should parse");
        assert_eq!(
            parsed,
            vec!["rust language".to_string(), "rust book".to_string()]
        );
    }

    #[test]
    fn parse_suggestions_response_returns_empty_for_missing_rows() {
        let parsed = parse_suggestions_response(r#"{"unexpected":true}"#, "rust", 8)
            .expect("missing suggest rows should map to empty vector");
        assert!(parsed.is_empty());
    }

    #[test]
    fn parse_suggestions_response_rejects_invalid_json() {
        let err = parse_suggestions_response("not-json", "rust", 8)
            .expect_err("invalid payload should fail");
        assert!(matches!(err, GoogleSuggestError::InvalidResponse(_)));
    }
}
