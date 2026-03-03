use std::path::PathBuf;

use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CliErrorKind {
    User,
    Runtime,
}

impl CliErrorKind {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::User => "user",
            Self::Runtime => "runtime",
        }
    }

    pub const fn exit_code(self) -> i32 {
        match self {
            Self::User => 2,
            Self::Runtime => 1,
        }
    }
}

#[derive(Debug, Error)]
pub enum WorkflowError {
    #[error("path does not exist: {0}")]
    MissingPath(PathBuf),
    #[error("path is not a directory: {0}")]
    NotDirectory(PathBuf),
    #[error("no remote 'origin' found in {0}")]
    MissingOrigin(PathBuf),
    #[error("unsupported remote URL format: {0}")]
    UnsupportedRemote(String),
    #[error("failed to execute git in {path}: {message}")]
    GitCommand { path: PathBuf, message: String },
    #[error("failed to persist usage log at {path}: {source}")]
    UsageWrite {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
}
