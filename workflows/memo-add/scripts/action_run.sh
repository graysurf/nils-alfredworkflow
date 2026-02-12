#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: action_run.sh <action-token>" >&2
  exit 2
fi

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

resolve_memo_workflow_cli() {
  if [[ -n "${MEMO_WORKFLOW_CLI_BIN:-}" && -x "${MEMO_WORKFLOW_CLI_BIN}" ]]; then
    clear_quarantine_if_needed "${MEMO_WORKFLOW_CLI_BIN}"
    printf '%s\n' "${MEMO_WORKFLOW_CLI_BIN}"
    return 0
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local packaged_cli
  packaged_cli="$script_dir/../bin/memo-workflow-cli"
  if [[ -x "$packaged_cli" ]]; then
    clear_quarantine_if_needed "$packaged_cli"
    printf '%s\n' "$packaged_cli"
    return 0
  fi

  local repo_root
  repo_root="$(cd "$script_dir/../../.." && pwd)"

  local release_cli
  release_cli="$repo_root/target/release/memo-workflow-cli"
  if [[ -x "$release_cli" ]]; then
    clear_quarantine_if_needed "$release_cli"
    printf '%s\n' "$release_cli"
    return 0
  fi

  local debug_cli
  debug_cli="$repo_root/target/debug/memo-workflow-cli"
  if [[ -x "$debug_cli" ]]; then
    clear_quarantine_if_needed "$debug_cli"
    printf '%s\n' "$debug_cli"
    return 0
  fi

  echo "memo-workflow-cli binary not found (checked MEMO_WORKFLOW_CLI_BIN/package/release/debug paths)" >&2
  return 1
}

notify() {
  local message="$1"
  local escaped
  escaped="$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')"

  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$escaped\" with title \"Memo Add\"" >/dev/null 2>&1 || true
  fi
}

action_token="$1"
memo_workflow_cli="$(resolve_memo_workflow_cli)"

set +e
output="$("$memo_workflow_cli" action --token "$action_token" 2>&1)"
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  [[ -n "$output" ]] && printf '%s\n' "$output"

  if [[ "$action_token" == "db-init" ]]; then
    notify "Memo DB initialized"
  else
    notify "Memo added"
  fi
  exit 0
fi

notify "Memo action failed"
[[ -n "$output" ]] && printf '%s\n' "$output" >&2
exit "$rc"
