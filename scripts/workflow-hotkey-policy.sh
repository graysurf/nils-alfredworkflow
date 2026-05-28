#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

usage() {
  cat <<USAGE
Usage:
  scripts/workflow-hotkey-policy.sh --check

Every Script Filter in every workflow must have its own unassigned ("empty")
hotkey trigger so users can bind their own shortcut in Alfred. A workflow must
therefore ship at least as many hotkey triggers as Script Filters, and every
hotkey trigger must ship unassigned (hotkey=0, hotmod=0).
USAGE
}

mode="check"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --check)
    mode="check"
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

echo "== Workflow hotkey policy audit =="
echo "mode: $mode"

mapfile -t plists < <(find "$repo_root/workflows" -type f -name 'info.plist.template' -path '*/src/*' | sort)

candidate_count=0
failures=0

for plist in "${plists[@]}"; do
  rel_path="${plist#"$repo_root"/}"

  # Only workflows that expose a Script Filter need customizable hotkeys.
  sf_count=$(grep -c "alfred.workflow.input.scriptfilter" "$plist" || true)
  if [[ "$sf_count" -eq 0 ]]; then
    continue
  fi
  candidate_count=$((candidate_count + 1))

  hk_count=$(grep -c "alfred.workflow.trigger.hotkey" "$plist" || true)

  reasons=()
  if [[ "$hk_count" -lt "$sf_count" ]]; then
    reasons+=("has $sf_count script filter(s) but only $hk_count hotkey trigger(s); every script filter needs its own unassigned hotkey")
  fi
  # Hotkeys must ship unassigned so the user can customize them.
  if grep -A1 "<key>hotkey</key>" "$plist" | grep "<integer>" | grep -qv "<integer>0</integer>"; then
    reasons+=("a hotkey trigger ships pre-assigned; hotkey must be 0 (unassigned)")
  fi
  if grep -A1 "<key>hotmod</key>" "$plist" | grep "<integer>" | grep -qv "<integer>0</integer>"; then
    reasons+=("a hotkey trigger ships pre-assigned modifiers; hotmod must be 0")
  fi

  if [[ ${#reasons[@]} -eq 0 ]]; then
    echo "PASS [check] $rel_path ($sf_count script filter(s), $hk_count hotkey(s))"
    continue
  fi

  failures=$((failures + 1))
  echo "FAIL [check] $rel_path" >&2
  for reason in "${reasons[@]}"; do
    echo "  - $reason" >&2
  done
done

echo
echo "Summary: candidates=$candidate_count failures=$failures"
if [[ "$failures" -gt 0 ]]; then
  echo "Result: FAIL (hotkey policy drift detected)" >&2
  exit 1
fi

echo "Result: PASS"
