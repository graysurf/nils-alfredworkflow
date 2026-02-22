#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

usage() {
  cat <<USAGE
Usage:
  scripts/workflow-cli-resolver-audit.sh --check
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

echo "== Workflow CLI resolver audit =="
echo "mode: $mode"

mapfile -t script_files < <(find "$repo_root/workflows" -type f -name '*.sh' -path '*/scripts/*' | sort)

candidate_count=0
failures=0

for script_path in "${script_files[@]}"; do
  if ! rg -n "\.\./bin/" "$script_path" >/dev/null 2>&1; then
    continue
  fi

  candidate_count=$((candidate_count + 1))
  rel_path="${script_path#"$repo_root"/}"

  missing_reasons=()
  if ! rg -n "workflow_cli_resolver\.sh" "$script_path" >/dev/null 2>&1; then
    missing_reasons+=("missing workflow_cli_resolver helper wiring")
  fi
  if ! rg -n "wfcr_resolve_binary" "$script_path" >/dev/null 2>&1; then
    missing_reasons+=("missing wfcr_resolve_binary call")
  fi

  if [[ ${#missing_reasons[@]} -eq 0 ]]; then
    echo "PASS [check] $rel_path"
    continue
  fi

  failures=$((failures + 1))
  echo "FAIL [check] $rel_path" >&2
  for reason in "${missing_reasons[@]}"; do
    echo "  - $reason" >&2
  done
done

echo
if [[ "$candidate_count" -eq 0 ]]; then
  echo "Summary: candidates=0 failures=$failures"
  echo "Result: PASS (no bundled-runtime scripts found)"
  exit 0
fi

echo "Summary: candidates=$candidate_count failures=$failures"
if [[ "$failures" -gt 0 ]]; then
  echo "Result: FAIL (resolver policy drift detected)" >&2
  exit 1
fi

echo "Result: PASS"
