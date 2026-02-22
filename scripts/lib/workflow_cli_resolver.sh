#!/bin/sh
# Shared CLI resolver helpers for Alfred workflow shell adapters.

wfcr_can_manage_quarantine() {
  if [ "$(uname -s 2>/dev/null || printf '')" != "Darwin" ]; then
    return 1
  fi

  if ! command -v xattr >/dev/null 2>&1; then
    return 1
  fi

  return 0
}

wfcr_has_quarantine_attr() {
  target_path="${1-}"
  if [ -z "$target_path" ] || [ ! -e "$target_path" ]; then
    return 1
  fi

  xattr -p com.apple.quarantine "$target_path" >/dev/null 2>&1
}

wfcr_find_workflow_root_from_seed_path() {
  seed_path="$(wfcr_expand_home_path "${1-}")"
  if [ -z "$seed_path" ]; then
    return 1
  fi

  probe_dir="$seed_path"
  if [ -f "$probe_dir" ]; then
    probe_dir="$(dirname "$probe_dir")"
  fi

  while [ -n "$probe_dir" ]; do
    if [ -f "$probe_dir/info.plist" ]; then
      printf '%s\n' "$probe_dir"
      return 0
    fi

    parent_dir="$(dirname "$probe_dir")"
    if [ "$parent_dir" = "$probe_dir" ]; then
      break
    fi
    probe_dir="$parent_dir"
  done

  return 1
}

wfcr_quarantine_marker_file_for_root() {
  workflow_root="${1-}"
  if [ -z "$workflow_root" ]; then
    return 1
  fi

  marker_dir="${TMPDIR:-/tmp}/nils-workflow-quarantine-markers"
  mkdir -p "$marker_dir" >/dev/null 2>&1 || return 1

  fingerprint="$(printf '%s' "$workflow_root" | cksum | awk '{print $1}')"
  if [ -z "$fingerprint" ]; then
    return 1
  fi

  printf '%s/%s.marker\n' "$marker_dir" "$fingerprint"
}

wfcr_clear_workflow_quarantine_once_if_needed() {
  seed_path="$(wfcr_expand_home_path "${1-}")"
  if [ -z "$seed_path" ]; then
    return 0
  fi

  if ! wfcr_can_manage_quarantine; then
    return 0
  fi

  workflow_root="$(wfcr_find_workflow_root_from_seed_path "$seed_path" || true)"
  if [ -z "$workflow_root" ]; then
    return 0
  fi

  marker_file="$(wfcr_quarantine_marker_file_for_root "$workflow_root" || true)"
  if [ -z "$marker_file" ]; then
    return 0
  fi

  if [ -f "$marker_file" ]; then
    return 0
  fi

  should_clear=1
  if wfcr_has_quarantine_attr "$workflow_root"; then
    should_clear=0
  fi
  if wfcr_has_quarantine_attr "$workflow_root/info.plist"; then
    should_clear=0
  fi
  if wfcr_has_quarantine_attr "$seed_path"; then
    should_clear=0
  fi

  if [ "$should_clear" -eq 0 ]; then
    xattr -dr com.apple.quarantine "$workflow_root" >/dev/null 2>&1 || true
  fi

  : >"$marker_file" 2>/dev/null || true
}

wfcr_clear_quarantine_if_needed() {
  cli_path="${1-}"
  if [ -z "$cli_path" ]; then
    return 0
  fi

  if ! wfcr_can_manage_quarantine; then
    return 0
  fi

  if xattr -p com.apple.quarantine "$cli_path" >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "$cli_path" >/dev/null 2>&1 || true
  fi
}

wfcr_expand_home_path() {
  value="${1-}"

  case "$value" in
  "~")
    if [ -n "${HOME:-}" ]; then
      printf '%s\n' "${HOME%/}"
      return 0
    fi
    ;;
  \~/*)
    if [ -n "${HOME:-}" ]; then
      printf '%s/%s\n' "${HOME%/}" "${value#\~/}"
      return 0
    fi
    ;;
  esac

  printf '%s\n' "$value"
}

wfcr_try_candidate() {
  candidate="$(wfcr_expand_home_path "${1-}")"
  if [ -z "$candidate" ]; then
    return 1
  fi

  wfcr_clear_workflow_quarantine_once_if_needed "$candidate"

  if [ ! -x "$candidate" ]; then
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
