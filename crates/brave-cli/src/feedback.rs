use alfred_core::{Feedback, Item};

use crate::brave_api::WebSearchResult;

const NO_RESULTS_TITLE: &str = "No results found";
const NO_RESULTS_SUBTITLE: &str = "Try a different search query";
#[cfg_attr(not(test), allow(dead_code))]
const ERROR_TITLE: &str = "Brave search failed";
const EMPTY_DESCRIPTION_SUBTITLE: &str = "No description available";
const SUBTITLE_MAX_CHARS: usize = 120;

pub fn search_results_to_feedback(results: &[WebSearchResult]) -> Feedback {
    if results.is_empty() {
        return no_results_feedback();
    }

    let items = results.iter().map(result_to_item).collect();
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

fn result_to_item(result: &WebSearchResult) -> Item {
    let title = result.title.trim();
    let normalized_title = if title.is_empty() {
        "(untitled result)"
    } else {
        title
    };

    let subtitle = if result.description.trim().is_empty() {
        EMPTY_DESCRIPTION_SUBTITLE.to_string()
    } else {
        single_line_subtitle(&result.description, SUBTITLE_MAX_CHARS)
    };

    Item::new(normalized_title)
        .with_subtitle(subtitle)
        .with_arg(result.url.trim())
}

fn no_results_feedback() -> Feedback {
    Feedback::new(vec![
        Item::new(NO_RESULTS_TITLE)
            .with_subtitle(NO_RESULTS_SUBTITLE)
            .with_valid(false),
    ])
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

    fn fixture_result(description: &str) -> WebSearchResult {
        WebSearchResult {
            title: "Rust Language".to_string(),
            url: "https://www.rust-lang.org/".to_string(),
            description: description.to_string(),
        }
    }

    #[test]
    fn maps_search_result_to_alfred_item() {
        let feedback = search_results_to_feedback(&[fixture_result("Build reliable software")]);
        let item = feedback.items.first().expect("expected one item");

        assert_eq!(item.title, "Rust Language");
        assert_eq!(
            item.subtitle.as_deref(),
            Some("Build reliable software"),
            "subtitle should map from description"
        );
        assert_eq!(
            item.arg.as_deref(),
            Some("https://www.rust-lang.org/"),
            "arg should map to source URL"
        );
    }

    #[test]
    fn truncates_long_snippet_deterministically() {
        let long_snippet = " line1\nline2\tline3 ".repeat(30);
        let feedback = search_results_to_feedback(&[fixture_result(&long_snippet)]);
        let subtitle = feedback.items[0]
            .subtitle
            .as_deref()
            .expect("subtitle should exist")
            .to_string();

        let feedback_again = search_results_to_feedback(&[fixture_result(&long_snippet)]);
        let subtitle_again = feedback_again.items[0]
            .subtitle
            .as_deref()
            .expect("subtitle should exist")
            .to_string();

        assert_eq!(
            subtitle, subtitle_again,
            "truncation should be deterministic"
        );
        assert!(!subtitle.contains('\n'), "subtitle should be single-line");
        assert!(!subtitle.contains('\t'), "subtitle should normalize tabs");
        assert!(
            subtitle.chars().count() <= SUBTITLE_MAX_CHARS,
            "subtitle should not exceed max length"
        );
    }

    #[test]
    fn no_results_item_is_invalid_and_has_expected_title() {
        let feedback = search_results_to_feedback(&[]);
        let item = feedback.items.first().expect("fallback item should exist");

        assert_eq!(item.title, NO_RESULTS_TITLE);
        assert_eq!(item.valid, Some(false));
        assert!(item.arg.is_none(), "fallback item must not include arg");
    }

    #[test]
    fn empty_description_uses_fallback_subtitle() {
        let feedback = search_results_to_feedback(&[fixture_result("  ")]);
        let item = feedback.items.first().expect("expected one item");

        assert_eq!(item.subtitle.as_deref(), Some(EMPTY_DESCRIPTION_SUBTITLE));
    }

    #[test]
    fn error_feedback_returns_single_invalid_item() {
        let feedback = error_feedback("request timed out\nplease retry");

        assert_eq!(
            feedback.items.len(),
            1,
            "error feedback should contain one item"
        );
        assert_eq!(feedback.items[0].title, ERROR_TITLE);
        assert_eq!(feedback.items[0].valid, Some(false));
        assert!(
            feedback.items[0]
                .subtitle
                .as_deref()
                .is_some_and(|value| !value.contains('\n')),
            "error subtitle should be single-line"
        );
    }
}
