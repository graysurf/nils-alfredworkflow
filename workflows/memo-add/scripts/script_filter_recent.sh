#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
query=""
query_provided=0
if [[ $# -gt 0 ]]; then
  query="${1-}"
  query_provided=1
fi

# Alfred debug/log output may show '(null)' for missing argv.
if [[ "$query" == "(null)" ]]; then
  query=""
  query_provided=0
fi
if [[ "$query_provided" -eq 0 && -z "$query" && -n "${alfred_workflow_query:-}" ]]; then
  query="${alfred_workflow_query}"
elif [[ "$query_provided" -eq 0 && -z "$query" && -n "${ALFRED_WORKFLOW_QUERY:-}" ]]; then
  query="${ALFRED_WORKFLOW_QUERY}"
elif [[ "$query_provided" -eq 0 && -z "$query" && ! -t 0 ]]; then
  query="$(cat)"
fi

query="$(printf '%s' "$query" | xargs)"

# mmr <number> => route to item-id action menu.
if [[ "$query" =~ ^[0-9]+$ ]]; then
  MEMO_QUERY_PREFIX="item" exec "$script_dir/script_filter.sh" "$query"
fi

# Default: always render latest list (newest first) via empty-query mode.
alfred_workflow_query="" ALFRED_WORKFLOW_QUERY="" exec "$script_dir/script_filter.sh" "" </dev/null
