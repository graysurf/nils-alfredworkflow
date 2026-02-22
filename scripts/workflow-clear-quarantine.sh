#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

prefs_root_default="$HOME/Library/Application Support/Alfred/Alfred.alfredpreferences/workflows"
prefs_root="${ALFRED_PREFS_ROOT:-$prefs_root_default}"

declare -a requested_ids=()

usage() {
  cat <<USAGE
Usage:
  scripts/workflow-clear-quarantine.sh [--all]
  scripts/workflow-clear-quarantine.sh --id <workflow-id> [--id <workflow-id> ...]

Behavior:
  - Clears macOS Gatekeeper quarantine recursively on installed Alfred workflows.
  - Resolves installed workflow directories by bundle id from workflows/<id>/workflow.toml.
  - Skips workflow ids that are not installed in Alfred (non-fatal).

Options:
  --all                 Target all tracked workflows (default when no --id is provided).
  --id <workflow-id>    Target one workflow id (can repeat).
  -h, --help            Show this help.

Environment:
  ALFRED_PREFS_ROOT     Override Alfred workflows directory.
USAGE
}

toml_string() {
  local file="$1"
  local key="$2"
  awk -F'=' -v key="$key" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      value=$2
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      gsub(/^\"|\"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

list_workflow_ids() {
  find "$repo_root/workflows" -mindepth 1 -maxdepth 1 -type d \
    ! -name '_template' -exec basename {} \; | sort
}

has_workflow_manifest() {
  local id="$1"
  [[ -f "$repo_root/workflows/$id/workflow.toml" ]]
}

find_installed_workflow_dir_by_bundle_id() {
  local bundle_id="$1"
  local info bid

  for info in "$prefs_root"/*/info.plist; do
    [[ -f "$info" ]] || continue
    bid="$(plutil -extract bundleid raw -o - "$info" 2>/dev/null || true)"
    if [[ "$bid" == "$bundle_id" ]]; then
      dirname "$info"
      return 0
    fi
  done

  return 1
}

add_target_id() {
  local id="$1"
  local existing
  for existing in "${requested_ids[@]:-}"; do
    if [[ "$existing" == "$id" ]]; then
      return 0
    fi
  done
  requested_ids+=("$id")
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --id)
    [[ -n "${2:-}" ]] || {
      echo "error: --id requires a value" >&2
      exit 2
    }
    add_target_id "$2"
    shift 2
    ;;
  --all)
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "error: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ "$(uname -s 2>/dev/null || printf '')" != "Darwin" ]]; then
  echo "skip: workflow-clear-quarantine is macOS-only"
  exit 0
fi

if ! command -v plutil >/dev/null 2>&1; then
  echo "warn: plutil not found; cannot resolve installed workflows"
  exit 0
fi

if ! command -v xattr >/dev/null 2>&1; then
  echo "warn: xattr not found; cannot clear quarantine"
  exit 0
fi

if [[ ! -d "$prefs_root" ]]; then
  echo "warn: Alfred workflows directory not found: $prefs_root"
  exit 0
fi

if [[ "${#requested_ids[@]}" -eq 0 ]]; then
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    requested_ids+=("$id")
  done < <(list_workflow_ids)
fi

cleared_count=0
skip_count=0
fail_count=0

for id in "${requested_ids[@]}"; do
  if ! has_workflow_manifest "$id"; then
    echo "warn: unknown workflow id (missing manifest): $id"
    fail_count=$((fail_count + 1))
    continue
  fi

  manifest="$repo_root/workflows/$id/workflow.toml"
  bundle_id="$(toml_string "$manifest" bundle_id)"
  if [[ -z "$bundle_id" ]]; then
    echo "warn: missing bundle_id in $manifest"
    fail_count=$((fail_count + 1))
    continue
  fi

  workflow_dir="$(find_installed_workflow_dir_by_bundle_id "$bundle_id" || true)"
  if [[ -z "$workflow_dir" ]]; then
    echo "skip: not installed ($id, $bundle_id)"
    skip_count=$((skip_count + 1))
    continue
  fi

  if xattr -dr com.apple.quarantine "$workflow_dir" >/dev/null 2>&1; then
    echo "ok: removed quarantine ($id -> $workflow_dir)"
    cleared_count=$((cleared_count + 1))
  else
    echo "warn: failed to clear quarantine ($id -> $workflow_dir)"
    fail_count=$((fail_count + 1))
  fi
done

echo "summary: cleared=$cleared_count skipped=$skip_count failed=$fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
