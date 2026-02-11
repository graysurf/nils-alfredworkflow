use chrono::{DateTime, Utc};
use clap::{Parser, Subcommand, ValueEnum};
use serde_json::json;

use market_cli::{
    config::RuntimeConfig,
    error::AppError,
    expression,
    model::{MarketKind, MarketRequest},
    providers::{HttpProviders, ProviderApi},
    service,
};

#[derive(Debug, Parser)]
#[command(author, version, about = "FX + crypto market data CLI")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Query fiat exchange rate (Frankfurter).
    Fx {
        #[arg(long)]
        base: String,
        #[arg(long)]
        quote: String,
        #[arg(long)]
        amount: String,
        #[arg(long, value_enum)]
        output: Option<OutputModeArg>,
        #[arg(long)]
        json: bool,
    },
    /// Query crypto spot price (Coinbase with Kraken fallback).
    Crypto {
        #[arg(long)]
        base: String,
        #[arg(long)]
        quote: String,
        #[arg(long)]
        amount: String,
        #[arg(long, value_enum)]
        output: Option<OutputModeArg>,
        #[arg(long)]
        json: bool,
    },
    /// Evaluate market expressions and return Alfred Script Filter JSON.
    Expr {
        #[arg(long)]
        query: String,
        #[arg(long, default_value = "USD")]
        default_fiat: String,
        #[arg(long, value_enum)]
        output: Option<OutputModeArg>,
        #[arg(long)]
        json: bool,
    },
}

