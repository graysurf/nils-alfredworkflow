use chrono::Utc;
use reqwest::blocking::{Client, RequestBuilder};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::config::RetryPolicy;
use crate::geocoding::ResolvedLocation;

use super::{ProviderError, ProviderForecast, ProviderForecastDay, execute_with_retry};

const PROVIDER_NAME: &str = "open_meteo";
const GEOCODE_ENDPOINT: &str = "https://geocoding-api.open-meteo.com/v1/search";
const FORECAST_ENDPOINT: &str = "https://api.open-meteo.com/v1/forecast";
const FORECAST_DAILY_FIELDS: &str =
    "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max";

#[derive(Debug, Serialize)]
struct GeocodeQuery<'a> {
    name: &'a str,
    count: u8,
    language: &'a str,
    format: &'a str,
}

#[derive(Debug, Deserialize)]
struct GeocodeResponse {
    #[serde(default)]
    results: Vec<GeocodeResult>,
}

#[derive(Debug, Deserialize)]
struct GeocodeResult {
    name: String,
    latitude: f64,
    longitude: f64,
    timezone: Option<String>,
}

#[derive(Debug, Serialize)]
struct ForecastQuery<'a> {
    latitude: f64,
    longitude: f64,
    timezone: &'a str,
    forecast_days: usize,
    daily: &'a str,
}

#[derive(Debug, Deserialize)]
struct ForecastResponse {
    timezone: Option<String>,
    daily: Option<ForecastDaily>,
}

#[derive(Debug, Deserialize)]
struct ForecastDaily {
    #[serde(default)]
    time: Vec<String>,
    #[serde(default)]
    weather_code: Vec<i32>,
    #[serde(default)]
    temperature_2m_max: Vec<f64>,
    #[serde(default)]
    temperature_2m_min: Vec<f64>,
    #[serde(default)]
    precipitation_probability_max: Vec<Option<f64>>,
}

pub fn fetch_geocode(
    client: &Client,
    city: &str,
    retry_policy: RetryPolicy,
) -> Result<ResolvedLocation, ProviderError> {
    execute_with_retry(
        PROVIDER_NAME,
        retry_policy,
        || fetch_geocode_once(client, city),
        std::thread::sleep,
    )
}

pub fn fetch_forecast(
    client: &Client,
    lat: f64,
    lon: f64,
    forecast_days: usize,
    retry_policy: RetryPolicy,
) -> Result<ProviderForecast, ProviderError> {
    execute_with_retry(
        PROVIDER_NAME,
        retry_policy,
        || fetch_forecast_once(client, lat, lon, forecast_days),
        std::thread::sleep,
    )
}

fn fetch_geocode_once(client: &Client, city: &str) -> Result<ResolvedLocation, ProviderError> {
    let query = GeocodeQuery {
        name: city,
        count: 1,
        language: "en",
        format: "json",
    };

    let body = execute_request(client.get(GEOCODE_ENDPOINT).query(&query))?;
    parse_geocode_response(&body, city)
}

fn fetch_forecast_once(
    client: &Client,
    lat: f64,
    lon: f64,
    forecast_days: usize,
) -> Result<ProviderForecast, ProviderError> {
    let query = ForecastQuery {
        latitude: lat,
        longitude: lon,
        timezone: "auto",
        forecast_days,
        daily: FORECAST_DAILY_FIELDS,
    };

    let body = execute_request(client.get(FORECAST_ENDPOINT).query(&query))?;
    parse_forecast_response(&body)
}

fn execute_request(request: RequestBuilder) -> Result<String, ProviderError> {
    let response = request
        .send()
        .map_err(|error| ProviderError::Transport(error.to_string()))?;
    let status = response.status();
    let body = response
        .text()
        .map_err(|error| ProviderError::Transport(error.to_string()))?;

    if status.is_success() {
        return Ok(body);
    }

    let message = extract_error_message(&body).unwrap_or_else(|| {
        status
            .canonical_reason()
            .unwrap_or("request failed")
            .to_string()
    });

    Err(ProviderError::Http {
        status: status.as_u16(),
        message,
    })
}

fn parse_geocode_response(body: &str, city: &str) -> Result<ResolvedLocation, ProviderError> {
    let payload: GeocodeResponse = serde_json::from_str(body)
        .map_err(|error| ProviderError::InvalidResponse(format!("geocode payload: {error}")))?;

    let Some(result) = payload.results.into_iter().next() else {
        return Err(ProviderError::NotFound(city.to_string()));
    };

    if result.name.trim().is_empty() {
        return Err(ProviderError::InvalidResponse(
            "geocode payload: empty location name".to_string(),
        ));
    }

    let timezone = result
        .timezone
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .ok_or_else(|| {
            ProviderError::InvalidResponse("geocode payload: missing timezone".to_string())
        })?;

    Ok(ResolvedLocation {
        name: result.name,
        latitude: result.latitude,
        longitude: result.longitude,
        timezone,
    })
}

