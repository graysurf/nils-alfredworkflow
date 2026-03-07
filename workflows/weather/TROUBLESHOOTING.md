# Weather Workflow Troubleshooting

Reference: [ALFRED_WORKFLOW_DEVELOPMENT.md](../../ALFRED_WORKFLOW_DEVELOPMENT.md)

## Quick operator checks

Run from repository root.

```bash
# Required scripts
ls -l \
  workflows/weather/scripts/script_filter_today.sh \
  workflows/weather/scripts/script_filter_week.sh \
  workflows/weather/scripts/script_filter_common.sh \
  workflows/weather/scripts/action_copy.sh

# Runtime candidate check
test -x workflows/weather/bin/weather-cli && echo "bundled weather-cli found"
command -v weather-cli || true

# CLI contract checks
cargo run -q -p nils-weather-cli -- today --output json --city Tokyo | jq -e '.schema_version == "v1" and .ok == true'
cargo run -q -p nils-weather-cli -- today --output alfred-json --city Tokyo | jq -e '.items | type == "array"'
cargo run -q -p nils-weather-cli -- today --output alfred-json --city Tokyo --city Osaka | jq -e '.items | type == "array"'

# Workflow entrypoints
bash workflows/weather/scripts/script_filter_today.sh "Tokyo" | jq -e '.items | type == "array"'
bash workflows/weather/scripts/script_filter_today.sh "Tokyo,Osaka" | jq -e '.items | type == "array"'
bash workflows/weather/scripts/script_filter_today.sh "city::Tokyo" | jq -e '.items | type == "array"'
bash workflows/weather/scripts/script_filter_week.sh "Tokyo" | jq -e '.items | type == "array"'
bash workflows/weather/scripts/script_filter_week.sh "city::Tokyo" | jq -e '.items | type == "array"'

# Confirm default env configuration
rg -n "WEATHER_CLI_BIN|WEATHER_LOCALE|WEATHER_DEFAULT_CITIES|WEATHER_CACHE_TTL_SECS" workflows/weather/workflow.toml
```

`jq` is recommended for local validation and shell-side normalization/token rewriting:

```bash
command -v jq || echo "jq missing: single-city normalization and local validation will be degraded"
```

## Common failures and actions

| Symptom                            | Likely cause                                      | Action                                                                    |
| ---------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------------- |
| `weather-cli binary not found` row | Binary absent in lookup paths                     | Re-package workflow or set `WEATHER_CLI_BIN` to executable absolute path. |
| `Invalid location input`           | Bad city/coordinate format                        | Use `City` or `lat,lon` (example: `25.03,121.56`).                        |
| `Location not found`               | Ambiguous/unknown city                            | Use more specific name or coordinates.                                    |
| `Weather provider unavailable`     | Upstream provider/API transient issue             | Retry later before changing workflow code/config.                         |
| `Weather output format error`      | Custom/old `weather-cli` returned unexpected JSON | Use packaged pinned binary or update local override binary.               |
| Single-city rows show raw header / extra metadata | `jq` missing, so shell cannot normalize single-city Alfred rows | Install `jq` for local runs or use the packaged workflow environment.     |

If only `ww` mode looks odd, verify the two-stage flow first: `ww <query>` to pick a city, then select the city row.
If only `wt` stage two looks odd, inspect the persistent geocoding cache under the workflow cache root:

```bash
find "${ALFRED_WORKFLOW_CACHE:-${TMPDIR:-/tmp}/nils-weather-cli}/weather-cli/geocode" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort
```

## Validation

```bash
bash workflows/weather/tests/smoke.sh
scripts/workflow-test.sh --id weather
scripts/workflow-pack.sh --id weather
```

Optional asset consistency check:

```bash
bash workflows/weather/scripts/generate_weather_icons.sh
bash scripts/weather-cli-live-smoke.sh
```

## Rollback guidance

1. Re-install the previous known-good package from `dist/weather/<version>/`.
2. Reset variables to defaults (`WEATHER_CLI_BIN=""`, `WEATHER_LOCALE="en"`, `WEATHER_DEFAULT_CITIES="Tokyo"`,
   `WEATHER_CACHE_TTL_SECS="900"`).
3. If regression remains, roll back `workflows/weather/` on a branch, then rerun Validation before release.
