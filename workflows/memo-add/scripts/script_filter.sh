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

error_json_helper="$(resolve_helper "script_filter_error_json.sh" || true)"
if [[ -n "$error_json_helper" ]]; then
  # shellcheck disable=SC1090
  source "$error_json_helper"
fi

if ! declare -F sfej_emit_error_item_json >/dev/null 2>&1; then
  sfej_fallback_json_escape() {
    local value="${1-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"
    printf '%s' "$value"
  }

  sfej_emit_error_item_json() {
    local title="${1-Error}"
    local subtitle="${2-}"
    printf '{"items":[{"title":"%s","subtitle":"%s","valid":false}]}' \
      "$(sfej_fallback_json_escape "$title")" \
      "$(sfej_fallback_json_escape "$subtitle")"
    printf '\n'
  }
fi

workflow_cli_resolver_helper="$(resolve_helper "workflow_cli_resolver.sh" || true)"
if [[ -z "$workflow_cli_resolver_helper" ]]; then
  sfej_emit_error_item_json "Workflow helper missing" "Cannot locate workflow_cli_resolver.sh runtime helper."
  exit 0
fi
# shellcheck disable=SC1090
source "$workflow_cli_resolver_helper"

query_policy_helper="$(resolve_helper "script_filter_query_policy.sh" || true)"
if [[ -z "$query_policy_helper" ]]; then
  sfej_emit_error_item_json "Workflow helper missing" "Cannot locate script_filter_query_policy.sh runtime helper."
  exit 0
fi
# shellcheck disable=SC1090
source "$query_policy_helper"

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

query="$(sfqp_resolve_query_input_memo "$@")"

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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

memo_workflow_cli=""
if ! memo_workflow_cli="$(
  wfcr_resolve_binary \
    "MEMO_WORKFLOW_CLI_BIN" \
    "$script_dir/../bin/memo-workflow-cli" \
    "$repo_root/target/release/memo-workflow-cli" \
    "$repo_root/target/debug/memo-workflow-cli" \
    "memo-workflow-cli binary not found (checked MEMO_WORKFLOW_CLI_BIN/package/release/debug paths)" \
    2>"$err_file"
)"; then
  sfej_emit_error_item_json "memo-workflow-cli binary not found" "Re-import workflow package or set MEMO_WORKFLOW_CLI_BIN."
  exit 0
fi

if json_output="$("$memo_workflow_cli" script-filter --query "$query" 2>"$err_file")"; then
  if [[ -z "$json_output" ]]; then
    sfej_emit_error_item_json "Memo workflow error" "memo-workflow-cli returned empty response"
    exit 0
  fi

  if command -v jq >/dev/null 2>&1; then
    if ! jq -e '.items | type == "array"' >/dev/null <<<"$json_output"; then
      sfej_emit_error_item_json "Memo workflow error" "memo-workflow-cli returned malformed Alfred JSON"
      exit 0
    fi
  fi

  printf '%s\n' "$json_output"
  exit 0
fi

err_msg="$(cat "$err_file")"
[[ -n "$err_msg" ]] || err_msg="memo-workflow-cli script-filter failed"
sfej_emit_error_item_json "$(map_error_title "$err_msg")" "$err_msg"
