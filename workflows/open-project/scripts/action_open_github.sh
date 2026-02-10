#!/bin/sh
set -eu

resolve_workflow_cli() {
  if [ -n "${WORKFLOW_CLI_BIN:-}" ] && [ -x "${WORKFLOW_CLI_BIN}" ]; then
    printf '%s\n' "${WORKFLOW_CLI_BIN}"
    return 0
  fi

  script_dir=$(
    CDPATH=
    cd -- "$(dirname -- "$0")" && pwd
  )

  packaged_cli="$script_dir/../bin/workflow-cli"
  if [ -x "$packaged_cli" ]; then
    printf '%s\n' "$packaged_cli"
    return 0
  fi

  repo_root=$(
    CDPATH=
    cd -- "$script_dir/../../.." && pwd
  )

  release_cli="$repo_root/target/release/workflow-cli"
  if [ -x "$release_cli" ]; then
    printf '%s\n' "$release_cli"
    return 0
  fi

  debug_cli="$repo_root/target/debug/workflow-cli"
  if [ -x "$debug_cli" ]; then
    printf '%s\n' "$debug_cli"
    return 0
  fi

  echo "error: workflow-cli binary not found (checked package/release/debug paths)" >&2
  return 1
}

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
  echo "usage: action_open_github.sh <project-path>" >&2
  exit 2
fi

project_path="$(printf '%s' "$1")"
if [ -z "$project_path" ]; then
  echo "usage: action_open_github.sh <project-path>" >&2
  exit 2
fi

workflow_cli="$(resolve_workflow_cli)"
url="$("$workflow_cli" github-url --path "$project_path")"
exec open "$url"
