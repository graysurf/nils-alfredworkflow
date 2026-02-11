#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for weather-cli-live-smoke" >&2
  exit 1
fi

run_and_check() {
  local period="$1"
  local tmp
  tmp="$(mktemp)"

  if ! cargo run -q -p nils-weather-cli -- "$period" --city Taipei --json >"$tmp" 2>/dev/null; then
    echo "skip: unable to fetch live $period forecast (network/provider unavailable)"
    rm -f "$tmp"
    return 0
  fi

  jq -e '
    .period and
    .location and
    .timezone and
    (.forecast | type == "array") and
    .source and
    .freshness
  ' "$tmp" >/dev/null

  echo "ok: $period contract"
  rm -f "$tmp"
}

run_and_check today
run_and_check week
