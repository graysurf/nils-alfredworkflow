#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

resolve_helper() {
  local helper_name="$1"
  local candidate
  local cwd_repo_root

  for candidate in \
    "$script_dir/lib/$helper_name" \
    "$script_dir/../../../scripts/lib/$helper_name"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if command -v git >/dev/null 2>&1; then
    cwd_repo_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$cwd_repo_root" ]]; then
      candidate="$cwd_repo_root/scripts/lib/$helper_name"
      if [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  fi

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

query="${1:-}"
config_zones="${MULTI_TZ_ZONES:-}"

err_file="${TMPDIR:-/tmp}/multi-timezone-script-filter.err.$$"
trap 'rm -f "$err_file"' EXIT

timezone_cli=""
if ! timezone_cli="$(resolve_timezone_cli 2>"$err_file")"; then
  err_msg="$(cat "$err_file")"
  print_error_item "$err_msg"
  exit 0
fi

if json_output="$("$timezone_cli" now --query "$query" --config-zones "$config_zones" --mode alfred 2>"$err_file")"; then
  if [[ -z "$json_output" ]]; then
    print_error_item "timezone-cli returned empty response"
    exit 0
  fi

  if command -v jq >/dev/null 2>&1; then
    if ! jq -e '.items | type == "array"' >/dev/null <<<"$json_output"; then
      print_error_item "timezone-cli returned malformed Alfred JSON"
      exit 0
    fi
  fi

  printf '%s\n' "$json_output"
  exit 0
fi

err_msg="$(cat "$err_file")"
print_error_item "$err_msg"
