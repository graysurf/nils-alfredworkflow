/// Split comma/newline separated config values into a deterministic token list.
///
/// Rules:
/// - separators: `,` and `\n`
/// - trim surrounding whitespace per token
/// - ignore empty tokens
/// - preserve original non-empty token order
pub fn split_ordered_list(raw: &str) -> Vec<String> {
    raw.split([',', '\n'])
        .map(str::trim)
        .filter(|token| !token.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

/// Parse an ordered list via a caller-provided normalization/validation hook.
///
/// The hook can:
/// - return `Some(T)` to keep a parsed token
/// - return `None` to skip the token
/// - return `Err(E)` to stop parsing and surface a typed error
pub fn parse_ordered_list_with<T, E, F>(raw: &str, mut map: F) -> Result<Vec<T>, E>
where
    F: FnMut(&str) -> Result<Option<T>, E>,
{
    let mut parsed = Vec::new();
    for token in split_ordered_list(raw) {
        if let Some(value) = map(&token)? {
            parsed.push(value);
        }
    }

    Ok(parsed)
}

#[cfg(test)]
mod tests {
    use std::error::Error as StdError;
    use std::fmt::{Display, Formatter};

    use super::*;

    #[derive(Debug, Clone, PartialEq, Eq)]
    enum FixtureError {
        UnsupportedToken(String),
    }

    impl Display for FixtureError {
        fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
            match self {
                FixtureError::UnsupportedToken(token) => write!(f, "unsupported token: {token}"),
            }
        }
    }

    impl StdError for FixtureError {}

    #[test]
    fn split_ordered_list_preserves_mixed_separator_order() {
        let parsed = split_ordered_list("zh\nen,ja");

        assert_eq!(parsed, vec!["zh", "en", "ja"]);
    }

    #[test]
    fn split_ordered_list_ignores_empty_tokens() {
        let parsed = split_ordered_list(", , zh,\n\nen ,,");

        assert_eq!(parsed, vec!["zh", "en"]);
    }

    #[test]
    fn split_ordered_list_keeps_duplicates_for_caller_level_dedup() {
        let parsed = split_ordered_list("zh,en,zh");

        assert_eq!(parsed, vec!["zh", "en", "zh"]);
    }

    #[test]
    fn parse_ordered_list_with_supports_normalization_hook() {
        let parsed = parse_ordered_list_with(" ZH, en ", |token| {
            Ok::<Option<String>, FixtureError>(Some(token.to_ascii_lowercase()))
        })
        .expect("normalization should succeed");

        assert_eq!(parsed, vec!["zh", "en"]);
    }

    #[test]
    fn parse_ordered_list_with_supports_skip_hook() {
        let parsed = parse_ordered_list_with("en,zh,ja", |token| {
            if token == "en" {
                return Ok::<Option<String>, FixtureError>(None);
            }

            Ok(Some(token.to_string()))
        })
        .expect("skip hook should succeed");

        assert_eq!(parsed, vec!["zh", "ja"]);
    }

    #[test]
    fn parse_ordered_list_with_surfaces_typed_errors() {
        let error = parse_ordered_list_with("en,unknown,zh", |token| match token {
            "en" | "zh" => Ok::<Option<String>, FixtureError>(Some(token.to_string())),
            other => Err(FixtureError::UnsupportedToken(other.to_string())),
        })
        .expect_err("unsupported token should fail");

        assert_eq!(error, FixtureError::UnsupportedToken("unknown".to_string()));
    }
}
