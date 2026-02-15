use alfred_core::{Feedback, Item};
use reqwest::Url;

use crate::bilibili_api::SuggestionTerm;

const NO_SUGGESTIONS_TITLE: &str = "No suggestions found";
const NO_SUGGESTIONS_SUBTITLE: &str = "Press Enter to search bilibili directly.";
const DIRECT_SEARCH_TITLE: &str = "Search bilibili directly";
const RESULT_SUBTITLE_PREFIX: &str = "Search bilibili for ";
const ERROR_TITLE: &str = "Bilibili search failed";
const SUBTITLE_MAX_CHARS: usize = 120;

pub fn suggestions_to_feedback(query: &str, suggestions: &[SuggestionTerm]) -> Feedback {
    let mut items = Vec::new();

    for suggestion in suggestions {
        let value = suggestion.value.trim();
        if value.is_empty() {
            continue;
        }

        items.push(
            Item::new(value)
                .with_subtitle(single_line_subtitle(
                    &format!("{RESULT_SUBTITLE_PREFIX}{value}"),
                    SUBTITLE_MAX_CHARS,
                ))
                .with_arg(search_url(value))
                .with_autocomplete(value),
        );
    }

    if items.is_empty() {
        let fallback_query = query.trim();
        let fallback_query = if fallback_query.is_empty() {
            "bilibili".to_string()
        } else {
            fallback_query.to_string()
        };

        return Feedback::new(vec![
            Item::new(NO_SUGGESTIONS_TITLE)
                .with_subtitle(NO_SUGGESTIONS_SUBTITLE)
                .with_valid(false),
            Item::new(DIRECT_SEARCH_TITLE)
                .with_subtitle(format!("Open bilibili search for {fallback_query}"))
                .with_arg(search_url(&fallback_query)),
        ]);
    }

    Feedback::new(items)
}

#[cfg_attr(not(test), allow(dead_code))]
pub fn error_feedback(message: &str) -> Feedback {
    Feedback::new(vec![
        Item::new(ERROR_TITLE)
            .with_subtitle(single_line_subtitle(message, SUBTITLE_MAX_CHARS))
            .with_valid(false),
    ])
}

pub fn search_url(query: &str) -> String {
    let mut url =
        Url::parse("https://search.bilibili.com/all").expect("bilibili search base url must parse");
    url.query_pairs_mut().append_pair("keyword", query);
    url.to_string()
}

fn single_line_subtitle(input: &str, max_chars: usize) -> String {
    let compact = input.split_whitespace().collect::<Vec<_>>().join(" ");

    if compact.chars().count() <= max_chars {
        return compact;
    }

    if max_chars <= 3 {
        return "...".chars().take(max_chars).collect();
    }

    let truncated: String = compact.chars().take(max_chars - 3).collect();
    format!("{truncated}...")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn term(value: &str) -> SuggestionTerm {
        SuggestionTerm {
            value: value.to_string(),
        }
    }

    #[test]
    fn feedback_maps_suggestions_to_alfred_items() {
        let feedback = suggestions_to_feedback("naruto", &[term("naruto"), term("naruto mobile")]);
        assert_eq!(feedback.items.len(), 2);
        assert_eq!(feedback.items[0].title, "naruto");
        assert_eq!(
            feedback.items[0].arg.as_deref(),
            Some("https://search.bilibili.com/all?keyword=naruto")
        );
        assert_eq!(feedback.items[0].autocomplete.as_deref(), Some("naruto"));
    }

    #[test]
    fn feedback_no_results_returns_direct_search_item() {
        let feedback = suggestions_to_feedback("naruto", &[]);
        assert_eq!(feedback.items.len(), 2);
        assert_eq!(feedback.items[0].title, NO_SUGGESTIONS_TITLE);
        assert_eq!(feedback.items[0].valid, Some(false));
        assert_eq!(feedback.items[1].title, DIRECT_SEARCH_TITLE);
    }

    #[test]
    fn url_builder_encodes_query_for_bilibili_search() {
        assert_eq!(
            search_url("naruto mobile"),
            "https://search.bilibili.com/all?keyword=naruto+mobile"
        );
    }

    #[test]
    fn error_feedback_returns_single_invalid_item() {
        let feedback = error_feedback("request timed out\nretry later");
        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].title, ERROR_TITLE);
        assert_eq!(feedback.items[0].valid, Some(false));
    }
}
