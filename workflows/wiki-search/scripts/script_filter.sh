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
  elif [[ "$lower" == *"invalid wiki_language"* || "$lower" == *"invalid wiki_language_options"* || "$lower" == *"invalid wiki_max_results"* ]]; then
    title="Invalid Wiki workflow config"
    subtitle="Check WIKI_LANGUAGE, WIKI_LANGUAGE_OPTIONS, and WIKI_MAX_RESULTS."
  elif [[ "$lower" == *"wikipedia api request failed"* || "$lower" == *"wikipedia api unavailable"* || "$lower" == *"invalid wikipedia api response"* || "$lower" == *"timed out"* || "$lower" == *"timeout"* || "$lower" == *"connection"* || "$lower" == *"dns"* || "$lower" == *"tls"* || "$lower" == *"status 500"* || "$lower" == *"status 502"* || "$lower" == *"status 503"* || "$lower" == *"status 504"* || "$lower" == *"api error (5"* ]]; then
    title="Wikipedia API unavailable"
    subtitle="Cannot reach Wikipedia now. Check network and retry."
  fi

  emit_error_item "$title" "$subtitle"
}

resolve_wiki_cli() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local packaged_cli
  packaged_cli="$script_dir/../bin/wiki-cli"

  local repo_root
  repo_root="$(cd "$script_dir/../../.." && pwd)"

  local release_cli
  release_cli="$repo_root/target/release/wiki-cli"

  local debug_cli
  debug_cli="$repo_root/target/debug/wiki-cli"

  wfcr_resolve_binary \
    "WIKI_CLI_BIN" \
    "$packaged_cli" \
    "$release_cli" \
    "$debug_cli" \
    "wiki-cli binary not found (checked package/release/debug paths)"
}

resolve_cache_dir() {
  local candidate
  for candidate in \
    "${ALFRED_WORKFLOW_CACHE:-}" \
    "${ALFRED_WORKFLOW_DATA:-}"; do
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' "${TMPDIR:-/tmp}/nils-wiki-search-workflow"
}

wiki_override_state_file() {
  local cache_dir
  cache_dir="$(resolve_cache_dir)"
  mkdir -p "$cache_dir"
  printf '%s/wiki-language-override.state\n' "$cache_dir"
}

validate_language_code() {
  local value="${1:-}"
  [[ "$value" =~ ^[a-z]{2,12}$ ]]
}

clear_language_override() {
  local state_file
  state_file="$(wiki_override_state_file)"
  rm -f "$state_file"
}

read_override_language() {
  local state_file
  state_file="$(wiki_override_state_file)"
  [[ -f "$state_file" ]] || return 1

  local raw normalized
  raw="$(sed -n '1p' "$state_file")"
  normalized="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

  if validate_language_code "$normalized"; then
    printf '%s\n' "$normalized"
    return 0
  fi

  rm -f "$state_file"
  return 1
}

resolve_active_language() {
  local override_language
  if override_language="$(read_override_language)"; then
    printf '%s\n' "$override_language"
    return 0
  fi

  local configured
  configured="$(printf '%s' "${WIKI_LANGUAGE:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [[ -z "$configured" ]]; then
    configured="en"
  fi

  printf '%s\n' "$configured"
}

WIKI_ACTIVE_LANGUAGE=""

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
  if json_output="$(WIKI_LANGUAGE="$WIKI_ACTIVE_LANGUAGE" "$wiki_cli" search --query "$query" --mode alfred 2>"$err_file")"; then
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
  clear_language_override
  emit_error_item "Enter a search query" "Type keywords after wk to search Wikipedia."
  exit 0
fi

WIKI_ACTIVE_LANGUAGE="$(resolve_active_language)"
workflow_cache_key="wiki-search-${WIKI_ACTIVE_LANGUAGE}"

if sfqp_is_short_query "$query" 2; then
  sfqp_emit_short_query_item_json \
    2 \
    "Keep typing (2+ chars)" \
    "Type at least %s characters before searching Wikipedia."
  exit 0
fi

# Shared driver owns cache/coalesce orchestration only.
# Wikipedia-specific backend fetch and error mapping remain local in this script.
sfsd_run_search_flow \
  "$query" \
  "$workflow_cache_key" \
  "nils-wiki-search-workflow" \
  "WIKI_QUERY_CACHE_TTL_SECONDS" \
  "WIKI_QUERY_COALESCE_SETTLE_SECONDS" \
  "WIKI_QUERY_COALESCE_RERUN_SECONDS" \
  "Searching Wikipedia..." \
  "Waiting for final query before calling Wikipedia API." \
  "wiki_search_fetch_json" \
  "print_error_item"
