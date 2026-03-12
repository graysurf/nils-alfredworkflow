#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GOOGLE_REQUERY_PREFIX="google-requery:"

dispatch_requery_payload() {
  local arg="$1"

  if ! wfar_parse_requery_payload "$arg" "$GOOGLE_REQUERY_PREFIX"; then
    echo "usage: action_open.sh <url|google-requery:search:query>" >&2
    exit 2
  fi

  local selector query keyword requery_text
  selector="${WFAR_REQUERY_SELECTOR:-}"
  query="${WFAR_REQUERY_QUERY:-}"

  if [[ "$selector" != "search" ]]; then
    echo "invalid google requery selector: $selector" >&2
    exit 2
  fi

  keyword="${GOOGLE_REQUERY_KEYWORD:-gg}"
  requery_text="$(wfar_build_keyword_requery_text "$keyword" "res::$query")"

  if ! wfar_trigger_requery "$requery_text" "${GOOGLE_REQUERY_COMMAND:-}" "${GOOGLE_ALFRED_APP_NAME:-Alfred 5}"; then
    exit 1
  fi
}

loader_path=""
for candidate in \
  "$script_dir/lib/workflow_helper_loader.sh" \
  "$script_dir/../../../scripts/lib/workflow_helper_loader.sh"; do
  if [[ -f "$candidate" ]]; then
    loader_path="$candidate"
    break
  fi
done

if [[ -z "$loader_path" ]]; then
  echo "Workflow helper missing: Cannot locate workflow_helper_loader.sh runtime helper." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$loader_path"

if ! wfhl_source_helper "$script_dir" "workflow_action_requery.sh" off; then
  wfhl_print_missing_helper_stderr "workflow_action_requery.sh"
  exit 1
fi

if [[ "${1:-}" == "$GOOGLE_REQUERY_PREFIX"* ]]; then
  dispatch_requery_payload "$1"
  exit 0
fi

helper="$(wfhl_resolve_helper_path "$script_dir" "workflow_action_open_url.sh" off || true)"
if [[ -z "$helper" ]]; then
  wfhl_print_missing_helper_stderr "workflow_action_open_url.sh"
  exit 1
fi

exec "$helper" "$@"
