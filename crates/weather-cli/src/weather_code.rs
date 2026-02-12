pub fn summary_zh(code: i32) -> &'static str {
    match code {
        0 => "晴朗",
        1 => "大致晴朗",
        2 => "晴時多雲",
        3 => "陰天",
        45 | 48 => "有霧",
        51 | 53 | 55 | 56 | 57 => "毛毛雨",
        61 | 63 | 65 | 66 | 67 => "降雨",
        71 | 73 | 75 | 77 => "降雪",
        80..=82 => "陣雨",
        85 | 86 => "陣雪",
        95 | 96 | 99 => "雷雨",
        _ => "天氣狀態未知",
    }
}

pub fn summary_en(code: i32) -> &'static str {
    match code {
        0 => "Clear sky",
        1 => "Mainly clear",
        2 => "Partly cloudy",
        3 => "Cloudy",
        45 | 48 => "Fog",
        51 | 53 | 55 | 56 | 57 => "Drizzle",
        61 | 63 | 65 | 66 | 67 => "Rain",
        71 | 73 | 75 | 77 => "Snow",
        80..=82 => "Rain showers",
        85 | 86 => "Snow showers",
        95 | 96 | 99 => "Thunderstorm",
        _ => "Unknown weather",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn weather_code_maps_clear_sky() {
        assert_eq!(summary_zh(0), "晴朗");
    }

    #[test]
    fn weather_code_maps_rain_family() {
        assert_eq!(summary_zh(63), "降雨");
        assert_eq!(summary_zh(81), "陣雨");
    }

    #[test]
    fn weather_code_maps_english_labels() {
        assert_eq!(summary_en(0), "Clear sky");
        assert_eq!(summary_en(63), "Rain");
        assert_eq!(summary_en(81), "Rain showers");
    }

    #[test]
    fn summary_mapping_handles_unknown_code() {
        assert_eq!(summary_zh(999), "天氣狀態未知");
        assert_eq!(summary_en(999), "Unknown weather");
    }
}
