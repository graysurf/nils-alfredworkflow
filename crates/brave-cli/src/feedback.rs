use alfred_core::{Feedback, Item};
use reqwest::Url;

use crate::brave_api::WebSearchResult;

const EMPTY_INPUT_TITLE: &str = "Type a query for suggestions";
const EMPTY_INPUT_SUBTITLE: &str = "Select a suggestion, or use res::<query> for direct results";
const MISSING_SEARCH_TOKEN_TITLE: &str = "Result token is incomplete";
const MISSING_SEARCH_TOKEN_SUBTITLE: &str = "Use res::<query>, for example res::rust tutorial";
const SUGGEST_EMPTY_TITLE: &str = "No suggestions found";
const SUGGEST_EMPTY_SUBTITLE: &str = "Type another query to fetch suggestions";
const SUGGEST_GUIDANCE: &str = "Press Tab to load search results";

const NO_RESULTS_TITLE: &str = "No results found";
const NO_RESULTS_SUBTITLE: &str = "Try a different search query";
#[cfg_attr(not(test), allow(dead_code))]
const ERROR_TITLE: &str = "Brave search failed";
const EMPTY_DESCRIPTION_SUBTITLE: &str = "No description available";
const SUBTITLE_MAX_CHARS: usize = 120;

pub fn empty_input_feedback() -> Feedback {
    single_invalid_item(EMPTY_INPUT_TITLE, EMPTY_INPUT_SUBTITLE)
}

pub fn missing_search_target_feedback() -> Feedback {
    single_invalid_item(MISSING_SEARCH_TOKEN_TITLE, MISSING_SEARCH_TOKEN_SUBTITLE)
}

pub fn suggestions_to_feedback(query: &str, suggestions: &[String]) -> Feedback {
    let mut candidates = Vec::new();
    if let Some(base_query) = normalize_text(query) {
        candidates.push(base_query);
    }

    for candidate in suggestions {
        let Some(normalized) = normalize_text(candidate) else {
            continue;
        };
        if candidates
            .iter()
            .any(|existing| existing.eq_ignore_ascii_case(&normalized))
        {
            continue;
        }
        candidates.push(normalized);
    }

    if candidates.is_empty() {
        return single_invalid_item(SUGGEST_EMPTY_TITLE, SUGGEST_EMPTY_SUBTITLE);
    }

    let items = candidates
        .into_iter()
        .map(|candidate| {
            Item::new(candidate.clone())
                .with_subtitle(format!("Search \"{candidate}\" | {SUGGEST_GUIDANCE}"))
                .with_autocomplete(format!("res::{candidate}"))
                .with_valid(false)
        })
        .collect();
    Feedback::new(items)
}

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

    let base_subtitle = if result.description.trim().is_empty() {
        EMPTY_DESCRIPTION_SUBTITLE.to_string()
    } else {
        single_line_subtitle(&result.description, SUBTITLE_MAX_CHARS)
    };
    let subtitle = prefix_source_domain(result.url.trim(), &base_subtitle);

    Item::new(normalized_title)
        .with_subtitle(subtitle)
        .with_arg(result.url.trim())
}

fn no_results_feedback() -> Feedback {
    single_invalid_item(NO_RESULTS_TITLE, NO_RESULTS_SUBTITLE)
}

fn single_invalid_item(title: &str, subtitle: &str) -> Feedback {
    Feedback::new(vec![
        Item::new(title).with_subtitle(subtitle).with_valid(false),
    ])
}

fn normalize_text(input: &str) -> Option<String> {
    let compact = input.split_whitespace().collect::<Vec<_>>().join(" ");
    let trimmed = compact.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn prefix_source_domain(url: &str, subtitle: &str) -> String {
    let Some(domain) = normalize_source_domain(url) else {
        return subtitle.to_string();
    };
    single_line_subtitle(&format!("{domain} | {subtitle}"), SUBTITLE_MAX_CHARS)
}

fn normalize_source_domain(url: &str) -> Option<String> {
    let parsed = Url::parse(url.trim()).ok()?;
    let host = parsed.host_str()?.trim().to_ascii_lowercase();
    if host.is_empty() {
        return None;
    }

    let normalized = host.strip_prefix("www.").unwrap_or(&host).trim();
    if normalized.is_empty() {
        None
    } else {
        Some(normalized.to_string())
    }
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
    fn empty_input_feedback_returns_single_invalid_item() {
        let feedback = empty_input_feedback();
        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].title, EMPTY_INPUT_TITLE);
        assert_eq!(feedback.items[0].valid, Some(false));
    }

    #[test]
    fn missing_search_target_feedback_returns_single_invalid_item() {
        let feedback = missing_search_target_feedback();
        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].title, MISSING_SEARCH_TOKEN_TITLE);
        assert_eq!(feedback.items[0].valid, Some(false));
    }

    #[test]
    fn suggestions_feedback_includes_base_query_and_autocomplete_tokens() {
        let feedback = suggestions_to_feedback(
            "rust",
            &[
                "rust language".to_string(),
                "Rust Language".to_string(),
                "rust book".to_string(),
            ],
        );

        assert_eq!(feedback.items.len(), 3);
        assert_eq!(feedback.items[0].title, "rust");
        assert_eq!(feedback.items[0].autocomplete.as_deref(), Some("res::rust"));
        assert_eq!(
            feedback.items[1].autocomplete.as_deref(),
            Some("res::rust language")
        );
        assert_eq!(
            feedback.items[2].autocomplete.as_deref(),
            Some("res::rust book")
        );
        assert!(
            feedback.items[0]
                .subtitle
                .as_deref()
                .is_some_and(|subtitle| subtitle.contains("Press Tab")),
            "suggest subtitle should include transition guidance"
        );
        assert!(feedback.items.iter().all(|item| item.valid == Some(false)));
    }

    #[test]
    fn suggestions_feedback_returns_no_result_fallback_when_candidates_are_empty() {
        let feedback = suggestions_to_feedback("  ", &[String::new()]);
        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].title, SUGGEST_EMPTY_TITLE);
        assert_eq!(feedback.items[0].valid, Some(false));
    }

    #[test]
    fn maps_search_result_to_alfred_item() {
        let feedback = search_results_to_feedback(&[fixture_result("Build reliable software")]);
        let item = feedback.items.first().expect("expected one item");

        assert_eq!(item.title, "Rust Language");
        assert_eq!(
            item.subtitle.as_deref(),
            Some("rust-lang.org | Build reliable software"),
            "subtitle should include source domain and description"
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

        assert_eq!(
            item.subtitle.as_deref(),
            Some("rust-lang.org | No description available")
        );
    }

    #[test]
    fn source_domain_prefix_strips_www_prefix() {
        let feedback = search_results_to_feedback(&[WebSearchResult {
            title: "gamer".to_string(),
            url: "https://www.gamer.com/article".to_string(),
            description: "news".to_string(),
        }]);
        let item = feedback.items.first().expect("expected one item");

        assert_eq!(item.subtitle.as_deref(), Some("gamer.com | news"));
    }

    #[test]
    fn source_domain_prefix_falls_back_when_url_is_unparseable() {
        let feedback = search_results_to_feedback(&[WebSearchResult {
            title: "local".to_string(),
            url: "not-a-url".to_string(),
            description: "snippet".to_string(),
        }]);
        let item = feedback.items.first().expect("expected one item");

        assert_eq!(item.subtitle.as_deref(), Some("snippet"));
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
