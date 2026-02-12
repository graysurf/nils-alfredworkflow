use chrono::{DateTime, Utc};
use clap::{Parser, Subcommand, ValueEnum};
use serde_json::json;

use weather_cli::{
    config::RuntimeConfig,
    error::AppError,
    model::{ForecastPeriod, ForecastRequest, OutputMode as RequestOutputMode},
    providers::{HttpProviders, ProviderApi},
    service,
};

#[cfg(test)]
use weather_cli::{
    geocoding::ResolvedLocation,
    providers::{ProviderError, ProviderForecast, ProviderForecastDay},
};

#[derive(Debug, Parser)]
#[command(author, version, about = "Weather forecast CLI (free no-token APIs)")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Today weather forecast.
    Today {
        #[arg(long)]
        city: Option<String>,
        #[arg(long)]
        lat: Option<f64>,
        #[arg(long)]
        lon: Option<f64>,
        #[arg(long, value_enum)]
        output: Option<OutputModeArg>,
        #[arg(long)]
        json: bool,
        #[arg(long, value_enum)]
        lang: Option<LanguageArg>,
    },
    /// 7-day weather forecast.
    Week {
        #[arg(long)]
        city: Option<String>,
        #[arg(long)]
        lat: Option<f64>,
        #[arg(long)]
        lon: Option<f64>,
        #[arg(long, value_enum)]
        output: Option<OutputModeArg>,
        #[arg(long)]
        json: bool,
        #[arg(long, value_enum)]
        lang: Option<LanguageArg>,
    },
}

