use std::collections::{BTreeMap, HashMap};
use std::time::Duration;

use chrono::{DateTime, Utc};
use reqwest::blocking::Client;
use reqwest::header::USER_AGENT;
use serde::Deserialize;
use serde_json::Value;

use crate::config::{MET_NO_USER_AGENT, RetryPolicy};

use super::{ProviderError, ProviderForecast, ProviderForecastDay, execute_with_retry};

const MET_NO_COMPACT_ENDPOINT: &str = "https://api.met.no/weatherapi/locationforecast/2.0/compact";

pub fn fetch_forecast(
    client: &Client,
    lat: f64,
    lon: f64,
    forecast_days: usize,
    retry_policy: RetryPolicy,
) -> Result<ProviderForecast, ProviderError> {
    fetch_forecast_with_endpoint_and_sleep(
        client,
        MET_NO_COMPACT_ENDPOINT,
        lat,
        lon,
        forecast_days,
        retry_policy,
        std::thread::sleep,
    )
}

fn fetch_forecast_with_endpoint_and_sleep<S>(
    client: &Client,
    endpoint: &str,
    lat: f64,
    lon: f64,
    forecast_days: usize,
    retry_policy: RetryPolicy,
    sleep_fn: S,
) -> Result<ProviderForecast, ProviderError>
where
    S: FnMut(Duration),
{
    if forecast_days == 0 {
        return Ok(ProviderForecast {
            timezone: "UTC".to_string(),
            fetched_at: Utc::now(),
            days: Vec::new(),
        });
    }

    execute_with_retry(
        "met_no",
        retry_policy,
        || fetch_forecast_once(client, endpoint, lat, lon, forecast_days),
        sleep_fn,
    )
}

fn fetch_forecast_once(
    client: &Client,
    endpoint: &str,
    lat: f64,
    lon: f64,
    forecast_days: usize,
) -> Result<ProviderForecast, ProviderError> {
    let response = client
        .get(endpoint)
        .query(&[("lat", lat), ("lon", lon)])
        .header(USER_AGENT, MET_NO_USER_AGENT)
        .send()
        .map_err(|error| ProviderError::Transport(error.to_string()))?;

    let status = response.status();
    let response_body = response
        .text()
        .map_err(|error| ProviderError::Transport(error.to_string()))?;

    if !status.is_success() {
        return Err(ProviderError::Http {
            status: status.as_u16(),
            message: extract_http_error_message(&response_body, status.as_u16()),
        });
    }

    let parsed: MetNoForecastResponse = serde_json::from_str(&response_body).map_err(|error| {
        ProviderError::InvalidResponse(format!("failed to decode MET Norway response: {error}"))
    })?;

    parse_provider_forecast(parsed, forecast_days)
}

fn parse_provider_forecast(
    payload: MetNoForecastResponse,
    forecast_days: usize,
) -> Result<ProviderForecast, ProviderError> {
    if payload.properties.timeseries.is_empty() {
        return Err(ProviderError::InvalidResponse(
            "MET Norway response has empty timeseries".to_string(),
        ));
    }

    let fetched_at = payload
        .properties
        .meta
        .as_ref()
        .and_then(|meta| meta.updated_at.as_deref())
        .and_then(parse_rfc3339_utc)
        .unwrap_or_else(Utc::now);

    let mut daily = BTreeMap::<String, DailyAccumulator>::new();

    for point in payload.properties.timeseries {
        let datetime = parse_rfc3339_utc(&point.time).ok_or_else(|| {
            ProviderError::InvalidResponse(format!(
                "MET Norway response contains invalid time '{}'",
                point.time
            ))
        })?;

        let day_key = datetime.format("%Y-%m-%d").to_string();
        let entry = daily.entry(day_key).or_default();

        entry.observe_temperature(point.data.instant.details.air_temperature);

        if let Some(code) = point.data.primary_weather_code() {
            entry.observe_weather_code(code);
        }

        for prob in point.data.precipitation_probabilities() {
            entry.observe_precip_probability(prob);
        }
    }

    let mut days = Vec::with_capacity(daily.len().min(forecast_days));

    for (date, stats) in daily {
        days.push(ProviderForecastDay {
            date,
            weather_code: stats.choose_weather_code(),
            temp_min_c: stats.temp_min_c.ok_or_else(|| {
                ProviderError::InvalidResponse(
                    "MET Norway response missing minimum daily temperature".to_string(),
                )
            })?,
            temp_max_c: stats.temp_max_c.ok_or_else(|| {
                ProviderError::InvalidResponse(
                    "MET Norway response missing maximum daily temperature".to_string(),
                )
            })?,
            precip_prob_max_pct: stats.precip_prob_max_pct,
        });
    }

    if days.len() < forecast_days {
        return Err(ProviderError::InvalidResponse(format!(
            "MET Norway response does not include {forecast_days} forecast days"
        )));
    }

    days.truncate(forecast_days);

    Ok(ProviderForecast {
        timezone: "UTC".to_string(),
        fetched_at,
        days,
    })
}

