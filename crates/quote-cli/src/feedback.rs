use alfred_core::{Feedback, Item};

const ITEM_SUBTITLE: &str = "Press Enter to copy quote.";
const EMPTY_CACHE_TITLE: &str = "No quotes cached yet";
const EMPTY_CACHE_SUBTITLE: &str = "Refresh will run automatically; retry shortly.";
const NO_MATCH_TITLE: &str = "No quotes match query";
const NO_MATCH_SUBTITLE: &str = "Try broader keywords or clear query text.";
const REFRESH_UNAVAILABLE_TITLE: &str = "Quote refresh unavailable";
const TITLE_WRAP_CHARS: usize = 56;

pub fn quotes_to_feedback(
    quotes: &[String],
    display_count: usize,
    query: &str,
    refresh_error: Option<&str>,
) -> Feedback {
    let filtered = filter_quotes(quotes, query);

    if filtered.is_empty() {
        if !query.trim().is_empty() {
            return single_invalid_item(NO_MATCH_TITLE, NO_MATCH_SUBTITLE);
        }

        if let Some(message) = refresh_error {
            return single_invalid_item(REFRESH_UNAVAILABLE_TITLE, &normalize_subtitle(message));
        }

        return single_invalid_item(EMPTY_CACHE_TITLE, EMPTY_CACHE_SUBTITLE);
    }

    let mut items = Vec::new();
    for quote_line in filtered.iter().rev().take(display_count) {
        let (quote_text, author_name) = parse_quote_line(quote_line);
        let (display_title, display_subtitle) = build_display_lines(quote_text, author_name);

        items.push(
            Item::new(display_title)
                .with_subtitle(display_subtitle)
                .with_arg(quote_text)
                .with_valid(true),
        );
    }

    Feedback::new(items)
}

fn filter_quotes<'a>(quotes: &'a [String], query: &str) -> Vec<&'a String> {
    let query = query.trim();
    if query.is_empty() {
        return quotes.iter().collect();
    }

    let needle = query.to_ascii_lowercase();
    quotes
        .iter()
        .filter(|quote| quote.to_ascii_lowercase().contains(&needle))
        .collect()
}

fn single_invalid_item(title: &str, subtitle: &str) -> Feedback {
    Feedback::new(vec![
        Item::new(title).with_subtitle(subtitle).with_valid(false),
    ])
}

fn parse_quote_line(line: &str) -> (&str, Option<&str>) {
    let trimmed = line.trim();
    if let Some((quote, author)) = trimmed.rsplit_once(" — ") {
        let quote = strip_wrapping_quotes(quote.trim());
        let author = author.trim();
        if !quote.is_empty() && !author.is_empty() {
            return (quote, Some(author));
        }
    }

    (strip_wrapping_quotes(trimmed), None)
}

fn strip_wrapping_quotes(raw: &str) -> &str {
    let trimmed = raw.trim();
    for (open, close) in [("\"", "\""), ("“", "”")] {
        if let Some(inner) = trimmed
            .strip_prefix(open)
            .and_then(|rest| rest.strip_suffix(close))
        {
            return inner.trim();
        }
    }

    trimmed
}

fn normalize_subtitle(raw: &str) -> String {
    let compact = raw
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .trim()
        .to_string();

    if compact.is_empty() {
        "Refresh failed; retry later.".to_string()
    } else {
        compact
    }
}

fn build_display_lines(quote_text: &str, author_name: Option<&str>) -> (String, String) {
    let (title, continuation) = split_quote_for_two_lines(quote_text, TITLE_WRAP_CHARS);

    let subtitle = match (continuation, author_name) {
        (Some(quote_line_2), Some(author)) => format!("{quote_line_2} — {author}"),
        (Some(quote_line_2), None) => quote_line_2,
        (None, Some(author)) => author.to_string(),
        (None, None) => ITEM_SUBTITLE.to_string(),
    };

    (title, subtitle)
}

