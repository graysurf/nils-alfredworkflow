//! Shared open-project domain modules.
//!
//! - `config`: environment/default parsing and path expansion.
//! - `discovery`: git repository scan + query filtering.
//! - `usage_log`: usage file read/write + timestamp sort keys.
//! - `git`: git metadata helpers and GitHub URL normalization.
//! - `feedback`: Alfred item assembly.

pub mod config;
pub mod discovery;
pub mod error;
pub mod feedback;
pub mod git;
pub mod usage_log;

pub use config::{
    DEFAULT_PROJECT_DIRS, DEFAULT_USAGE_FILE, DEFAULT_VSCODE_PATH, RuntimeConfig,
    expand_home_tokens, parse_project_dirs,
};
pub use error::WorkflowError;
pub use feedback::{
    ScriptFilterMode, build_script_filter_feedback, build_script_filter_feedback_with_mode,
    no_projects_feedback, subtitle_format,
};
pub use git::{github_url_for_project, normalize_github_remote};
pub use usage_log::{parse_usage_timestamp, record_usage};

use alfred_core::Feedback;

pub fn build_feedback(query: &str) -> Feedback {
    let config = RuntimeConfig::from_env();
    build_script_filter_feedback(query, &config)
}
