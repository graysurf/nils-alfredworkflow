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
    fn summary_mapping_handles_unknown_code() {
        assert_eq!(summary_zh(999), "天氣狀態未知");
    }
}
