use crate::model::ForecastLocation;

#[derive(Debug, Clone, PartialEq)]
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
        let slug = slugify(&self.name);
        format!(
            "{}-{:.4}-{:.4}",
            slug,
            round4(self.latitude),
            round4(self.longitude)
        )
    }
}

pub fn coordinate_label(lat: f64, lon: f64) -> String {
    format!("{:.4},{:.4}", round4(lat), round4(lon))
}

fn round4(value: f64) -> f64 {
    (value * 10_000.0).round() / 10_000.0
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
}
