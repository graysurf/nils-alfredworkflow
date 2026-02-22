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
load_helper_or_exit "script_filter_cli_driver.sh"

print_error_item() {
  local raw_message="${1:-timezone-cli now failed}"
  local message
  message="$(sfej_normalize_error_message "$raw_message")"
  [[ -n "$message" ]] || message="timezone-cli now failed"

  local title="Multi Timezone error"
  local subtitle="$message"
  local lower
  lower="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"

  if [[ "$lower" == *"binary not found"* ]]; then
    title="timezone-cli binary not found"
    subtitle="Package workflow or set TIMEZONE_CLI_BIN to an executable timezone-cli path."
  elif [[ "$lower" == *"invalid timezone"* || "$lower" == *"unsupported timezone"* || "$lower" == *"iana"* ]]; then
    title="Invalid timezone"
    subtitle="Use IANA timezone IDs, for example Asia/Taipei."
  elif [[ "$lower" == *"timeout"* || "$lower" == *"timed out"* || "$lower" == *"io error"* || "$lower" == *"internal error"* || "$lower" == *"panic"* ]]; then
    title="Timezone runtime failure"
    subtitle="timezone-cli failed during conversion. Retry or inspect stderr details."
  fi

  sfej_emit_error_item_json "$title" "$subtitle"
}

resolve_timezone_cli() {
  wfcr_resolve_binary \
    "TIMEZONE_CLI_BIN" \
    "$script_dir/../bin/timezone-cli" \
    "$repo_root/target/release/timezone-cli" \
    "$repo_root/target/debug/timezone-cli" \
    "timezone-cli binary not found (checked TIMEZONE_CLI_BIN/package/release/debug paths)"
}

execute_timezone_now() {
  local query="$1"
  local config_zones="$2"
  local timezone_cli=""

  if ! timezone_cli="$(resolve_timezone_cli)"; then
    return 1
  fi

  "$timezone_cli" now --query "$query" --config-zones "$config_zones" --mode alfred
}

query="${1:-}"
config_zones="${MULTI_TZ_ZONES:-}"

sfcd_run_cli_flow \
  "execute_timezone_now" \
  "print_error_item" \
  "timezone-cli returned empty response" \
  "timezone-cli returned malformed Alfred JSON" \
  "$query" \
  "$config_zones"
