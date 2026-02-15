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

helper="$(resolve_helper "workflow_action_open_url.sh" || true)"
if [[ -z "$helper" ]]; then
  echo "workflow_action_open_url.sh helper not found" >&2
  exit 1
fi

exec "$helper" "$@"
