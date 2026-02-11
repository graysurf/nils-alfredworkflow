use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ForecastPeriod {
    Today,
    Week,
}

impl ForecastPeriod {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Today => "today",
            Self::Week => "week",
        }
    }

    pub fn forecast_days(self) -> usize {
        match self {
            Self::Today => 1,
            Self::Week => 7,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FreshnessStatus {
    Live,
    CacheFresh,
    CacheStaleFallback,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CacheMetadata {
    pub status: FreshnessStatus,
    pub key: String,
    pub ttl_secs: u64,
    pub age_secs: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ForecastLocation {
    pub name: String,
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ForecastDay {
    pub date: String,
    pub weather_code: i32,
    pub summary_zh: String,
    pub temp_min_c: f64,
    pub temp_max_c: f64,
    pub precip_prob_max_pct: u8,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ForecastOutput {
    pub period: ForecastPeriod,
    pub location: ForecastLocation,
    pub timezone: String,
    pub forecast: Vec<ForecastDay>,
    pub source: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub source_trace: Vec<String>,
    pub fetched_at: String,
    pub freshness: CacheMetadata,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputMode {
    Json,
    Text,
}

#[derive(Debug, Clone, PartialEq)]
pub enum LocationQuery {
    City(String),
    Coordinates { lat: f64, lon: f64 },
}

#[derive(Debug, Clone, PartialEq)]
pub struct ForecastRequest {
    pub period: ForecastPeriod,
    pub location: LocationQuery,
    pub output_mode: OutputMode,
}

impl ForecastRequest {
    pub fn new(
        period: ForecastPeriod,
        city: Option<&str>,
        lat: Option<f64>,
        lon: Option<f64>,
        output_mode: OutputMode,
    ) -> Result<Self, ValidationError> {
        let has_city = city.is_some();
        let has_coords = lat.is_some() || lon.is_some();

        if has_city && has_coords {
            return Err(ValidationError::ConflictingLocationInput);
        }

        let location = match (city, lat, lon) {
            (Some(raw_city), None, None) => {
                let city = normalize_city(raw_city)?;
                LocationQuery::City(city)
            }
            (None, Some(lat), Some(lon)) => {
                validate_coordinates(lat, lon)?;
                LocationQuery::Coordinates { lat, lon }
            }
            (None, None, None) => return Err(ValidationError::MissingLocationInput),
            _ => return Err(ValidationError::PartialCoordinates),
        };

        Ok(Self {
            period,
            location,
            output_mode,
        })
    }
}

pub fn normalize_city(raw: &str) -> Result<String, ValidationError> {
    let value = raw.trim();
    if value.is_empty() {
        return Err(ValidationError::EmptyCity);
    }
    Ok(value.to_string())
}

pub fn validate_coordinates(lat: f64, lon: f64) -> Result<(), ValidationError> {
    if !((-90.0)..=90.0).contains(&lat) {
        return Err(ValidationError::InvalidLatitude(lat));
    }
    if !((-180.0)..=180.0).contains(&lon) {
        return Err(ValidationError::InvalidLongitude(lon));
    }
    Ok(())
}

#[derive(Debug, Error, PartialEq)]
pub enum ValidationError {
    #[error("missing location input: use --city or --lat/--lon")]
    MissingLocationInput,
    #[error("partial coordinates: provide both --lat and --lon")]
    PartialCoordinates,
    #[error("conflicting location input: use either --city or --lat/--lon")]
    ConflictingLocationInput,
    #[error("city must not be empty")]
    EmptyCity,
    #[error("invalid latitude: {0}")]
    InvalidLatitude(f64),
    #[error("invalid longitude: {0}")]
    InvalidLongitude(f64),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn model_request_accepts_city_input() {
        let request = ForecastRequest::new(
            ForecastPeriod::Today,
            Some("Taipei"),
            None,
            None,
            OutputMode::Json,
        )
        .expect("request");

        assert!(matches!(request.location, LocationQuery::City(_)));
        assert_eq!(request.period, ForecastPeriod::Today);
    }

    #[test]
    fn model_request_accepts_coordinate_input() {
        let request = ForecastRequest::new(
            ForecastPeriod::Week,
            None,
            Some(25.03),
            Some(121.56),
            OutputMode::Text,
        )
        .expect("request");

        assert!(matches!(
            request.location,
            LocationQuery::Coordinates { .. }
        ));
        assert_eq!(request.period, ForecastPeriod::Week);
    }

    #[test]
    fn model_rejects_missing_location_input() {
        let err = ForecastRequest::new(ForecastPeriod::Today, None, None, None, OutputMode::Json)
            .expect_err("must fail");

        assert_eq!(err, ValidationError::MissingLocationInput);
    }

    #[test]
    fn model_rejects_partial_coordinates() {
        let err = ForecastRequest::new(
            ForecastPeriod::Today,
            None,
            Some(25.0),
            None,
            OutputMode::Json,
        )
        .expect_err("must fail");

        assert_eq!(err, ValidationError::PartialCoordinates);
    }

    #[test]
    fn model_rejects_conflicting_location_input() {
        let err = ForecastRequest::new(
            ForecastPeriod::Today,
            Some("Taipei"),
            Some(25.0),
            Some(121.5),
            OutputMode::Json,
        )
        .expect_err("must fail");

        assert_eq!(err, ValidationError::ConflictingLocationInput);
    }

    #[test]
    fn model_rejects_invalid_latitude() {
        let err = ForecastRequest::new(
            ForecastPeriod::Today,
            None,
            Some(100.0),
            Some(121.5),
            OutputMode::Json,
        )
        .expect_err("must fail");

        assert_eq!(err, ValidationError::InvalidLatitude(100.0));
    }

    #[test]
    fn model_rejects_invalid_longitude() {
        let err = ForecastRequest::new(
            ForecastPeriod::Today,
            None,
            Some(25.0),
            Some(190.0),
            OutputMode::Json,
        )
        .expect_err("must fail");

        assert_eq!(err, ValidationError::InvalidLongitude(190.0));
    }

    #[test]
    fn model_normalize_city_trims_input() {
        let city = normalize_city("  Taipei  ").expect("city");
        assert_eq!(city, "Taipei");
    }
}
