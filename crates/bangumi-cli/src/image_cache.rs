use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use reqwest::blocking::Client;
use thiserror::Error;

use crate::bangumi_api::{BangumiSubject, build_headers, fallback_subject_image_url};
use crate::config::RuntimeConfig;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImageCandidate {
    pub image_type: String,
    pub url: String,
}

pub fn image_candidates_for_subject(subject: &BangumiSubject) -> Vec<ImageCandidate> {
    if let Some((image_type, url)) = subject.images.preferred_image_candidate() {
        return vec![ImageCandidate {
            image_type: image_type.to_string(),
            url: url.to_string(),
        }];
    }

    vec![ImageCandidate {
        image_type: "small".to_string(),
        url: fallback_subject_image_url(subject.id),
    }]
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImageCacheManager {
    cache_dir: PathBuf,
    ttl: Duration,
    max_bytes: u64,
}

impl ImageCacheManager {
    pub fn new(config: &RuntimeConfig) -> Self {
        Self {
            cache_dir: config.cache_dir.join("images"),
            ttl: Duration::from_secs(config.image_cache_ttl_seconds),
            max_bytes: config.image_cache_max_bytes,
        }
    }

    pub fn cache_dir(&self) -> &Path {
        &self.cache_dir
    }

    pub fn resolve_subject_icon_with<F>(
        &self,
        subject: &BangumiSubject,
        mut fetch: F,
    ) -> Result<Option<PathBuf>, ImageCacheError>
    where
        F: FnMut(&str) -> Result<Vec<u8>, ImageCacheError>,
    {
        self.resolve_subject_icon_at_with(subject, SystemTime::now(), &mut fetch)
    }

    fn resolve_subject_icon_at_with<F>(
        &self,
        subject: &BangumiSubject,
        now: SystemTime,
        fetch: &mut F,
    ) -> Result<Option<PathBuf>, ImageCacheError>
    where
        F: FnMut(&str) -> Result<Vec<u8>, ImageCacheError>,
    {
        fs::create_dir_all(&self.cache_dir).map_err(ImageCacheError::Io)?;

        let candidates = image_candidates_for_subject(subject);
        let mut last_error = None;

        for candidate in candidates {
            let path = self.cache_file_path(subject.id, &candidate.image_type, &candidate.url);

            if self.is_fresh_cache_file(&path, now)? {
                return Ok(Some(path));
            }

            match fetch(&candidate.url) {
                Ok(bytes) => {
                    if bytes.is_empty() {
                        continue;
                    }

                    write_atomic(&path, &bytes)?;
                    self.cleanup_max_size()?;
                    return Ok(Some(path));
                }
                Err(error) => {
                    last_error = Some(error);
                }
            }
        }

        if let Some(error) = last_error {
            return Err(error);
        }

        Ok(None)
    }

    fn cache_file_path(&self, subject_id: u64, image_type: &str, source_url: &str) -> PathBuf {
        let normalized_type = sanitize_token(image_type);
        let extension = extension_from_url(source_url).unwrap_or("img");
        self.cache_dir
            .join(format!("{subject_id}-{normalized_type}.{extension}"))
    }

    fn is_fresh_cache_file(&self, path: &Path, now: SystemTime) -> Result<bool, ImageCacheError> {
        if !path.exists() {
            return Ok(false);
        }

        let metadata = fs::metadata(path).map_err(ImageCacheError::Io)?;
        let modified = metadata.modified().map_err(ImageCacheError::Io)?;
        let age = match now.duration_since(modified) {
            Ok(age) => age,
            Err(_) => return Ok(false),
        };

        Ok(age <= self.ttl)
    }

    fn cleanup_max_size(&self) -> Result<(), ImageCacheError> {
        let mut entries = Vec::new();
        let mut total_size = 0_u64;

        for entry in fs::read_dir(&self.cache_dir).map_err(ImageCacheError::Io)? {
            let entry = entry.map_err(ImageCacheError::Io)?;
            let path = entry.path();
            if !path.is_file() {
                continue;
            }

            let metadata = entry.metadata().map_err(ImageCacheError::Io)?;
            let size = metadata.len();
            let modified = metadata.modified().unwrap_or(UNIX_EPOCH);

            total_size = total_size.saturating_add(size);
            entries.push((path, size, modified));
        }

        if total_size <= self.max_bytes {
            return Ok(());
        }

        entries.sort_by_key(|(_, _, modified)| *modified);
        for (path, size, _) in entries {
            if total_size <= self.max_bytes {
                break;
            }

            if fs::remove_file(&path).is_ok() {
                total_size = total_size.saturating_sub(size);
            }
        }

        Ok(())
    }
}

fn sanitize_token(raw: &str) -> String {
    let filtered = raw
        .chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '-' })
        .collect::<String>();

    let compact = filtered
        .trim_matches('-')
        .split('-')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("-");

    if compact.is_empty() {
        "image".to_string()
    } else {
        compact.to_ascii_lowercase()
    }
}