const ENVELOPE_SCHEMA_VERSION: &str = "v1";
const ERROR_CODE_USER_INVALID_INPUT: &str = "user.invalid_input";
const ERROR_CODE_USER_OUTPUT_MODE_CONFLICT: &str = "user.output_mode_conflict";
const ERROR_CODE_RUNTIME_PROVIDER_INIT: &str = "runtime.provider_init_failed";
const ERROR_CODE_RUNTIME_PROVIDER_FAILED: &str = "runtime.provider_failed";
const ERROR_CODE_RUNTIME_SERIALIZE: &str = "runtime.serialize_failed";

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum OutputModeArg {
    Human,
    Json,
    AlfredJson,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CliOutputMode {
    Human,
    Json,
    AlfredJson,
}

impl From<OutputModeArg> for CliOutputMode {
    fn from(value: OutputModeArg) -> Self {
        match value {
            OutputModeArg::Human => CliOutputMode::Human,
            OutputModeArg::Json => CliOutputMode::Json,
            OutputModeArg::AlfredJson => CliOutputMode::AlfredJson,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CliError {
    kind: market_cli::error::ErrorKind,
    code: &'static str,
    message: String,
}

impl CliError {
    fn user(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            kind: market_cli::error::ErrorKind::User,
            code,
            message: message.into(),
        }
    }

    fn runtime(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            kind: market_cli::error::ErrorKind::Runtime,
            code,
            message: message.into(),
        }
    }

    fn exit_code(&self) -> i32 {
        match self.kind {
            market_cli::error::ErrorKind::User => 2,
            market_cli::error::ErrorKind::Runtime => 1,
        }
    }
}

impl Cli {
    fn command_name(&self) -> &'static str {
        match &self.command {
            Commands::Fx { .. } => "market.fx",
            Commands::Crypto { .. } => "market.crypto",
            Commands::Expr { .. } => "market.expr",
        }
    }

    fn output_mode_hint(&self) -> CliOutputMode {
        match &self.command {
            Commands::Fx { output, json, .. } | Commands::Crypto { output, json, .. } => {
                if *json {
                    CliOutputMode::Json
                } else if let Some(explicit) = output {
                    (*explicit).into()
                } else {
                    CliOutputMode::Human
                }
            }
            Commands::Expr { output, json, .. } => {
                if *json {
                    CliOutputMode::Json
                } else if let Some(explicit) = output {
                    (*explicit).into()
                } else {
                    CliOutputMode::AlfredJson
                }
            }
        }
    }
}

fn main() {
    let cli = Cli::parse();
    let command = cli.command_name();
    let output_mode = cli.output_mode_hint();
    match run(cli) {
        Ok(output) => {
            println!("{output}");
        }
        Err(error) => {
            emit_error(command, output_mode, &error);
            std::process::exit(error.exit_code());
        }
    }
}

fn run(cli: Cli) -> Result<String, CliError> {
    let config = RuntimeConfig::from_env();
    let providers = HttpProviders::new()
        .map_err(|error| runtime_error(ERROR_CODE_RUNTIME_PROVIDER_INIT, error.to_string()))?;
    run_with(cli, &config, &providers, Utc::now)
}

fn run_with<P, N>(
    cli: Cli,
    config: &RuntimeConfig,
    providers: &P,
    now_fn: N,
) -> Result<String, CliError>
where
    P: ProviderApi,
    N: Fn() -> DateTime<Utc> + Copy,
{
    match cli.command {
        Commands::Fx {
            base,
            quote,
            amount,
            output,
            json,
        } => run_market_command(
            config,
            providers,
            now_fn,
            MarketCommandArgs {
                command: "market.fx",
                kind: MarketKind::Fx,
                base: &base,
                quote: &quote,
                amount: &amount,
                output,
                json_flag: json,
                default_mode: CliOutputMode::Human,
            },
        ),
        Commands::Crypto {
            base,
            quote,
            amount,
            output,
            json,
        } => run_market_command(
            config,
            providers,
            now_fn,
            MarketCommandArgs {
                command: "market.crypto",
                kind: MarketKind::Crypto,
                base: &base,
                quote: &quote,
                amount: &amount,
                output,
                json_flag: json,
                default_mode: CliOutputMode::Human,
            },
        ),
        Commands::Expr {
            query,
            default_fiat,
            output,
            json,
        } => {
            let feedback =
                expression::evaluate_query(config, providers, now_fn, &query, &default_fiat)
                    .map_err(map_app_error)?;
            let output_mode = resolve_output_mode(output, json, CliOutputMode::AlfredJson)?;
            let alfred_json = feedback.to_json().map_err(|error| {
                runtime_error(
                    ERROR_CODE_RUNTIME_SERIALIZE,
                    format!("failed to serialize Alfred feedback: {error}"),
                )
            })?;

            match output_mode {
                CliOutputMode::AlfredJson => Ok(alfred_json),
                CliOutputMode::Json => build_json_envelope_from_raw("market.expr", &alfred_json),
                CliOutputMode::Human => format_expr_human_output(&alfred_json),
            }
        }
    }
}

#[derive(Debug, Clone, Copy)]
struct MarketCommandArgs<'a> {
    command: &'static str,
    kind: MarketKind,
    base: &'a str,
    quote: &'a str,
    amount: &'a str,
    output: Option<OutputModeArg>,
    json_flag: bool,
    default_mode: CliOutputMode,
}

fn run_market_command<P, N>(
    config: &RuntimeConfig,
    providers: &P,
    now_fn: N,
    args: MarketCommandArgs<'_>,
) -> Result<String, CliError>
where
    P: ProviderApi,
    N: Fn() -> DateTime<Utc>,
{
    let output_mode = resolve_output_mode(args.output, args.json_flag, args.default_mode)?;
    let request = MarketRequest::new(args.kind, args.base, args.quote, args.amount)
        .map_err(|error| user_error(ERROR_CODE_USER_INVALID_INPUT, error.to_string()))?;
    let result =
        service::resolve_market(config, providers, now_fn, &request).map_err(map_app_error)?;

    match output_mode {
        CliOutputMode::Json => {
            let raw = serde_json::to_string(&result).map_err(|error| {
                runtime_error(
                    ERROR_CODE_RUNTIME_SERIALIZE,
                    format!("failed to serialize output: {error}"),
                )
            })?;
            build_json_envelope_from_raw(args.command, &raw)
        }
        CliOutputMode::Human => Ok(format_market_human_output(&result)),
        CliOutputMode::AlfredJson => render_market_alfred_output(&result),
    }
}

