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
  local raw_message="${1:-wiki-cli search failed}"
  local message
  message="$(normalize_error_message "$raw_message")"
  [[ -n "$message" ]] || message="wiki-cli search failed"

  local title="Wiki Search error"
  local subtitle="$message"
  local lower
  lower="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"

  if [[ "$lower" == *"query must not be empty"* || "$lower" == *"empty query"* ]]; then
    title="Enter a search query"
    subtitle="Type keywords after wk to search Wikipedia."
  elif [[ "$lower" == *"invalid wiki_language"* || "$lower" == *"invalid wiki_max_results"* ]]; then
    title="Invalid Wiki workflow config"
    subtitle="Check WIKI_LANGUAGE and WIKI_MAX_RESULTS, then retry."
  elif [[ "$lower" == *"wikipedia api request failed"* || "$lower" == *"wikipedia api unavailable"* || "$lower" == *"invalid wikipedia api response"* || "$lower" == *"timed out"* || "$lower" == *"timeout"* || "$lower" == *"connection"* || "$lower" == *"dns"* || "$lower" == *"tls"* || "$lower" == *"status 500"* || "$lower" == *"status 502"* || "$lower" == *"status 503"* || "$lower" == *"status 504"* || "$lower" == *"api error (5"* ]]; then
    title="Wikipedia API unavailable"
    subtitle="Cannot reach Wikipedia now. Check network and retry."
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

resolve_wiki_cli() {
  if [[ -n "${WIKI_CLI_BIN:-}" && -x "${WIKI_CLI_BIN}" ]]; then
    clear_quarantine_if_needed "${WIKI_CLI_BIN}"
    printf '%s\n' "${WIKI_CLI_BIN}"
    return 0
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local packaged_cli
  packaged_cli="$script_dir/../bin/wiki-cli"
  if [[ -x "$packaged_cli" ]]; then
    clear_quarantine_if_needed "$packaged_cli"
    printf '%s\n' "$packaged_cli"
    return 0
  fi

  local repo_root
  repo_root="$(cd "$script_dir/../../.." && pwd)"

  local release_cli
  release_cli="$repo_root/target/release/wiki-cli"
  if [[ -x "$release_cli" ]]; then
    clear_quarantine_if_needed "$release_cli"
    printf '%s\n' "$release_cli"
    return 0
  fi

  local debug_cli
  debug_cli="$repo_root/target/debug/wiki-cli"
  if [[ -x "$debug_cli" ]]; then
    clear_quarantine_if_needed "$debug_cli"
    printf '%s\n' "$debug_cli"
    return 0
  fi

  echo "wiki-cli binary not found (checked package/release/debug paths)" >&2
  return 1
}

wiki_search_fetch_json() {
  local query="$1"
  local err_file="${TMPDIR:-/tmp}/wiki-search-script-filter.err.$$.$RANDOM"

  local wiki_cli
  if ! wiki_cli="$(resolve_wiki_cli 2>"$err_file")"; then
    cat "$err_file" >&2
    rm -f "$err_file"
    return 1
  fi

  local json_output
  if json_output="$("$wiki_cli" search --query "$query" --mode alfred 2>"$err_file")"; then
    rm -f "$err_file"
    if [[ -z "$json_output" ]]; then
      echo "wiki-cli returned empty response" >&2
      return 1
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
  emit_error_item "Enter a search query" "Type keywords after wk to search Wikipedia."
  exit 0
fi

if sfqp_is_short_query "$query" 2; then
  sfqp_emit_short_query_item_json \
    2 \
    "Keep typing (2+ chars)" \
    "Type at least %s characters before searching Wikipedia."
  exit 0
fi

sfac_init_context "wiki-search" "nils-wiki-search-workflow"
cache_ttl_seconds="$(sfac_resolve_positive_int_env "WIKI_QUERY_CACHE_TTL_SECONDS" "10")"
settle_seconds="$(sfac_resolve_non_negative_number_env "WIKI_QUERY_COALESCE_SETTLE_SECONDS" "2")"
rerun_seconds="$(sfac_resolve_non_negative_number_env "WIKI_QUERY_COALESCE_RERUN_SECONDS" "0.4")"

if sfac_load_cache_result "$query" "$cache_ttl_seconds"; then
  if [[ "$SFAC_CACHE_STATUS" == "ok" ]]; then
    printf '%s\n' "$SFAC_CACHE_PAYLOAD"
  else
    print_error_item "$SFAC_CACHE_PAYLOAD"
  fi
  exit 0
fi

if [[ "$settle_seconds" == "0" || "$settle_seconds" == "0.0" ]]; then
  sync_err_file="${TMPDIR:-/tmp}/wiki-search-script-filter.sync.err.$$.$RANDOM"
  if json_output="$(wiki_search_fetch_json "$query" 2>"$sync_err_file")"; then
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
    "Searching Wikipedia..." \
    "Waiting for final query before calling Wikipedia API." \
    "$rerun_seconds"
  exit 0
fi

final_err_file="${TMPDIR:-/tmp}/wiki-search-script-filter.final.err.$$.$RANDOM"
if json_output="$(wiki_search_fetch_json "$query" 2>"$final_err_file")"; then
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
