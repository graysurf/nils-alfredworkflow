pub mod config;
pub mod oauth;
pub mod store;

/// Native auth account-manager stance for Sprint 1.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ManageBehavior {
    SummaryOnly,
}

pub fn manage_behavior() -> ManageBehavior {
    ManageBehavior::SummaryOnly
}
