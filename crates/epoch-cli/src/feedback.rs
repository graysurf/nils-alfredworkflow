use alfred_core::{Feedback, Item};

use crate::convert::ConversionRow;

const NO_RESULTS_TITLE: &str = "No conversion results";
const NO_RESULTS_SUBTITLE: &str = "Try a different query";

pub fn rows_to_feedback(rows: &[ConversionRow]) -> Feedback {
    if rows.is_empty() {
        return Feedback::new(vec![
            Item::new(NO_RESULTS_TITLE)
                .with_subtitle(NO_RESULTS_SUBTITLE)
                .with_valid(false),
        ]);
    }

    let items = rows
        .iter()
        .map(|row| {
            Item::new(row.value.clone())
                .with_subtitle(row.label.clone())
                .with_arg(row.value.clone())
                .with_valid(true)
        })
        .collect();

    Feedback::new(items)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rows_to_feedback_maps_conversion_rows_to_items() {
        let rows = vec![ConversionRow::new("UTC epoch (s)", "1700000000")];

        let feedback = rows_to_feedback(&rows);

        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].title, "1700000000");
        assert_eq!(feedback.items[0].subtitle.as_deref(), Some("UTC epoch (s)"));
        assert_eq!(feedback.items[0].arg.as_deref(), Some("1700000000"));
        assert_eq!(feedback.items[0].valid, Some(true));
    }

    #[test]
    fn rows_to_feedback_returns_invalid_item_when_no_rows() {
        let feedback = rows_to_feedback(&[]);

        assert_eq!(feedback.items.len(), 1);
        assert_eq!(feedback.items[0].title, NO_RESULTS_TITLE);
        assert_eq!(
            feedback.items[0].subtitle.as_deref(),
            Some(NO_RESULTS_SUBTITLE)
        );
        assert_eq!(feedback.items[0].valid, Some(false));
    }
}
