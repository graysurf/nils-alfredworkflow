#!/usr/bin/env bash
set -euo pipefail

resolve_helper() {
  local helper_name="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local git_repo_root=""
  git_repo_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"

  local candidates=(
    "$script_dir/lib/$helper_name"
    "$script_dir/../../../scripts/lib/$helper_name"
  )
  if [[ -n "$git_repo_root" ]]; then
    candidates+=("$git_repo_root/scripts/lib/$helper_name")
  fi

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

async_coalesce_helper="$(resolve_helper "script_filter_async_coalesce.sh" || true)"
if [[ -z "$async_coalesce_helper" ]]; then
  echo "script_filter_async_coalesce.sh helper not found" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$async_coalesce_helper"

workflow_key="$(sfac_sanitize_component "bangumi-search")"
cache_dir="$(sfac_resolve_workflow_cache_dir "nils-bangumi-search-workflow")"
state_dir="$cache_dir/script-filter-async-coalesce/$workflow_key"

if [[ -d "$state_dir" ]]; then
  rm -rf "$state_dir"
fi
