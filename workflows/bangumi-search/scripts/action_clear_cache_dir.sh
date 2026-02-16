#!/usr/bin/env bash
set -euo pipefail

resolve_helper() {
  local helper_name="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local candidate
  for candidate in \
    "$script_dir/lib/$helper_name" \
    "$script_dir/../../../scripts/lib/$helper_name"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

workflow_cli_resolver_helper="$(resolve_helper "workflow_cli_resolver.sh" || true)"
if [[ -z "$workflow_cli_resolver_helper" ]]; then
  echo "error: workflow helper missing: workflow_cli_resolver.sh" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$workflow_cli_resolver_helper"

cache_dir_raw="${BANGUMI_CACHE_DIR:-}"
cache_dir="$(printf '%s' "$cache_dir_raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
cache_dir="$(wfcr_expand_home_path "$cache_dir")"

if [[ -z "$cache_dir" ]]; then
  exit 0
fi

case "$cache_dir" in
"/" | "." | "..")
  echo "refusing to clear unsafe BANGUMI_CACHE_DIR value: $cache_dir" >&2
  exit 1
  ;;
esac

if [[ -d "$cache_dir" ]]; then
  find "$cache_dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
fi
