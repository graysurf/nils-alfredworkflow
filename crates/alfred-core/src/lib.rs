use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Feedback {
    pub items: Vec<Item>,
}

impl Feedback {
    pub fn new(items: Vec<Item>) -> Self {
        Self { items }
    }

    pub fn to_json(&self) -> serde_json::Result<String> {
        serde_json::to_string(self)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Item {
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subtitle: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub arg: Option<String>,
}

impl Item {
    pub fn new(title: impl Into<String>) -> Self {
        Self {
            title: title.into(),
            subtitle: None,
            arg: None,
        }
    }

    pub fn with_subtitle(mut self, subtitle: impl Into<String>) -> Self {
        self.subtitle = Some(subtitle.into());
        self
    }

    pub fn with_arg(mut self, arg: impl Into<String>) -> Self {
        self.arg = Some(arg.into());
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn feedback_serializes() {
        let payload = Feedback::new(vec![Item::new("hello").with_subtitle("world")]);
        let json = payload.to_json().expect("serialize feedback");
        assert!(json.contains("items"));
    }
}
