# weather-cli contract

## Goal

Provide token-free weather forecast data for current day and 7-day horizon.
Primary source is Open-Meteo, fallback source is MET Norway.

## Commands

- `weather-cli today --city <name> [--json]`
- `weather-cli today --lat <f64> --lon <f64> [--json]`
- `weather-cli week --city <name> [--json]`
- `weather-cli week --lat <f64> --lon <f64> [--json]`

Location input rules:

- Use either `--city` OR `--lat/--lon`.
- `--lat` and `--lon` must be provided together.
- `--city` cannot be empty.

## Output schema (JSON mode)

```json
{
  "period": "today|week",
  "location": {
    "name": "Taipei City",
    "latitude": 25.0531,
    "longitude": 121.5264
  },
  "timezone": "Asia/Taipei",
  "forecast": [
    {
      "date": "2026-02-11",
      "weather_code": 3,
      "summary_zh": "陰天",
      "temp_min_c": 14.5,
      "temp_max_c": 19.9,
      "precip_prob_max_pct": 13
    }
  ],
  "source": "open_meteo|met_no",
  "source_trace": ["open_meteo: transport error: timeout"],
  "fetched_at": "2026-02-11T03:30:00Z",
  "freshness": {
    "status": "live|cache_fresh|cache_stale_fallback",
    "key": "today-taipei-city-25.0531-121.5264",
    "ttl_secs": 1800,
    "age_secs": 0
  }
}
```

## Provider policy

- No token required for all command paths.
- Forecast order:
  1. Open-Meteo (primary)
  2. MET Norway (fallback)
- If both providers fail and stale cache exists, return stale cache with `freshness.status=cache_stale_fallback`.
- If all fail and no cache exists, command exits with runtime error.

## Exit codes

- `0`: success
- `1`: runtime/provider failure
- `2`: user input validation failure

## Cache policy

- TTL is fixed at 30 minutes (`1800` seconds).
- Cache key includes period + normalized location identity.
- Corrupt cache payload is treated as cache miss.

## No-token statement

This CLI intentionally uses free and no-token endpoints only:

- Open-Meteo geocoding + forecast API
- MET Norway Locationforecast API (requires User-Agent header, no token)
