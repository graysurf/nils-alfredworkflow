use std::collections::HashSet;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use crate::config::RuntimeConfig;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StorePaths {
    pub quotes_file: PathBuf,
    pub timestamp_file: PathBuf,
}

impl StorePaths {
    pub fn from_config(config: &RuntimeConfig) -> Self {
        Self {
            quotes_file: config.quotes_file(),
            timestamp_file: config.timestamp_file(),
        }
    }
}

pub fn load_quotes(path: &Path) -> io::Result<Vec<String>> {
    if !path.exists() {
        return Ok(Vec::new());
    }

    let content = fs::read_to_string(path)?;
    let quotes = content
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect();
    Ok(quotes)
}

pub fn save_quotes(path: &Path, quotes: &[String]) -> io::Result<()> {
    let payload = if quotes.is_empty() {
        String::new()
    } else {
        let mut joined = quotes.join("\n");
        joined.push('\n');
        joined
    };

    write_atomic(path, payload.as_bytes())
}

pub fn merge_and_trim(
    existing: Vec<String>,
    new_quotes: &[String],
    max_entries: usize,
) -> Vec<String> {
    let mut merged = Vec::with_capacity(existing.len() + new_quotes.len());
    let mut seen = HashSet::new();

    for quote in existing.iter().chain(new_quotes.iter()) {
        let quote = quote.trim();
        if quote.is_empty() {
            continue;
        }
        if seen.insert(quote.to_string()) {
            merged.push(quote.to_string());
        }
    }

    if merged.len() > max_entries {
        let keep_from = merged.len() - max_entries;
        merged = merged.split_off(keep_from);
    }

    merged
}

pub fn read_timestamp(path: &Path) -> io::Result<Option<u64>> {
    if !path.exists() {
        return Ok(None);
    }

    let content = fs::read_to_string(path)?;
    let parsed = content.trim().parse::<u64>().ok();
    Ok(parsed)
}

pub fn write_timestamp(path: &Path, value: u64) -> io::Result<()> {
    write_atomic(path, value.to_string().as_bytes())
}

fn write_atomic(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let parent = path.parent().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "target path must have a parent",
        )
    })?;
    fs::create_dir_all(parent)?;

    let tmp_path = path.with_extension(format!("{}.tmp", std::process::id()));
    fs::write(&tmp_path, bytes)?;
    fs::rename(tmp_path, path)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn store_load_quotes_returns_empty_for_missing_file() {
        let dir = tempfile::tempdir().expect("temp dir");
        let path = dir.path().join("quotes.txt");

        let quotes = load_quotes(&path).expect("load should succeed");
        assert!(quotes.is_empty());
    }

    #[test]
    fn store_save_and_load_roundtrip_preserves_non_empty_lines() {
        let dir = tempfile::tempdir().expect("temp dir");
        let path = dir.path().join("quotes.txt");
        let input = vec![
            "\"Stay hungry, stay foolish.\" — Steve Jobs".to_string(),
            "\"Simplicity is the soul of efficiency.\" — Austin Freeman".to_string(),
        ];

        save_quotes(&path, &input).expect("save should succeed");
        let loaded = load_quotes(&path).expect("load should succeed");

        assert_eq!(loaded, input);
    }

    #[test]
    fn store_merge_dedupe_preserves_first_seen_order() {
        let merged = merge_and_trim(
            vec!["\"a\" — author".to_string(), "\"b\" — author".to_string()],
            &["\"b\" — author".to_string(), "\"c\" — author".to_string()],
            100,
        );

        assert_eq!(
            merged,
            vec![
                "\"a\" — author".to_string(),
                "\"b\" — author".to_string(),
                "\"c\" — author".to_string(),
            ]
        );
    }

    #[test]
    fn store_trim_retains_only_max_entries() {
        let merged = merge_and_trim(
            vec![
                "\"1\" — a".to_string(),
                "\"2\" — a".to_string(),
                "\"3\" — a".to_string(),
            ],
            &["\"4\" — a".to_string()],
            2,
        );

        assert_eq!(
            merged,
            vec!["\"3\" — a".to_string(), "\"4\" — a".to_string()]
        );
    }

    #[test]
    fn store_timestamp_roundtrip() {
        let dir = tempfile::tempdir().expect("temp dir");
        let path = dir.path().join("quotes.timestamp");

        assert_eq!(read_timestamp(&path).expect("read should succeed"), None);

        write_timestamp(&path, 123456).expect("write should succeed");
        assert_eq!(
            read_timestamp(&path).expect("read should succeed"),
            Some(123456)
        );
    }

    #[test]
    fn store_timestamp_tolerates_garbage_content() {
        let dir = tempfile::tempdir().expect("temp dir");
        let path = dir.path().join("quotes.timestamp");
        fs::write(&path, "not-a-number\n").expect("fixture write");

        assert_eq!(read_timestamp(&path).expect("read should succeed"), None);
    }
}
