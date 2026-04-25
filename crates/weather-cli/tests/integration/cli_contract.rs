use std::path::PathBuf;
use std::process::{Command, Output};

use serde_json::Value;
use weather_cli::model::{
    CacheMetadata, ForecastBatchEntry, ForecastBatchOutput, ForecastDay, ForecastLocation,
    ForecastOutput, ForecastPeriod, FreshnessStatus,
};

fn run_cli(args: &[&str], envs: &[(&str, &str)]) -> Output {
    let mut cmd = Command::new(resolve_cli_path());
    cmd.args(args);
    for (key, value) in envs {
        cmd.env(key, value);
    }
    cmd.output().expect("run weather-cli")
}

#[test]
fn cli_contract_output_contains_required_fields_for_today() {
    let output = ForecastOutput {
        period: ForecastPeriod::Today,
        location: ForecastLocation {
            name: "Taipei City".to_string(),
            latitude: 25.0531,
            longitude: 121.5264,
        },
        timezone: "Asia/Taipei".to_string(),
        forecast: vec![ForecastDay {
            date: "2026-02-11".to_string(),
            weather_code: 3,
            summary_zh: "陰天".to_string(),
            temp_min_c: 14.5,
            temp_max_c: 19.9,
            precip_prob_max_pct: 13,
        }],
        source: "open_meteo".to_string(),
        source_trace: vec![],
        fetched_at: "2026-02-11T03:30:00Z".to_string(),
        freshness: CacheMetadata {
            status: FreshnessStatus::Live,
            key: "today-taipei-city-25.0531-121.5264".to_string(),
            ttl_secs: 1800,
            age_secs: 0,
        },
    };

    let value = serde_json::to_value(output).expect("json");

    for field in [
        "period",
        "location",
        "timezone",
        "forecast",
        "source",
        "fetched_at",
        "freshness",
    ] {
        assert!(value.get(field).is_some(), "missing field: {field}");
    }
}

#[test]
fn cli_contract_freshness_status_serializes_in_snake_case() {
    let output = ForecastOutput {
        period: ForecastPeriod::Week,
        location: ForecastLocation {
            name: "Taipei City".to_string(),
            latitude: 25.0531,
            longitude: 121.5264,
        },
        timezone: "Asia/Taipei".to_string(),
        forecast: vec![],
        source: "met_no".to_string(),
        source_trace: vec!["open_meteo: timeout".to_string()],
        fetched_at: "2026-02-11T03:30:00Z".to_string(),
        freshness: CacheMetadata {
            status: FreshnessStatus::CacheStaleFallback,
            key: "week-taipei-city-25.0531-121.5264".to_string(),
            ttl_secs: 1800,
            age_secs: 7200,
        },
    };

    let value = serde_json::to_value(output).expect("json");
    assert_eq!(
        value
            .get("freshness")
            .and_then(|f| f.get("status"))
            .and_then(serde_json::Value::as_str),
        Some("cache_stale_fallback")
    );
}

#[test]
fn cli_contract_batch_output_contains_entries_and_city_key() {
    let output = ForecastBatchOutput {
        period: ForecastPeriod::Today,
        entries: vec![ForecastBatchEntry {
            city: "Taipei".to_string(),
            result: Some(ForecastOutput {
                period: ForecastPeriod::Today,
                location: ForecastLocation {
                    name: "Taipei".to_string(),
                    latitude: 25.033,
                    longitude: 121.5654,
                },
                timezone: "Asia/Taipei".to_string(),
                forecast: vec![ForecastDay {
                    date: "2026-02-11".to_string(),
                    weather_code: 3,
                    summary_zh: "陰天".to_string(),
                    temp_min_c: 14.5,
                    temp_max_c: 19.9,
                    precip_prob_max_pct: 13,
                }],
                source: "open_meteo".to_string(),
                source_trace: vec![],
                fetched_at: "2026-02-11T03:30:00Z".to_string(),
                freshness: CacheMetadata {
                    status: FreshnessStatus::Live,
                    key: "today-taipei-25.0330-121.5654".to_string(),
                    ttl_secs: 1800,
                    age_secs: 0,
                },
            }),
            error: None,
        }],
    };

    let value = serde_json::to_value(output).expect("json");
    assert_eq!(
        value
            .get("entries")
            .and_then(Value::as_array)
            .and_then(|entries| entries.first())
            .and_then(|entry| entry.get("city"))
            .and_then(Value::as_str),
        Some("Taipei")
    );
}

#[test]
fn service_json_error_envelope_has_required_keys() {
    let output = run_cli(
        &["today", "--output", "json"],
        &[("WEATHER_TEST_SECRET", "unused")],
    );
    assert_eq!(output.status.code(), Some(2));

    let json: Value = serde_json::from_slice(&output.stdout).expect("stdout should be json");
    assert_eq!(
        json.get("schema_version").and_then(Value::as_str),
        Some("cli-envelope@v1")
    );
    assert_eq!(
        json.get("command").and_then(Value::as_str),
        Some("weather.today")
    );
    assert_eq!(json.get("ok").and_then(Value::as_bool), Some(false));
    assert_eq!(
        json.get("error")
            .and_then(|error| error.get("code"))
            .and_then(Value::as_str),
        Some("user.invalid_input")
    );
    assert!(
        json.get("error")
            .and_then(|error| error.get("details"))
            .is_some()
    );
}

#[test]
fn unknown_output_value_is_rejected_by_clap() {
    let output = run_cli(&["today", "--city", "Taipei", "--output", "yaml"], &[]);
    assert_eq!(output.status.code(), Some(2));
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("invalid value 'yaml'"),
        "expected clap rejection message, got: {stderr}"
    );
}

fn resolve_cli_path() -> PathBuf {
    if let Some(path) = std::env::var_os("CARGO_BIN_EXE_weather-cli") {
        return PathBuf::from(path);
    }

    if let Ok(current_exe) = std::env::current_exe()
        && let Some(debug_dir) = current_exe.parent().and_then(|deps| deps.parent())
    {
        let candidate = debug_dir.join(format!("weather-cli{}", std::env::consts::EXE_SUFFIX));
        if candidate.exists() {
            return candidate;
        }
    }

    PathBuf::from(env!("CARGO_BIN_EXE_weather-cli"))
}
