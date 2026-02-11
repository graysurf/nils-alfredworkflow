use std::fmt;

pub const ENVELOPE_SCHEMA_VERSION: &str = "v1";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputMode {
    Human,
    Json,
    AlfredJson,
}

impl OutputMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Human => "human",
            Self::Json => "json",
            Self::AlfredJson => "alfred-json",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw.trim().to_ascii_lowercase().as_str() {
            "human" | "text" => Some(Self::Human),
            "json" => Some(Self::Json),
            "alfred-json" | "alfred_json" | "alfred" => Some(Self::AlfredJson),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EnvelopePayloadKind {
    Result,
    Results,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OutputModeSelectionError {
    pub explicit: OutputMode,
}

impl fmt::Display for OutputModeSelectionError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "conflicting output mode flags: --json requires --output json (got {})",
            self.explicit.as_str()
        )
    }
}

pub fn select_output_mode(
    explicit: Option<OutputMode>,
    json_flag: bool,
    default_mode: OutputMode,
) -> Result<OutputMode, OutputModeSelectionError> {
    match (explicit, json_flag) {
        (Some(mode), true) if mode != OutputMode::Json => {
            Err(OutputModeSelectionError { explicit: mode })
        }
        (Some(mode), _) => Ok(mode),
        (None, true) => Ok(OutputMode::Json),
        (None, false) => Ok(default_mode),
    }
}

pub fn build_success_envelope(
    command: &str,
    payload_kind: EnvelopePayloadKind,
    payload_json: &str,
) -> String {
    let payload_key = match payload_kind {
        EnvelopePayloadKind::Result => "result",
        EnvelopePayloadKind::Results => "results",
    };

    format!(
        "{{\"schema_version\":\"{}\",\"command\":\"{}\",\"ok\":true,\"{}\":{}}}",
        ENVELOPE_SCHEMA_VERSION,
        escape_json_string(command),
        payload_key,
        payload_json
    )
}

pub fn build_error_envelope(
    command: &str,
    code: &str,
    message: &str,
    details_json: Option<&str>,
) -> String {
    let safe_message = escape_json_string(&redact_sensitive(message));
    let mut output = format!(
        "{{\"schema_version\":\"{}\",\"command\":\"{}\",\"ok\":false,\"error\":{{\"code\":\"{}\",\"message\":\"{}\"",
        ENVELOPE_SCHEMA_VERSION,
        escape_json_string(command),
        escape_json_string(code),
        safe_message
    );

    if let Some(details) = details_json {
        output.push_str(",\"details\":");
        output.push_str(details);
    }

    output.push_str("}}");
    output
}

pub fn build_error_details_json(kind: &str, exit_code: i32) -> String {
    format!(
        "{{\"kind\":\"{}\",\"exit_code\":{}}}",
        escape_json_string(kind),
        exit_code
    )
}

pub fn redact_sensitive(input: &str) -> String {
    let mut output = input.to_string();

    for pattern in [
        "token=",
        "token:",
        "secret=",
        "secret:",
        "client_secret=",
        "client_secret:",
        "password=",
        "password:",
        "apikey=",
        "apikey:",
        "api_key=",
        "api_key:",
        "authorization=",
        "authorization:",
    ] {
        output = redact_after_pattern(&output, pattern);
    }

    redact_bearer_token(&output)
}

fn redact_after_pattern(input: &str, pattern: &str) -> String {
    let lower = input.to_ascii_lowercase();
    let pattern_lower = pattern.to_ascii_lowercase();
    let is_authorization_pattern = pattern_lower.starts_with("authorization");
    let mut output = String::with_capacity(input.len());
    let mut cursor = 0;

    while let Some(found) = lower[cursor..].find(&pattern_lower) {
        let start = cursor + found;
        let value_start = start + pattern.len();
        let value_content_start = skip_whitespace(input, value_start);
        let (redaction_start, value_end) = if is_authorization_pattern
            && input[value_content_start..]
                .to_ascii_lowercase()
                .starts_with("bearer ")
        {
            let bearer_start = value_content_start + "bearer ".len();
            (bearer_start, find_value_end(input, bearer_start))
        } else {
            (
                value_content_start,
                find_value_end(input, value_content_start),
            )
        };

        output.push_str(&input[cursor..redaction_start]);
        if redaction_start < value_end {
            output.push_str("[REDACTED]");
        }

        cursor = value_end;
    }

    output.push_str(&input[cursor..]);
    output
}

