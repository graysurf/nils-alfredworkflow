#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthFlowMode {
    Loopback,
    Manual,
    Remote,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AuthFlowPlan {
    pub mode: AuthFlowMode,
    pub account_hint: Option<String>,
}

impl AuthFlowPlan {
    pub fn new(mode: AuthFlowMode, account_hint: Option<String>) -> Self {
        Self { mode, account_hint }
    }
}