fn extension_from_url(url: &str) -> Option<&str> {
    let file_name = url.split('?').next()?.rsplit('/').next()?;
    let extension = file_name.rsplit('.').next()?;

    let normalized = extension.trim();
    if normalized.is_empty() || normalized.len() > 8 {
        return None;
    }

    if normalized.chars().all(|ch| ch.is_ascii_alphanumeric()) {
        Some(normalized)
    } else {
        None
    }
}

fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), ImageCacheError> {
    let parent = path.parent().ok_or_else(|| {
        ImageCacheError::Io(io::Error::new(
            io::ErrorKind::InvalidInput,
            "image cache path must have a parent directory",
        ))
    })?;
    fs::create_dir_all(parent).map_err(ImageCacheError::Io)?;

    let tmp_path = path.with_extension(format!("{}.tmp", std::process::id()));
    fs::write(&tmp_path, bytes).map_err(ImageCacheError::Io)?;
    fs::rename(&tmp_path, path).map_err(ImageCacheError::Io)?;

    Ok(())
}

pub fn download_image_bytes(
    client: &Client,
    config: &RuntimeConfig,
    url: &str,
) -> Result<Vec<u8>, ImageCacheError> {
    let response = client
        .get(url)
        .headers(build_headers(config))
        .send()
        .map_err(|source| ImageCacheError::Transport { source })?;

    let status = response.status().as_u16();
    if !(200..=299).contains(&status) {
        return Err(ImageCacheError::Http { status });
    }

    let bytes = response
        .bytes()
        .map_err(|source| ImageCacheError::Transport { source })?;

    Ok(bytes.to_vec())
}

#[derive(Debug, Error)]
pub enum ImageCacheError {
    #[error("image request failed")]
    Transport {
        #[source]
        source: reqwest::Error,
    },
    #[error("image request returned HTTP {status}")]
    Http { status: u16 },
    #[error("image cache I/O error: {0}")]
    Io(io::Error),
}

#[cfg(test)]
mod tests {
    use tempfile::tempdir;

    use super::*;
    use crate::config::{ApiFallbackPolicy, DEFAULT_USER_AGENT};
    use crate::input::SubjectType;

    fn fixture_subject_with_image() -> BangumiSubject {
        BangumiSubject {
            id: 2782,
            subject_type: Some(SubjectType::Anime),
            name: "Cowboy Bebop".to_string(),
            name_cn: Some("星際牛仔".to_string()),
            summary: Some("space western".to_string()),
            url: "https://bgm.tv/subject/2782".to_string(),
            rank: Some(1),
            score: Some(9.1),
            images: crate::bangumi_api::SubjectImages {
                small: Some("https://img.example.com/2782-small.jpg".to_string()),
                grid: None,
                common: None,
                large: None,
            },
        }
    }

    fn fixture_subject_without_image() -> BangumiSubject {
        BangumiSubject {
            images: crate::bangumi_api::SubjectImages::default(),
            ..fixture_subject_with_image()
        }
    }

