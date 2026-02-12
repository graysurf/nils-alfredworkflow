use std::fs;
use std::io;
use std::path::Path;

use chrono::{DateTime, Duration, SecondsFormat, Timelike, Utc};
use serde::{Deserialize, Serialize};

use crate::config::RuntimeConfig;
use crate::error::AppError;
use crate::geocoding::{ResolvedLocation, city_query_cache_key, coordinate_label};
use crate::model::{
    CacheMetadata, ForecastLocation, ForecastPeriod, HourlyForecastOutput, HourlyForecastPoint,
    LocationQuery,
};
use crate::providers::{ProviderApi, ProviderHourlyForecast};

const MAX_HOURLY_COUNT: usize = 48;
pub const DEFAULT_HOURLY_COUNT: usize = 24;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
struct HourlyCacheRecord {
    location: ForecastLocation,
    timezone: String,
    #[serde(default)]
    utc_offset_seconds: i32,
    hourly: Vec<HourlyForecastPoint>,
    source: String,
    #[serde(default)]
    source_trace: Vec<String>,
    fetched_at: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Freshness {
    age_secs: u64,
    is_fresh: bool,
}

pub fn resolve_hourly_forecast<P, N>(
    config: &RuntimeConfig,
    providers: &P,
    now_fn: N,
    location_query: &LocationQuery,
    hour_count: usize,
) -> Result<HourlyForecastOutput, AppError>
where
    P: ProviderApi,
    N: Fn() -> DateTime<Utc>,
{
    let now = now_fn();
    let requested_hours = normalize_hour_count(hour_count);

    let (cache_key, mut resolved_location) = match location_query {
        LocationQuery::City(city) => (city_query_cache_key(city), None),
        _ => {
            let location = resolve_location(providers, location_query)?;
            let key = location.cache_key();
            (key, Some(location))
        }
    };
    let path = crate::cache::cache_path(&config.cache_dir, ForecastPeriod::Hourly, &cache_key);
    let output_context = OutputContext {
        cache_key: cache_key.clone(),
        requested_hours,
        now,
        ttl_secs: config.cache_ttl_secs,
    };

    let cached = read_hourly_cache(&path).map_err(|error| AppError::runtime(error.to_string()))?;
    let cached_state = cached.as_ref().map(|record| {
        let freshness = evaluate_freshness(record, now, config.cache_ttl_secs);
        (record.clone(), freshness.age_secs, freshness.is_fresh)
    });

    if let Some((record, age_secs, true)) = &cached_state {
        let location = resolved_location
            .as_ref()
            .cloned()
            .unwrap_or_else(|| resolved_location_from_record(record));
        return Ok(build_output_from_record(
            record,
            &location,
            FreshnessStatus::CacheFresh,
            *age_secs,
            &output_context,
        ));
    }

    let location = match resolved_location.take() {
        Some(location) => location,
        None => match cached.as_ref() {
            Some(record) => resolved_location_from_record(record),
            None => resolve_location(providers, location_query)?,
        },
    };

    let mut trace = Vec::new();
    match providers.fetch_open_meteo_hourly_forecast(
        location.latitude,
        location.longitude,
        MAX_HOURLY_COUNT,
    ) {
        Ok(forecast) => build_live_output(&path, &location, forecast, trace, &output_context),
        Err(error) => {
            trace.push(format!("open_meteo: {error}"));
            fallback_or_error(cached_state, &location, trace, &output_context)
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FreshnessStatus {
    Live,
    CacheFresh,
    CacheStaleFallback,
}

fn resolve_location<P: ProviderApi>(
    providers: &P,
    location: &LocationQuery,
) -> Result<ResolvedLocation, AppError> {
    match location {
        LocationQuery::City(city) => providers.geocode_city(city).map_err(|error| {
            AppError::runtime(format!("failed to resolve city '{city}': {error}"))
        }),
        LocationQuery::Coordinates { lat, lon } => Ok(ResolvedLocation {
            name: coordinate_label(*lat, *lon),
            latitude: *lat,
            longitude: *lon,
            timezone: "UTC".to_string(),
        }),
    }
}

fn build_live_output(
    path: &Path,
    location: &ResolvedLocation,
    provider_forecast: ProviderHourlyForecast,
    source_trace: Vec<String>,
    output_context: &OutputContext,
) -> Result<HourlyForecastOutput, AppError> {
    let ProviderHourlyForecast {
        timezone: provider_timezone,
        utc_offset_seconds,
        fetched_at,
        hours,
    } = provider_forecast;

    let timezone = if provider_timezone.trim().is_empty() {
        location.timezone.clone()
    } else {
        provider_timezone
    };

    let record = HourlyCacheRecord {
        location: location.to_output_location(),
        timezone,
        utc_offset_seconds,
        hourly: normalize_hours(hours, MAX_HOURLY_COUNT),
        source: "open_meteo".to_string(),
        source_trace,
        fetched_at: fetched_at.to_rfc3339_opts(SecondsFormat::Secs, true),
    };

    write_hourly_cache(path, &record).map_err(|error| AppError::runtime(error.to_string()))?;

    Ok(build_output_from_record(
        &record,
        location,
        FreshnessStatus::Live,
        0,
        output_context,
    ))
}

fn fallback_or_error(
    cached_state: Option<(HourlyCacheRecord, u64, bool)>,
    location: &ResolvedLocation,
    trace: Vec<String>,
    output_context: &OutputContext,
) -> Result<HourlyForecastOutput, AppError> {
    if let Some((record, age_secs, false)) = cached_state {
        return Ok(build_output_from_record(
            &record,
            location,
            FreshnessStatus::CacheStaleFallback,
            age_secs,
            output_context,
        ));
    }

    Err(AppError::runtime_with_trace(
        "failed to fetch hourly forecast from providers",
        &trace,
    ))
}

fn build_output_from_record(
    record: &HourlyCacheRecord,
    location: &ResolvedLocation,
    freshness_status: FreshnessStatus,
    age_secs: u64,
    output_context: &OutputContext,
) -> HourlyForecastOutput {
    let fetched_at = parse_fetched_at(record)
        .unwrap_or_else(Utc::now)
        .to_rfc3339_opts(SecondsFormat::Secs, true);

    HourlyForecastOutput {
        location: location.to_output_location(),
        timezone: record.timezone.clone(),
        hourly: take_current_hours(
            &record.hourly,
            output_context.requested_hours,
            output_context.now,
            record.utc_offset_seconds,
        ),
        source: record.source.clone(),
        source_trace: record.source_trace.clone(),
        fetched_at,
        freshness: CacheMetadata {
            status: match freshness_status {
                FreshnessStatus::Live => crate::model::FreshnessStatus::Live,
                FreshnessStatus::CacheFresh => crate::model::FreshnessStatus::CacheFresh,
                FreshnessStatus::CacheStaleFallback => {
                    crate::model::FreshnessStatus::CacheStaleFallback
                }
            },
            key: output_context.cache_key.clone(),
            ttl_secs: output_context.ttl_secs,
            age_secs,
        },
    }
}

#[derive(Debug, Clone)]
struct OutputContext {
    cache_key: String,
    requested_hours: usize,
    now: DateTime<Utc>,
    ttl_secs: u64,
}

fn normalize_hour_count(hour_count: usize) -> usize {
    hour_count.clamp(1, MAX_HOURLY_COUNT)
}

fn take_hours(hourly: &[HourlyForecastPoint], requested_hours: usize) -> Vec<HourlyForecastPoint> {
    hourly.iter().take(requested_hours).cloned().collect()
}

fn take_current_hours(
    hourly: &[HourlyForecastPoint],
    requested_hours: usize,
    now: DateTime<Utc>,
    utc_offset_seconds: i32,
) -> Vec<HourlyForecastPoint> {
    let start = current_hour_start_label(now, utc_offset_seconds);
    let filtered: Vec<HourlyForecastPoint> = hourly
        .iter()
        .filter(|item| item.datetime.as_str() >= start.as_str())
        .take(requested_hours)
        .cloned()
        .collect();

    if filtered.is_empty() {
        return take_hours(hourly, requested_hours);
    }

    filtered
}

fn current_hour_start_label(now: DateTime<Utc>, utc_offset_seconds: i32) -> String {
    let local = now + Duration::seconds(i64::from(utc_offset_seconds));
    let floored = local
        .with_minute(0)
        .and_then(|value| value.with_second(0))
        .and_then(|value| value.with_nanosecond(0))
        .unwrap_or(local);
    floored.format("%Y-%m-%dT%H:%M").to_string()
}

fn normalize_hours(
    hours: Vec<crate::providers::ProviderForecastHour>,
    limit: usize,
) -> Vec<HourlyForecastPoint> {
    hours
        .into_iter()
        .take(limit)
        .map(|item| HourlyForecastPoint {
            datetime: item.datetime,
            weather_code: item.weather_code,
            temp_c: round1(item.temp_c),
            precip_prob_pct: item.precip_prob_pct.min(100),
        })
        .collect()
}

fn round1(value: f64) -> f64 {
    (value * 10.0).round() / 10.0
}

fn resolved_location_from_record(record: &HourlyCacheRecord) -> ResolvedLocation {
    ResolvedLocation {
        name: record.location.name.clone(),
        latitude: record.location.latitude,
        longitude: record.location.longitude,
        timezone: record.timezone.clone(),
    }
}

fn parse_fetched_at(record: &HourlyCacheRecord) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(&record.fetched_at)
        .ok()
        .map(|value| value.with_timezone(&Utc))
}

fn evaluate_freshness(record: &HourlyCacheRecord, now: DateTime<Utc>, ttl_secs: u64) -> Freshness {
    let fetched_at = parse_fetched_at(record)
        .unwrap_or(now - chrono::Duration::seconds((ttl_secs + 1).try_into().unwrap_or(0)));
    let age_secs = now
        .signed_duration_since(fetched_at)
        .num_seconds()
        .max(0)
        .try_into()
        .unwrap_or(u64::MAX);

    Freshness {
        age_secs,
        is_fresh: age_secs <= ttl_secs,
    }
}

fn read_hourly_cache(path: &Path) -> io::Result<Option<HourlyCacheRecord>> {
    if !path.exists() {
        return Ok(None);
    }

    let payload = fs::read_to_string(path)?;
    let parsed = serde_json::from_str::<HourlyCacheRecord>(&payload).ok();
    Ok(parsed)
}

fn write_hourly_cache(path: &Path, record: &HourlyCacheRecord) -> io::Result<()> {
    let payload = serde_json::to_vec(record)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.to_string()))?;
    write_atomic(path, &payload)
}

fn write_atomic(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let parent = path.parent().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "cache path must have a parent directory",
        )
    })?;
    fs::create_dir_all(parent)?;

    let tmp_path = path.with_extension(format!("{}.tmp", std::process::id()));
    fs::write(&tmp_path, bytes)?;
    fs::rename(&tmp_path, path)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;
    use std::cell::Cell;

    use super::*;
    use crate::providers::{ProviderError, ProviderForecast, ProviderForecastHour};

    struct FakeProviders {
        geocode_result: Result<ResolvedLocation, ProviderError>,
        hourly_result: Result<ProviderHourlyForecast, ProviderError>,
        geocode_calls: Cell<usize>,
        hourly_calls: Cell<usize>,
    }

    impl FakeProviders {
        fn ok() -> Self {
            let now = Utc
                .with_ymd_and_hms(2026, 2, 12, 0, 0, 0)
                .single()
                .expect("time");
            Self {
                geocode_result: Ok(ResolvedLocation {
                    name: "Tokyo".to_string(),
                    latitude: 35.6762,
                    longitude: 139.6503,
                    timezone: "Asia/Tokyo".to_string(),
                }),
                hourly_result: Ok(ProviderHourlyForecast {
                    timezone: "Asia/Tokyo".to_string(),
                    utc_offset_seconds: 0,
                    fetched_at: now,
                    hours: vec![
                        ProviderForecastHour {
                            datetime: "2026-02-12T00:00".to_string(),
                            weather_code: 3,
                            temp_c: 1.0,
                            precip_prob_pct: 10,
                        },
                        ProviderForecastHour {
                            datetime: "2026-02-12T01:00".to_string(),
                            weather_code: 2,
                            temp_c: 0.5,
                            precip_prob_pct: 0,
                        },
                    ],
                }),
                geocode_calls: Cell::new(0),
                hourly_calls: Cell::new(0),
            }
        }
    }

    impl ProviderApi for FakeProviders {
        fn geocode_city(&self, _city: &str) -> Result<ResolvedLocation, ProviderError> {
            self.geocode_calls.set(self.geocode_calls.get() + 1);
            self.geocode_result.clone()
        }

        fn fetch_open_meteo_forecast(
            &self,
            _lat: f64,
            _lon: f64,
            _forecast_days: usize,
        ) -> Result<ProviderForecast, ProviderError> {
            Err(ProviderError::Transport("unused".to_string()))
        }

        fn fetch_open_meteo_hourly_forecast(
            &self,
            _lat: f64,
            _lon: f64,
            _forecast_hours: usize,
        ) -> Result<ProviderHourlyForecast, ProviderError> {
            self.hourly_calls.set(self.hourly_calls.get() + 1);
            self.hourly_result.clone()
        }

        fn fetch_met_no_forecast(
            &self,
            _lat: f64,
            _lon: f64,
            _forecast_days: usize,
        ) -> Result<ProviderForecast, ProviderError> {
            Err(ProviderError::Transport("unused".to_string()))
        }
    }

    fn config_in_tempdir() -> RuntimeConfig {
        RuntimeConfig {
            cache_dir: tempfile::tempdir().expect("tempdir").path().to_path_buf(),
            cache_ttl_secs: crate::config::WEATHER_CACHE_TTL_SECS,
        }
    }

    fn fixed_now() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 2, 12, 0, 5, 0)
            .single()
            .expect("time")
    }

    #[test]
    fn hourly_service_returns_live_output() {
        let config = config_in_tempdir();
        let providers = FakeProviders::ok();
        let query = LocationQuery::City("Tokyo".to_string());

        let output =
            resolve_hourly_forecast(&config, &providers, fixed_now, &query, 24).expect("must pass");
        assert_eq!(output.freshness.status, crate::model::FreshnessStatus::Live);
        assert_eq!(output.hourly.len(), 2);
        assert_eq!(providers.hourly_calls.get(), 1);
    }

    #[test]
    fn hourly_service_uses_fresh_cache_without_provider_calls() {
        let config = config_in_tempdir();
        let providers = FakeProviders::ok();
        let query = LocationQuery::City("Tokyo".to_string());
        let path = crate::cache::cache_path(
            &config.cache_dir,
            ForecastPeriod::Hourly,
            &city_query_cache_key("Tokyo"),
        );

        write_hourly_cache(
            &path,
            &HourlyCacheRecord {
                location: ForecastLocation {
                    name: "Tokyo".to_string(),
                    latitude: 35.6762,
                    longitude: 139.6503,
                },
                timezone: "Asia/Tokyo".to_string(),
                utc_offset_seconds: 0,
                hourly: vec![HourlyForecastPoint {
                    datetime: "2026-02-12T00:00".to_string(),
                    weather_code: 3,
                    temp_c: 1.0,
                    precip_prob_pct: 20,
                }],
                source: "open_meteo".to_string(),
                source_trace: Vec::new(),
                fetched_at: "2026-02-12T00:00:00Z".to_string(),
            },
        )
        .expect("cache");

        let output =
            resolve_hourly_forecast(&config, &providers, fixed_now, &query, 24).expect("must pass");
        assert_eq!(
            output.freshness.status,
            crate::model::FreshnessStatus::CacheFresh
        );
        assert_eq!(providers.geocode_calls.get(), 0);
        assert_eq!(providers.hourly_calls.get(), 0);
    }

    #[test]
    fn hourly_service_filters_out_hours_older_than_current_hour() {
        let config = config_in_tempdir();
        let providers = FakeProviders::ok();
        let query = LocationQuery::City("Tokyo".to_string());
        let path = crate::cache::cache_path(
            &config.cache_dir,
            ForecastPeriod::Hourly,
            &city_query_cache_key("Tokyo"),
        );

        write_hourly_cache(
            &path,
            &HourlyCacheRecord {
                location: ForecastLocation {
                    name: "Tokyo".to_string(),
                    latitude: 35.6762,
                    longitude: 139.6503,
                },
                timezone: "Asia/Tokyo".to_string(),
                utc_offset_seconds: 0,
                hourly: vec![
                    HourlyForecastPoint {
                        datetime: "2026-02-12T09:00".to_string(),
                        weather_code: 3,
                        temp_c: 1.0,
                        precip_prob_pct: 10,
                    },
                    HourlyForecastPoint {
                        datetime: "2026-02-12T10:00".to_string(),
                        weather_code: 3,
                        temp_c: 2.0,
                        precip_prob_pct: 20,
                    },
                    HourlyForecastPoint {
                        datetime: "2026-02-12T11:00".to_string(),
                        weather_code: 3,
                        temp_c: 3.0,
                        precip_prob_pct: 30,
                    },
                ],
                source: "open_meteo".to_string(),
                source_trace: Vec::new(),
                fetched_at: "2026-02-12T10:30:00Z".to_string(),
            },
        )
        .expect("cache");

        let now = || {
            Utc.with_ymd_and_hms(2026, 2, 12, 10, 30, 0)
                .single()
                .expect("time")
        };
        let output =
            resolve_hourly_forecast(&config, &providers, now, &query, 24).expect("must pass");

        assert_eq!(output.hourly.len(), 2);
        assert_eq!(output.hourly[0].datetime, "2026-02-12T10:00");
        assert_eq!(output.hourly[1].datetime, "2026-02-12T11:00");
    }
}
