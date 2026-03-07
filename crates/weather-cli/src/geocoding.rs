use crate::model::ForecastLocation;
use serde::{Deserialize, Serialize};
use std::collections::hash_map::DefaultHasher;
use std::fs;
use std::hash::{Hash, Hasher};
use std::io;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResolvedLocation {
    pub name: String,
    pub latitude: f64,
    pub longitude: f64,
    pub timezone: String,
}

impl ResolvedLocation {
    pub fn to_output_location(&self) -> ForecastLocation {
        ForecastLocation {
            name: self.name.clone(),
            latitude: self.latitude,
            longitude: self.longitude,
        }
    }

    pub fn cache_key(&self) -> String {
        let slug = slugify_for_cache(&self.name);
        format!(
            "{}-{:.4}-{:.4}",
            slug,
            round4(self.latitude),
            round4(self.longitude)
        )
    }
}

pub fn city_query_cache_key(city: &str) -> String {
    format!("city-{}", slugify_for_cache(city))
}

pub fn coordinate_label(lat: f64, lon: f64) -> String {
    format!("{:.4},{:.4}", round4(lat), round4(lon))
}

pub fn location_from_coordinates(lat: f64, lon: f64) -> ResolvedLocation {
    ResolvedLocation {
        name: coordinate_label(lat, lon),
        latitude: lat,
        longitude: lon,
        timezone: "UTC".to_string(),
    }
}

pub fn geocode_cache_path(config_cache_dir: &Path, city: &str) -> PathBuf {
    config_cache_dir
        .join("weather-cli")
        .join("geocode")
        .join(format!("{}.json", city_query_cache_key(city)))
}

pub fn read_cached_city_location(
    config_cache_dir: &Path,
    city: &str,
) -> io::Result<Option<ResolvedLocation>> {
    let path = geocode_cache_path(config_cache_dir, city);
    if !path.exists() {
        return Ok(None);
    }

    let payload = fs::read_to_string(path)?;
    let parsed = serde_json::from_str::<ResolvedLocation>(&payload).ok();
    Ok(parsed)
}

pub fn write_cached_city_location(
    config_cache_dir: &Path,
    city: &str,
    location: &ResolvedLocation,
) -> io::Result<()> {
    let path = geocode_cache_path(config_cache_dir, city);
    let payload = serde_json::to_vec(location)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.to_string()))?;
    write_atomic(&path, &payload)
}

fn round4(value: f64) -> f64 {
    (value * 10_000.0).round() / 10_000.0
}

pub fn slugify_for_cache(raw: &str) -> String {
    let slug = slugify(raw);
    if !slug.is_empty() {
        return slug;
    }

    // Keep cache keys deterministic for non-ASCII-only city names.
    let mut hasher = DefaultHasher::new();
    raw.hash(&mut hasher);
    format!("q{:016x}", hasher.finish())
}

fn slugify(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut prev_dash = false;

    for ch in raw.chars() {
        if ch.is_ascii_alphanumeric() {
            prev_dash = false;
            out.push(ch.to_ascii_lowercase());
            continue;
        }

        if !prev_dash {
            out.push('-');
            prev_dash = true;
        }
    }

    out.trim_matches('-').to_string()
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
    use super::*;

    #[test]
    fn geocoding_cache_key_includes_slug_and_coords() {
        let location = ResolvedLocation {
            name: "Taipei City".to_string(),
            latitude: 25.053056,
            longitude: 121.52639,
            timezone: "Asia/Taipei".to_string(),
        };

        assert_eq!(location.cache_key(), "taipei-city-25.0531-121.5264");
    }

    #[test]
    fn geocoding_coordinate_label_is_deterministic() {
        assert_eq!(
            coordinate_label(25.0330123, 121.5654123),
            "25.0330,121.5654"
        );
    }

    #[test]
    fn geocoding_slugify_cleans_non_ascii_boundaries() {
        let location = ResolvedLocation {
            name: "Taipei / Xinyi Dist.".to_string(),
            latitude: 25.03,
            longitude: 121.56,
            timezone: "Asia/Taipei".to_string(),
        };

        assert_eq!(location.cache_key(), "taipei-xinyi-dist-25.0300-121.5600");
    }

    #[test]
    fn geocoding_city_query_cache_key_uses_city_prefix() {
        assert_eq!(city_query_cache_key("Tokyo"), "city-tokyo");
    }

    #[test]
    fn geocoding_slugify_for_cache_falls_back_for_non_ascii() {
        let key = slugify_for_cache("東京");
        assert!(key.starts_with('q'));
        assert_eq!(key.len(), 17);
    }

    #[test]
    fn geocoding_cache_roundtrip_for_city_location() {
        let dir = tempfile::tempdir().expect("tempdir");
        let location = ResolvedLocation {
            name: "Taipei".to_string(),
            latitude: 25.033,
            longitude: 121.5654,
            timezone: "Asia/Taipei".to_string(),
        };

        write_cached_city_location(dir.path(), "Taipei", &location).expect("write cache");
        let loaded = read_cached_city_location(dir.path(), "Taipei")
            .expect("read cache")
            .expect("cached location");

        assert_eq!(loaded, location);
    }

    #[test]
    fn geocoding_location_from_coordinates_uses_normalized_label() {
        let location = location_from_coordinates(25.0330123, 121.5654123);
        assert_eq!(location.name, "25.0330,121.5654");
        assert_eq!(location.timezone, "UTC");
    }
}
