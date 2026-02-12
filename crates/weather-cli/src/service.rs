use chrono::{DateTime, SecondsFormat, Utc};

use crate::cache::{
    CacheRecord, cache_path, evaluate_freshness, parse_fetched_at, read_cache, write_cache,
};
use crate::config::{RuntimeConfig, WEATHER_CACHE_TTL_SECS};
use crate::error::AppError;
use crate::geocoding::{ResolvedLocation, city_query_cache_key, coordinate_label};
use crate::model::{
    CacheMetadata, ForecastDay, ForecastOutput, ForecastRequest, FreshnessStatus, LocationQuery,
};
use crate::providers::{ProviderApi, ProviderForecast};
use crate::weather_code;

pub fn resolve_forecast<P, N>(
    config: &RuntimeConfig,
    providers: &P,
    now_fn: N,
    request: &ForecastRequest,
) -> Result<ForecastOutput, AppError>
where
    P: ProviderApi,
    N: Fn() -> DateTime<Utc>,
{
    let now = now_fn();
    let (cache_key, mut resolved_location) = match &request.location {
        LocationQuery::City(city) => (city_query_cache_key(city), None),
        _ => {
            let location = resolve_location(providers, &request.location)?;
            let key = location.cache_key();
            (key, Some(location))
        }
    };
    let path = cache_path(&config.cache_dir, request.period, &cache_key);

    let cached = read_cache(&path).map_err(|error| AppError::runtime(error.to_string()))?;
    let cached_state = cached.as_ref().map(|record| {
        let freshness = evaluate_freshness(record, now, WEATHER_CACHE_TTL_SECS);
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
            request,
            FreshnessStatus::CacheFresh,
            *age_secs,
            cache_key,
        ));
    }

    let location = match resolved_location.take() {
        Some(location) => location,
        None => match cached.as_ref() {
            Some(record) => resolved_location_from_record(record),
            None => resolve_location(providers, &request.location)?,
        },
    };

    let mut trace = Vec::new();

    match providers.fetch_open_meteo_forecast(
        location.latitude,
        location.longitude,
        request.period.forecast_days(),
    ) {
        Ok(forecast) => {
            return build_live_output(
                &path,
                &location,
                request,
                forecast,
                "open_meteo",
                trace,
                cache_key.clone(),
            );
        }
        Err(error) => trace.push(format!("open_meteo: {error}")),
    }

    match providers.fetch_met_no_forecast(
        location.latitude,
        location.longitude,
        request.period.forecast_days(),
    ) {
        Ok(forecast) => build_live_output(
            &path,
            &location,
            request,
            forecast,
            "met_no",
            trace,
            cache_key.clone(),
        ),
        Err(error) => {
            trace.push(format!("met_no: {error}"));
            fallback_or_error(cached_state, &location, request, trace, cache_key)
        }
    }
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
    path: &std::path::Path,
    location: &ResolvedLocation,
    request: &ForecastRequest,
    provider_forecast: ProviderForecast,
    source: &str,
    source_trace: Vec<String>,
    cache_key: String,
) -> Result<ForecastOutput, AppError> {
    let ProviderForecast {
        timezone: provider_timezone,
        fetched_at,
        days,
    } = provider_forecast;

    let timezone = if provider_timezone.trim().is_empty() {
        location.timezone.clone()
    } else {
        provider_timezone
    };

    let record = CacheRecord {
        period: request.period,
        location: location.to_output_location(),
        timezone,
        forecast: normalize_days(days),
        source: source.to_string(),
        source_trace,
        fetched_at: fetched_at.to_rfc3339_opts(SecondsFormat::Secs, true),
    };

    write_cache(path, &record).map_err(|error| AppError::runtime(error.to_string()))?;

    Ok(build_output_from_record(
        &record,
        location,
        request,
        FreshnessStatus::Live,
        0,
        cache_key,
    ))
}

fn fallback_or_error(
    cached_state: Option<(CacheRecord, u64, bool)>,
    location: &ResolvedLocation,
    request: &ForecastRequest,
    trace: Vec<String>,
    cache_key: String,
) -> Result<ForecastOutput, AppError> {
    if let Some((record, age_secs, false)) = cached_state {
        return Ok(build_output_from_record(
            &record,
            location,
            request,
            FreshnessStatus::CacheStaleFallback,
            age_secs,
            cache_key,
        ));
    }

    Err(AppError::runtime_with_trace(
        "failed to fetch forecast from providers",
        &trace,
    ))
}

