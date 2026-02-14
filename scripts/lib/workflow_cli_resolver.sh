#!/bin/sh
# Shared CLI resolver helpers for Alfred workflow shell adapters.

wfcr_clear_quarantine_if_needed() {
  cli_path="${1-}"
  if [ -z "$cli_path" ]; then
    return 0
  fi

  if [ "$(uname -s 2>/dev/null || printf '')" != "Darwin" ]; then
    return 0
  fi

  if ! command -v xattr >/dev/null 2>&1; then
    return 0
  fi

  if xattr -p com.apple.quarantine "$cli_path" >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "$cli_path" >/dev/null 2>&1 || true
  fi
}

wfcr_try_candidate() {
  candidate="${1-}"
  if [ -z "$candidate" ] || [ ! -x "$candidate" ]; then
    return 1
  fi

  wfcr_clear_quarantine_if_needed "$candidate"
  printf '%s\n' "$candidate"
  return 0
}

wfcr_resolve_binary() {
  if [ "$#" -lt 5 ]; then
    echo "wfcr_resolve_binary requires: env-var packaged release debug error-msg" >&2
    return 2
  fi

  env_var_name="$1"
  packaged_candidate="$2"
  release_candidate="$3"
  debug_candidate="$4"
  error_msg="$5"

  env_candidate=""
  # shellcheck disable=SC2086
  eval "env_candidate=\${$env_var_name:-}"

  if wfcr_try_candidate "$env_candidate"; then
    return 0
  fi

  if wfcr_try_candidate "$packaged_candidate"; then
    return 0
  fi

  if wfcr_try_candidate "$release_candidate"; then
    return 0
  fi

  if wfcr_try_candidate "$debug_candidate"; then
    return 0
  fi

  printf '%s\n' "$error_msg" >&2
  return 1
}
