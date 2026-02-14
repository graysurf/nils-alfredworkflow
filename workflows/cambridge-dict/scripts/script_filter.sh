#!/usr/bin/env bash
set -euo pipefail

resolve_helper() {
  local helper_name="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local git_repo_root=""
  git_repo_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"

  local candidates=(
    "$script_dir/lib/$helper_name"
    "$script_dir/../../../scripts/lib/$helper_name"
  )
  if [[ -n "$git_repo_root" ]]; then
    candidates+=("$git_repo_root/scripts/lib/$helper_name")
  fi
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

error_json_helper="$(resolve_helper "script_filter_error_json.sh" || true)"
if [[ -z "$error_json_helper" ]]; then
  printf '{"items":[{"title":"Workflow helper missing","subtitle":"Cannot locate script_filter_error_json.sh runtime helper.","valid":false}]}\n'
  exit 0
fi
# shellcheck disable=SC1090
source "$error_json_helper"

cli_resolver_helper="$(resolve_helper "workflow_cli_resolver.sh" || true)"
if [[ -z "$cli_resolver_helper" ]]; then
  sfej_emit_error_item_json "Workflow helper missing" "Cannot locate workflow_cli_resolver.sh runtime helper."
  exit 0
fi
# shellcheck disable=SC1090
source "$cli_resolver_helper"

normalize_error_message() {
  sfej_normalize_error_message "${1-}"
}

emit_error_item() {
  local title="$1"
  local subtitle="$2"
  sfej_emit_error_item_json "$title" "$subtitle"
}

print_error_item() {
  local raw_message="${1:-cambridge-cli query failed}"
  local message
  message="$(normalize_error_message "$raw_message")"
  [[ -n "$message" ]] || message="cambridge-cli query failed"

  local title="Cambridge Dict error"
  local subtitle="$message"
  local lower
  lower="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"

  if [[ "$lower" == *"query must not be empty"* || "$lower" == *"query cannot be empty"* || "$lower" == *"empty query"* ]]; then
    title="Enter a word"
    subtitle="Type a word after cd, then pick a candidate entry."
  elif [[ "$lower" == *"invalid cambridge_dict_mode"* || "$lower" == *"invalid cambridge_max_results"* || "$lower" == *"invalid cambridge_timeout_ms"* || "$lower" == *"invalid cambridge_headless"* || "$lower" == *"invalid config"* ]]; then
    title="Invalid Cambridge workflow config"
    subtitle="Check CAMBRIDGE_DICT_MODE/CAMBRIDGE_MAX_RESULTS/CAMBRIDGE_TIMEOUT_MS/CAMBRIDGE_HEADLESS."
  elif [[ "$lower" == *"anti_bot"* || "$lower" == *"cloudflare"* || "$lower" == *"challenge page"* || "$lower" == *"bot"* ]]; then
    title="Cambridge anti-bot challenge"
    subtitle="Cambridge blocked automation. Retry later or open dictionary site directly."
  elif [[ "$lower" == *"cookie_wall"* || "$lower" == *"cookie consent"* || "$lower" == *"enable cookies"* ]]; then
    title="Cambridge cookie consent required"
    subtitle="Open Cambridge Dictionary in browser once, accept cookies, then retry."
  elif [[ "$lower" == *"timed out"* || "$lower" == *"timeout"* ]]; then
    title="Cambridge request timed out"
    subtitle="Increase CAMBRIDGE_TIMEOUT_MS or retry with shorter query."
  elif [[ "$lower" == *"node"*"not found"* || "$lower" == *"playwright"* || "$lower" == *"chromium executable doesn't exist"* || "$lower" == *"browser executable"* ]]; then
    title="Node/Playwright runtime unavailable"
    subtitle="Run scripts/setup-cambridge-workflow-runtime.sh to install workflow runtime."
  elif [[ "$lower" == *"binary not found"* || "$lower" == *"cambridge-cli binary not found"* ]]; then
    title="cambridge-cli binary not found"
    subtitle="Package workflow or set CAMBRIDGE_CLI_BIN to a cambridge-cli executable."
  elif [[ "$lower" == *"connection"* || "$lower" == *"dns"* || "$lower" == *"tls"* || "$lower" == *"network"* || "$lower" == *"status 500"* || "$lower" == *"status 502"* || "$lower" == *"status 503"* || "$lower" == *"status 504"* ]]; then
    title="Cambridge service unavailable"
    subtitle="Cannot reach Cambridge now. Check network and retry."
  fi

  emit_error_item "$title" "$subtitle"
}

resolve_cambridge_cli() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local packaged_cli
  packaged_cli="$script_dir/../bin/cambridge-cli"

  local repo_root
  repo_root="$(cd "$script_dir/../../.." && pwd)"

  local release_cli
  release_cli="$repo_root/target/release/cambridge-cli"

  local debug_cli
  debug_cli="$repo_root/target/debug/cambridge-cli"

  wfcr_resolve_binary \
    "CAMBRIDGE_CLI_BIN" \
    "$packaged_cli" \
    "$release_cli" \
    "$debug_cli" \
    "cambridge-cli binary not found (checked CAMBRIDGE_CLI_BIN/package/release/debug paths)"
}

