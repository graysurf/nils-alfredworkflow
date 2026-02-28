use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NativeAuthConfig {
    pub config_dir: PathBuf,
    pub default_account: Option<String>,
}

impl NativeAuthConfig {
    pub fn new(config_dir: PathBuf) -> Self {
        Self {
            config_dir,
            default_account: None,
        }
    }
}
