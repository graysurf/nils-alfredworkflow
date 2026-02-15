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
  local raw_message="${1:-bangumi-cli query failed}"
  local message
  message="$(normalize_error_message "$raw_message")"
  [[ -n "$message" ]] || message="bangumi-cli query failed"

  local title="Bangumi Search error"
  local subtitle="$message"
  local lower
  lower="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"

  if [[ "$lower" == *"query must not be empty"* || "$lower" == *"empty query"* ]]; then
    title="Enter a search query"
    subtitle="Type keywords after bgm to search Bangumi."
  elif [[ "$lower" == *"missing bangumi_api_key"* || "$lower" == *"api key required"* ]]; then
    title="Bangumi API key is missing"
    subtitle="Set BANGUMI_API_KEY in workflow configuration and retry."
  elif [[ "$lower" == *"invalid bangumi_"* || "$lower" == *"invalid config"* ]]; then
    title="Invalid Bangumi workflow config"
    subtitle="Check BANGUMI_MAX_RESULTS/BANGUMI_TIMEOUT_MS/BANGUMI_API_FALLBACK and retry."
  elif [[ "$lower" == *"rate limit"* || "$lower" == *"status 429"* ]]; then
    title="Bangumi API rate-limited"
    subtitle="Bangumi API returned 429. Retry later or lower BANGUMI_MAX_RESULTS."
  elif [[ "$lower" == *"bangumi-cli binary not found"* || "$lower" == *"binary not found"* ]]; then
    title="bangumi-cli binary not found"
    subtitle="Package workflow or set BANGUMI_CLI_BIN to a bangumi-cli executable."
  elif [[ "$lower" == *"bangumi api request failed"* || "$lower" == *"bangumi api unavailable"* || "$lower" == *"invalid bangumi api response"* || "$lower" == *"timed out"* || "$lower" == *"timeout"* || "$lower" == *"connection"* || "$lower" == *"dns"* || "$lower" == *"tls"* || "$lower" == *"status 500"* || "$lower" == *"status 502"* || "$lower" == *"status 503"* || "$lower" == *"status 504"* || "$lower" == *"api error (5"* ]]; then
    title="Bangumi API unavailable"
    subtitle="Cannot reach Bangumi API now. Check network and retry."
  fi

  emit_error_item "$title" "$subtitle"
}

resolve_bangumi_cli() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local packaged_cli
  packaged_cli="$script_dir/../bin/bangumi-cli"

  local repo_root
  repo_root="$(cd "$script_dir/../../.." && pwd)"

  local release_cli
  release_cli="$repo_root/target/release/bangumi-cli"

  local debug_cli
  debug_cli="$repo_root/target/debug/bangumi-cli"

  wfcr_resolve_binary \
    "BANGUMI_CLI_BIN" \
    "$packaged_cli" \
    "$release_cli" \
    "$debug_cli" \
    "bangumi-cli binary not found (checked BANGUMI_CLI_BIN/package/release/debug paths)"
}

bangumi_query_fetch_json() {
  local query="$1"
  local err_file="${TMPDIR:-/tmp}/bangumi-search-script-filter.err.$$.$RANDOM"

  local bangumi_cli
  if ! bangumi_cli="$(resolve_bangumi_cli 2>"$err_file")"; then
    cat "$err_file" >&2
    rm -f "$err_file"
    return 1
  fi

  local json_output
  if json_output="$("$bangumi_cli" query --input "$query" --mode alfred 2>"$err_file")"; then
    rm -f "$err_file"

    if [[ -z "$json_output" ]]; then
      echo "bangumi-cli returned empty response" >&2
      return 1
    fi

    if command -v jq >/dev/null 2>&1; then
      if ! jq -e '.items | type == "array"' >/dev/null <<<"$json_output"; then
        echo "bangumi-cli returned malformed Alfred JSON" >&2
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
  emit_error_item "Enter a search query" "Type keywords after bgm to search Bangumi."
  exit 0
fi

if sfqp_is_short_query "$query" 2; then
  sfqp_emit_short_query_item_json \
    2 \
    "Keep typing (2+ chars)" \
    "Type at least %s characters before searching Bangumi."
  exit 0
fi

# Shared driver owns cache/coalesce orchestration only.
# Bangumi-specific backend fetch and error mapping remain local in this script.
sfsd_run_search_flow \
  "$query" \
  "bangumi-search" \
  "nils-bangumi-search-workflow" \
  "BANGUMI_QUERY_CACHE_TTL_SECONDS" \
  "BANGUMI_QUERY_COALESCE_SETTLE_SECONDS" \
  "BANGUMI_QUERY_COALESCE_RERUN_SECONDS" \
  "Searching Bangumi..." \
  "Waiting for final query before calling Bangumi API." \
  "bangumi_query_fetch_json" \
  "print_error_item"