cambridge_query_fetch_json() {
  local query="$1"
  local err_file="${TMPDIR:-/tmp}/cambridge-dict-script-filter.err.$$.$RANDOM"

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  export CAMBRIDGE_SCRAPER_SCRIPT="$script_dir/cambridge_scraper.mjs"

  local cambridge_cli
  if ! cambridge_cli="$(resolve_cambridge_cli 2>"$err_file")"; then
    cat "$err_file" >&2
    rm -f "$err_file"
    return 1
  fi

  local json_output
  if json_output="$("$cambridge_cli" query --input "$query" --mode alfred 2>"$err_file")"; then
    rm -f "$err_file"

    if [[ -z "$json_output" ]]; then
      echo "cambridge-cli returned empty response" >&2
      return 1
    fi

    if command -v jq >/dev/null 2>&1; then
      if ! jq -e '.items | type == "array"' >/dev/null <<<"$json_output"; then
        echo "cambridge-cli returned malformed Alfred JSON" >&2
        return 1
      fi
    fi

    printf '%s\n' "$json_output"
    return 0
  fi

  cat "$err_file" >&2
  rm -f "$err_file"
  return 1
}

query_policy_helper="$(resolve_helper "script_filter_query_policy.sh" || true)"
if [[ -z "$query_policy_helper" ]]; then
  emit_error_item "Workflow helper missing" "Cannot locate script_filter_query_policy.sh runtime helper."
  exit 0
fi
# shellcheck disable=SC1090
source "$query_policy_helper"

async_coalesce_helper="$(resolve_helper "script_filter_async_coalesce.sh" || true)"
if [[ -z "$async_coalesce_helper" ]]; then
  emit_error_item "Workflow helper missing" "Cannot locate script_filter_async_coalesce.sh runtime helper."
  exit 0
fi
# shellcheck disable=SC1090
source "$async_coalesce_helper"

search_driver_helper="$(resolve_helper "script_filter_search_driver.sh" || true)"
if [[ -z "$search_driver_helper" ]]; then
  emit_error_item "Workflow helper missing" "Cannot locate script_filter_search_driver.sh runtime helper."
  exit 0
fi
# shellcheck disable=SC1090
source "$search_driver_helper"

query="$(sfqp_resolve_query_input "${1:-}")"
trimmed_query="$(sfqp_trim "$query")"
query="$trimmed_query"

if [[ -z "$query" ]]; then
  emit_error_item "Enter a word" "Type a word after cd, then pick a candidate entry."
  exit 0
fi

if sfqp_is_short_query "$query" 2; then
  sfqp_emit_short_query_item_json \
    2 \
    "Keep typing (2+ chars)" \
    "Type at least %s characters before searching Cambridge Dictionary."
  exit 0
fi

# Shared driver owns cache/coalesce orchestration only.
# Cambridge-specific backend fetch and error mapping remain local in this script.
sfsd_run_search_flow \
  "$query" \
  "cambridge-dict" \
  "nils-cambridge-dict-workflow" \
  "CAMBRIDGE_QUERY_CACHE_TTL_SECONDS" \
  "CAMBRIDGE_QUERY_COALESCE_SETTLE_SECONDS" \
  "CAMBRIDGE_QUERY_COALESCE_RERUN_SECONDS" \
  "Searching Cambridge..." \
  "Waiting for final query before calling Cambridge backend." \
  "cambridge_query_fetch_json" \
  "print_error_item"