fn parse_rfc3339_utc(value: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|dt| dt.with_timezone(&Utc))
}

fn extract_http_error_message(body: &str, status: u16) -> String {
    let trimmed = body.trim();
    if trimmed.is_empty() {
        return format!("HTTP {status}");
    }

    if let Ok(json) = serde_json::from_str::<Value>(trimmed)
        && let Some(message) = extract_message_from_json(&json)
    {
        return message;
    }

    const MAX_LEN: usize = 240;
    if trimmed.len() > MAX_LEN {
        format!("{}...", &trimmed[..MAX_LEN])
    } else {
        trimmed.to_string()
    }
}

fn extract_message_from_json(value: &Value) -> Option<String> {
    match value {
        Value::String(text) => {
            let trimmed = text.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        }
        Value::Object(map) => {
            const CANDIDATE_KEYS: [&str; 7] = [
                "message",
                "error",
                "reason",
                "detail",
                "description",
                "title",
                "status",
            ];

            for key in CANDIDATE_KEYS {
                if let Some(message) = map.get(key).and_then(extract_message_from_json) {
                    return Some(message);
                }
            }

            for value in map.values() {
                if let Some(message) = extract_message_from_json(value) {
                    return Some(message);
                }
            }

            None
        }
        Value::Array(items) => items.iter().find_map(extract_message_from_json),
        _ => None,
    }
}

fn met_symbol_to_open_meteo_code(symbol: &str) -> i32 {
    let normalized = symbol.split('_').next().unwrap_or(symbol);

    match normalized {
        "clearsky" => 0,
        "fair" => 1,
        "partlycloudy" => 2,
        "cloudy" => 3,
        "fog" => 45,
        "lightrain" => 61,
        "rain" => 63,
        "heavyrain" => 65,
        "lightsleet" => 66,
        "sleet" => 67,
        "heavysleet" => 67,
        "lightsnow" => 71,
        "snow" => 73,
        "heavysnow" => 75,
        "lightrainshowers" => 80,
        "rainshowers" => 81,
        "heavyrainshowers" => 82,
        "lightsleetshowers" => 81,
        "sleetshowers" => 82,
        "heavysleetshowers" => 82,
        "lightsnowshowers" => 85,
        "snowshowers" => 85,
        "heavysnowshowers" => 86,
        "lightrainandthunder" => 95,
        "rainandthunder" => 95,
        "heavyrainandthunder" => 99,
        "lightrainshowersandthunder" => 95,
        "rainshowersandthunder" => 95,
        "heavyrainshowersandthunder" => 99,
        "lightsleetandthunder" => 96,
        "sleetandthunder" => 96,
        "heavysleetandthunder" => 99,
        "lightsleetshowersandthunder" => 96,
        "sleetshowersandthunder" => 96,
        "heavysleetshowersandthunder" => 99,
        "lightsnowandthunder" => 99,
        "snowandthunder" => 99,
        "heavysnowandthunder" => 99,
        "lightsnowshowersandthunder" => 99,
        "snowshowersandthunder" => 99,
        "heavysnowshowersandthunder" => 99,
        _ => 3,
    }
}

fn weather_severity(code: i32) -> i32 {
    match code {
        95 | 96 | 99 => 9,
        75 | 82 | 86 => 8,
        65 | 67 | 73 | 81 | 85 => 7,
        61 | 63 | 66 | 71 | 80 => 6,
        51 | 53 | 55 | 56 | 57 => 5,
        45 | 48 => 4,
        3 => 3,
        2 => 2,
        1 => 1,
        0 => 0,
        _ => 1,
    }
}

