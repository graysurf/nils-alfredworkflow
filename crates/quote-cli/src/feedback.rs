use alfred_core::{Feedback, Item};

const ITEM_SUBTITLE: &str = "Press Enter to copy quote.";
const EMPTY_CACHE_TITLE: &str = "No quotes cached yet";
const EMPTY_CACHE_SUBTITLE: &str = "Refresh will run automatically; retry shortly.";
const NO_MATCH_TITLE: &str = "No quotes match query";
const NO_MATCH_SUBTITLE: &str = "Try broader keywords or clear query text.";
const REFRESH_UNAVAILABLE_TITLE: &str = "Quote refresh unavailable";

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
        let subtitle = author_name.unwrap_or(ITEM_SUBTITLE);

        items.push(
            Item::new(quote_text)
                .with_subtitle(subtitle)
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
