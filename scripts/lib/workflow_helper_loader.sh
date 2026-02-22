#!/usr/bin/env bash
# Shared helper-loader primitives for workflow shell adapters.
#
# Deterministic resolution order:
# 1) Packaged helper: <script-dir>/lib/<helper-name>
# 2) Repo-relative helper: <script-dir>/../../../scripts/lib/<helper-name>
# 3) Optional git-root fallback: <git-root>/scripts/lib/<helper-name>

wfhl_missing_helper_title() {
  printf 'Workflow helper missing'
}

wfhl_missing_helper_message() {
  local helper_name="${1-}"
  printf 'Cannot locate %s runtime helper.' "$helper_name"
}

wfhl_json_escape() {
  local value="${1-}"
  value="$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  value="$(printf '%s' "$value" | tr '\n\r' '  ')"
  printf '%s' "$value"
}

wfhl_emit_missing_helper_item_json() {
  local helper_name="${1-}"
  printf '{"items":[{"title":"%s","subtitle":"%s","valid":false}]}\n' \
    "$(wfhl_json_escape "$(wfhl_missing_helper_title)")" \
    "$(wfhl_json_escape "$(wfhl_missing_helper_message "$helper_name")")"
}

wfhl_print_missing_helper_stderr() {
  local helper_name="${1-}"
  printf '%s: %s\n' \
    "$(wfhl_missing_helper_title)" \
    "$(wfhl_missing_helper_message "$helper_name")" >&2
}

wfhl_resolve_git_root() {
  local start_dir="${1:-$PWD}"

  if ! command -v git >/dev/null 2>&1; then
    return 1
  fi

  git -C "$start_dir" rev-parse --show-toplevel 2>/dev/null
}

wfhl_resolve_helper_path() {
  if [[ $# -lt 2 ]]; then
    echo "wfhl_resolve_helper_path requires: script-dir helper-name [git-root|auto|off]" >&2
    return 2
  fi

  local script_dir="$1"
  local helper_name="$2"
  local git_fallback="${3:-auto}"
  local candidate=""
  local git_root=""

  if [[ -z "$script_dir" || -z "$helper_name" ]]; then
    echo "wfhl_resolve_helper_path requires non-empty script-dir and helper-name" >&2
    return 2
  fi

  candidate="$script_dir/lib/$helper_name"
  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate="$script_dir/../../../scripts/lib/$helper_name"
  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  case "$git_fallback" in
  "" | off | none | no | false | 0)
    return 1
    ;;
  auto | on | yes | true | 1)
    git_root="$(wfhl_resolve_git_root "${WFHL_GIT_ROOT_START_DIR:-$PWD}" || true)"
    ;;
  *)
    git_root="$git_fallback"
    ;;
  esac

  if [[ -n "$git_root" ]]; then
    candidate="$git_root/scripts/lib/$helper_name"
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  return 1
}

wfhl_source_helper() {
  if [[ $# -lt 2 ]]; then
    echo "wfhl_source_helper requires: script-dir helper-name [git-root|auto|off]" >&2
    return 2
  fi

  local script_dir="$1"
  local helper_name="$2"
  local git_fallback="${3:-auto}"
  local helper_path=""

  helper_path="$(wfhl_resolve_helper_path "$script_dir" "$helper_name" "$git_fallback" || true)"
  if [[ -z "$helper_path" ]]; then
    return 1
  fi

  # shellcheck disable=SC1090
  source "$helper_path"
}
