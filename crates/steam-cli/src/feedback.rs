use alfred_core::{Feedback, Item};

use crate::steam_store_api::{SteamItemType, SteamPrice, SteamSearchResult};

const NO_RESULTS_TITLE: &str = "No games found";
const NO_RESULTS_SUBTITLE: &str = "Try broader keywords or switch STEAM_REGION.";
const NO_SPECIALS_TITLE: &str = "No Steam specials right now";
const NO_SPECIALS_SUBTITLE: &str = "Steam returned no featured discounts for this region.";
const REGION_CURRENT_TITLE_PREFIX: &str = "Current region:";
const REGION_SWITCH_TITLE_PREFIX: &str = "Search in";
const REGION_SWITCH_ARG_PREFIX: &str = "steam-requery:";
#[cfg_attr(not(test), allow(dead_code))]
const ERROR_TITLE: &str = "Steam search failed";
const UNKNOWN_PRICE_LABEL: &str = "Price unavailable";
const FREE_TO_PLAY_LABEL: &str = "Free to play";
const SUBTITLE_MAX_CHARS: usize = 120;
const STRIKETHROUGH_OVERLAY: char = '\u{0336}';

pub fn search_results_to_feedback(
    region: &str,
    query: &str,
    region_options: &[String],
    show_region_options: bool,
    language: &str,
    results: &[SteamSearchResult],
) -> Feedback {
    let mut items = Vec::new();
    if show_region_options {
        items.extend(region_switch_items(region, query, region_options, language));
    }

    if results.is_empty() {
        items.push(no_results_item());
        return Feedback::new(items);
    }

    let mut ordered: Vec<&SteamSearchResult> = results.iter().collect();
    ordered.sort_by(|a, b| {
        let a_discount = a.price.as_ref().and_then(|price| price.discount_percent);
        let b_discount = b.price.as_ref().and_then(|price| price.discount_percent);
        b_discount.unwrap_or(0).cmp(&a_discount.unwrap_or(0))
    });

    items.extend(
        ordered
            .into_iter()
            .map(|result| result_to_item(region, language, result)),
    );
    Feedback::new(items)
}

pub fn specials_to_feedback(
    region: &str,
    language: &str,
    results: &[SteamSearchResult],
) -> Feedback {
    if results.is_empty() {
        return Feedback::new(vec![
            Item::new(NO_SPECIALS_TITLE)
                .with_subtitle(NO_SPECIALS_SUBTITLE)
                .with_valid(false),
        ]);
    }

    search_results_to_feedback(region, "", &[], false, language, results)
}

#[cfg_attr(not(test), allow(dead_code))]
pub fn error_feedback(message: &str) -> Feedback {
    Feedback::new(vec![
        Item::new(ERROR_TITLE)
            .with_subtitle(single_line_subtitle(message, SUBTITLE_MAX_CHARS))
            .with_valid(false),
    ])
}

fn result_to_item(region: &str, language: &str, result: &SteamSearchResult) -> Item {
    let title = result.name.trim();
    let normalized_title = if title.is_empty() {
        "(untitled app)"
    } else {
        title
    };

    let price = format_price(result);
    let item_type = format_item_type(result.item_type);
    let subtitle = single_line_subtitle(&format!("{price} | {item_type}"), SUBTITLE_MAX_CHARS);

    Item::new(normalized_title)
        .with_subtitle(subtitle)
        .with_arg(canonical_app_url(result.app_id, region, language))
}

#[cfg_attr(not(test), allow(dead_code))]
fn canonical_app_url(app_id: u32, region: &str, language: &str) -> String {
    if language.is_empty() {
        return format!("https://store.steampowered.com/app/{app_id}/?cc={region}");
    }

    format!("https://store.steampowered.com/app/{app_id}/?cc={region}&l={language}")
}

fn format_price(result: &SteamSearchResult) -> String {
    let Some(price) = result.price.as_ref() else {
        return UNKNOWN_PRICE_LABEL.to_string();
    };

    let final_text = final_price_text(price);

    let Some(discount_percent) = price.discount_percent else {
        return final_text;
    };

    let Some(original_text) = original_price_text(price) else {
        return final_text;
    };

    format!(
        "{final_text} ({struck}, -{discount_percent}%)",
        struck = strike_through(&original_text),
    )
}

fn final_price_text(price: &SteamPrice) -> String {
    if let Some(formatted) = price.final_formatted.as_deref().map(str::trim)
        && !formatted.is_empty()
    {
        return formatted.to_string();
    }

    match price.final_price_cents {
        Some(0) => FREE_TO_PLAY_LABEL.to_string(),
        Some(value) => fallback_currency(value),
        None => UNKNOWN_PRICE_LABEL.to_string(),
    }
}

