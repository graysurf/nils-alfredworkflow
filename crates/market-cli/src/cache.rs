use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::config::{CRYPTO_TTL_SECS, FX_TTL_SECS, RuntimeConfig};
use crate::model::MarketKind;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CacheRecord {
    pub base: String,
    pub quote: String,
    pub provider: String,
    pub unit_price: String,
    pub fetched_at: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Freshness {
    pub age_secs: u64,
    pub is_fresh: bool,
}

pub fn cache_key(kind: MarketKind, base: &str, quote: &str) -> String {
    format!(
        "{}-{}-{}",
        kind.as_str(),
        base.to_ascii_lowercase(),
        quote.to_ascii_lowercase()
    )
}

pub fn cache_path(config: &RuntimeConfig, kind: MarketKind, base: &str, quote: &str) -> PathBuf {
    config
        .cache_dir
        .join("market-cli")
        .join(format!("{}.json", cache_key(kind, base, quote)))
}

pub fn ttl_for_kind(kind: MarketKind) -> u64 {
    match kind {
        MarketKind::Fx => FX_TTL_SECS,
        MarketKind::Crypto => CRYPTO_TTL_SECS,
    }
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
            base: "USD".to_string(),
            quote: "TWD".to_string(),
            provider: "frankfurter".to_string(),
            unit_price: "32.1".to_string(),
            fetched_at: fetched_at.to_string(),
        }
    }

    #[test]
    fn cache_key_contains_kind_base_quote() {
        assert_eq!(cache_key(MarketKind::Fx, "USD", "TWD"), "fx-usd-twd");
        assert_eq!(
            cache_key(MarketKind::Crypto, "BTC", "USD"),
            "crypto-btc-usd"
        );
    }

    #[test]
    fn cache_read_write_roundtrip() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("cache.json");
        let record = fixture_record("2026-02-10T12:00:00Z");

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
