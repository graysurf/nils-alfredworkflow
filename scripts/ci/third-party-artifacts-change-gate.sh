#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ci/third-party-artifacts-change-gate.sh [--base <ref>] [--plan-only] [--changed-file <path>]...

Description:
  Runs the strict third-party artifact audit when the current change set touches
  files that feed or represent the generated third-party artifacts.

Options:
  --base <ref>            Diff base for committed changes.
                          Default: THIRD_PARTY_ARTIFACTS_GATE_BASE or origin/main.
  --plan-only             Print the detected gate plan and do not run it.
  --changed-file <path>   Override changed-file detection. Repeatable.
  -h, --help              Show this help.
USAGE
}

base="${THIRD_PARTY_ARTIFACTS_GATE_BASE:-origin/main}"
plan_only=0
declare -a forced_changed_files=()

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
  --base)
    [[ $# -ge 2 ]] || {
      echo "error: --base requires a value" >&2
      exit 2
    }
    base="${2:-}"
    shift 2
    ;;
  --base=*)
    base="${1#--base=}"
    shift
    ;;
  --plan-only)
    plan_only=1
    shift
    ;;
  --changed-file)
    [[ $# -ge 2 ]] || {
      echo "error: --changed-file requires a value" >&2
      exit 2
    }
    forced_changed_files+=("${2:-}")
    shift 2
    ;;
  --changed-file=*)
    forced_changed_files+=("${1#--changed-file=}")
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "error: unknown argument: ${1:-}" >&2
    usage >&2
    exit 2
    ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" || ! -d "$repo_root" ]]; then
  echo "error: must run inside a git work tree" >&2
  exit 2
fi
cd "$repo_root"

collect_changed_files() {
  if [[ "${#forced_changed_files[@]}" -gt 0 ]]; then
    printf '%s\n' "${forced_changed_files[@]}" | sed '/^$/d' | sort -u
    return 0
  fi

  if ! git rev-parse --verify "${base}^{commit}" >/dev/null 2>&1; then
    echo "error: base ref does not resolve to a commit: $base" >&2
    exit 2
  fi

  local merge_base
  merge_base="$(git merge-base HEAD "$base")"
  {
    git diff --name-only --diff-filter=ACMRT "$merge_base"...HEAD
    git diff --name-only --diff-filter=ACMRT
    git diff --name-only --cached --diff-filter=ACMRT
    git ls-files --others --exclude-standard
  } | sed '/^$/d' | sort -u
}

affects_third_party_artifacts() {
  local path="$1"
  case "$path" in
  Cargo.toml | Cargo.lock | package.json | package-lock.json)
    return 0
    ;;
  THIRD_PARTY_LICENSES.md | THIRD_PARTY_NOTICES.md)
    return 0
    ;;
  scripts/generate-third-party-artifacts.sh | scripts/ci/third-party-artifacts-audit.sh)
    return 0
    ;;
  scripts/ci/third-party-artifacts-change-gate.sh | scripts/lib/codex_cli_version.sh)
    return 0
    ;;
  crates/*/Cargo.toml)
    return 0
    ;;
  esac
  return 1
}

declare -a changed_files=()
declare -a trigger_files=()

while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  changed_files+=("$path")
  if affects_third_party_artifacts "$path"; then
    trigger_files+=("$path")
  fi
done < <(collect_changed_files)

echo "THIRD_PARTY_ARTIFACTS_GATE_BASE=$base"
echo "THIRD_PARTY_ARTIFACTS_GATE_CHANGED_COUNT=${#changed_files[@]}"
for path in "${changed_files[@]}"; do
  echo "THIRD_PARTY_ARTIFACTS_GATE_CHANGED=$path"
done

if [[ "${#trigger_files[@]}" -eq 0 ]]; then
  echo "THIRD_PARTY_ARTIFACTS_GATE=skip"
  echo "skip: no third-party artifact inputs changed"
  exit 0
fi

echo "THIRD_PARTY_ARTIFACTS_GATE=run"
for path in "${trigger_files[@]}"; do
  echo "THIRD_PARTY_ARTIFACTS_GATE_TRIGGER=$path"
done

if [[ "$plan_only" -eq 1 ]]; then
  exit 0
fi

bash scripts/ci/third-party-artifacts-audit.sh --strict
