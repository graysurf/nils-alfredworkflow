#!/usr/bin/env bash
set -euo pipefail

resolve_helper() {
  local helper_name="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local candidates=(
    "$script_dir/lib/$helper_name"
    "$script_dir/../../../scripts/lib/$helper_name"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

json_escape() {
  local value="${1-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  printf '%s' "$value"
}

normalize_error_message() {
  local value="${1-}"
  value="$(printf '%s' "$value" | tr '\n\r' '  ' | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
  value="${value#error: }"
  value="${value#Error: }"
  printf '%s' "$value"
}

emit_error_item() {
  local title="$1"
  local subtitle="$2"
  printf '{"items":[{"title":"%s","subtitle":"%s","valid":false}]}' \
    "$(json_escape "$title")" \
    "$(json_escape "$subtitle")"
  printf '\n'
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

clear_quarantine_if_needed() {
  local cli_path="$1"

  if [[ "$(uname -s 2>/dev/null || printf '')" != "Darwin" ]]; then
    return 0
  fi

  if ! command -v xattr >/dev/null 2>&1; then
    return 0
  fi

  if xattr -p com.apple.quarantine "$cli_path" >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "$cli_path" >/dev/null 2>&1 || true
  fi
}

resolve_cambridge_cli() {
  if [[ -n "${CAMBRIDGE_CLI_BIN:-}" && -x "${CAMBRIDGE_CLI_BIN}" ]]; then
    clear_quarantine_if_needed "${CAMBRIDGE_CLI_BIN}"
    printf '%s\n' "${CAMBRIDGE_CLI_BIN}"
    return 0
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local packaged_cli
  packaged_cli="$script_dir/../bin/cambridge-cli"
  if [[ -x "$packaged_cli" ]]; then
    clear_quarantine_if_needed "$packaged_cli"
    printf '%s\n' "$packaged_cli"
    return 0
  fi

  local repo_root
  repo_root="$(cd "$script_dir/../../.." && pwd)"

  local release_cli
  release_cli="$repo_root/target/release/cambridge-cli"
  if [[ -x "$release_cli" ]]; then
    clear_quarantine_if_needed "$release_cli"
    printf '%s\n' "$release_cli"
    return 0
  fi

  local debug_cli
  debug_cli="$repo_root/target/debug/cambridge-cli"
  if [[ -x "$debug_cli" ]]; then
    clear_quarantine_if_needed "$debug_cli"
    printf '%s\n' "$debug_cli"
    return 0
  fi

  echo "cambridge-cli binary not found (checked CAMBRIDGE_CLI_BIN/package/release/debug paths)" >&2
  return 1
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

sfac_init_context "cambridge-dict" "nils-cambridge-dict-workflow"
cache_ttl_seconds="$(sfac_resolve_positive_int_env "CAMBRIDGE_QUERY_CACHE_TTL_SECONDS" "10")"
settle_seconds="$(sfac_resolve_non_negative_number_env "CAMBRIDGE_QUERY_COALESCE_SETTLE_SECONDS" "2")"
rerun_seconds="$(sfac_resolve_non_negative_number_env "CAMBRIDGE_QUERY_COALESCE_RERUN_SECONDS" "0.4")"

if sfac_load_cache_result "$query" "$cache_ttl_seconds"; then
  if [[ "$SFAC_CACHE_STATUS" == "ok" ]]; then
    printf '%s\n' "$SFAC_CACHE_PAYLOAD"
  else
    print_error_item "$SFAC_CACHE_PAYLOAD"
  fi
  exit 0
fi

if [[ "$settle_seconds" == "0" || "$settle_seconds" == "0.0" ]]; then
  sync_err_file="${TMPDIR:-/tmp}/cambridge-dict-script-filter.sync.err.$$.$RANDOM"
  if json_output="$(cambridge_query_fetch_json "$query" 2>"$sync_err_file")"; then
    if [[ "$cache_ttl_seconds" -gt 0 ]]; then
      sfac_store_cache_result "$query" "ok" "$json_output" || true
    fi
    rm -f "$sync_err_file"
    printf '%s\n' "$json_output"
    exit 0
  fi

  err_msg="$(cat "$sync_err_file")"
  rm -f "$sync_err_file"
  if [[ "$cache_ttl_seconds" -gt 0 ]]; then
    sfac_store_cache_result "$query" "err" "$err_msg" || true
  fi
  print_error_item "$err_msg"
  exit 0
fi

if ! sfac_wait_for_final_query "$query" "$settle_seconds"; then
  sfac_emit_pending_item_json \
    "Searching Cambridge..." \
    "Waiting for final query before calling Cambridge backend." \
    "$rerun_seconds"
  exit 0
fi

final_err_file="${TMPDIR:-/tmp}/cambridge-dict-script-filter.final.err.$$.$RANDOM"
if json_output="$(cambridge_query_fetch_json "$query" 2>"$final_err_file")"; then
  if [[ "$cache_ttl_seconds" -gt 0 ]]; then
    sfac_store_cache_result "$query" "ok" "$json_output" || true
  fi
  rm -f "$final_err_file"
  printf '%s\n' "$json_output"
  exit 0
fi

err_msg="$(cat "$final_err_file")"
rm -f "$final_err_file"
if [[ "$cache_ttl_seconds" -gt 0 ]]; then
  sfac_store_cache_result "$query" "err" "$err_msg" || true
fi
print_error_item "$err_msg"
