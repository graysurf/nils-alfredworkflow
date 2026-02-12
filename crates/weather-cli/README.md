# nils-weather-cli

CLI backend for one-day and seven-day weather forecast retrieval.

## Commands

| Command | Options | Description |
| --- | --- | --- |
| `weather-cli today` | `--city <CITY>` or `--lat <LAT> --lon <LON>` `[--json]` `[--output <human|json|alfred-json>]` `[--lang <en|zh>]` | Today weather forecast. |
| `weather-cli week` | `--city <CITY>` or `--lat <LAT> --lon <LON>` `[--json]` `[--output <human|json|alfred-json>]` `[--lang <en|zh>]` | 7-day weather forecast. |
| `weather-cli hourly` | `--city <CITY>` or `--lat <LAT> --lon <LON>` `[--json]` `[--output <human|json|alfred-json>]` `[--lang <en|zh>]` `[--hours <1..48>]` | Hourly weather forecast from current hour (24h default). |

## Environment Variables

- Optional cache override: `WEATHER_CACHE_DIR`
- Alfred fallback cache paths: `alfred_workflow_cache`, `alfred_workflow_data`

## Output Contract

- Default mode: human-readable text summary.
- JSON mode: `--json` returns structured forecast object.
- Language mode: `--lang` controls text/Alfred labels (`en` default, `zh` optional).
- `stderr`: user/runtime error text.
- Exit codes: `0` success, `1` runtime/provider error, `2` user/input error.

### Provider stack (no token)

- Open-Meteo primary
- MET Norway fallback
- Freshness states: `live`, `cache_fresh`, `cache_stale_fallback`

## Standards Status

- README/command docs: compliant.
- Human-readable default + explicit JSON mode: compliant.
- JSON service envelope (`schema_version/command/ok`): not yet migrated.

## Validation

- `cargo run -p nils-weather-cli -- --help`
- `cargo run -p nils-weather-cli -- today --help`
- `cargo run -p nils-weather-cli -- week --help`
- `cargo run -p nils-weather-cli -- hourly --help`
- `cargo test -p nils-weather-cli`