const ENVELOPE_SCHEMA_VERSION: &str = "v1";
const ERROR_CODE_USER_INVALID_INPUT: &str = "user.invalid_input";
const ERROR_CODE_USER_OUTPUT_MODE_CONFLICT: &str = "user.output_mode_conflict";
const ERROR_CODE_RUNTIME_PROVIDER_INIT: &str = "runtime.provider_init_failed";
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum LanguageArg {
    En,
    Zh,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum OutputLanguage {
    En,
    Zh,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CliError {
    kind: weather_cli::error::ErrorKind,
    code: &'static str,
    message: String,
}

impl CliError {
    fn user(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            kind: weather_cli::error::ErrorKind::User,
            code,
            message: message.into(),
        }
    }

    fn runtime(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            kind: weather_cli::error::ErrorKind::Runtime,
            code,
            message: message.into(),
        }
    }

    fn exit_code(&self) -> i32 {
        match self.kind {
            weather_cli::error::ErrorKind::User => 2,
            weather_cli::error::ErrorKind::Runtime => 1,
        }
    }
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

impl From<LanguageArg> for OutputLanguage {
    fn from(value: LanguageArg) -> Self {
        match value {
            LanguageArg::En => OutputLanguage::En,
            LanguageArg::Zh => OutputLanguage::Zh,
        }
    }
}

impl Cli {
    fn command_name(&self) -> &'static str {
        match &self.command {
            Commands::Today { .. } => "weather.today",
            Commands::Week { .. } => "weather.week",
        }
    }

    fn output_mode_hint(&self) -> CliOutputMode {
        match &self.command {
            Commands::Today { output, json, .. } | Commands::Week { output, json, .. } => {
                if *json {
                    CliOutputMode::Json
                } else if let Some(explicit) = output {
                    (*explicit).into()
                } else {
                    CliOutputMode::Human
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
        Ok(output) => println!("{output}"),
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
        Commands::Today {
            city,
            lat,
            lon,
            output,
            json,
            lang,
        } => run_command(
            config,
            providers,
            now_fn,
            CommandArgs {
                command: "weather.today",
                period: ForecastPeriod::Today,
                city: city.as_deref(),
                lat,
                lon,
                output,
                json,
                lang,
            },
        ),
        Commands::Week {
            city,
            lat,
            lon,
            output,
            json,
            lang,
        } => run_command(
            config,
            providers,
            now_fn,
            CommandArgs {
                command: "weather.week",
                period: ForecastPeriod::Week,
                city: city.as_deref(),
                lat,
                lon,
                output,
                json,
                lang,
            },
        ),
    }
}

#[derive(Debug, Clone, Copy)]
struct CommandArgs<'a> {
    command: &'static str,
    period: ForecastPeriod,
    city: Option<&'a str>,
    lat: Option<f64>,
    lon: Option<f64>,
    output: Option<OutputModeArg>,
    json: bool,
    lang: Option<LanguageArg>,
}

fn run_command<P, N>(
    config: &RuntimeConfig,
    providers: &P,
    now_fn: N,
    args: CommandArgs<'_>,
) -> Result<String, CliError>
where
    P: ProviderApi,
    N: Fn() -> DateTime<Utc>,
{
    let output_mode = resolve_output_mode(args.output, args.json, CliOutputMode::Human)?;
    let output_language = args.lang.map(Into::into).unwrap_or(OutputLanguage::En);
    let request_mode = match output_mode {
        CliOutputMode::Json => RequestOutputMode::Json,
        CliOutputMode::Human | CliOutputMode::AlfredJson => RequestOutputMode::Text,
    };
    let request = ForecastRequest::new(args.period, args.city, args.lat, args.lon, request_mode)
        .map_err(user_invalid_input)?;
    let output =
        service::resolve_forecast(config, providers, now_fn, &request).map_err(map_app_error)?;

    match output_mode {
        CliOutputMode::Json => render_service_json_envelope(args.command, &output),
        CliOutputMode::Human => Ok(format_text_output(&output, output_language)),
        CliOutputMode::AlfredJson => render_alfred_json(&output, output_language),
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

fn render_service_json_envelope(
    command: &str,
    output: &weather_cli::model::ForecastOutput,
) -> Result<String, CliError> {
    let result = serde_json::to_value(output).map_err(|error| {
        runtime_error(
            ERROR_CODE_RUNTIME_SERIALIZE,
            format!("failed to serialize output: {error}"),
        )
    })?;
    serde_json::to_string(&json!({
        "schema_version": ENVELOPE_SCHEMA_VERSION,
        "command": command,
        "ok": true,
        "result": result,
    }))
    .map_err(|error| {
        runtime_error(
            ERROR_CODE_RUNTIME_SERIALIZE,
            format!("failed to serialize output envelope: {error}"),
        )
    })
}

fn render_alfred_json(
    output: &weather_cli::model::ForecastOutput,
    language: OutputLanguage,
) -> Result<String, CliError> {
    let mut items = Vec::with_capacity(output.forecast.len() + 1);
    items.push(json!({
        "title": format!("{} ({})", output.location.name, output.timezone),
        "subtitle": format!(
            "source={} freshness={} lat={:.4} lon={:.4}",
            output.source,
            freshness_label(output.freshness.status),
            output.location.latitude,
            output.location.longitude
        ),
        "arg": output.location.name,
        "valid": false,
    }));

    for day in &output.forecast {
        let summary = localized_summary(day, language);
        items.push(json!({
            "title": format!(
                "{} {} {:.1}~{:.1}°C",
                day.date, summary, day.temp_min_c, day.temp_max_c
            ),
            "subtitle": format!("{}:{}%", precip_label(language), day.precip_prob_max_pct),
            "arg": day.date,
            "valid": false,
        }));
    }

    serde_json::to_string(&json!({ "items": items })).map_err(|error| {
        runtime_error(
            ERROR_CODE_RUNTIME_SERIALIZE,
            format!("failed to serialize Alfred output: {error}"),
        )
    })
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

fn user_invalid_input(error: weather_cli::model::ValidationError) -> CliError {
    user_error(ERROR_CODE_USER_INVALID_INPUT, error.to_string())
}

fn user_error(code: &'static str, message: impl Into<String>) -> CliError {
    CliError::user(code, message)
}

fn runtime_error(code: &'static str, message: impl Into<String>) -> CliError {
    CliError::runtime(code, message)
}

fn map_app_error(error: AppError) -> CliError {
    match error.kind {
        weather_cli::error::ErrorKind::User => {
            user_error(ERROR_CODE_USER_INVALID_INPUT, error.message)
        }
        weather_cli::error::ErrorKind::Runtime => {
            runtime_error("runtime.provider_failed", error.message)
        }
    }
}

fn error_kind_label(kind: weather_cli::error::ErrorKind) -> &'static str {
    match kind {
        weather_cli::error::ErrorKind::User => "user",
        weather_cli::error::ErrorKind::Runtime => "runtime",
    }
}

fn output_mode_label(mode: CliOutputMode) -> &'static str {
    match mode {
        CliOutputMode::Human => "human",
        CliOutputMode::Json => "json",
        CliOutputMode::AlfredJson => "alfred-json",
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

fn format_text_output(
    output: &weather_cli::model::ForecastOutput,
    language: OutputLanguage,
) -> String {
    let mut lines = vec![format!(
        "{} ({}) | source={} | freshness={}",
        output.location.name,
        output.timezone,
        output.source,
        freshness_label(output.freshness.status)
    )];

    for day in &output.forecast {
        let summary = localized_summary(day, language);
        lines.push(format!(
            "{} {} {:.1}~{:.1}°C {}:{}%",
            day.date,
            summary,
            day.temp_min_c,
            day.temp_max_c,
            precip_label(language),
            day.precip_prob_max_pct
        ));
    }

    lines.join("\n")
}

fn localized_summary(day: &weather_cli::model::ForecastDay, language: OutputLanguage) -> String {
    match language {
        OutputLanguage::En => weather_cli::weather_code::summary_en(day.weather_code).to_string(),
        OutputLanguage::Zh => day.summary_zh.clone(),
    }
}

fn precip_label(language: OutputLanguage) -> &'static str {
    match language {
        OutputLanguage::En => "rain",
        OutputLanguage::Zh => "降雨",
    }
}

fn freshness_label(status: weather_cli::model::FreshnessStatus) -> &'static str {
    match status {
        weather_cli::model::FreshnessStatus::Live => "live",
        weather_cli::model::FreshnessStatus::CacheFresh => "cache_fresh",
        weather_cli::model::FreshnessStatus::CacheStaleFallback => "cache_stale_fallback",
    }
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;
    use serde_json::Value;

    use super::*;

    struct FakeProviders {
        geocode_result: Result<ResolvedLocation, ProviderError>,
        open_meteo_result: Result<ProviderForecast, ProviderError>,
        met_no_result: Result<ProviderForecast, ProviderError>,
    }

    impl FakeProviders {
        fn ok() -> Self {
            let now = Utc
                .with_ymd_and_hms(2026, 2, 11, 0, 0, 0)
                .single()
                .expect("time");

            Self {
                geocode_result: Ok(ResolvedLocation {
                    name: "Taipei City".to_string(),
                    latitude: 25.05,
                    longitude: 121.52,
                    timezone: "Asia/Taipei".to_string(),
                }),
                open_meteo_result: Ok(ProviderForecast {
                    timezone: "Asia/Taipei".to_string(),
                    fetched_at: now,
                    days: vec![ProviderForecastDay {
                        date: "2026-02-11".to_string(),
                        weather_code: 3,
                        temp_min_c: 14.5,
                        temp_max_c: 20.1,
                        precip_prob_max_pct: 20,
                    }],
                }),
                met_no_result: Ok(ProviderForecast {
                    timezone: "UTC".to_string(),
                    fetched_at: now,
                    days: vec![ProviderForecastDay {
                        date: "2026-02-11".to_string(),
                        weather_code: 61,
                        temp_min_c: 11.0,
                        temp_max_c: 15.0,
                        precip_prob_max_pct: 70,
                    }],
                }),
            }
        }
    }

    impl ProviderApi for FakeProviders {
        fn geocode_city(&self, _city: &str) -> Result<ResolvedLocation, ProviderError> {
            self.geocode_result.clone()
        }

        fn fetch_open_meteo_forecast(
            &self,
            _lat: f64,
            _lon: f64,
            _forecast_days: usize,
        ) -> Result<ProviderForecast, ProviderError> {
            self.open_meteo_result.clone()
        }

        fn fetch_met_no_forecast(
            &self,
            _lat: f64,
            _lon: f64,
            _forecast_days: usize,
        ) -> Result<ProviderForecast, ProviderError> {
            self.met_no_result.clone()
        }
    }

    fn config_in_tempdir() -> RuntimeConfig {
        RuntimeConfig {
            cache_dir: tempfile::tempdir().expect("tempdir").path().to_path_buf(),
        }
    }

    fn fixed_now() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 2, 11, 0, 5, 0)
            .single()
            .expect("time")
    }

    #[test]
    fn main_outputs_today_json_contract() {
        let cli = Cli::parse_from(["weather-cli", "today", "--city", "Taipei", "--json"]);

        let output = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect("today should pass");
        let json: Value = serde_json::from_str(&output).expect("json");

        assert_eq!(
            json.get("schema_version").and_then(Value::as_str),
            Some("v1")
        );
        assert_eq!(
            json.get("command").and_then(Value::as_str),
            Some("weather.today")
        );
        assert_eq!(json.get("ok").and_then(Value::as_bool), Some(true));
        assert_eq!(
            json.get("result")
                .and_then(|result| result.get("period"))
                .and_then(Value::as_str),
            Some("today")
        );
        assert_eq!(
            json.get("result")
                .and_then(|result| result.get("location"))
                .and_then(|x| x.get("name"))
                .and_then(Value::as_str),
            Some("Taipei City")
        );
        assert!(
            json.get("result")
                .and_then(|result| result.get("forecast"))
                .is_some()
        );
    }

    #[test]
    fn main_outputs_week_json_contract() {
        let mut providers = FakeProviders::ok();
        providers.open_meteo_result = Ok(ProviderForecast {
            timezone: "Asia/Taipei".to_string(),
            fetched_at: Utc
                .with_ymd_and_hms(2026, 2, 11, 0, 0, 0)
                .single()
                .expect("time"),
            days: (0..7)
                .map(|i| ProviderForecastDay {
                    date: format!("2026-02-1{}", i + 1),
                    weather_code: 2,
                    temp_min_c: 14.0 + i as f64,
                    temp_max_c: 20.0 + i as f64,
                    precip_prob_max_pct: 10 + i as u8,
                })
                .collect(),
        });

        let cli = Cli::parse_from(["weather-cli", "week", "--city", "Taipei", "--json"]);

        let output =
            run_with(cli, &config_in_tempdir(), &providers, fixed_now).expect("week should pass");
        let json: Value = serde_json::from_str(&output).expect("json");

        assert_eq!(
            json.get("schema_version").and_then(Value::as_str),
            Some("v1")
        );
        assert_eq!(
            json.get("command").and_then(Value::as_str),
            Some("weather.week")
        );
        assert_eq!(
            json.get("result")
                .and_then(|result| result.get("period"))
                .and_then(Value::as_str),
            Some("week")
        );
        assert_eq!(
            json.get("result")
                .and_then(|result| result.get("forecast"))
                .and_then(Value::as_array)
                .map(Vec::len),
            Some(7)
        );
    }

    #[test]
    fn main_maps_invalid_input_to_user_error() {
        let cli = Cli::parse_from([
            "weather-cli",
            "today",
            "--city",
            "Taipei",
            "--lat",
            "25.0",
            "--lon",
            "121.5",
        ]);

        let err = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect_err("must fail");

        assert_eq!(err.kind, weather_cli::error::ErrorKind::User);
        assert_eq!(err.code, ERROR_CODE_USER_INVALID_INPUT);
        assert_eq!(err.exit_code(), 2);
    }

    #[test]
    fn main_maps_runtime_provider_failure() {
        let cli = Cli::parse_from(["weather-cli", "today", "--city", "Taipei", "--json"]);

        let providers = FakeProviders {
            open_meteo_result: Err(ProviderError::Transport("timeout".to_string())),
            met_no_result: Err(ProviderError::Http {
                status: 503,
                message: "down".to_string(),
            }),
            ..FakeProviders::ok()
        };

        let err =
            run_with(cli, &config_in_tempdir(), &providers, fixed_now).expect_err("must fail");
        assert_eq!(err.kind, weather_cli::error::ErrorKind::Runtime);
        assert_eq!(err.code, "runtime.provider_failed");
        assert_eq!(err.exit_code(), 1);
    }

    #[test]
    fn exit_code_mapping_user_and_runtime_are_stable() {
        assert_eq!(weather_cli::error::AppError::user("x").exit_code(), 2);
        assert_eq!(weather_cli::error::AppError::runtime("x").exit_code(), 1);
    }

    #[test]
    fn main_outputs_text_mode_when_json_flag_not_set() {
        let cli = Cli::parse_from(["weather-cli", "today", "--city", "Taipei"]);
        let output = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect("text mode");

        assert!(output.contains("Taipei City"));
        assert!(output.contains("source=open_meteo"));
        assert!(output.contains("Cloudy"));
        assert!(output.contains("rain:20%"));
    }

    #[test]
    fn main_outputs_text_mode_in_zh_when_requested() {
        let cli = Cli::parse_from(["weather-cli", "today", "--city", "Taipei", "--lang", "zh"]);
        let output = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect("zh text mode");

        assert!(output.contains("陰天"));
        assert!(output.contains("降雨:20%"));
    }

    #[test]
    fn main_outputs_alfred_json_mode_when_requested() {
        let cli = Cli::parse_from([
            "weather-cli",
            "today",
            "--city",
            "Taipei",
            "--output",
            "alfred-json",
        ]);

        let output = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect("alfred mode");
        let json: Value = serde_json::from_str(&output).expect("json");

        let first_item = json
            .get("items")
            .and_then(Value::as_array)
            .and_then(|items| items.first())
            .expect("first item");
        assert!(first_item.get("title").is_some());

        let second_item_title = json
            .get("items")
            .and_then(Value::as_array)
            .and_then(|items| items.get(1))
            .and_then(|item| item.get("title"))
            .and_then(Value::as_str);
        assert_eq!(second_item_title, Some("2026-02-11 Cloudy 14.5~20.1°C"));
    }

    #[test]
    fn main_outputs_alfred_json_mode_in_zh_when_requested() {
        let cli = Cli::parse_from([
            "weather-cli",
            "today",
            "--city",
            "Taipei",
            "--output",
            "alfred-json",
            "--lang",
            "zh",
        ]);

        let output = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect("alfred zh mode");
        let json: Value = serde_json::from_str(&output).expect("json");

        let second_item_title = json
            .get("items")
            .and_then(Value::as_array)
            .and_then(|items| items.get(1))
            .and_then(|item| item.get("title"))
            .and_then(Value::as_str);
        assert_eq!(second_item_title, Some("2026-02-11 陰天 14.5~20.1°C"));
    }

    #[test]
    fn main_rejects_conflicting_json_flags() {
        let cli = Cli::parse_from([
            "weather-cli",
            "today",
            "--city",
            "Taipei",
            "--json",
            "--output",
            "human",
        ]);

        let err = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect_err("must fail");
        assert_eq!(err.kind, weather_cli::error::ErrorKind::User);
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
        let help = Cli::try_parse_from(["weather-cli", "--help"]).expect_err("help");
        assert_eq!(help.kind(), clap::error::ErrorKind::DisplayHelp);
    }
}