#[derive(Debug, Default)]
struct DailyAccumulator {
    temp_min_c: Option<f64>,
    temp_max_c: Option<f64>,
    precip_prob_max_pct: u8,
    weather_counts: HashMap<i32, usize>,
}

impl DailyAccumulator {
    fn observe_temperature(&mut self, temp_c: f64) {
        self.temp_min_c = Some(
            self.temp_min_c
                .map_or(temp_c, |current| current.min(temp_c)),
        );
        self.temp_max_c = Some(
            self.temp_max_c
                .map_or(temp_c, |current| current.max(temp_c)),
        );
    }

    fn observe_weather_code(&mut self, code: i32) {
        *self.weather_counts.entry(code).or_insert(0) += 1;
    }

    fn observe_precip_probability(&mut self, probability_pct: f64) {
        if probability_pct.is_finite() {
            let normalized = probability_pct.clamp(0.0, 100.0).round() as u8;
            self.precip_prob_max_pct = self.precip_prob_max_pct.max(normalized);
        }
    }

    fn choose_weather_code(&self) -> i32 {
        self.weather_counts
            .iter()
            .max_by(|(code_a, count_a), (code_b, count_b)| {
                count_a
                    .cmp(count_b)
                    .then_with(|| weather_severity(**code_a).cmp(&weather_severity(**code_b)))
                    .then_with(|| code_a.cmp(code_b))
            })
            .map(|(code, _)| *code)
            .unwrap_or(3)
    }
}

#[derive(Debug, Deserialize)]
struct MetNoForecastResponse {
    properties: MetNoProperties,
}

#[derive(Debug, Deserialize)]
struct MetNoProperties {
    #[serde(default)]
    meta: Option<MetNoMeta>,
    timeseries: Vec<MetNoTimeSeriesPoint>,
}

#[derive(Debug, Deserialize)]
struct MetNoMeta {
    #[serde(default)]
    updated_at: Option<String>,
}

#[derive(Debug, Deserialize)]
struct MetNoTimeSeriesPoint {
    time: String,
    data: MetNoTimeSeriesData,
}

#[derive(Debug, Deserialize)]
struct MetNoTimeSeriesData {
    instant: MetNoInstant,
    #[serde(default)]
    next_1_hours: Option<MetNoHorizonData>,
    #[serde(default)]
    next_6_hours: Option<MetNoHorizonData>,
    #[serde(default)]
    next_12_hours: Option<MetNoHorizonData>,
}

impl MetNoTimeSeriesData {
    fn primary_weather_code(&self) -> Option<i32> {
        self.next_1_hours
            .as_ref()
            .and_then(|window| window.summary.as_ref())
            .or_else(|| {
                self.next_6_hours
                    .as_ref()
                    .and_then(|window| window.summary.as_ref())
            })
            .or_else(|| {
                self.next_12_hours
                    .as_ref()
                    .and_then(|window| window.summary.as_ref())
            })
            .map(|summary| met_symbol_to_open_meteo_code(&summary.symbol_code))
    }

    fn precipitation_probabilities(&self) -> impl Iterator<Item = f64> + '_ {
        [
            self.next_1_hours.as_ref(),
            self.next_6_hours.as_ref(),
            self.next_12_hours.as_ref(),
        ]
        .into_iter()
        .filter_map(|window| {
            window
                .and_then(|horizon| horizon.details.as_ref())
                .and_then(|details| details.probability_of_precipitation)
        })
    }
}

#[derive(Debug, Deserialize)]
struct MetNoInstant {
    details: MetNoInstantDetails,
}

#[derive(Debug, Deserialize)]
struct MetNoInstantDetails {
    air_temperature: f64,
}

#[derive(Debug, Deserialize)]
struct MetNoHorizonData {
    #[serde(default)]
    summary: Option<MetNoSummary>,
    #[serde(default)]
    details: Option<MetNoDetails>,
}

#[derive(Debug, Deserialize)]
struct MetNoSummary {
    symbol_code: String,
}

#[derive(Debug, Deserialize)]
struct MetNoDetails {
    #[serde(default)]
    probability_of_precipitation: Option<f64>,
}

#[cfg(test)]
mod tests {
    use std::io::{BufRead, BufReader, Write};
    use std::net::TcpListener;
    use std::sync::{Arc, Mutex};
    use std::thread;
    use std::time::{Duration, Instant};