    fn fixture_config(cache_dir: &Path) -> RuntimeConfig {
        RuntimeConfig {
            api_key: None,
            max_results: 10,
            timeout_ms: 8_000,
            user_agent: DEFAULT_USER_AGENT.to_string(),
            cache_dir: cache_dir.to_path_buf(),
            image_cache_ttl_seconds: 120,
            image_cache_max_bytes: 1024,
            api_fallback: ApiFallbackPolicy::Auto,
        }
    }

    #[test]
    fn image_fallback_uses_v0_subject_image_endpoint_when_payload_image_missing() {
        let subject = fixture_subject_without_image();
        let candidates = image_candidates_for_subject(&subject);

        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].image_type, "small");
        assert_eq!(
            candidates[0].url,
            "https://api.bgm.tv/v0/subjects/2782/image?type=small"
        );
    }

    #[test]
    fn image_cache_resolves_and_reuses_file_within_ttl_window() {
        let dir = tempdir().expect("temp dir");
        let config = fixture_config(dir.path());
        let manager = ImageCacheManager::new(&config);
        let subject = fixture_subject_with_image();
        let base = SystemTime::now();

        let mut fetch_count = 0;
        let first = manager
            .resolve_subject_icon_at_with(&subject, base, &mut |_url| {
                fetch_count += 1;
                Ok(vec![1, 2, 3])
            })
            .expect("first resolve should succeed")
            .expect("icon path should exist");

        let second = manager
            .resolve_subject_icon_at_with(&subject, base + Duration::from_secs(1), &mut |_url| {
                fetch_count += 1;
                Ok(vec![4, 5, 6])
            })
            .expect("second resolve should succeed")
            .expect("icon path should exist");

        assert_eq!(fetch_count, 1, "second call should hit cache");
        assert_eq!(first, second);
        assert!(first.exists(), "cached icon should be written to disk");
    }

    #[test]
    fn cache_ttl_expired_file_is_refetched() {
        let dir = tempdir().expect("temp dir");
        let mut config = fixture_config(dir.path());
        config.image_cache_ttl_seconds = 30;
        let base = SystemTime::now();

        let manager = ImageCacheManager::new(&config);
        let subject = fixture_subject_with_image();

        let mut fetch_count = 0;
        manager
            .resolve_subject_icon_at_with(&subject, base, &mut |_url| {
                fetch_count += 1;
                Ok(vec![1])
            })
            .expect("first resolve should succeed");

        manager
            .resolve_subject_icon_at_with(&subject, base + Duration::from_secs(31), &mut |_url| {
                fetch_count += 1;
                Ok(vec![2])
            })
            .expect("second resolve should succeed");

        assert_eq!(fetch_count, 2, "stale icon should be refetched");
    }

    #[test]
    fn image_cache_cleanup_removes_oldest_entries_when_size_limit_exceeded() {
        let dir = tempdir().expect("temp dir");
        let mut config = fixture_config(dir.path());
        config.image_cache_max_bytes = 4;

        let manager = ImageCacheManager::new(&config);
        let subject = fixture_subject_with_image();

        manager
            .resolve_subject_icon_at_with(
                &subject,
                SystemTime::UNIX_EPOCH + Duration::from_secs(1_000),
                &mut |_url| Ok(vec![1, 2, 3, 4]),
            )
            .expect("first write should succeed");

        let other_subject = BangumiSubject { id: 999, ..subject };
        manager
            .resolve_subject_icon_at_with(
                &other_subject,
                SystemTime::UNIX_EPOCH + Duration::from_secs(1_200),
                &mut |_url| Ok(vec![5, 6, 7, 8]),
            )
            .expect("second write should succeed");

        let cached_files = fs::read_dir(manager.cache_dir())
            .expect("list cache dir")
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .filter(|path| path.is_file())
            .collect::<Vec<_>>();

        assert_eq!(
            cached_files.len(),
            1,
            "cleanup should keep newest file only"
        );
        assert!(
            cached_files[0]
                .file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with("999-")),
            "oldest cached file should be evicted first"
        );
    }
}
