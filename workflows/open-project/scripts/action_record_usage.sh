#!/bin/sh
set -eu

resolve_helper() {
  helper_name="$1"

  script_dir=$(
    CDPATH=
    cd -- "$(dirname -- "$0")" && pwd
  )

  for candidate in \
    "$script_dir/lib/$helper_name" \
    "$script_dir/../../../scripts/lib/$helper_name"; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

workflow_cli_resolver_helper="$(resolve_helper "workflow_cli_resolver.sh" || true)"
if [ -z "$workflow_cli_resolver_helper" ]; then
  echo "error: workflow helper missing: workflow_cli_resolver.sh" >&2
  exit 1
fi
# shellcheck disable=SC1090
. "$workflow_cli_resolver_helper"

resolve_workflow_cli() {
  script_dir=$(
    CDPATH=
    cd -- "$(dirname -- "$0")" && pwd
  )

  repo_root=$(
    CDPATH=
    cd -- "$script_dir/../../.." && pwd
  )

  wfcr_resolve_binary \
    "WORKFLOW_CLI_BIN" \
    "$script_dir/../bin/workflow-cli" \
    "$repo_root/target/release/workflow-cli" \
    "$repo_root/target/debug/workflow-cli" \
    "error: workflow-cli binary not found (checked package/release/debug paths)"
}

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
  echo "usage: action_record_usage.sh <project-path>" >&2
  exit 2
fi

project_path="$(printf '%s' "$1")"
if [ -z "$project_path" ]; then
  echo "usage: action_record_usage.sh <project-path>" >&2
  exit 2
fi

workflow_cli="$(resolve_workflow_cli)"
recorded_path="$("$workflow_cli" record-usage --path "$project_path")"
printf '%s' "$recorded_path"