    use super::*;

    #[test]
    fn met_no_maps_symbols_to_open_meteo_codes() {
        assert_eq!(met_symbol_to_open_meteo_code("clearsky_day"), 0);
        assert_eq!(met_symbol_to_open_meteo_code("rainshowers_day"), 81);
        assert_eq!(met_symbol_to_open_meteo_code("lightsnowshowers_night"), 85);
        assert_eq!(met_symbol_to_open_meteo_code("rainandthunder_day"), 95);
        assert_eq!(met_symbol_to_open_meteo_code("unknown_symbol"), 3);
    }

    #[test]
    fn met_no_aggregates_timeseries_into_daily_summary() {
        let payload: MetNoForecastResponse =
            serde_json::from_str(&sample_success_body()).expect("payload");

        let forecast = parse_provider_forecast(payload, 2).expect("forecast");

        assert_eq!(forecast.timezone, "UTC");
        assert_eq!(forecast.days.len(), 2);

        let day1 = &forecast.days[0];
        assert_eq!(day1.date, "2026-02-11");
        assert_eq!(day1.weather_code, 81);
        assert_eq!(day1.temp_min_c, 10.0);
        assert_eq!(day1.temp_max_c, 15.0);
        assert_eq!(day1.precip_prob_max_pct, 60);

        let day2 = &forecast.days[1];
        assert_eq!(day2.date, "2026-02-12");
        assert_eq!(day2.weather_code, 71);
        assert_eq!(day2.temp_min_c, 8.0);
        assert_eq!(day2.temp_max_c, 14.0);
        assert_eq!(day2.precip_prob_max_pct, 45);
    }

    #[test]
    fn met_no_returns_invalid_response_when_insufficient_days() {
        let payload: MetNoForecastResponse =
            serde_json::from_str(&sample_success_body()).expect("payload");

        let error = parse_provider_forecast(payload, 3).expect_err("must fail");

        match error {
            ProviderError::InvalidResponse(message) => {
                assert!(message.contains("does not include 3 forecast days"));
            }
            other => panic!("unexpected error: {other:?}"),
        }
    }

    #[test]
    fn met_no_fetch_forecast_retries_and_sets_user_agent() {
        let server = MockServer::spawn(vec![
            MockResponse::json(
                503,
                "Service Unavailable",
                r#"{"error":{"message":"upstream overload"}}"#,
            ),
            MockResponse::json(200, "OK", &sample_success_body()),
        ]);

        let client = Client::builder().build().expect("client");
        let forecast = fetch_forecast_with_endpoint_and_sleep(
            &client,
            &server.base_url,
            25.03,
            121.56,
            2,
            RetryPolicy {
                max_attempts: 2,
                base_backoff_ms: 0,
            },
            |_| {},
        )
        .expect("retry should succeed");

        assert_eq!(forecast.days.len(), 2);
        assert_eq!(
            server.user_agents(),
            vec![MET_NO_USER_AGENT, MET_NO_USER_AGENT]
        );

        server.join();
    }

    #[test]
    fn met_no_fetch_forecast_extracts_http_error_message() {
        let server = MockServer::spawn(vec![MockResponse::json(
            400,
            "Bad Request",
            r#"{"detail":"invalid coordinates"}"#,
        )]);

        let client = Client::builder().build().expect("client");
        let error = fetch_forecast_with_endpoint_and_sleep(
            &client,
            &server.base_url,
            999.0,
            999.0,
            1,
            RetryPolicy {
                max_attempts: 1,
                base_backoff_ms: 0,
            },
            |_| {},
        )
        .expect_err("must fail");

        match error {
            ProviderError::Http { status, message } => {
                assert_eq!(status, 400);
                assert!(message.contains("met_no: invalid coordinates"));
            }
            other => panic!("unexpected error: {other:?}"),
        }

        server.join();
    }

