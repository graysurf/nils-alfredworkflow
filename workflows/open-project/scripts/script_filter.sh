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
