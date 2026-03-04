#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

core_only=0
third_party_only=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/script-tests.sh [--core-only | --third-party-only]

Suites:
  default             scripts/tests/*.test.sh + tests/third-party-artifacts/*.test.sh
  --core-only         scripts/tests/*.test.sh
  --third-party-only  tests/third-party-artifacts/*.test.sh
USAGE
}

run_test_file() {
  local test_file="$1"
  echo "+ bash ${test_file#"$repo_root"/}"
  bash "$test_file"
}

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
  --core-only)
    core_only=1
    shift
    ;;
  --third-party-only)
    third_party_only=1
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

if [[ "$core_only" -eq 1 && "$third_party_only" -eq 1 ]]; then
  echo "error: --core-only and --third-party-only cannot be combined" >&2
  exit 2
fi

declare -a test_files=()
if [[ "$third_party_only" -eq 0 ]]; then
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    test_files+=("$path")
  done < <(find "$repo_root/scripts/tests" -type f -name '*.test.sh' | sort)
fi

if [[ "$core_only" -eq 0 ]]; then
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    test_files+=("$path")
  done < <(find "$repo_root/tests/third-party-artifacts" -type f -name '*.test.sh' | sort)
fi

if [[ "${#test_files[@]}" -eq 0 ]]; then
  echo "ok: no script tests selected"
  exit 0
fi

for test_file in "${test_files[@]}"; do
  run_test_file "$test_file"
done

echo "ok: script tests passed (${#test_files[@]} files)"
