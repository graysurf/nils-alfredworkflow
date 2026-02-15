#!/usr/bin/env bash
set -euo pipefail

BANGUMI_CLEAR_CACHE_ACTION_ARG="__BANGUMI_CLEAR_CACHE__"
BANGUMI_CLEAR_CACHE_DIR_ACTION_ARG="__BANGUMI_CLEAR_CACHE_DIR__"

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

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: action_open.sh <url>" >&2
  exit 2
fi

if [[ "${1:-}" == "$BANGUMI_CLEAR_CACHE_ACTION_ARG" ]]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  exec "$script_dir/action_clear_cache.sh"
fi

if [[ "${1:-}" == "$BANGUMI_CLEAR_CACHE_DIR_ACTION_ARG" ]]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  exec "$script_dir/action_clear_cache_dir.sh"
fi

helper="$(resolve_helper "workflow_action_open_url.sh" || true)"
if [[ -z "$helper" ]]; then
  echo "workflow_action_open_url.sh helper not found" >&2
  exit 1
fi

exec "$helper" "$@"
