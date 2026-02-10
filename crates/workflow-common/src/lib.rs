use alfred_core::{Feedback, Item};

pub fn build_feedback(query: &str) -> Feedback {
    let trimmed = query.trim();
    let title = if trimmed.is_empty() {
        "Open project"
    } else {
        trimmed
    };

    let item = Item::new(title)
        .with_subtitle("Monorepo skeleton result")
        .with_arg(title.to_string());

    Feedback::new(vec![item])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_query_uses_default_title() {
        let payload = build_feedback("");
        assert_eq!(payload.items[0].title, "Open project");
    }
}
