use alfred_core::{Feedback, Item};

use crate::spotify_api::TrackSearchResult;

const NO_RESULTS_TITLE: &str = "No tracks found";
const NO_RESULTS_SUBTITLE: &str = "Try a different search query";
#[cfg_attr(not(test), allow(dead_code))]
const ERROR_TITLE: &str = "Spotify search failed";
const UNKNOWN_ARTIST_SUBTITLE: &str = "Unknown artist";
const UNKNOWN_ALBUM_SUBTITLE: &str = "Unknown album";
const SUBTITLE_MAX_CHARS: usize = 120;

pub fn tracks_to_feedback(tracks: &[TrackSearchResult]) -> Feedback {
    if tracks.is_empty() {
        return no_results_feedback();
    }

    let items = tracks.iter().map(track_to_item).collect();
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

fn track_to_item(track: &TrackSearchResult) -> Item {
    let title = track.name.trim();
    let normalized_title = if title.is_empty() {
        "(untitled track)"
    } else {
        title
    };

    let artists = normalized_artists(&track.artists);
    let album = normalized_album_name(&track.album_name);
    let subtitle = single_line_subtitle(&format!("{artists} | {album}"), SUBTITLE_MAX_CHARS);

    Item::new(normalized_title)
        .with_subtitle(subtitle)
        .with_arg(track.external_url.trim())
}

fn normalized_artists(artists: &[String]) -> String {
    let names: Vec<&str> = artists
        .iter()
        .map(|artist| artist.trim())
        .filter(|artist| !artist.is_empty())
        .collect();

    if names.is_empty() {
        return UNKNOWN_ARTIST_SUBTITLE.to_string();
    }

    names.join(", ")
}

fn normalized_album_name(album_name: &str) -> String {
    let normalized = album_name.trim();
    if normalized.is_empty() {
        return UNKNOWN_ALBUM_SUBTITLE.to_string();
    }

    normalized.to_string()
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

    fn fixture_track(subtitle: &str) -> TrackSearchResult {
        TrackSearchResult {
            name: "Harder, Better, Faster, Stronger".to_string(),
            artists: vec!["Daft Punk".to_string()],
            album_name: subtitle.to_string(),
            external_url: "https://open.spotify.com/track/abc123".to_string(),
        }
    }

    #[test]
    fn feedback_maps_tracks_to_alfred_items() {
        let feedback = tracks_to_feedback(&[fixture_track("Discovery")]);
        let item = feedback.items.first().expect("expected one item");

        assert_eq!(item.title, "Harder, Better, Faster, Stronger");
        assert_eq!(item.subtitle.as_deref(), Some("Daft Punk | Discovery"));
        assert_eq!(
            item.arg.as_deref(),
            Some("https://open.spotify.com/track/abc123")
        );
    }

    #[test]
    fn feedback_subtitle_truncation_is_deterministic_and_single_line() {
        let long_album_name = " album\nname\tsegment ".repeat(30);
        let feedback = tracks_to_feedback(&[fixture_track(&long_album_name)]);
        let subtitle = feedback.items[0]
            .subtitle
            .as_deref()
            .expect("subtitle should exist")
            .to_string();

        let feedback_again = tracks_to_feedback(&[fixture_track(&long_album_name)]);
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
        let feedback = tracks_to_feedback(&[]);
        let item = feedback.items.first().expect("fallback item should exist");

        assert_eq!(item.title, NO_RESULTS_TITLE);
        assert_eq!(item.valid, Some(false));
        assert!(item.arg.is_none(), "fallback item must not include arg");
    }

    #[test]
    fn feedback_uses_unknown_metadata_fallbacks() {
        let feedback = tracks_to_feedback(&[TrackSearchResult {
            name: "Unknown Track".to_string(),
            artists: vec![" ".to_string()],
            album_name: "  ".to_string(),
            external_url: "https://open.spotify.com/track/unknown".to_string(),
        }]);

        let subtitle = feedback.items[0]
            .subtitle
            .as_deref()
            .expect("subtitle should exist");
        assert_eq!(subtitle, "Unknown artist | Unknown album");
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
