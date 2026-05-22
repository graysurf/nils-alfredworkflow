#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

helper_loader=""
for candidate in \
  "$script_dir/lib/workflow_helper_loader.sh" \
  "$script_dir/../../../scripts/lib/workflow_helper_loader.sh"; do
  if [[ -f "$candidate" ]]; then
    helper_loader="$candidate"
    break
  fi
done

if [[ -z "$helper_loader" ]]; then
  echo "Workflow helper missing: Cannot locate workflow_helper_loader.sh runtime helper." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$helper_loader"

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: action_open.sh <action-token-json>" >&2
  exit 2
fi

token="$1"
action="open"
url="$token"
title=""
repo=""
number=""
markdown=""

sanitize_one_line() {
  local value="${1-}"
  value="$(printf '%s' "$value" | tr '\r\n' '  ' | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
  printf '%s' "$value"
}

parse_json_token() {
  command -v jq >/dev/null 2>&1 || return 1
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$token" || return 1

  action="$(jq -r '.action // "open"' <<<"$token")"
  url="$(jq -r '.url // empty' <<<"$token")"
  title="$(jq -r '.title // empty' <<<"$token")"
  repo="$(jq -r '.repo // empty' <<<"$token")"
  number="$(jq -r '.number // empty' <<<"$token")"
  markdown="$(jq -r '.markdown // empty' <<<"$token")"
}

parse_json_token || true

copy_to_clipboard() {
  local value="$1"
  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$value" | pbcopy
    return 0
  fi
  if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$value" | wl-copy
    return 0
  fi
  if command -v xclip >/dev/null 2>&1; then
    printf '%s' "$value" | xclip -selection clipboard
    return 0
  fi

  echo "error: no clipboard command found (pbcopy, wl-copy, or xclip)" >&2
  return 1
}

open_url() {
  local value="$1"
  if [[ -z "$value" ]]; then
    echo "error: action token has no URL" >&2
    return 2
  fi

  if command -v open >/dev/null 2>&1; then
    open "$value"
    return 0
  fi
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$value"
    return 0
  fi

  echo "error: no URL opener found (open or xdg-open)" >&2
  return 1
}

markdown_reference() {
  if [[ -n "$markdown" ]]; then
    sanitize_one_line "$markdown"
    return 0
  fi

  local label=""
  title="$(sanitize_one_line "$title")"
  repo="$(sanitize_one_line "$repo")"
  number="$(sanitize_one_line "$number")"

  if [[ -n "$repo" && -n "$number" ]]; then
    label="$repo#$number"
    if [[ -n "$title" ]]; then
      label="$label $title"
    fi
  elif [[ -n "$title" ]]; then
    label="$title"
  else
    label="$url"
  fi

  printf '[%s](%s)' "$label" "$url"
}

case "$action" in
open | "")
  open_url "$url"
  ;;
copy-url)
  if [[ -z "$url" ]]; then
    echo "error: action token has no URL" >&2
    exit 2
  fi
  copy_to_clipboard "$url"
  ;;
copy-md)
  if [[ -z "$url" ]]; then
    echo "error: action token has no URL" >&2
    exit 2
  fi
  copy_to_clipboard "$(markdown_reference)"
  ;;
*)
  echo "error: unsupported forge inbox action: $action" >&2
  exit 2
  ;;
esac
