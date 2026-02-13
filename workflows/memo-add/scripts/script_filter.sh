#!/usr/bin/env bash
set -euo pipefail

json_escape() {
  local value="${1-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
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

map_error_title() {
  local message
  message="$(printf '%s' "${1-}" | tr '[:upper:]' '[:lower:]')"

  if [[ "$message" == *"invalid memo_"* ]]; then
    printf '%s\n' "Invalid Memo workflow config"
    return
  fi

  if [[ "$message" == *"binary not found"* ]]; then
    printf '%s\n' "memo-workflow-cli binary not found"
    return
  fi

  printf '%s\n' "Memo workflow error"
}

query=""
query_provided=0
if [[ $# -gt 0 ]]; then
  query="${1-}"
  query_provided=1
fi
# Alfred debug/log output may show '(null)' for missing argv.
if [[ "$query" == "(null)" ]]; then
  query=""
  query_provided=0
fi
if [[ "$query_provided" -eq 0 && -z "$query" && -n "${alfred_workflow_query:-}" ]]; then
  query="${alfred_workflow_query}"
elif [[ "$query_provided" -eq 0 && -z "$query" && -n "${ALFRED_WORKFLOW_QUERY:-}" ]]; then
  query="${ALFRED_WORKFLOW_QUERY}"
elif [[ "$query_provided" -eq 0 && -z "$query" && ! -t 0 ]]; then
  query="$(cat)"
fi

query_prefix="${MEMO_QUERY_PREFIX:-}"
if [[ -n "$query_prefix" ]]; then
  if [[ -n "$query" ]]; then
    query="$query_prefix $query"
  else
    query="$query_prefix"
  fi
fi

err_file="${TMPDIR:-/tmp}/memo-add-script-filter.err.$$"
trap 'rm -f "$err_file"' EXIT

memo_workflow_cli=""
if ! memo_workflow_cli="$(resolve_memo_workflow_cli 2>"$err_file")"; then
  emit_error_item "memo-workflow-cli binary not found" "Re-import workflow package or set MEMO_WORKFLOW_CLI_BIN."
  exit 0
fi

if json_output="$("$memo_workflow_cli" script-filter --query "$query" 2>"$err_file")"; then
  if [[ -z "$json_output" ]]; then
    emit_error_item "Memo workflow error" "memo-workflow-cli returned empty response"
    exit 0
  fi

  if command -v jq >/dev/null 2>&1; then
    if ! jq -e '.items | type == "array"' >/dev/null <<<"$json_output"; then
      emit_error_item "Memo workflow error" "memo-workflow-cli returned malformed Alfred JSON"
      exit 0
    fi
  fi

  printf '%s\n' "$json_output"
  exit 0
fi

err_msg="$(cat "$err_file")"
[[ -n "$err_msg" ]] || err_msg="memo-workflow-cli script-filter failed"
emit_error_item "$(map_error_title "$err_msg")" "$err_msg"
