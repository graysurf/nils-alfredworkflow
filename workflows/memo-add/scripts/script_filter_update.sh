#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resolve_helper() {
  local helper_name="$1"
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

query_policy_helper="$(resolve_helper "script_filter_query_policy.sh" || true)"
if [[ -z "$query_policy_helper" ]]; then
  echo "memo-workflow helper missing: script_filter_query_policy.sh" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$query_policy_helper"

query="$(sfqp_resolve_query_input_memo_trimmed "$@")"

# Default behavior follows mmr for empty query (latest list only).
if [[ -z "$query" ]]; then
  exec "$script_dir/script_filter_recent.sh" "$query"
fi

MEMO_QUERY_PREFIX="update" exec "$script_dir/script_filter.sh" "$query"
