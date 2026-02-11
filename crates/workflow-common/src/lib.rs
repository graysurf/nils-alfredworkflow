//! Shared open-project domain modules.
//!
//! - `config`: environment/default parsing and path expansion.
//! - `discovery`: git repository scan + query filtering.
//! - `usage_log`: usage file read/write + timestamp sort keys.
//! - `git`: git metadata helpers and GitHub URL normalization.
//! - `feedback`: Alfred item assembly.
//! - `output_contract`: shared output modes + JSON envelope helpers.

pub mod config;
pub mod discovery;
pub mod error;
pub mod feedback;
pub mod git;
pub mod output_contract;
pub mod usage_log;

pub use alfred_core::Feedback;
pub use config::{
    DEFAULT_OPEN_PROJECT_MAX_RESULTS, DEFAULT_PROJECT_DIRS, DEFAULT_USAGE_FILE,
    DEFAULT_VSCODE_PATH, RuntimeConfig, expand_home_tokens, parse_project_dirs,
};
pub use error::WorkflowError;
pub use feedback::{
    ScriptFilterMode, build_script_filter_feedback, build_script_filter_feedback_with_mode,
    no_projects_feedback, subtitle_format,
};
pub use git::{github_url_for_project, normalize_github_remote};
pub use output_contract::{
    ENVELOPE_SCHEMA_VERSION, EnvelopePayloadKind, OutputMode, OutputModeSelectionError,
    build_error_details_json, build_error_envelope, build_success_envelope, redact_sensitive,
    select_output_mode,
};
pub use usage_log::{parse_usage_timestamp, record_usage};

pub fn build_feedback(query: &str) -> Feedback {
    let config = RuntimeConfig::from_env();
    build_script_filter_feedback(query, &config)
}
