use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::model::{ForecastDay, ForecastLocation, ForecastPeriod};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CacheRecord {
    pub period: ForecastPeriod,
    pub location: ForecastLocation,
    pub timezone: String,
    pub forecast: Vec<ForecastDay>,
    pub source: String,
    #[serde(default)]
    pub source_trace: Vec<String>,
    pub fetched_at: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Freshness {
    pub age_secs: u64,
    pub is_fresh: bool,
}

pub fn cache_key(period: ForecastPeriod, location_key: &str) -> String {
    format!("{}-{location_key}", period.as_str())
}

pub fn cache_path(config_cache_dir: &Path, period: ForecastPeriod, location_key: &str) -> PathBuf {
    config_cache_dir
        .join("weather-cli")
        .join(format!("{}.json", cache_key(period, location_key)))
}

pub fn read_cache(path: &Path) -> io::Result<Option<CacheRecord>> {
    if !path.exists() {
        return Ok(None);
    }

    let payload = fs::read_to_string(path)?;
    let parsed = serde_json::from_str::<CacheRecord>(&payload).ok();
    Ok(parsed)
}

pub fn write_cache(path: &Path, record: &CacheRecord) -> io::Result<()> {
    let payload = serde_json::to_vec(record)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.to_string()))?;
    write_atomic(path, &payload)
}

pub fn evaluate_freshness(record: &CacheRecord, now: DateTime<Utc>, ttl_secs: u64) -> Freshness {
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

pub fn parse_fetched_at(record: &CacheRecord) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(&record.fetched_at)
        .ok()
        .map(|value| value.with_timezone(&Utc))
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
    use chrono::{TimeZone, Utc};

    use super::*;

    fn fixture_record(fetched_at: &str) -> CacheRecord {
        CacheRecord {
            period: ForecastPeriod::Today,
            location: ForecastLocation {
                name: "Taipei".to_string(),
                latitude: 25.03,
                longitude: 121.56,
            },
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
            fetched_at: fetched_at.to_string(),
        }
    }

    #[test]
    fn cache_key_contains_period_and_location_key() {
        assert_eq!(
            cache_key(ForecastPeriod::Today, "taipei-25.03-121.56"),
            "today-taipei-25.03-121.56"
        );
        assert_eq!(
            cache_key(ForecastPeriod::Week, "tokyo-35.68-139.69"),
            "week-tokyo-35.68-139.69"
        );
    }

    #[test]
    fn cache_read_write_roundtrip() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("cache.json");
        let record = fixture_record("2026-02-11T00:00:00Z");

        write_cache(&path, &record).expect("write");
        let loaded = read_cache(&path).expect("read").expect("record");
        assert_eq!(loaded, record);
    }

    #[test]
    fn cache_handles_corrupt_payload_as_miss() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("cache.json");
        fs::write(&path, "{not-json").expect("write");

        let loaded = read_cache(&path).expect("read");
        assert_eq!(loaded, None);
    }

    #[test]
    fn cache_freshness_marks_record_as_fresh_within_ttl() {
        let record = fixture_record("2026-02-10T12:00:00Z");
        let now = Utc
            .with_ymd_and_hms(2026, 2, 10, 12, 4, 0)
            .single()
            .expect("time");

        let result = evaluate_freshness(&record, now, 300);
        assert_eq!(result.age_secs, 240);
        assert!(result.is_fresh);
    }

    #[test]
    fn cache_freshness_marks_record_as_stale_after_ttl() {
        let record = fixture_record("2026-02-10T12:00:00Z");
        let now = Utc
            .with_ymd_and_hms(2026, 2, 10, 12, 6, 0)
            .single()
            .expect("time");

        let result = evaluate_freshness(&record, now, 300);
        assert_eq!(result.age_secs, 360);
        assert!(!result.is_fresh);
    }
}
