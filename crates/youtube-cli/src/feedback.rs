use alfred_core::{Feedback, Item};

use crate::youtube_api::VideoSearchResult;

const NO_RESULTS_TITLE: &str = "No videos found";
const NO_RESULTS_SUBTITLE: &str = "Try a different search query";
#[cfg_attr(not(test), allow(dead_code))]
const ERROR_TITLE: &str = "YouTube search failed";
const EMPTY_DESCRIPTION_SUBTITLE: &str = "No description available";
const SUBTITLE_MAX_CHARS: usize = 120;

pub fn videos_to_feedback(videos: &[VideoSearchResult]) -> Feedback {
    if videos.is_empty() {
        return no_results_feedback();
    }

    let items = videos.iter().map(video_to_item).collect();
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

pub fn watch_url(video_id: &str) -> String {
    format!("https://www.youtube.com/watch?v={video_id}")
}

fn video_to_item(video: &VideoSearchResult) -> Item {
    let title = video.title.trim();
    let normalized_title = if title.is_empty() {
        "(untitled video)"
    } else {
        title
    };

    let subtitle = if video.description.trim().is_empty() {
        EMPTY_DESCRIPTION_SUBTITLE.to_string()
    } else {
        single_line_subtitle(&video.description, SUBTITLE_MAX_CHARS)
    };

    Item::new(normalized_title)
        .with_subtitle(subtitle)
        .with_arg(watch_url(video.video_id.trim()))
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

    fn fixture_video(description: &str) -> VideoSearchResult {
        VideoSearchResult {
            video_id: "abc123".to_string(),
            title: "Rust Tutorial".to_string(),
            description: description.to_string(),
        }
    }

    #[test]
    fn feedback_maps_videos_to_alfred_items() {
        let feedback = videos_to_feedback(&[fixture_video("Build fast apps")]);
        let item = feedback.items.first().expect("expected one item");

        assert_eq!(item.title, "Rust Tutorial");
        assert_eq!(
            item.subtitle.as_deref(),
            Some("Build fast apps"),
            "subtitle should map from description"
        );
        assert_eq!(
            item.arg.as_deref(),
            Some("https://www.youtube.com/watch?v=abc123"),
            "arg should map to canonical watch URL"
        );
    }

    #[test]
    fn feedback_subtitle_truncation_is_deterministic_and_single_line() {
        let long_description = " line1\nline2\tline3 ".repeat(30);
        let feedback = videos_to_feedback(&[fixture_video(&long_description)]);
        let subtitle = feedback.items[0]
            .subtitle
            .as_deref()
            .expect("subtitle should exist")
            .to_string();

        let feedback_again = videos_to_feedback(&[fixture_video(&long_description)]);
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
    fn feedback_no_results_is_invalid_item() {
        let feedback = videos_to_feedback(&[]);
        let item = feedback.items.first().expect("fallback item should exist");

        assert_eq!(item.title, NO_RESULTS_TITLE);
        assert_eq!(item.valid, Some(false));
    }

    #[test]
    fn watch_url_builds_canonical_watch_link() {
        assert_eq!(
            watch_url("abc123"),
            "https://www.youtube.com/watch?v=abc123",
            "watch URL should be canonical"
        );
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
