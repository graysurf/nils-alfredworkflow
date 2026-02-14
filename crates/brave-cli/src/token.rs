const SEARCH_PREFIX: &str = "res::";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum QueryToken {
    Empty,
    Suggest { query: String },
    Search { query: String },
    SearchMissingQuery,
}

pub fn parse_query_token(raw_input: &str) -> QueryToken {
    let input = raw_input.trim();
    if input.is_empty() {
        return QueryToken::Empty;
    }

    if let Some(rest) = input.strip_prefix(SEARCH_PREFIX) {
        let query = rest.trim();
        if query.is_empty() {
            QueryToken::SearchMissingQuery
        } else {
            QueryToken::Search {
                query: query.to_string(),
            }
        }
    } else {
        QueryToken::Suggest {
            query: input.to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn token_parser_detects_empty_input() {
        assert_eq!(parse_query_token(" \t "), QueryToken::Empty);
    }

    #[test]
    fn token_parser_routes_plain_text_to_suggest_mode() {
        assert_eq!(
            parse_query_token(" rust "),
            QueryToken::Suggest {
                query: "rust".to_string(),
            }
        );
    }

    #[test]
    fn token_parser_routes_result_prefix_to_search_mode() {
        assert_eq!(
            parse_query_token("res::rust tutorial"),
            QueryToken::Search {
                query: "rust tutorial".to_string(),
            }
        );
    }

    #[test]
    fn token_parser_trims_result_query_value() {
        assert_eq!(
            parse_query_token("res::   rust book  "),
            QueryToken::Search {
                query: "rust book".to_string(),
            }
        );
    }

    #[test]
    fn token_parser_flags_missing_result_query() {
        assert_eq!(parse_query_token("res::  "), QueryToken::SearchMissingQuery);
    }

    #[test]
    fn token_parser_is_case_sensitive_for_prefix() {
        assert_eq!(
            parse_query_token("RES::rust"),
            QueryToken::Suggest {
                query: "RES::rust".to_string(),
            }
        );
    }
}