    fn sample_success_body() -> String {
        r#"{
            "properties": {
                "meta": {
                    "updated_at": "2026-02-11T00:00:00Z"
                },
                "timeseries": [
                    {
                        "time": "2026-02-11T00:00:00Z",
                        "data": {
                            "instant": { "details": { "air_temperature": 10.0 } },
                            "next_1_hours": {
                                "summary": { "symbol_code": "rainshowers_day" },
                                "details": { "probability_of_precipitation": 40 }
                            }
                        }
                    },
                    {
                        "time": "2026-02-11T06:00:00Z",
                        "data": {
                            "instant": { "details": { "air_temperature": 15.0 } },
                            "next_6_hours": {
                                "summary": { "symbol_code": "rainshowers_day" },
                                "details": { "probability_of_precipitation": 60 }
                            }
                        }
                    },
                    {
                        "time": "2026-02-11T12:00:00Z",
                        "data": {
                            "instant": { "details": { "air_temperature": 12.0 } },
                            "next_1_hours": {
                                "summary": { "symbol_code": "cloudy" },
                                "details": { "probability_of_precipitation": 35 }
                            }
                        }
                    },
                    {
                        "time": "2026-02-12T00:00:00Z",
                        "data": {
                            "instant": { "details": { "air_temperature": 8.0 } },
                            "next_12_hours": {
                                "summary": { "symbol_code": "lightsnow" },
                                "details": { "probability_of_precipitation": 45 }
                            }
                        }
                    },
                    {
                        "time": "2026-02-12T12:00:00Z",
                        "data": {
                            "instant": { "details": { "air_temperature": 14.0 } },
                            "next_1_hours": {
                                "summary": { "symbol_code": "lightsnow" },
                                "details": { "probability_of_precipitation": 30 }
                            }
                        }
                    }
                ]
            }
        }"#
        .to_string()
    }

    #[derive(Debug)]
    struct MockResponse {
        status: u16,
        reason: &'static str,
        content_type: &'static str,
        body: String,
    }

    impl MockResponse {
        fn json(status: u16, reason: &'static str, body: &str) -> Self {
            Self {
                status,
                reason,
                content_type: "application/json",
                body: body.to_string(),
            }
        }
    }

    struct MockServer {
        base_url: String,
        user_agents: Arc<Mutex<Vec<String>>>,
        handle: thread::JoinHandle<()>,
    }

    impl MockServer {
        fn spawn(responses: Vec<MockResponse>) -> Self {
            let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
            listener.set_nonblocking(true).expect("nonblocking");
            let base_url = format!("http://{}", listener.local_addr().expect("addr"));
            let user_agents = Arc::new(Mutex::new(Vec::new()));
            let captured_user_agents = Arc::clone(&user_agents);

            let handle = thread::spawn(move || {
                for response in responses {
                    let start = Instant::now();
                    let mut stream = loop {
                        match listener.accept() {
                            Ok((stream, _)) => break stream,
                            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                                if start.elapsed() > Duration::from_secs(3) {
                                    panic!("mock server timed out waiting for request");
                                }
                                thread::sleep(Duration::from_millis(10));
                            }
                            Err(error) => panic!("mock server accept failed: {error}"),
                        }
                    };

                    let cloned = stream.try_clone().expect("clone stream");
                    let mut reader = BufReader::new(cloned);
                    let mut request_lines = Vec::new();

                    loop {
                        let mut line = String::new();
                        let bytes = reader.read_line(&mut line).expect("read line");
                        if bytes == 0 || line == "\r\n" {
                            break;
                        }
                        request_lines.push(line.trim_end_matches(['\r', '\n']).to_string());
                    }

                    if let Some(line) = request_lines
                        .iter()
                        .find(|line| line.to_ascii_lowercase().starts_with("user-agent:"))
                    {
                        let value = line
                            .split_once(':')
                            .map(|(_, value)| value.trim().to_string())
                            .unwrap_or_default();
                        captured_user_agents.lock().expect("ua lock").push(value);
                    }

                    let response_head = format!(
                        "HTTP/1.1 {} {}\r\nContent-Type: {}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                        response.status,
                        response.reason,
                        response.content_type,
                        response.body.len()
                    );

                    stream
                        .write_all(response_head.as_bytes())
                        .and_then(|_| stream.write_all(response.body.as_bytes()))
                        .expect("write response");
                }
            });

            Self {
                base_url,
                user_agents,
                handle,
            }
        }

        fn user_agents(&self) -> Vec<String> {
            self.user_agents.lock().expect("ua lock").clone()
        }

        fn join(self) {
            self.handle.join().expect("mock server thread");
        }
    }
}
