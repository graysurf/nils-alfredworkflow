#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CITY_TOKEN_PREFIX="city::"

trim_query() {
  local value="${1-}"
  printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

present_today_with_hourly_token() {
  local json_output="$1"

  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$json_output"
    return 0
  fi

  jq -ce --arg token "$CITY_TOKEN_PREFIX" '
    if (.items | type) != "array" then
      .
    else
      .items |= map(
        . as $item
        | (.title // "") as $title
        | (
            if ($title | test("^(?<location>.+) -?[0-9]+(?:\\.[0-9]+)?~-?[0-9]+(?:\\.[0-9]+)?°C .+ [0-9?]+%$"))
            then ($title | capture("^(?<location>.+) -?[0-9]+(?:\\.[0-9]+)?~-?[0-9]+(?:\\.[0-9]+)?°C .+ [0-9?]+%$")).location
            else null
            end
          ) as $location
        | if $location == null then
            $item + { "valid": false }
          else
            $item + {
              "valid": false,
              "autocomplete": ($token + $location)
            }
          end
      )
    end
  ' <<<"$json_output"
}

query="${1:-}"
trimmed_query="$(trim_query "$query")"

if [[ "$trimmed_query" == "${CITY_TOKEN_PREFIX}"* ]]; then
  selected_city="$(trim_query "${trimmed_query#"${CITY_TOKEN_PREFIX}"}")"
  if [[ -z "$selected_city" ]]; then
    selected_city=""
  fi

  "$script_dir/script_filter_common.sh" hourly "$selected_city"
  exit 0
fi

today_json="$("$script_dir/script_filter_common.sh" today "$trimmed_query")"
present_today_with_hourly_token "$today_json"