fn redact_bearer_token(input: &str) -> String {
    let lower = input.to_ascii_lowercase();
    let pattern = "bearer ";
    let mut output = String::with_capacity(input.len());
    let mut cursor = 0;

    while let Some(found) = lower[cursor..].find(pattern) {
        let start = cursor + found;
        let value_start = start + pattern.len();
        let value_end = find_value_end(input, value_start);

        output.push_str(&input[cursor..value_start]);
        if value_start < value_end {
            output.push_str("[REDACTED]");
        }

        cursor = value_end;
    }

    output.push_str(&input[cursor..]);
    output
}

fn skip_whitespace(input: &str, mut index: usize) -> usize {
    let bytes = input.as_bytes();
    while index < bytes.len() && bytes[index].is_ascii_whitespace() {
        index += 1;
    }
    index
}

fn find_value_end(input: &str, mut index: usize) -> usize {
    let bytes = input.as_bytes();
    while index < bytes.len() {
        let byte = bytes[index];
        if byte.is_ascii_whitespace() || matches!(byte, b'&' | b',' | b';' | b')' | b']' | b'}') {
            break;
        }
        index += 1;
    }
    index
}

fn escape_json_string(raw: &str) -> String {
    let mut escaped = String::with_capacity(raw.len());
    for ch in raw.chars() {
        match ch {
            '"' => escaped.push_str("\\\""),
            '\\' => escaped.push_str("\\\\"),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            '\u{08}' => escaped.push_str("\\b"),
            '\u{0C}' => escaped.push_str("\\f"),
            c if c < '\u{20}' => {
                let code = c as u32;
                escaped.push_str(&format!("\\u{code:04x}"));
            }
            c => escaped.push(c),
        }
    }
    escaped
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn output_mode_parse_accepts_aliases() {
        assert_eq!(OutputMode::parse("human"), Some(OutputMode::Human));
        assert_eq!(OutputMode::parse("text"), Some(OutputMode::Human));
        assert_eq!(OutputMode::parse("json"), Some(OutputMode::Json));
        assert_eq!(
            OutputMode::parse("alfred_json"),
            Some(OutputMode::AlfredJson)
        );
        assert_eq!(OutputMode::parse("invalid"), None);
    }

    #[test]
    fn output_mode_select_rejects_conflicting_json_flag() {
        let err = select_output_mode(Some(OutputMode::Human), true, OutputMode::Human)
            .expect_err("must fail");
        assert_eq!(err.explicit, OutputMode::Human);
        assert!(err.to_string().contains("--json requires --output json"));
    }

    #[test]
    fn envelope_builders_emit_required_keys() {
        let success =
            build_success_envelope("weather.today", EnvelopePayloadKind::Result, "{\"foo\":1}");
        assert!(success.contains("\"schema_version\":\"v1\""));
        assert!(success.contains("\"command\":\"weather.today\""));
        assert!(success.contains("\"ok\":true"));
        assert!(success.contains("\"result\":{\"foo\":1}"));

        let details = build_error_details_json("runtime", 1);
        let failure = build_error_envelope(
            "weather.today",
            "runtime.provider_failed",
            "token=abc",
            Some(&details),
        );
        assert!(failure.contains("\"ok\":false"));
        assert!(failure.contains("\"code\":\"runtime.provider_failed\""));
        assert!(failure.contains("\"details\":{\"kind\":\"runtime\",\"exit_code\":1}"));
        assert!(failure.contains("token=[REDACTED]"));
    }

    #[test]
    fn redaction_masks_sensitive_patterns() {
        let raw = "authorization: Bearer top.secret token=abc123 client_secret:zzz";
        let redacted = redact_sensitive(raw);

        assert!(!redacted.contains("top.secret"));
        assert!(!redacted.contains("abc123"));
        assert!(!redacted.contains("zzz"));
        assert!(redacted.contains("Bearer [REDACTED]"));
    }
}