fn original_price_text(price: &SteamPrice) -> Option<String> {
    if let Some(formatted) = price.original_formatted.as_deref().map(str::trim)
        && !formatted.is_empty()
    {
        return Some(formatted.to_string());
    }

    price.original_price_cents.map(fallback_currency)
}

fn fallback_currency(cents: u32) -> String {
    let major = cents / 100;
    let minor = cents % 100;
    format!("${major}.{minor:02}")
}

fn strike_through(input: &str) -> String {
    let mut out = String::with_capacity(input.len() * 2);
    for ch in input.chars() {
        out.push(ch);
        if !ch.is_whitespace() {
            out.push(STRIKETHROUGH_OVERLAY);
        }
    }
    out
}

fn format_item_type(item_type: SteamItemType) -> &'static str {
    item_type.label()
}

fn no_results_item() -> Item {
    Item::new(NO_RESULTS_TITLE)
        .with_subtitle(NO_RESULTS_SUBTITLE)
        .with_valid(false)
}

fn region_switch_items(
    current_region: &str,
    query: &str,
    options: &[String],
    language: &str,
) -> Vec<Item> {
    let current_region_upper = current_region.to_ascii_uppercase();
    let current_region_subtitle = if language.is_empty() {
        format!("Searching Steam Store in {current_region_upper}.")
    } else {
        format!("Searching Steam Store in {current_region_upper} ({language}).")
    };
    let mut items = Vec::with_capacity(options.len() + 1);
    items.push(
        Item::new(format!(
            "{REGION_CURRENT_TITLE_PREFIX} {current_region_upper}"
        ))
        .with_subtitle(current_region_subtitle)
        .with_valid(false),
    );

    items.extend(options.iter().map(|candidate| {
        let candidate_upper = candidate.to_ascii_uppercase();
        let subtitle = single_line_subtitle(
            &format!("Press Enter to requery \"{query}\" in {candidate_upper}."),
            SUBTITLE_MAX_CHARS,
        );

        Item::new(format!(
            "{REGION_SWITCH_TITLE_PREFIX} {candidate_upper} region"
        ))
        .with_subtitle(subtitle)
        .with_arg(switch_region_arg(candidate, query))
        .with_valid(true)
    }));

    items
}

