#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TokenStoreKey {
    pub account: String,
}

impl TokenStoreKey {
    pub fn new(account: impl Into<String>) -> Self {
        Self {
            account: account.into(),
        }
    }
}
