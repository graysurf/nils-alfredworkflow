use alfred_core::{Feedback, Item};

use crate::wiki_api::WikiSearchResult;

const NO_RESULTS_TITLE: &str = "No articles found";
const NO_RESULTS_SUBTITLE: &str = "Try broader keywords or switch WIKI_LANGUAGE.";
const LANGUAGE_CURRENT_TITLE_PREFIX: &str = "Current language:";
const LANGUAGE_SWITCH_TITLE_PREFIX: &str = "Search in";
const LANGUAGE_SWITCH_ARG_PREFIX: &str = "wiki-requery:";
#[cfg_attr(not(test), allow(dead_code))]
const ERROR_TITLE: &str = "Wiki search failed";
const EMPTY_DESCRIPTION_SUBTITLE: &str = "No description available";
const SUBTITLE_MAX_CHARS: usize = 120;

pub fn search_results_to_feedback(
    language: &str,
    query: &str,
    language_options: &[String],
    results: &[WikiSearchResult],
) -> Feedback {
    let mut items = language_switch_items(language, query, language_options);

    if results.is_empty() {
        items.push(no_results_item());
        return Feedback::new(items);
    }

    items.extend(
        results
            .iter()
            .map(|result| result_to_item(language, result)),
    );
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

fn result_to_item(language: &str, result: &WikiSearchResult) -> Item {
    let title = result.title.trim();
    let normalized_title = if title.is_empty() {
        "(untitled article)"
    } else {
        title
    };

    let normalized_snippet = normalize_snippet(&result.snippet);
    let subtitle = if normalized_snippet.is_empty() {
        EMPTY_DESCRIPTION_SUBTITLE.to_string()
    } else {
        single_line_subtitle(&normalized_snippet, SUBTITLE_MAX_CHARS)
    };

    Item::new(normalized_title)
        .with_subtitle(subtitle)
        .with_arg(canonical_article_url(language, result.pageid))
}

#[cfg_attr(not(test), allow(dead_code))]
fn canonical_article_url(language: &str, pageid: u64) -> String {
    format!("https://{language}.wikipedia.org/?curid={pageid}")
}

fn no_results_item() -> Item {
    Item::new(NO_RESULTS_TITLE)
        .with_subtitle(NO_RESULTS_SUBTITLE)
        .with_valid(false)
}

fn language_switch_items(current_language: &str, query: &str, options: &[String]) -> Vec<Item> {
    options
        .iter()
        .map(|candidate| {
            if candidate == current_language {
                return Item::new(format!("{LANGUAGE_CURRENT_TITLE_PREFIX} {candidate}"))
                    .with_subtitle(format!("Searching Wikipedia in {candidate}."))
                    .with_valid(false);
            }

            let subtitle = single_line_subtitle(
                &format!("Press Enter to requery \"{query}\" in {candidate}."),
                SUBTITLE_MAX_CHARS,
            );
            Item::new(format!(
                "{LANGUAGE_SWITCH_TITLE_PREFIX} {candidate} Wikipedia"
            ))
            .with_subtitle(subtitle)
            .with_arg(switch_language_arg(candidate, query))
            .with_valid(true)
        })
        .collect()
}

fn switch_language_arg(language: &str, query: &str) -> String {
    let compact_query = query.split_whitespace().collect::<Vec<_>>().join(" ");
    format!("{LANGUAGE_SWITCH_ARG_PREFIX}{language}:{compact_query}")
}

fn normalize_snippet(input: &str) -> String {
    let without_tags = strip_html_tags(input);
    let decoded = decode_html_entities(&without_tags).replace('\u{00A0}', " ");

    decoded
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .trim()
        .to_string()
}

fn strip_html_tags(input: &str) -> String {
    let mut output = String::with_capacity(input.len());
    let mut in_tag = false;

    for ch in input.chars() {
        match ch {
            '<' => in_tag = true,
            '>' => {
                if in_tag {
                    in_tag = false;
                } else {
                    output.push(ch);
                }
            }
            _ if !in_tag => output.push(ch),
            _ => {}
        }
    }

    output
}

fn decode_html_entities(input: &str) -> String {
    input
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&nbsp;", " ")
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

    fn fixture_result(snippet: &str) -> WikiSearchResult {
        WikiSearchResult {
            title: "Rust (programming language)".to_string(),
            snippet: snippet.to_string(),
            pageid: 36192,
        }
    }

    #[test]
    fn feedback_maps_result_to_alfred_item() {
        let feedback =
            search_results_to_feedback("en", "rust", &[], &[fixture_result("A language")]);
        let item = feedback.items.first().expect("expected one item");

        assert_eq!(item.title, "Rust (programming language)");
        assert_eq!(item.subtitle.as_deref(), Some("A language"));
        assert_eq!(
            item.arg.as_deref(),
            Some("https://en.wikipedia.org/?curid=36192")
        );
    }

    #[test]
    fn feedback_strips_html_tags_and_truncates() {
        let snippet = "<span class=\"searchmatch\">Rust</span> &amp; systems\nprogramming &quot;language&quot;\t".repeat(20);

        let feedback = search_results_to_feedback("en", "rust", &[], &[fixture_result(&snippet)]);
        let subtitle = feedback.items[0]
            .subtitle
            .as_deref()
            .expect("subtitle should exist")
            .to_string();

        let feedback_again =
            search_results_to_feedback("en", "rust", &[], &[fixture_result(&snippet)]);
        let subtitle_again = feedback_again.items[0]
            .subtitle
            .as_deref()
            .expect("subtitle should exist")
            .to_string();

        assert_eq!(
            subtitle, subtitle_again,
            "truncation should be deterministic"
        );
        assert!(!subtitle.contains('<'));
        assert!(!subtitle.contains('>'));
        assert!(!subtitle.contains('\n'));
        assert!(!subtitle.contains('\t'));
        assert!(subtitle.contains("Rust & systems"));
        assert!(subtitle.chars().count() <= SUBTITLE_MAX_CHARS);
    }

    #[test]
    fn feedback_no_results_item_is_invalid_and_has_expected_title() {
        let feedback = search_results_to_feedback("en", "rust", &[], &[]);
        let item = feedback.items.first().expect("fallback item should exist");

        assert_eq!(item.title, NO_RESULTS_TITLE);
        assert_eq!(item.subtitle.as_deref(), Some(NO_RESULTS_SUBTITLE));
        assert_eq!(item.valid, Some(false));
        assert!(item.arg.is_none());
    }

    #[test]
    fn feedback_empty_snippet_uses_fallback_subtitle() {
        let feedback =
            search_results_to_feedback("en", "rust", &[], &[fixture_result("  <b> </b>  ")]);
        let item = feedback.items.first().expect("expected one item");

        assert_eq!(item.subtitle.as_deref(), Some(EMPTY_DESCRIPTION_SUBTITLE));
    }

    #[test]
    fn feedback_language_switch_items_follow_configured_order() {
        let options = vec!["zh".to_string(), "en".to_string(), "ja".to_string()];
        let feedback = search_results_to_feedback("en", "rust", &options, &[]);

        assert_eq!(feedback.items[0].title, "Search in zh Wikipedia");
        assert_eq!(feedback.items[1].title, "Current language: en");
        assert_eq!(feedback.items[2].title, "Search in ja Wikipedia");
        assert_eq!(feedback.items[0].valid, Some(true));
        assert_eq!(feedback.items[1].valid, Some(false));
        assert_eq!(feedback.items[2].valid, Some(true));
    }

    #[test]
    fn feedback_language_switch_items_use_requery_arg_contract() {
        let options = vec!["zh".to_string(), "en".to_string()];
        let feedback = search_results_to_feedback("en", "rust lang", &options, &[]);

        assert_eq!(
            feedback.items[0].arg.as_deref(),
            Some("wiki-requery:zh:rust lang")
        );
    }

    #[test]
    fn error_feedback_returns_single_invalid_item() {
        let feedback = error_feedback("request timed out\nplease retry");

        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].title, ERROR_TITLE);
        assert_eq!(feedback.items[0].valid, Some(false));
        assert!(
            feedback.items[0]
                .subtitle
                .as_deref()
                .is_some_and(|value| !value.contains('\n'))
        );
    }

    #[test]
    fn url_builds_curid_canonical_url() {
        assert_eq!(
            canonical_article_url("ja", 12345),
            "https://ja.wikipedia.org/?curid=12345"
        );
    }
}