fn switch_region_arg(region: &str, query: &str) -> String {
    let compact_query = query.split_whitespace().collect::<Vec<_>>().join(" ");
    format!("{REGION_SWITCH_ARG_PREFIX}{region}:{compact_query}")
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
    use crate::steam_store_api::{SteamItemType, SteamPlatforms, SteamPrice};

    fn fixture_result(price: Option<SteamPrice>, item_type: SteamItemType) -> SteamSearchResult {
        SteamSearchResult {
            app_id: 730,
            name: "Counter-Strike 2".to_string(),
            price,
            item_type,
            platforms: SteamPlatforms::default(),
        }
    }

    #[test]
    fn feedback_maps_result_to_alfred_item_with_canonical_url() {
        let feedback = search_results_to_feedback(
            "us",
            "counter strike",
            &[],
            false,
            "english",
            &[fixture_result(
                Some(SteamPrice {
                    final_price_cents: Some(0),
                    final_formatted: Some("Free".to_string()),
                    ..SteamPrice::default()
                }),
                SteamItemType::Game,
            )],
        );

        let item = feedback.items.first().expect("expected one result row");

        assert_eq!(item.title, "Counter-Strike 2");
        assert_eq!(item.subtitle.as_deref(), Some("Free | Game"));
        assert_eq!(
            item.arg.as_deref(),
            Some("https://store.steampowered.com/app/730/?cc=us&l=english")
        );
    }

    #[test]
    fn feedback_switch_rows_follow_configured_order() {
        let options = vec!["jp".to_string(), "us".to_string(), "kr".to_string()];
        let feedback = search_results_to_feedback("us", "dota", &options, true, "english", &[]);

        assert_eq!(feedback.items[0].title, "Current region: US");
        assert_eq!(feedback.items[1].title, "Search in JP region");
        assert_eq!(feedback.items[2].title, "Search in US region");
        assert_eq!(feedback.items[3].title, "Search in KR region");
        assert_eq!(feedback.items[0].valid, Some(false));
        assert_eq!(feedback.items[1].valid, Some(true));
        assert_eq!(feedback.items[2].valid, Some(true));
        assert_eq!(feedback.items[3].valid, Some(true));
    }

    #[test]
    fn feedback_switch_rows_use_requery_arg_contract() {
        let options = vec!["jp".to_string(), "us".to_string()];
        let feedback = search_results_to_feedback("us", "dota 2", &options, true, "english", &[]);

        assert_eq!(
            feedback.items[1].arg.as_deref(),
            Some("steam-requery:jp:dota 2")
        );
        assert_eq!(
            feedback.items[2].arg.as_deref(),
            Some("steam-requery:us:dota 2")
        );
    }

    #[test]
    fn feedback_current_region_subtitle_omits_language_when_not_configured() {
        let options = vec!["jp".to_string(), "us".to_string()];
        let feedback = search_results_to_feedback("us", "dota 2", &options, true, "", &[]);

        assert_eq!(
            feedback.items[0].subtitle.as_deref(),
            Some("Searching Steam Store in US.")
        );
    }

    #[test]
    fn feedback_subtitle_truncation_is_deterministic_and_single_line() {
        let long_price = " very long price segment\n\t".repeat(30);
        let feedback = search_results_to_feedback(
            "us",
            "rust",
            &[],
            false,
            "english",
            &[fixture_result(
                Some(SteamPrice {
                    final_price_cents: None,
                    final_formatted: Some(long_price.clone()),
                    ..SteamPrice::default()
                }),
                SteamItemType::Soundtrack,
            )],
        );
        let subtitle = feedback.items[0]
            .subtitle
            .as_deref()
            .expect("subtitle should exist")
            .to_string();

        let feedback_again = search_results_to_feedback(
            "us",
            "rust",
            &[],
            false,
            "english",
            &[fixture_result(
                Some(SteamPrice {
                    final_price_cents: None,
                    final_formatted: Some(long_price),
                    ..SteamPrice::default()
                }),
                SteamItemType::Soundtrack,
            )],
        );
        let subtitle_again = feedback_again.items[0]
            .subtitle
            .as_deref()
            .expect("subtitle should exist")
            .to_string();

        assert_eq!(subtitle, subtitle_again, "subtitle should be deterministic");
        assert!(!subtitle.contains('\n'));
        assert!(!subtitle.contains('\t'));
        assert!(subtitle.chars().count() <= SUBTITLE_MAX_CHARS);
    }

    #[test]
    fn feedback_no_results_item_is_invalid_and_has_expected_title() {
        let feedback = search_results_to_feedback("us", "dota", &[], false, "english", &[]);
        let item = feedback.items.first().expect("fallback item should exist");

        assert_eq!(item.title, NO_RESULTS_TITLE);
        assert_eq!(item.subtitle.as_deref(), Some(NO_RESULTS_SUBTITLE));
        assert_eq!(item.valid, Some(false));
        assert!(item.arg.is_none());
    }

    #[test]
    fn feedback_uses_fallback_labels_for_missing_price_and_type() {
        let feedback = search_results_to_feedback(
            "us",
            "dota",
            &[],
            false,
            "english",
            &[fixture_result(None, SteamItemType::Unknown)],
        );

        assert_eq!(
            feedback.items[0].subtitle.as_deref(),
            Some("Price unavailable | Unknown")
        );
    }

    #[test]
    fn feedback_hides_region_rows_when_switch_is_disabled() {
        let options = vec!["jp".to_string(), "us".to_string(), "kr".to_string()];
        let feedback = search_results_to_feedback(
            "us",
            "dota",
            &options,
            false,
            "english",
            &[fixture_result(None, SteamItemType::Unknown)],
        );

        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].title, "Counter-Strike 2");
        assert!(feedback.items[0].arg.is_some());
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
    fn url_builds_canonical_store_url() {
        assert_eq!(
            canonical_app_url(570, "jp", "schinese"),
            "https://store.steampowered.com/app/570/?cc=jp&l=schinese"
        );
    }

    #[test]
    fn url_omits_language_parameter_when_not_configured() {
        assert_eq!(
            canonical_app_url(570, "jp", ""),
            "https://store.steampowered.com/app/570/?cc=jp"
        );
    }

    #[test]
    fn feedback_subtitle_renders_discount_with_strikethrough_when_discounted() {
        let mut result = fixture_result(
            Some(SteamPrice {
                final_price_cents: Some(34000),
                final_formatted: Some("NT$ 340".to_string()),
                original_price_cents: Some(85000),
                original_formatted: Some("NT$ 850".to_string()),
                discount_percent: Some(60),
            }),
            SteamItemType::Game,
        );
        result.app_id = 12345;
        result.name = "Discounted Pack".to_string();

        let feedback =
            search_results_to_feedback("us", "pack", &[], false, "english", &[result.clone()]);
        let subtitle = feedback.items[0]
            .subtitle
            .as_deref()
            .expect("subtitle exists");

        assert!(
            subtitle.starts_with("NT$ 340 (N"),
            "unexpected subtitle: {subtitle}"
        );
        assert!(subtitle.contains("-60%"), "missing discount: {subtitle}");
        assert!(
            subtitle.contains('\u{0336}'),
            "expected strikethrough overlay in subtitle: {subtitle}"
        );
        assert!(
            !subtitle.contains("was "),
            "should not emit `was` literal: {subtitle}"
        );
    }

    #[test]
    fn feedback_subtitle_keeps_legacy_format_when_no_discount() {
        let result = fixture_result(
            Some(SteamPrice {
                final_price_cents: Some(15999),
                final_formatted: Some("NT$ 1,599".to_string()),
                ..SteamPrice::default()
            }),
            SteamItemType::Game,
        );

        let feedback = search_results_to_feedback("us", "x", &[], false, "english", &[result]);
        assert_eq!(
            feedback.items[0].subtitle.as_deref(),
            Some("NT$ 1,599 | Game")
        );
    }

    #[test]
    fn feedback_sorts_results_by_discount_percent_descending() {
        let full_price = SteamSearchResult {
            app_id: 1,
            name: "Full Price".to_string(),
            price: Some(SteamPrice {
                final_price_cents: Some(15999),
                final_formatted: Some("NT$ 1,599".to_string()),
                ..SteamPrice::default()
            }),
            item_type: SteamItemType::Game,
            platforms: SteamPlatforms::default(),
        };
        let light_discount = SteamSearchResult {
            app_id: 2,
            name: "Light".to_string(),
            price: Some(SteamPrice {
                final_price_cents: Some(7500),
                final_formatted: Some("NT$ 75".to_string()),
                original_price_cents: Some(10000),
                original_formatted: Some("NT$ 100".to_string()),
                discount_percent: Some(25),
            }),
            item_type: SteamItemType::Game,
            platforms: SteamPlatforms::default(),
        };
        let heavy_discount = SteamSearchResult {
            app_id: 3,
            name: "Heavy".to_string(),
            price: Some(SteamPrice {
                final_price_cents: Some(3400),
                final_formatted: Some("NT$ 340".to_string()),
                original_price_cents: Some(8500),
                original_formatted: Some("NT$ 850".to_string()),
                discount_percent: Some(60),
            }),
            item_type: SteamItemType::Game,
            platforms: SteamPlatforms::default(),
        };

        let feedback = search_results_to_feedback(
            "us",
            "x",
            &[],
            false,
            "english",
            &[
                full_price.clone(),
                light_discount.clone(),
                heavy_discount.clone(),
            ],
        );

        assert_eq!(feedback.items[0].title, "Heavy");
        assert_eq!(feedback.items[1].title, "Light");
        assert_eq!(feedback.items[2].title, "Full Price");
    }

    #[test]
    fn feedback_specials_empty_emits_dedicated_no_specials_row() {
        let feedback = specials_to_feedback("tw", "english", &[]);
        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].title, NO_SPECIALS_TITLE);
        assert_eq!(
            feedback.items[0].subtitle.as_deref(),
            Some(NO_SPECIALS_SUBTITLE)
        );
        assert_eq!(feedback.items[0].valid, Some(false));
    }

    #[test]
    fn feedback_specials_sorts_by_discount_and_skips_region_rows() {
        let light = SteamSearchResult {
            app_id: 1,
            name: "Light".to_string(),
            price: Some(SteamPrice {
                final_price_cents: Some(7500),
                final_formatted: Some("NT$ 75".to_string()),
                original_price_cents: Some(10000),
                original_formatted: Some("NT$ 100".to_string()),
                discount_percent: Some(25),
            }),
            item_type: SteamItemType::Game,
            platforms: SteamPlatforms::default(),
        };
        let heavy = SteamSearchResult {
            app_id: 2,
            name: "Heavy".to_string(),
            price: Some(SteamPrice {
                final_price_cents: Some(3400),
                final_formatted: Some("NT$ 340".to_string()),
                original_price_cents: Some(8500),
                original_formatted: Some("NT$ 850".to_string()),
                discount_percent: Some(60),
            }),
            item_type: SteamItemType::Game,
            platforms: SteamPlatforms::default(),
        };

        let feedback = specials_to_feedback("tw", "english", &[light, heavy]);

        assert_eq!(feedback.items.len(), 2);
        assert_eq!(feedback.items[0].title, "Heavy");
        assert_eq!(feedback.items[1].title, "Light");
        assert!(feedback.items[0].arg.is_some());
    }

    #[test]
    fn feedback_sort_is_stable_for_undiscounted_results() {
        let make = |app_id, name: &str| SteamSearchResult {
            app_id,
            name: name.to_string(),
            price: Some(SteamPrice {
                final_price_cents: Some(1000),
                final_formatted: Some("NT$ 10".to_string()),
                ..SteamPrice::default()
            }),
            item_type: SteamItemType::Game,
            platforms: SteamPlatforms::default(),
        };
        let inputs = [make(1, "Alpha"), make(2, "Bravo"), make(3, "Charlie")];

        let feedback = search_results_to_feedback("us", "x", &[], false, "english", &inputs);

        assert_eq!(feedback.items[0].title, "Alpha");
        assert_eq!(feedback.items[1].title, "Bravo");
        assert_eq!(feedback.items[2].title, "Charlie");
    }
}