fn build_output_from_record(
    record: &CacheRecord,
    location: &ResolvedLocation,
    request: &ForecastRequest,
    freshness_status: FreshnessStatus,
    age_secs: u64,
    cache_key: String,
) -> ForecastOutput {
    let fetched_at = parse_fetched_at(record)
        .unwrap_or_else(Utc::now)
        .to_rfc3339_opts(SecondsFormat::Secs, true);

    ForecastOutput {
        period: request.period,
        location: location.to_output_location(),
        timezone: record.timezone.clone(),
        forecast: record.forecast.clone(),
        source: record.source.clone(),
        source_trace: record.source_trace.clone(),
        fetched_at,
        freshness: CacheMetadata {
            status: freshness_status,
            key: cache_key,
            ttl_secs: WEATHER_CACHE_TTL_SECS,
            age_secs,
        },
    }
}

fn resolved_location_from_record(record: &CacheRecord) -> ResolvedLocation {
    ResolvedLocation {
        name: record.location.name.clone(),
        latitude: record.location.latitude,
        longitude: record.location.longitude,
        timezone: record.timezone.clone(),
    }
}

fn normalize_days(days: Vec<crate::providers::ProviderForecastDay>) -> Vec<ForecastDay> {
    days.into_iter()
        .map(|item| ForecastDay {
            date: item.date,
            weather_code: item.weather_code,
            summary_zh: weather_code::summary_zh(item.weather_code).to_string(),
            temp_min_c: round1(item.temp_min_c),
            temp_max_c: round1(item.temp_max_c),
            precip_prob_max_pct: item.precip_prob_max_pct.min(100),
        })
        .collect()
}