fn resolve_output_mode(
    output: Option<OutputModeArg>,
    json_flag: bool,
    default_mode: CliOutputMode,
) -> Result<CliOutputMode, CliError> {
    match (output.map(Into::into), json_flag) {
        (Some(mode), true) if mode != CliOutputMode::Json => Err(user_error(
            ERROR_CODE_USER_OUTPUT_MODE_CONFLICT,
            format!(
                "conflicting output flags: --json requires --output json (got {})",
                output_mode_label(mode)
            ),
        )),
        (Some(mode), _) => Ok(mode),
        (None, true) => Ok(CliOutputMode::Json),
        (None, false) => Ok(default_mode),
    }
}

fn build_json_envelope_from_raw(command: &str, raw_json: &str) -> Result<String, CliError> {
    let parsed: serde_json::Value = serde_json::from_str(raw_json).map_err(|error| {
        runtime_error(
            ERROR_CODE_RUNTIME_SERIALIZE,
            format!("failed to parse serialized payload: {error}"),
        )
    })?;

    serde_json::to_string(&json!({
        "schema_version": ENVELOPE_SCHEMA_VERSION,
        "command": command,
        "ok": true,
        "result": parsed,
    }))
    .map_err(|error| {
        runtime_error(
            ERROR_CODE_RUNTIME_SERIALIZE,
            format!("failed to serialize output envelope: {error}"),
        )
    })
}

fn format_market_human_output(output: &market_cli::model::MarketOutput) -> String {
    format!(
        "{} {} {} -> {} {} (price={} provider={} cache={})",
        output.kind.as_str().to_ascii_uppercase(),
        output.amount,
        output.base,
        output.converted,
        output.quote,
        output.unit_price,
        output.provider,
        cache_status_label(output.cache.status),
    )
}

fn render_market_alfred_output(
    output: &market_cli::model::MarketOutput,
) -> Result<String, CliError> {
    let payload = json!({
        "items": [{
            "title": format!("{} {} = {} {}", output.amount, output.base, output.converted, output.quote),
            "subtitle": format!(
                "price={} provider={} cache={}",
                output.unit_price,
                output.provider,
                cache_status_label(output.cache.status)
            ),
            "arg": output.converted,
            "valid": false
        }]
    });

    serde_json::to_string(&payload).map_err(|error| {
        runtime_error(
            ERROR_CODE_RUNTIME_SERIALIZE,
            format!("failed to serialize Alfred output: {error}"),
        )
    })
}

fn format_expr_human_output(alfred_json: &str) -> Result<String, CliError> {
    let parsed: serde_json::Value = serde_json::from_str(alfred_json).map_err(|error| {
        runtime_error(
            ERROR_CODE_RUNTIME_SERIALIZE,
            format!("failed to parse Alfred payload: {error}"),
        )
    })?;

    let title = parsed
        .get("items")
        .and_then(serde_json::Value::as_array)
        .and_then(|items| items.first())
        .and_then(|item| item.get("title"))
        .and_then(serde_json::Value::as_str)
        .unwrap_or("");
    let subtitle = parsed
        .get("items")
        .and_then(serde_json::Value::as_array)
        .and_then(|items| items.first())
        .and_then(|item| item.get("subtitle"))
        .and_then(serde_json::Value::as_str)
        .unwrap_or("");

    if subtitle.is_empty() {
        Ok(title.to_string())
    } else {
        Ok(format!("{title} | {subtitle}"))
    }
}

