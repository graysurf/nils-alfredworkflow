#!/bin/sh
set -eu

clear_quarantine_if_needed() {
  cli_path="$1"

  if [ "$(uname -s 2>/dev/null || printf '')" != "Darwin" ]; then
    return 0
  fi

  if ! command -v xattr >/dev/null 2>&1; then
    return 0
  fi

  # Release artifacts downloaded from GitHub may carry quarantine.
  if xattr -p com.apple.quarantine "$cli_path" >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "$cli_path" >/dev/null 2>&1 || true
  fi
}

resolve_workflow_cli() {
  if [ -n "${WORKFLOW_CLI_BIN:-}" ] && [ -x "${WORKFLOW_CLI_BIN}" ]; then
    clear_quarantine_if_needed "${WORKFLOW_CLI_BIN}"
    printf '%s\n' "${WORKFLOW_CLI_BIN}"
    return 0
  fi

  script_dir=$(
    CDPATH=
    cd -- "$(dirname -- "$0")" && pwd
  )

  packaged_cli="$script_dir/../bin/workflow-cli"
  if [ -x "$packaged_cli" ]; then
    clear_quarantine_if_needed "$packaged_cli"
    printf '%s\n' "$packaged_cli"
    return 0
  fi

  repo_root=$(
    CDPATH=
    cd -- "$script_dir/../../.." && pwd
  )

  release_cli="$repo_root/target/release/workflow-cli"
  if [ -x "$release_cli" ]; then
    clear_quarantine_if_needed "$release_cli"
    printf '%s\n' "$release_cli"
    return 0
  fi

  debug_cli="$repo_root/target/debug/workflow-cli"
  if [ -x "$debug_cli" ]; then
    clear_quarantine_if_needed "$debug_cli"
    printf '%s\n' "$debug_cli"
    return 0
  fi

  echo "error: workflow-cli binary not found (checked package/release/debug paths)" >&2
  return 1
}

query="${1-}"
mode="${OPEN_PROJECT_MODE:-open}"
workflow_cli="$(resolve_workflow_cli)"
err_file="${TMPDIR:-/tmp}/open-project-script-filter.err.$$"

if json="$("$workflow_cli" script-filter --query "$query" --mode "$mode" 2>"$err_file")"; then
  printf '%s\n' "$json"
  rm -f "$err_file"
  exit 0
fi

err_msg=""
if [ -f "$err_file" ]; then
  err_msg="$(tr '\n' ' ' <"$err_file" | sed 's/[[:space:]]\+/ /g; s/"/\\"/g')"
  rm -f "$err_file"
fi

if [ -z "$err_msg" ]; then
  err_msg="workflow-cli script-filter failed"
fi

printf '{"items":[{"title":"Open Project error","subtitle":"%s","valid":false}]}' "$err_msg"
printf '\n'
