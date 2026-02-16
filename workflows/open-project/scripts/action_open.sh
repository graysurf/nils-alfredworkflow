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

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
  echo "usage: action_open.sh <project-path>" >&2
  exit 2
fi

project_path="$(printf '%s' "$1")"
if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
  echo "error: project path is not a directory: $project_path" >&2
  exit 2
fi

workflow_cli_resolver_helper="$(resolve_helper "workflow_cli_resolver.sh" || true)"
if [ -z "$workflow_cli_resolver_helper" ]; then
  echo "error: workflow helper missing: workflow_cli_resolver.sh" >&2
  exit 1
fi
# shellcheck disable=SC1090
. "$workflow_cli_resolver_helper"

vscode_bin_raw="${VSCODE_PATH:-/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code}"
vscode_bin="$(wfcr_expand_home_path "$vscode_bin_raw")"

if [ -x "$vscode_bin" ]; then
  exec "$vscode_bin" "$project_path"
fi

resolved_bin="$(command -v "$vscode_bin" 2>/dev/null || true)"
if [ -n "$resolved_bin" ] && [ -x "$resolved_bin" ]; then
  exec "$resolved_bin" "$project_path"
fi

echo "error: unable to execute VSCODE_PATH: $vscode_bin" >&2
exit 1