fn emit_error(command: &str, output_mode: CliOutputMode, error: &CliError) {
    match output_mode {
        CliOutputMode::Json => {
            let payload = json!({
                "schema_version": ENVELOPE_SCHEMA_VERSION,
                "command": command,
                "ok": false,
                "error": {
                    "code": error.code,
                    "message": redact_sensitive(&error.message),
                    "details": {
                        "kind": error_kind_label(error.kind),
                        "exit_code": error.exit_code(),
                    }
                }
            });
            let rendered = serde_json::to_string(&payload).unwrap_or_else(|serialize_error| {
                format!(
                    "{{\"schema_version\":\"{}\",\"command\":\"{}\",\"ok\":false,\"error\":{{\"code\":\"{}\",\"message\":\"{}\"}}}}",
                    ENVELOPE_SCHEMA_VERSION,
                    command,
                    ERROR_CODE_RUNTIME_SERIALIZE,
                    escape_json_string(&format!(
                        "failed to serialize error envelope: {serialize_error}"
                    )),
                )
            });
            println!("{rendered}");
        }
        CliOutputMode::AlfredJson => {
            let payload = json!({
                "items": [{
                    "title": format!("Error [{}]", error.code),
                    "subtitle": redact_sensitive(&error.message),
                    "valid": false
                }]
            });
            let rendered = serde_json::to_string(&payload).unwrap_or_else(|_| {
                "{\"items\":[{\"title\":\"Error\",\"subtitle\":\"failed to serialize error output\",\"valid\":false}]}".to_string()
            });
            println!("{rendered}");
        }
        CliOutputMode::Human => {
            eprintln!(
                "error[{}]: {}",
                error.code,
                redact_sensitive(&error.message)
            );
        }
    }
}

fn user_error(code: &'static str, message: impl Into<String>) -> CliError {
    CliError::user(code, message)
}

fn runtime_error(code: &'static str, message: impl Into<String>) -> CliError {
    CliError::runtime(code, message)
}

fn map_app_error(error: AppError) -> CliError {
    match error.kind {
        market_cli::error::ErrorKind::User => {
            user_error(ERROR_CODE_USER_INVALID_INPUT, error.message)
        }
        market_cli::error::ErrorKind::Runtime => {
            runtime_error(ERROR_CODE_RUNTIME_PROVIDER_FAILED, error.message)
        }
    }
}

fn output_mode_label(mode: CliOutputMode) -> &'static str {
    match mode {
        CliOutputMode::Human => "human",
        CliOutputMode::Json => "json",
        CliOutputMode::AlfredJson => "alfred-json",
    }
}

fn error_kind_label(kind: market_cli::error::ErrorKind) -> &'static str {
    match kind {
        market_cli::error::ErrorKind::User => "user",
        market_cli::error::ErrorKind::Runtime => "runtime",
    }
}

fn cache_status_label(status: market_cli::model::CacheStatus) -> &'static str {
    match status {
        market_cli::model::CacheStatus::Live => "live",
        market_cli::model::CacheStatus::CacheFresh => "cache_fresh",
        market_cli::model::CacheStatus::CacheStaleFallback => "cache_stale_fallback",
    }
}

