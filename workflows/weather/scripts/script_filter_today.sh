#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CITY_TOKEN_PREFIX="city::"

workflow_helper_loader="$script_dir/lib/workflow_helper_loader.sh"
if [[ ! -f "$workflow_helper_loader" ]]; then
  workflow_helper_loader="$script_dir/../../../scripts/lib/workflow_helper_loader.sh"
fi
if [[ ! -f "$workflow_helper_loader" ]]; then
  git_repo_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$git_repo_root" && -f "$git_repo_root/scripts/lib/workflow_helper_loader.sh" ]]; then
    workflow_helper_loader="$git_repo_root/scripts/lib/workflow_helper_loader.sh"
  fi
fi
if [[ ! -f "$workflow_helper_loader" ]]; then
  printf '{"items":[{"title":"Workflow helper missing","subtitle":"Cannot locate workflow_helper_loader.sh runtime helper.","valid":false}]}\n'
  exit 0
fi
# shellcheck disable=SC1090
source "$workflow_helper_loader"

if ! wfhl_source_required_helper "$script_dir" "script_filter_query_policy.sh" auto "json"; then
  exit 0
fi

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

query="$(sfqp_resolve_query_input "${1:-}")"
trimmed_query="$(sfqp_trim "$query")"

if [[ "$trimmed_query" == "${CITY_TOKEN_PREFIX}"* ]]; then
  selected_city="$(sfqp_trim "${trimmed_query#"${CITY_TOKEN_PREFIX}"}")"
  if [[ -z "$selected_city" ]]; then
    selected_city=""
  fi

  "$script_dir/script_filter_common.sh" hourly "$selected_city"
  exit 0
fi

today_json="$("$script_dir/script_filter_common.sh" today "$trimmed_query")"
present_today_with_hourly_token "$today_json"
