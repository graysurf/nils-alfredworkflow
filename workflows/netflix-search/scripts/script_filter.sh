#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

if ! wfhl_source_helper "$script_dir" "script_filter_error_json.sh"; then
  wfhl_emit_missing_helper_item_json "script_filter_error_json.sh"
  exit 0
fi

if ! wfhl_source_helper "$script_dir" "workflow_cli_resolver.sh"; then
  sfej_emit_error_item_json "Workflow helper missing" "Cannot locate workflow_cli_resolver.sh runtime helper."
  exit 0
fi

normalize_error_message() {
  sfej_normalize_error_message "${1-}"
}

emit_error_item() {
  local title="$1"
  local subtitle="$2"
  sfej_emit_error_item_json "$title" "$subtitle"
}

print_error_item() {
  local raw_message="${1:-brave-cli search failed}"
  local message
  message="$(normalize_error_message "$raw_message")"
  [[ -n "$message" ]] || message="brave-cli search failed"

  local title="Netflix Search error"
  local subtitle="$message"
  local lower
  lower="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"

  if [[ "$lower" == *"query must not be empty"* || "$lower" == *"query cannot be empty"* || "$lower" == *"empty query"* ]]; then
    title="Enter a search query"
    subtitle="Type keywords after nf or netflix to search Netflix titles."
  elif [[ "$lower" == *"missing brave_api_key"* || "$lower" == *"brave_api_key is missing"* || "$lower" == *"brave api key is missing"* || "$lower" == *"brave_api_key is required"* ]]; then
    title="Brave API key is missing"
    subtitle="Set BRAVE_API_KEY in workflow configuration and retry."
  elif [[ "$lower" == *"quota"* || "$lower" == *"rate limit"* || "$lower" == *"rate-limit"* || "$lower" == *"too many requests"* || "$lower" == *"http 429"* || "$lower" == *"status 429"* ]]; then
    title="Brave API rate limited"
    subtitle="Too many requests in a short time. Retry shortly or lower BRAVE_MAX_RESULTS."
  elif [[ "$lower" == *"unavailable"* || "$lower" == *"transport"* || "$lower" == *"timed out"* || "$lower" == *"timeout"* || "$lower" == *"connection"* || "$lower" == *"dns"* || "$lower" == *"tls"* || "$lower" == *"5xx"* || "$lower" == *"status 500"* || "$lower" == *"status 502"* || "$lower" == *"status 503"* || "$lower" == *"status 504"* ]]; then
    title="Brave API unavailable"
    subtitle="Cannot reach Brave API now. Check network and retry."
  elif [[ "$lower" == *"invalid brave_max_results"* || "$lower" == *"invalid brave_safesearch"* || "$lower" == *"invalid brave_country"* ]]; then
    title="Invalid Brave workflow config"
    subtitle="$message"
  fi

  emit_error_item "$title" "$subtitle"
}

resolve_brave_cli() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local packaged_cli
  packaged_cli="$script_dir/../bin/brave-cli"

  local repo_root
  repo_root="$(cd "$script_dir/../../.." && pwd)"

  local release_cli
  release_cli="$repo_root/target/release/brave-cli"

  local debug_cli
  debug_cli="$repo_root/target/debug/brave-cli"

  wfcr_resolve_binary \
    "BRAVE_CLI_BIN" \
    "$packaged_cli" \
    "$release_cli" \
    "$debug_cli" \
    "brave-cli binary not found (checked package/release/debug paths)"
}

normalize_country_segment() {
  local value="${1:-}"
  value="$(printf '%s' "$value" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"

  if [[ "$value" =~ ^[a-z]{2}$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  printf '\n'
}

resolve_brave_country_segment() {
  normalize_country_segment "${BRAVE_COUNTRY:-}"
}

resolve_netflix_catalog_region_segment() {
  local value
  value="$(normalize_country_segment "${NETFLIX_CATALOG_REGION:-}")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  resolve_brave_country_segment
}

load_country_map() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local country_map_file="$script_dir/country_map.sh"
  if [[ -f "$country_map_file" ]]; then
    # shellcheck disable=SC1090
    source "$country_map_file"
  fi

  if ! declare -F nfs_country_uses_regional_title_path >/dev/null 2>&1; then
    nfs_country_uses_regional_title_path() {
      local country="${1:-}"
      case "$country" in
      tw | jp | kr | hk | sg)
        return 0
        ;;
      *)
        return 1
        ;;
      esac
    }
  fi
}