fn redact_sensitive(input: &str) -> String {
    let mut output = input.to_string();
    for pattern in [
        "token=",
        "token:",
        "secret=",
        "secret:",
        "client_secret=",
        "client_secret:",
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
        let value_start = skip_whitespace(input, start + pattern.len());
        let (redaction_start, value_end) = if is_authorization_pattern
            && input[value_start..]
                .to_ascii_lowercase()
                .starts_with("bearer ")
        {
            let bearer_start = value_start + "bearer ".len();
            (bearer_start, find_value_end(input, bearer_start))
        } else {
            (value_start, find_value_end(input, value_start))
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
            c if c < '\u{20}' => escaped.push_str(&format!("\\u{:04x}", c as u32)),
            c => escaped.push(c),
        }
    }
    escaped
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;
    use market_cli::{model::MarketQuote, providers::ProviderError};
    use serde_json::Value;

    use super::*;

    struct FakeProviders {
        fx_result: Result<MarketQuote, ProviderError>,
        crypto_coinbase_result: Result<MarketQuote, ProviderError>,
        crypto_kraken_result: Result<MarketQuote, ProviderError>,
    }

    impl FakeProviders {
        fn ok() -> Self {
            let now = Utc
                .with_ymd_and_hms(2026, 2, 10, 12, 0, 0)
                .single()
                .expect("time");
            Self {
                fx_result: Ok(MarketQuote::new(
                    "frankfurter",
                    rust_decimal::Decimal::new(321, 1),
                    now,
                )),
                crypto_coinbase_result: Ok(MarketQuote::new(
                    "coinbase",
                    rust_decimal::Decimal::new(670001, 1),
                    now,
                )),
                crypto_kraken_result: Ok(MarketQuote::new(
                    "kraken",
                    rust_decimal::Decimal::new(670000, 1),
                    now,
                )),
            }
        }
    }

    impl ProviderApi for FakeProviders {
        fn fetch_fx_rate(&self, _base: &str, _quote: &str) -> Result<MarketQuote, ProviderError> {
            self.fx_result.clone()
        }

        fn fetch_crypto_coinbase(
            &self,
            _base: &str,
            _quote: &str,
        ) -> Result<MarketQuote, ProviderError> {
            self.crypto_coinbase_result.clone()
        }

        fn fetch_crypto_kraken(
            &self,
            _base: &str,
            _quote: &str,
        ) -> Result<MarketQuote, ProviderError> {
            self.crypto_kraken_result.clone()
        }
    }

    fn config_in_tempdir() -> RuntimeConfig {
        RuntimeConfig {
            cache_dir: tempfile::tempdir().expect("tempdir").path().to_path_buf(),
        }
    }

    fn fixed_now() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 2, 10, 12, 5, 0)
            .single()
            .expect("time")
    }

    #[test]
    fn main_outputs_fx_json_contract() {
        let cli = Cli::parse_from([
            "market-cli",
            "fx",
            "--base",
            "USD",
            "--quote",
            "TWD",
            "--amount",
            "100",
            "--json",
        ]);

        let output = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect("fx should pass");
        let json: Value = serde_json::from_str(&output).expect("json");

        assert_eq!(
            json.get("schema_version").and_then(Value::as_str),
            Some("v1")
        );
        assert_eq!(
            json.get("command").and_then(Value::as_str),
            Some("market.fx")
        );
        assert_eq!(json.get("ok").and_then(Value::as_bool), Some(true));
        assert_eq!(
            json.get("result")
                .and_then(|result| result.get("kind"))
                .and_then(Value::as_str),
            Some("fx")
        );
        assert_eq!(
            json.get("result")
                .and_then(|result| result.get("base"))
                .and_then(Value::as_str),
            Some("USD")
        );
        assert!(
            json.get("result")
                .and_then(|result| result.get("cache"))
                .is_some()
        );
    }

    #[test]
    fn main_outputs_crypto_json_contract() {
        let cli = Cli::parse_from([
            "market-cli",
            "crypto",
            "--base",
            "BTC",
            "--quote",
            "USD",
            "--amount",
            "0.5",
            "--json",
        ]);

        let output = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect("crypto should pass");
        let json: Value = serde_json::from_str(&output).expect("json");

        assert_eq!(
            json.get("result")
                .and_then(|result| result.get("kind"))
                .and_then(Value::as_str),
            Some("crypto")
        );
        assert_eq!(
            json.get("result")
                .and_then(|result| result.get("provider"))
                .and_then(Value::as_str),
            Some("coinbase")
        );
        assert!(
            json.get("result")
                .and_then(|result| result.get("converted"))
                .is_some()
        );
    }

    #[test]
    fn main_maps_invalid_symbols_to_user_error() {
        let cli = Cli::parse_from([
            "market-cli",
            "fx",
            "--base",
            "USDT",
            "--quote",
            "TWD",
            "--amount",
            "100",
        ]);

        let err = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect_err("must fail");
        assert_eq!(err.kind, market_cli::error::ErrorKind::User);
        assert_eq!(err.code, ERROR_CODE_USER_INVALID_INPUT);
        assert_eq!(err.exit_code(), 2);
    }

    #[test]
    fn main_maps_runtime_provider_failure() {
        let cli = Cli::parse_from([
            "market-cli",
            "crypto",
            "--base",
            "BTC",
            "--quote",
            "USD",
            "--amount",
            "1",
        ]);

        let providers = FakeProviders {
            crypto_coinbase_result: Err(ProviderError::Transport("timeout".to_string())),
            crypto_kraken_result: Err(ProviderError::Http {
                status: 503,
                message: "down".to_string(),
            }),
            ..FakeProviders::ok()
        };

        let err =
            run_with(cli, &config_in_tempdir(), &providers, fixed_now).expect_err("must fail");
        assert_eq!(err.kind, market_cli::error::ErrorKind::Runtime);
        assert_eq!(err.code, ERROR_CODE_RUNTIME_PROVIDER_FAILED);
        assert_eq!(err.exit_code(), 1);
    }

    #[test]
    fn main_outputs_expr_alfred_json_contract() {
        let cli = Cli::parse_from(["market-cli", "expr", "--query", "1+5"]);
        let output = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect("expr should pass");
        let json: Value = serde_json::from_str(&output).expect("json");

        let items = json
            .get("items")
            .and_then(Value::as_array)
            .expect("items should be array");
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].get("title").and_then(Value::as_str), Some("6"));
    }

    #[test]
    fn main_maps_expr_syntax_error_to_user_error() {
        let cli = Cli::parse_from(["market-cli", "expr", "--query", "2 btc + 5"]);
        let err = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect_err("must fail");

        assert_eq!(err.kind, market_cli::error::ErrorKind::User);
        assert_eq!(err.code, ERROR_CODE_USER_INVALID_INPUT);
        assert_eq!(err.exit_code(), 2);
    }

    #[test]
    fn main_outputs_fx_human_mode_by_default() {
        let cli = Cli::parse_from([
            "market-cli",
            "fx",
            "--base",
            "USD",
            "--quote",
            "TWD",
            "--amount",
            "100",
        ]);
        let output = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect("fx should pass");

        assert!(output.contains("USD"));
        assert!(output.contains("provider=frankfurter"));
    }

    #[test]
    fn main_outputs_fx_alfred_json_mode_when_requested() {
        let cli = Cli::parse_from([
            "market-cli",
            "fx",
            "--base",
            "USD",
            "--quote",
            "TWD",
            "--amount",
            "100",
            "--output",
            "alfred-json",
        ]);
        let output = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect("fx should pass");
        let json: Value = serde_json::from_str(&output).expect("json");
        let first_item = json
            .get("items")
            .and_then(Value::as_array)
            .and_then(|items| items.first())
            .expect("first item");

        assert!(first_item.get("title").is_some());
    }

    #[test]
    fn main_outputs_expr_json_envelope_when_requested() {
        let cli = Cli::parse_from(["market-cli", "expr", "--query", "1+5", "--json"]);
        let output = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect("expr should pass");
        let json: Value = serde_json::from_str(&output).expect("json");

        assert_eq!(
            json.get("schema_version").and_then(Value::as_str),
            Some("v1")
        );
        assert_eq!(
            json.get("command").and_then(Value::as_str),
            Some("market.expr")
        );
        assert_eq!(json.get("ok").and_then(Value::as_bool), Some(true));
        assert!(json.get("result").is_some());
    }

    #[test]
    fn main_rejects_conflicting_json_flags() {
        let cli = Cli::parse_from([
            "market-cli",
            "fx",
            "--base",
            "USD",
            "--quote",
            "TWD",
            "--amount",
            "100",
            "--json",
            "--output",
            "human",
        ]);
        let err = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect_err("must fail");

        assert_eq!(err.kind, market_cli::error::ErrorKind::User);
        assert_eq!(err.code, ERROR_CODE_USER_OUTPUT_MODE_CONFLICT);
    }

    #[test]
    fn main_redacts_sensitive_error_fragments() {
        let redacted = redact_sensitive(
            "authorization: Bearer abc token=xyz secret=hidden client_secret:demo",
        );
        assert!(!redacted.contains("abc"));
        assert!(!redacted.contains("xyz"));
        assert!(!redacted.contains("hidden"));
        assert!(!redacted.contains("demo"));
        assert!(redacted.contains("Bearer [REDACTED]"));
    }

    #[test]
    fn main_help_flag_is_supported() {
        let help = Cli::try_parse_from(["market-cli", "--help"]).expect_err("help");
        assert_eq!(help.kind(), clap::error::ErrorKind::DisplayHelp);
    }
}