fn parse_forecast_response(body: &str) -> Result<ProviderForecast, ProviderError> {
    let payload: ForecastResponse = serde_json::from_str(body)
        .map_err(|error| ProviderError::InvalidResponse(format!("forecast payload: {error}")))?;

    let timezone = payload
        .timezone
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .ok_or_else(|| {
            ProviderError::InvalidResponse("forecast payload: missing timezone".to_string())
        })?;

    let daily = payload
        .daily
        .ok_or_else(|| ProviderError::InvalidResponse("forecast payload: missing daily".into()))?;

    let days = build_forecast_days(daily)?;

    Ok(ProviderForecast {
        timezone,
        fetched_at: Utc::now(),
        days,
    })
}

fn build_forecast_days(daily: ForecastDaily) -> Result<Vec<ProviderForecastDay>, ProviderError> {
    let length = daily.time.len();

    if daily.weather_code.len() != length
        || daily.temperature_2m_max.len() != length
        || daily.temperature_2m_min.len() != length
        || daily.precipitation_probability_max.len() != length
    {
        return Err(ProviderError::InvalidResponse(
            "forecast payload: daily arrays length mismatch".to_string(),
        ));
    }

    let mut days = Vec::with_capacity(length);
    for index in 0..length {
        let date = daily.time[index].trim().to_string();
        if date.is_empty() {
            return Err(ProviderError::InvalidResponse(
                "forecast payload: empty date in daily.time".to_string(),
            ));
        }

        let precip = daily.precipitation_probability_max[index].unwrap_or(0.0);
        days.push(ProviderForecastDay {
            date,
            weather_code: daily.weather_code[index],
            temp_max_c: daily.temperature_2m_max[index],
            temp_min_c: daily.temperature_2m_min[index],
            precip_prob_max_pct: clamp_percentage(precip),
        });
    }

    Ok(days)
}

fn clamp_percentage(value: f64) -> u8 {
    if !value.is_finite() {
        return 0;
    }
    value.clamp(0.0, 100.0).round() as u8
}

fn extract_error_message(body: &str) -> Option<String> {
    let trimmed = body.trim();
    if trimmed.is_empty() {
        return None;
    }

    let from_json = serde_json::from_str::<Value>(trimmed)
        .ok()
        .and_then(|json| {
            for key in ["reason", "message", "error", "detail", "description"] {
                if let Some(value) = json.get(key).and_then(Value::as_str) {
                    let message = value.trim();
                    if !message.is_empty() {
                        return Some(message.to_string());
                    }
                }
            }
            None
        });

    from_json.or_else(|| Some(trimmed.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn open_meteo_geocode_parses_first_result() {
        let body = r#"{
            "results": [
                {
                    "name": "Taipei",
                    "latitude": 25.033,
                    "longitude": 121.5654,
                    "timezone": "Asia/Taipei"
                },
                {
                    "name": "Taipei County",
                    "latitude": 25.05,
                    "longitude": 121.52,
                    "timezone": "Asia/Taipei"
                }
            ]
        }"#;

        let location = parse_geocode_response(body, "Taipei").expect("location");
        assert_eq!(location.name, "Taipei");
        assert_eq!(location.latitude, 25.033);
        assert_eq!(location.longitude, 121.5654);
        assert_eq!(location.timezone, "Asia/Taipei");
    }

    #[test]
    fn open_meteo_geocode_returns_not_found_when_empty() {
        let body = r#"{"results":[]}"#;
        let error = parse_geocode_response(body, "Nowhere").expect_err("must fail");

        assert_eq!(error, ProviderError::NotFound("Nowhere".to_string()));
    }

    #[test]
    fn open_meteo_forecast_builds_days_and_clamps_precip() {
        let body = r#"{
            "timezone": "Asia/Taipei",
            "daily": {
                "time": ["2025-02-10", "2025-02-11"],
                "weather_code": [2, 61],
                "temperature_2m_max": [26.4, 24.1],
                "temperature_2m_min": [18.2, 17.0],
                "precipitation_probability_max": [120, -3]
            }
        }"#;

        let forecast = parse_forecast_response(body).expect("forecast");
        assert_eq!(forecast.timezone, "Asia/Taipei");
        assert_eq!(forecast.days.len(), 2);
        assert_eq!(forecast.days[0].precip_prob_max_pct, 100);
        assert_eq!(forecast.days[1].precip_prob_max_pct, 0);
    }

    #[test]
    fn open_meteo_forecast_rejects_mismatched_daily_lengths() {
        let body = r#"{
            "timezone": "Asia/Taipei",
            "daily": {
                "time": ["2025-02-10", "2025-02-11"],
                "weather_code": [2],
                "temperature_2m_max": [26.4, 24.1],
                "temperature_2m_min": [18.2, 17.0],
                "precipitation_probability_max": [30, 50]
            }
        }"#;

        let error = parse_forecast_response(body).expect_err("must fail");
        assert!(
            matches!(error, ProviderError::InvalidResponse(message) if message.contains("length mismatch"))
        );
    }

    #[test]
    fn open_meteo_extract_error_message_prefers_reason() {
        let body = r#"{"error": true, "reason": "rate limit exceeded"}"#;
        assert_eq!(
            extract_error_message(body),
            Some("rate limit exceeded".to_string())
        );
    }
}
