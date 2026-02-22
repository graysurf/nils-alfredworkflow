#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WIKI_REQUERY_PREFIX="wiki-requery:"

resolve_cache_dir() {
  local candidate
  for candidate in \
    "${ALFRED_WORKFLOW_CACHE:-}" \
    "${ALFRED_WORKFLOW_DATA:-}"; do
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' "${TMPDIR:-/tmp}/nils-wiki-search-workflow"
}

wiki_override_state_file() {
  local cache_dir
  cache_dir="$(resolve_cache_dir)"
  mkdir -p "$cache_dir"
  printf '%s/wiki-language-override.state\n' "$cache_dir"
}

validate_language_code() {
  local value="${1:-}"
  [[ "$value" =~ ^[a-z]{2,12}$ ]]
}

write_override_language() {
  local language="$1"
  local state_file
  state_file="$(wiki_override_state_file)"
  printf '%s\n' "$language" >"$state_file"
}

escape_applescript_string() {
  local input="${1:-}"
  input="${input//\\/\\\\}"
  input="${input//\"/\\\"}"
  input="${input//$'\n'/ }"
  input="${input//$'\r'/ }"
  printf '%s' "$input"
}

trigger_wiki_requery() {
  local query="$1"
  if [[ -n "${WIKI_REQUERY_COMMAND:-}" ]]; then
    "$WIKI_REQUERY_COMMAND" "$query"
    return 0
  fi

  if command -v osascript >/dev/null 2>&1; then
    local app_name="${WIKI_ALFRED_APP_NAME:-Alfred 5}"
    local escaped_query escaped_app_name
    escaped_query="$(escape_applescript_string "$query")"
    escaped_app_name="$(escape_applescript_string "$app_name")"
    osascript -e "tell application \"${escaped_app_name}\" to search \"${escaped_query}\""
    return 0
  fi

  echo "cannot trigger Alfred requery: set WIKI_REQUERY_COMMAND or install osascript support" >&2
  exit 1
}

dispatch_requery_payload() {
  local arg="$1"
  local payload="${arg#"$WIKI_REQUERY_PREFIX"}"
  local language="${payload%%:*}"
  local query="${payload#*:}"

  if [[ -z "$language" || "$payload" == "$language" ]]; then
    echo "usage: action_open.sh wiki-requery:<language>:<query>" >&2
    exit 2
  fi

  if ! validate_language_code "$language"; then
    echo "invalid requery language: $language" >&2
    exit 2
  fi

  write_override_language "$language"
  local keyword="${WIKI_KEYWORD:-wk}"
  local requery_text="$keyword"
  if [[ -n "${query//[[:space:]]/}" ]]; then
    requery_text="$keyword $query"
  fi

  trigger_wiki_requery "$requery_text"
}

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: action_open.sh <url|wiki-requery:language:query>" >&2
  exit 2
fi

if [[ "$1" == "$WIKI_REQUERY_PREFIX"* ]]; then
  dispatch_requery_payload "$1"
  exit 0
fi

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

helper="$(wfhl_resolve_helper_path "$script_dir" "workflow_action_open_url.sh" off || true)"
if [[ -z "$helper" ]]; then
  wfhl_print_missing_helper_stderr "workflow_action_open_url.sh"
  exit 1
fi

exec "$helper" "$@"
