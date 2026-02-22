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
  local raw_message="${1:-epoch-cli convert failed}"
  local message
  message="$(sfej_normalize_error_message "$raw_message")"
  [[ -n "$message" ]] || message="epoch-cli convert failed"

  local title="Epoch Converter error"
  local subtitle="$message"
  local lower
  lower="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"

  if [[ "$lower" == *"query must not be empty"* || "$lower" == *"query cannot be empty"* || "$lower" == *"empty query"* ]]; then
    title="Enter an epoch or datetime"
    subtitle="Type a value after ts, for example 1700000000 or 2025-01-02 03:04:05."
  elif [[ "$lower" == *"binary not found"* ]]; then
    title="epoch-cli binary not found"
    subtitle="Package workflow or set EPOCH_CLI_BIN to an executable epoch-cli path."
  elif [[ "$lower" == *"invalid input"* || "$lower" == *"failed to parse"* || "$lower" == *"parse error"* || "$lower" == *"unsupported input"* || "$lower" == *"unsupported query"* || "$lower" == *"out of range"* ]]; then
    title="Invalid input"
    subtitle="Use epoch (s/ms/us/ns) or datetime (YYYY-MM-DD HH:MM[:SS])."
  elif [[ "$lower" == *"timeout"* || "$lower" == *"timed out"* || "$lower" == *"io error"* || "$lower" == *"internal error"* || "$lower" == *"panic"* ]]; then
    title="Epoch Converter runtime failure"
    subtitle="epoch-cli failed during conversion. Retry or inspect stderr details."
  fi

  sfej_emit_error_item_json "$title" "$subtitle"
}

resolve_epoch_cli() {
  wfcr_resolve_binary \
    "EPOCH_CLI_BIN" \
    "$script_dir/../bin/epoch-cli" \
    "$repo_root/target/release/epoch-cli" \
    "$repo_root/target/debug/epoch-cli" \
    "epoch-cli binary not found (checked EPOCH_CLI_BIN/package/release/debug paths)"
}

execute_epoch_convert() {
  local query="$1"
  local epoch_cli=""

  if ! epoch_cli="$(resolve_epoch_cli)"; then
    return 1
  fi

  "$epoch_cli" convert --query "$query" --mode alfred
}

query="${1:-}"

sfcd_run_cli_flow \
  "execute_epoch_convert" \
  "print_error_item" \
  "epoch-cli returned empty response" \
  "epoch-cli returned malformed Alfred JSON" \
  "$query"
