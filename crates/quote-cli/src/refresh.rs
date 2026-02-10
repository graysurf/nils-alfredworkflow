use std::io;
use std::time::{SystemTime, UNIX_EPOCH};

use thiserror::Error;

use crate::config::RuntimeConfig;
use crate::store::{self, StorePaths};
use crate::zenquotes::ZenQuotesError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RefreshOutcome {
    pub quotes: Vec<String>,
    pub refresh_error: Option<String>,
}

pub fn unix_now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

pub fn maybe_refresh<Fetch, Now>(
    config: &RuntimeConfig,
    paths: &StorePaths,
    mut fetch_quotes: Fetch,
    now_secs: Now,
) -> Result<RefreshOutcome, RefreshError>
where
    Fetch: FnMut(usize) -> Result<Vec<String>, ZenQuotesError>,
    Now: Fn() -> u64,
{
    let current_quotes = store::load_quotes(&paths.quotes_file).map_err(RefreshError::Storage)?;
    let last_fetch = store::read_timestamp(&paths.timestamp_file).map_err(RefreshError::Storage)?;
    let now = now_secs();

    if !is_due(last_fetch, now, config.refresh_interval_secs) {
        return Ok(RefreshOutcome {
            quotes: current_quotes,
            refresh_error: None,
        });
    }

    let fetched = match fetch_quotes(config.fetch_count) {
        Ok(rows) => rows,
        Err(error) => {
            return Ok(RefreshOutcome {
                quotes: current_quotes,
                refresh_error: Some(error.to_string()),
            });
        }
    };

    if fetched.is_empty() {
        return Ok(RefreshOutcome {
            quotes: current_quotes,
            refresh_error: None,
        });
    }

    let merged = store::merge_and_trim(current_quotes, &fetched, config.max_entries);
    store::save_quotes(&paths.quotes_file, &merged).map_err(RefreshError::Storage)?;
    store::write_timestamp(&paths.timestamp_file, now).map_err(RefreshError::Storage)?;

    Ok(RefreshOutcome {
        quotes: merged,
        refresh_error: None,
    })
}

fn is_due(last_fetch: Option<u64>, now: u64, interval_secs: u64) -> bool {
    match last_fetch {
        None => true,
        Some(last) => now.saturating_sub(last) > interval_secs,
    }
}

#[derive(Debug, Error)]
pub enum RefreshError {
    #[error("quote storage operation failed")]
    Storage(#[source] io::Error),
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;
    use crate::config::{
        DEFAULT_DISPLAY_COUNT, DEFAULT_FETCH_COUNT, DEFAULT_MAX_ENTRIES,
        DEFAULT_REFRESH_INTERVAL_SECS,
    };

    fn fixture_config(temp_dir: &std::path::Path) -> RuntimeConfig {
        RuntimeConfig {
            display_count: DEFAULT_DISPLAY_COUNT,
            refresh_interval_secs: DEFAULT_REFRESH_INTERVAL_SECS,
            fetch_count: DEFAULT_FETCH_COUNT,
            max_entries: DEFAULT_MAX_ENTRIES,
            data_dir: temp_dir.to_path_buf(),
        }
    }

    #[test]
    fn refresh_skips_fetch_when_interval_not_elapsed() {
        let dir = tempfile::tempdir().expect("temp dir");
        let config = fixture_config(dir.path());
        let paths = StorePaths::from_config(&config);

        fs::write(&paths.quotes_file, "\"cached\" — author\n").expect("seed quotes");
        fs::write(&paths.timestamp_file, "1000").expect("seed timestamp");

        let mut called = false;
        let outcome = maybe_refresh(
            &config,
            &paths,
            |_| {
                called = true;
                Ok(vec!["\"new\" — author".to_string()])
            },
            || 1000 + config.refresh_interval_secs,
        )
        .expect("refresh should succeed");

        assert!(!called, "fetch should not run before interval elapses");
        assert_eq!(outcome.quotes, vec!["\"cached\" — author".to_string()]);
    }

    #[test]
    fn refresh_fetches_and_updates_when_stale() {
        let dir = tempfile::tempdir().expect("temp dir");
        let config = fixture_config(dir.path());
        let paths = StorePaths::from_config(&config);

        fs::write(&paths.timestamp_file, "1000").expect("seed timestamp");

        let outcome = maybe_refresh(
            &config,
            &paths,
            |_| Ok(vec!["\"new quote\" — author".to_string()]),
            || 1000 + config.refresh_interval_secs + 1,
        )
        .expect("refresh should succeed");

        assert_eq!(outcome.refresh_error, None);
        assert_eq!(outcome.quotes, vec!["\"new quote\" — author".to_string()]);

        let stored = fs::read_to_string(&paths.quotes_file).expect("read stored quotes");
        assert!(stored.contains("\"new quote\" — author"));

        let timestamp = fs::read_to_string(&paths.timestamp_file).expect("read timestamp");
        assert_eq!(
            timestamp,
            (1000 + config.refresh_interval_secs + 1).to_string()
        );
    }

    #[test]
    fn refresh_keeps_cache_when_fetch_fails() {
        let dir = tempfile::tempdir().expect("temp dir");
        let config = fixture_config(dir.path());
        let paths = StorePaths::from_config(&config);

        fs::write(&paths.quotes_file, "\"cached\" — author\n").expect("seed quotes");
        fs::write(&paths.timestamp_file, "1000").expect("seed timestamp");

        let outcome = maybe_refresh(
            &config,
            &paths,
            |_| {
                Err(ZenQuotesError::Http {
                    status: 503,
                    message: "HTTP 503".to_string(),
                })
            },
            || 1000 + config.refresh_interval_secs + 1,
        )
        .expect("refresh should not hard-fail on fetch errors");

        assert_eq!(outcome.quotes, vec!["\"cached\" — author".to_string()]);
        assert!(
            outcome
                .refresh_error
                .as_deref()
                .is_some_and(|message| message.contains("zenquotes api error"))
        );

        let timestamp = fs::read_to_string(&paths.timestamp_file).expect("read timestamp");
        assert_eq!(
            timestamp, "1000",
            "timestamp should not update on fetch error"
        );
    }

    #[test]
    fn refresh_trims_merged_quotes_to_max_entries() {
        let dir = tempfile::tempdir().expect("temp dir");
        let mut config = fixture_config(dir.path());
        config.max_entries = 2;
        let paths = StorePaths::from_config(&config);

        fs::write(&paths.quotes_file, "\"one\" — a\n\"two\" — a\n").expect("seed quotes");

        let outcome = maybe_refresh(
            &config,
            &paths,
            |_| Ok(vec!["\"three\" — a".to_string()]),
            || 5000,
        )
        .expect("refresh should succeed");

        assert_eq!(
            outcome.quotes,
            vec!["\"two\" — a".to_string(), "\"three\" — a".to_string()]
        );
    }
}