load_country_map

resolve_netflix_site_prefix() {
  local country_segment="$1"

  case "$country_segment" in
  # US and empty country always use global title scope.
  us | "")
    printf 'site:netflix.com/title\n'
    ;;
  *)
    if nfs_country_uses_regional_title_path "$country_segment"; then
      printf 'site:netflix.com/%s/title\n' "$country_segment"
    else
      printf 'site:netflix.com/title\n'
    fi
    ;;
  esac
}

build_netflix_site_query() {
  local query="$1"
  local country_segment
  country_segment="$(resolve_netflix_catalog_region_segment)"
  local prefix
  prefix="$(resolve_netflix_site_prefix "$country_segment")"

  printf '%s %s\n' "$prefix" "$query"
}

is_country_param_validation_error() {
  local message="${1:-}"
  local lower
  lower="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"
  [[ "$lower" == *"422"* && "$lower" == *"validate request parameter"* ]]
}

netflix_search_fetch_json() {
  local query="$1"
  local err_file="${TMPDIR:-/tmp}/netflix-search-script-filter.err.$$.$RANDOM"

  local brave_cli
  if ! brave_cli="$(resolve_brave_cli 2>"$err_file")"; then
    cat "$err_file" >&2
    rm -f "$err_file"
    return 1
  fi

  local search_query
  search_query="$(build_netflix_site_query "$query")"

  local json_output
  if json_output="$("$brave_cli" search --query "$search_query" --mode alfred 2>"$err_file")"; then
    rm -f "$err_file"
    if [[ -z "$json_output" ]]; then
      echo "brave-cli returned empty response" >&2
      return 1
    fi

    printf '%s\n' "$json_output"
    return 0
  fi

  local raw_err
  raw_err="$(cat "$err_file" 2>/dev/null || true)"
  local brave_country_segment
  brave_country_segment="$(resolve_brave_country_segment)"
  if [[ -n "$brave_country_segment" ]] && is_country_param_validation_error "$raw_err"; then
    if json_output="$(env -u BRAVE_COUNTRY "$brave_cli" search --query "$search_query" --mode alfred 2>"$err_file")"; then
      rm -f "$err_file"
      if [[ -z "$json_output" ]]; then
        echo "brave-cli returned empty response" >&2
        return 1
      fi

      printf '%s\n' "$json_output"
      return 0
    fi
    raw_err="$(cat "$err_file" 2>/dev/null || true)"
  fi

  if [[ -n "$raw_err" ]]; then
    printf '%s\n' "$raw_err" >&2
  fi
  rm -f "$err_file"
  return 1
}

if ! wfhl_source_helper "$script_dir" "script_filter_query_policy.sh"; then
  emit_error_item "Workflow helper missing" "Cannot locate script_filter_query_policy.sh runtime helper."
  exit 0
fi

if ! wfhl_source_helper "$script_dir" "script_filter_async_coalesce.sh"; then
  emit_error_item "Workflow helper missing" "Cannot locate script_filter_async_coalesce.sh runtime helper."
  exit 0
fi

if ! wfhl_source_helper "$script_dir" "script_filter_search_driver.sh"; then
  emit_error_item "Workflow helper missing" "Cannot locate script_filter_search_driver.sh runtime helper."
  exit 0
fi

query="$(sfqp_resolve_query_input "${1:-}")"
trimmed_query="$(sfqp_trim "$query")"
query="$trimmed_query"

if [[ -z "$query" ]]; then
  emit_error_item "Enter a search query" "Type keywords after nf or netflix to search Netflix titles."
  exit 0
fi

if sfqp_is_short_query "$query" 2; then
  sfqp_emit_short_query_item_json \
    2 \
    "Keep typing (2+ chars)" \
    "Type at least %s characters before searching Netflix titles."
  exit 0
fi

# Shared driver owns cache/coalesce orchestration only.
# Netflix-specific query shaping and error mapping remain local in this script.
sfsd_run_search_flow \
  "$query" \
  "netflix-search" \
  "nils-netflix-search-workflow" \
  "BRAVE_QUERY_CACHE_TTL_SECONDS" \
  "BRAVE_QUERY_COALESCE_SETTLE_SECONDS" \
  "BRAVE_QUERY_COALESCE_RERUN_SECONDS" \
  "Searching Netflix titles..." \
  "Waiting for final query before searching Netflix title pages." \
  "netflix_search_fetch_json" \
  "print_error_item"
