#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
base_filter="$script_dir/script_filter.sh"

trim() {
  local value="${1-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

query="${1:-}"
trimmed_query="$(trim "$query")"
lower_query="$(printf '%s' "$trimmed_query" | tr '[:upper:]' '[:lower:]')"

forward_query=""
if [[ -z "$trimmed_query" ]]; then
  forward_query="save"
elif [[ "$lower_query" == save* || "$lower_query" == "auth save"* ]]; then
  forward_query="$trimmed_query"
else
  forward_query="save $trimmed_query"
fi

exec "$base_filter" "$forward_query"
