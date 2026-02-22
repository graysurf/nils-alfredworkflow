#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
helper_loader=""
for candidate in \
  "$script_dir/lib/workflow_helper_loader.sh" \
  "$script_dir/../../../scripts/lib/workflow_helper_loader.sh"; do
  if [[ -f "$candidate" ]]; then
    helper_loader="$candidate"
    break
  fi
done

if [[ -z "$helper_loader" ]]; then
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
  local raw_message="${1:-workflow-cli script-filter failed}"
  local message
  message="$(sfej_normalize_error_message "$raw_message")"
  [[ -n "$message" ]] || message="workflow-cli script-filter failed"

  local title="Workflow runtime error"
  local subtitle="$message"
  local lower
  lower="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"

  if [[ "$lower" == *"query must not be empty"* || "$lower" == *"query cannot be empty"* || "$lower" == *"empty query"* ]]; then
    title="Enter a query"
    subtitle="Type keywords after the workflow keyword."
  fi

  sfej_emit_error_item_json "$title" "$subtitle"
}

resolve_workflow_cli() {
  local packaged_cli
  packaged_cli="$script_dir/../bin/workflow-cli"

  local repo_root
  repo_root="$(cd "$script_dir/../../.." && pwd)"

  local release_cli
  release_cli="$repo_root/target/release/workflow-cli"

  local debug_cli
  debug_cli="$repo_root/target/debug/workflow-cli"

  wfcr_resolve_binary \
    "WORKFLOW_CLI_BIN" \
    "$packaged_cli" \
    "$release_cli" \
    "$debug_cli" \
    "workflow-cli binary not found (checked package/release/debug paths)"
}

execute_workflow_script_filter() {
  local query="${1:-}"
  local workflow_cli
  workflow_cli="$(resolve_workflow_cli)"
  "$workflow_cli" script-filter --query "$query"
}

query="${1:-${ALFRED_QUERY:-}}"
if [[ -z "${query//[[:space:]]/}" && ! -t 0 ]]; then
  read -r query || true
fi

sfcd_run_cli_flow \
  "execute_workflow_script_filter" \
  "print_error_item" \
  "workflow-cli returned empty response" \
  "workflow-cli returned malformed Alfred JSON" \
  "$query"
