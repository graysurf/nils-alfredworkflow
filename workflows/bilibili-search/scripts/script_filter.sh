#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

helper_loader=""
for candidate in \
  "$script_dir/lib/workflow_helper_loader.sh" \
  "$script_dir/../../../scripts/lib/workflow_helper_loader.sh"; do
  if [[ -f "$candidate" ]]; then
    helper_loader="$candidate"
    break
  fi
done

if [[ -z "$helper_loader" ]] && command -v git >/dev/null 2>&1; then
  git_repo_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$git_repo_root" && -f "$git_repo_root/scripts/lib/workflow_helper_loader.sh" ]]; then
    helper_loader="$git_repo_root/scripts/lib/workflow_helper_loader.sh"
  fi
fi

if [[ -z "$helper_loader" ]]; then
  printf '{"items":[{"title":"Workflow helper missing","subtitle":"Cannot locate workflow_helper_loader.sh runtime helper.","valid":false}]}\n'
  exit 0
fi
# shellcheck disable=SC1090
source "$helper_loader"

load_helper_or_exit() {
  local helper_name="$1"
  if ! wfhl_source_helper "$script_dir" "$helper_name" auto; then
    wfhl_emit_missing_helper_item_json "$helper_name"
    exit 0
  fi
}

load_helper_or_exit "script_filter_error_json.sh"
load_helper_or_exit "workflow_cli_resolver.sh"
load_helper_or_exit "script_filter_query_policy.sh"
load_helper_or_exit "script_filter_async_coalesce.sh"
load_helper_or_exit "script_filter_search_driver.sh"
load_helper_or_exit "script_filter_cli_driver.sh"

normalize_error_message() {
  sfej_normalize_error_message "${1-}"
}

emit_error_item() {
  local title="$1"
  local subtitle="$2"
  sfej_emit_error_item_json "$title" "$subtitle"
}

print_error_item() {
  local raw_message="${1:-bilibili-cli query failed}"
  local message
  message="$(normalize_error_message "$raw_message")"
  [[ -n "$message" ]] || message="bilibili-cli query failed"

  local title="Bilibili Search error"
  local subtitle="$message"
  local lower
  lower="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"

  if [[ "$lower" == *"query must not be empty"* || "$lower" == *"empty query"* ]]; then
    title="Enter a search query"
    subtitle="Type keywords after bl to search Bilibili."
  elif [[ "$lower" == *"invalid bilibili_max_results"* || "$lower" == *"invalid bilibili_timeout_ms"* ]]; then
    title="Invalid Bilibili workflow config"
    subtitle="Check BILIBILI_MAX_RESULTS and BILIBILI_TIMEOUT_MS, then retry."
  elif [[ "$lower" == *"bilibili api request failed"* || "$lower" == *"invalid bilibili api response"* || "$lower" == *"timed out"* || "$lower" == *"timeout"* || "$lower" == *"connection"* || "$lower" == *"dns"* || "$lower" == *"tls"* || "$lower" == *"status 500"* || "$lower" == *"status 502"* || "$lower" == *"status 503"* || "$lower" == *"status 504"* || "$lower" == *"api error (5"* ]]; then
    title="Bilibili API unavailable"
    subtitle="Cannot reach bilibili now. Check network and retry."
  fi

  emit_error_item "$title" "$subtitle"
}

resolve_bilibili_cli() {
  wfcr_resolve_binary \
    "BILIBILI_CLI_BIN" \
    "$script_dir/../bin/bilibili-cli" \
    "$repo_root/target/release/bilibili-cli" \
    "$repo_root/target/debug/bilibili-cli" \
    "bilibili-cli binary not found (checked package/release/debug paths)"
}

bilibili_query_execute() {
  local query="$1"
  local bilibili_cli=""

  if ! bilibili_cli="$(resolve_bilibili_cli)"; then
    return 1
  fi

  "$bilibili_cli" query --input "$query" --mode alfred
}

execute_bilibili_search_flow() {
  local query="$1"

  sfsd_run_search_flow \
    "$query" \
    "bilibili-search" \
    "nils-bilibili-search-workflow" \
    "BILIBILI_QUERY_CACHE_TTL_SECONDS" \
    "BILIBILI_QUERY_COALESCE_SETTLE_SECONDS" \
    "BILIBILI_QUERY_COALESCE_RERUN_SECONDS" \
    "Searching bilibili suggestions..." \
    "Waiting for final query before calling bilibili suggest API." \
    "bilibili_query_execute" \
    "print_error_item"
}

query="$(sfqp_resolve_query_input "${1:-}")"
trimmed_query="$(sfqp_trim "$query")"
query="$trimmed_query"

if [[ -z "$query" ]]; then
  emit_error_item "Enter a search query" "Type keywords after bl to search Bilibili."
  exit 0
fi

if sfqp_is_short_query "$query" 2; then
  sfqp_emit_short_query_item_json \
    2 \
    "Keep typing (2+ chars)" \
    "Type at least %s characters before searching Bilibili."
  exit 0
fi

# Shared CLI driver owns err-file and JSON guard plumbing for the final response.
# Shared search driver still owns cache/coalesce orchestration for this workflow.
sfcd_run_cli_flow \
  "execute_bilibili_search_flow" \
  "print_error_item" \
  "bilibili-cli returned empty response" \
  "bilibili-cli returned malformed Alfred JSON" \
  "$query"
