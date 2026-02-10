#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
  echo "usage: action_open.sh <project-path>" >&2
  exit 2
fi

project_path="$(printf '%s' "$1")"
if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
  echo "error: project path is not a directory: $project_path" >&2
  exit 2
fi

vscode_bin="${VSCODE_PATH:-/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code}"

if [ -x "$vscode_bin" ]; then
  exec "$vscode_bin" "$project_path"
fi

resolved_bin="$(command -v "$vscode_bin" 2>/dev/null || true)"
if [ -n "$resolved_bin" ] && [ -x "$resolved_bin" ]; then
  exec "$resolved_bin" "$project_path"
fi

echo "error: unable to execute VSCODE_PATH: $vscode_bin" >&2
exit 1
