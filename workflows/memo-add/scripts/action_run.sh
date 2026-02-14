#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: action_run.sh <action-token>" >&2
  exit 2
fi

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

workflow_cli_resolver_helper="$(resolve_helper "workflow_cli_resolver.sh" || true)"
if [[ -z "$workflow_cli_resolver_helper" ]]; then
  echo "memo-workflow helper missing: workflow_cli_resolver.sh" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$workflow_cli_resolver_helper"

notify() {
  local message="$1"
  local escaped
  escaped="$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')"

  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$escaped\" with title \"Memo Add\"" >/dev/null 2>&1 || true
  fi
}

action_token="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
memo_workflow_cli="$(
  wfcr_resolve_binary \
    "MEMO_WORKFLOW_CLI_BIN" \
    "$script_dir/../bin/memo-workflow-cli" \
    "$repo_root/target/release/memo-workflow-cli" \
    "$repo_root/target/debug/memo-workflow-cli" \
    "memo-workflow-cli binary not found (checked MEMO_WORKFLOW_CLI_BIN/package/release/debug paths)"
)"

set +e
output="$("$memo_workflow_cli" action --token "$action_token" 2>&1)"
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  if [[ "$action_token" == copy::* || "$action_token" == copy-json::* ]]; then
    if ! command -v pbcopy >/dev/null 2>&1; then
      notify "Memo action failed"
      echo "pbcopy not found for copy action" >&2
      exit 1
    fi

    printf '%s' "$output" | pbcopy
    if [[ "$action_token" == copy-json::* ]]; then
      notify "Memo JSON copied"
    else
      notify "Memo copied"
    fi
    exit 0
  fi

  [[ -n "$output" ]] && printf '%s\n' "$output"

  if [[ "$action_token" == "db-init" ]]; then
    notify "Memo DB initialized"
  elif [[ "$action_token" == add::* ]]; then
    notify "Memo added"
  elif [[ "$action_token" == update::* ]]; then
    notify "Memo updated"
  elif [[ "$action_token" == delete::* ]]; then
    notify "Memo deleted"
  else
    notify "Memo added"
  fi
  exit 0
fi

notify "Memo action failed"
[[ -n "$output" ]] && printf '%s\n' "$output" >&2
exit "$rc"