fn round1(value: f64) -> f64 {
    (value * 10.0).round() / 10.0
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;
    use std::cell::Cell;

    use super::*;
    use crate::model::{ForecastPeriod, OutputMode};
    use crate::providers::{ProviderError, ProviderForecastDay};

    struct FakeProviders {
        geocode_result: Result<ResolvedLocation, ProviderError>,
        open_meteo_result: Result<ProviderForecast, ProviderError>,
        met_no_result: Result<ProviderForecast, ProviderError>,
        geocode_calls: Cell<usize>,
        open_meteo_calls: Cell<usize>,
        met_no_calls: Cell<usize>,
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
                        temp_min_c: 14.4,
                        temp_max_c: 20.2,
                        precip_prob_max_pct: 22,
                    }],
                }),
                met_no_result: Ok(ProviderForecast {
                    timezone: "UTC".to_string(),
                    fetched_at: now,
                    days: vec![ProviderForecastDay {
                        date: "2026-02-11".to_string(),
                        weather_code: 61,
                        temp_min_c: 10.2,
                        temp_max_c: 12.7,
                        precip_prob_max_pct: 70,
                    }],
                }),
                geocode_calls: Cell::new(0),
                open_meteo_calls: Cell::new(0),
                met_no_calls: Cell::new(0),
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
            self.open_meteo_calls.set(self.open_meteo_calls.get() + 1);
            self.open_meteo_result.clone()
        }

        fn fetch_open_meteo_hourly_forecast(
            &self,
            _lat: f64,
            _lon: f64,
            _forecast_days: usize,
        ) -> Result<crate::providers::ProviderHourlyForecast, ProviderError> {
            Err(ProviderError::Transport("unused".to_string()))
        }

        fn fetch_met_no_forecast(
            &self,
            _lat: f64,
            _lon: f64,
            _forecast_days: usize,
        ) -> Result<ProviderForecast, ProviderError> {
            self.met_no_calls.set(self.met_no_calls.get() + 1);
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

    fn city_request(period: ForecastPeriod) -> ForecastRequest {
        ForecastRequest::new(period, Some("Taipei"), None, None, OutputMode::Json).expect("request")
    }

    #[test]
    fn location_resolution_uses_geocoding_for_city() {
        let providers = FakeProviders::ok();
        let request = city_request(ForecastPeriod::Today);
        let _output = resolve_forecast(&config_in_tempdir(), &providers, fixed_now, &request)
            .expect("must pass");

        assert_eq!(providers.geocode_calls.get(), 1);
    }

    #[test]
    fn location_resolution_uses_coordinate_bypass_for_lat_lon() {
        let providers = FakeProviders::ok();
        let request = ForecastRequest::new(
            ForecastPeriod::Today,
            None,
            Some(25.03),
            Some(121.56),
            OutputMode::Json,
        )
        .expect("request");

        let output = resolve_forecast(&config_in_tempdir(), &providers, fixed_now, &request)
            .expect("must pass");

        assert_eq!(providers.geocode_calls.get(), 0);
        assert_eq!(output.location.name, "25.0300,121.5600");
    }

    #[test]
    fn service_uses_fallback_when_primary_fails() {
        let providers = FakeProviders {
            open_meteo_result: Err(ProviderError::Transport("timeout".to_string())),
            ..FakeProviders::ok()
        };
        let request = city_request(ForecastPeriod::Today);

        let output = resolve_forecast(&config_in_tempdir(), &providers, fixed_now, &request)
            .expect("must pass");

        assert_eq!(output.source, "met_no");
        assert_eq!(providers.open_meteo_calls.get(), 1);
        assert_eq!(providers.met_no_calls.get(), 1);
        assert_eq!(output.source_trace.len(), 1);
    }

    #[test]
    fn service_short_circuits_on_fresh_cache() {
        let dir = tempfile::tempdir().expect("tempdir");
        let config = RuntimeConfig {
            cache_dir: dir.path().to_path_buf(),
        };
        let request = city_request(ForecastPeriod::Today);
        let location = ResolvedLocation {
            name: "Taipei City".to_string(),
            latitude: 25.05,
            longitude: 121.52,
            timezone: "Asia/Taipei".to_string(),
        };
        let path = cache_path(
            &config.cache_dir,
            ForecastPeriod::Today,
            &city_query_cache_key("Taipei"),
        );
        write_cache(
            &path,
            &CacheRecord {
                period: ForecastPeriod::Today,
                location: location.to_output_location(),
                timezone: "Asia/Taipei".to_string(),
                forecast: vec![ForecastDay {
                    date: "2026-02-11".to_string(),
                    weather_code: 3,
                    summary_zh: "陰天".to_string(),
                    temp_min_c: 14.0,
                    temp_max_c: 20.0,
                    precip_prob_max_pct: 20,
                }],
                source: "open_meteo".to_string(),
                source_trace: Vec::new(),
                fetched_at: "2026-02-11T00:04:00Z".to_string(),
            },
        )
        .expect("write");

        let providers = FakeProviders::ok();
        let output = resolve_forecast(&config, &providers, fixed_now, &request).expect("must pass");

        assert_eq!(output.freshness.status, FreshnessStatus::CacheFresh);
        assert_eq!(providers.geocode_calls.get(), 0);
        assert_eq!(providers.open_meteo_calls.get(), 0);
    }

    #[test]
    fn service_returns_stale_cache_on_provider_failure() {
        let dir = tempfile::tempdir().expect("tempdir");
        let config = RuntimeConfig {
            cache_dir: dir.path().to_path_buf(),
        };
        let request = city_request(ForecastPeriod::Today);
        let location = ResolvedLocation {
            name: "Taipei City".to_string(),
            latitude: 25.05,
            longitude: 121.52,
            timezone: "Asia/Taipei".to_string(),
        };
        let path = cache_path(
            &config.cache_dir,
            ForecastPeriod::Today,
            &city_query_cache_key("Taipei"),
        );
        write_cache(
            &path,
            &CacheRecord {
                period: ForecastPeriod::Today,
                location: location.to_output_location(),
                timezone: "Asia/Taipei".to_string(),
                forecast: vec![ForecastDay {
                    date: "2026-02-11".to_string(),
                    weather_code: 61,
                    summary_zh: "降雨".to_string(),
                    temp_min_c: 12.0,
                    temp_max_c: 17.0,
                    precip_prob_max_pct: 80,
                }],
                source: "open_meteo".to_string(),
                source_trace: Vec::new(),
                fetched_at: "2026-02-10T20:00:00Z".to_string(),
            },
        )
        .expect("write");

        let providers = FakeProviders {
            open_meteo_result: Err(ProviderError::Transport("timeout".to_string())),
            met_no_result: Err(ProviderError::Transport("down".to_string())),
            ..FakeProviders::ok()
        };

        let output = resolve_forecast(&config, &providers, fixed_now, &request).expect("fallback");
        assert_eq!(output.freshness.status, FreshnessStatus::CacheStaleFallback);
        assert_eq!(output.source, "open_meteo");
        assert_eq!(providers.geocode_calls.get(), 0);
    }

    #[test]
    fn service_reports_provider_trace_on_total_failure() {
        let providers = FakeProviders {
            open_meteo_result: Err(ProviderError::Transport("timeout".to_string())),
            met_no_result: Err(ProviderError::Http {
                status: 503,
                message: "service unavailable".to_string(),
            }),
            ..FakeProviders::ok()
        };
        let request = city_request(ForecastPeriod::Today);

        let err = resolve_forecast(&config_in_tempdir(), &providers, fixed_now, &request)
            .expect_err("must fail");

        assert!(err.message.contains("provider trace"));
        assert!(err.message.contains("open_meteo"));
        assert!(err.message.contains("met_no"));
    }
}