fn split_quote_for_two_lines(quote_text: &str, max_title_chars: usize) -> (String, Option<String>) {
    let normalized = quote_text.split_whitespace().collect::<Vec<_>>().join(" ");
    if normalized.is_empty() {
        return (String::new(), None);
    }

    if normalized.chars().count() <= max_title_chars {
        return (normalized, None);
    }

    let words: Vec<&str> = normalized.split(' ').collect();
    let mut title = String::new();
    let mut consumed = 0usize;

    for (idx, word) in words.iter().enumerate() {
        let current_len = title.chars().count();
        let word_len = word.chars().count();
        let next_len = if title.is_empty() {
            word_len
        } else {
            current_len + 1 + word_len
        };

        if next_len > max_title_chars {
            if title.is_empty() {
                let first_line: String = word.chars().take(max_title_chars).collect();
                let rest_of_word: String = word.chars().skip(max_title_chars).collect();
                let mut remainder_parts = Vec::new();
                if !rest_of_word.is_empty() {
                    remainder_parts.push(rest_of_word);
                }
                remainder_parts.extend(words.iter().skip(idx + 1).map(|part| (*part).to_string()));
                return (first_line, Some(remainder_parts.join(" ")));
            }
            break;
        }

        if !title.is_empty() {
            title.push(' ');
        }
        title.push_str(word);
        consumed = idx + 1;
    }

    let remainder = words
        .iter()
        .skip(consumed)
        .copied()
        .collect::<Vec<_>>()
        .join(" ");

    (title, Some(remainder))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture_quotes() -> Vec<String> {
        vec![
            "\"stay hungry\" — steve jobs".to_string(),
            "\"simplicity is the soul of efficiency\" — austin freeman".to_string(),
            "\"fortune favors the bold\" — virgil".to_string(),
        ]
    }

    #[test]
    fn feedback_respects_display_count() {
        let feedback = quotes_to_feedback(&fixture_quotes(), 2, "", None);

        assert_eq!(feedback.items.len(), 2);
        assert_eq!(feedback.items[0].title, "fortune favors the bold");
        assert_eq!(feedback.items[0].subtitle.as_deref(), Some("virgil"));
        assert_eq!(
            feedback.items[0].arg.as_deref(),
            Some("fortune favors the bold")
        );

        assert_eq!(
            feedback.items[1].title,
            "simplicity is the soul of efficiency"
        );
        assert_eq!(
            feedback.items[1].subtitle.as_deref(),
            Some("austin freeman")
        );
        assert_eq!(
            feedback.items[1].arg.as_deref(),
            Some("simplicity is the soul of efficiency")
        );
    }

    #[test]
    fn feedback_filters_by_query_case_insensitive() {
        let feedback = quotes_to_feedback(&fixture_quotes(), 5, "FORTUNE", None);

        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].title, "fortune favors the bold");
        assert_eq!(feedback.items[0].subtitle.as_deref(), Some("virgil"));
    }

    #[test]
    fn feedback_strips_curly_wrapping_quotes() {
        let feedback = quotes_to_feedback(&["“hello world” — tester".to_string()], 5, "", None);

        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].title, "hello world");
        assert_eq!(feedback.items[0].arg.as_deref(), Some("hello world"));
    }

    #[test]
    fn feedback_uses_default_subtitle_when_author_missing() {
        let feedback = quotes_to_feedback(&["quote only".to_string()], 5, "", None);

        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].title, "quote only");
        assert_eq!(feedback.items[0].subtitle.as_deref(), Some(ITEM_SUBTITLE));
        assert_eq!(feedback.items[0].arg.as_deref(), Some("quote only"));
    }

    #[test]
    fn feedback_wraps_long_quote_into_second_line_and_preserves_author() {
        let quote = "it is up to each of us to sing as we feel moved by the overall song of life";
        let feedback = quotes_to_feedback(&[format!("\"{quote}\" — ming-dao deng")], 5, "", None);

        assert_eq!(feedback.items.len(), 1);
        let item = &feedback.items[0];
        let subtitle = item
            .subtitle
            .as_deref()
            .expect("subtitle should exist for wrapped quote");
        let (line_2, author) = subtitle
            .rsplit_once(" — ")
            .expect("wrapped quote subtitle should keep author");

        assert_eq!(author, "ming-dao deng");
        assert!(item.title.chars().count() <= TITLE_WRAP_CHARS);
        assert!(!line_2.is_empty());

        let reconstructed = format!("{} {}", item.title, line_2)
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ");
        assert_eq!(reconstructed, quote);
        assert_eq!(item.arg.as_deref(), Some(quote));
    }

    #[test]
    fn feedback_returns_no_match_item_when_query_has_no_hits() {
        let feedback = quotes_to_feedback(&fixture_quotes(), 5, "xyz", None);

        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].title, NO_MATCH_TITLE);
        assert_eq!(feedback.items[0].valid, Some(false));
    }

    #[test]
    fn feedback_returns_empty_cache_item_when_no_quotes() {
        let feedback = quotes_to_feedback(&[], 3, "", None);

        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].title, EMPTY_CACHE_TITLE);
        assert_eq!(feedback.items[0].valid, Some(false));
    }

    #[test]
    fn feedback_returns_refresh_unavailable_item_when_cache_empty_and_refresh_failed() {
        let feedback = quotes_to_feedback(&[], 3, "", Some("zenquotes api error (503): HTTP 503"));

        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].title, REFRESH_UNAVAILABLE_TITLE);
        assert_eq!(feedback.items[0].valid, Some(false));
    }
}
