#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
query="${1:-}"

# Alfred debug/log output may show '(null)' for missing argv.
if [[ "$query" == "(null)" ]]; then
  query=""
fi
if [[ -z "$query" && -n "${alfred_workflow_query:-}" ]]; then
  query="${alfred_workflow_query}"
elif [[ -z "$query" && -n "${ALFRED_WORKFLOW_QUERY:-}" ]]; then
  query="${ALFRED_WORKFLOW_QUERY}"
elif [[ -z "$query" && ! -t 0 ]]; then
  query="$(cat)"
fi

query="$(printf '%s' "$query" | xargs)"

# mmr <number> => route to item-id action menu.
if [[ "$query" =~ ^[0-9]+$ ]]; then
  MEMO_QUERY_PREFIX="item" exec "$script_dir/script_filter.sh" "$query"
fi

# Default: always render latest list (newest first) via empty-query mode.
alfred_workflow_query="" ALFRED_WORKFLOW_QUERY="" exec "$script_dir/script_filter.sh" "" </dev/null
