#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

strict_mode=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/ci/third-party-artifacts-audit.sh [--strict]

Options:
  --strict   Treat warnings as failures.
  -h, --help Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --strict)
    strict_mode=1
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

hard_failures=0
warnings=0

artifact_generator="$repo_root/scripts/generate-third-party-artifacts.sh"
required_artifacts=(
  "$repo_root/THIRD_PARTY_LICENSES.md"
  "$repo_root/THIRD_PARTY_NOTICES.md"
)

pass() {
  local message="$1"
  printf 'PASS [third-party-artifacts] %s\n' "$message"
}

warn() {
  local message="$1"
  printf 'WARN [third-party-artifacts] %s\n' "$message"
  warnings=$((warnings + 1))
}

fail() {
  local message="$1"
  printf 'FAIL [third-party-artifacts] %s\n' "$message"
  hard_failures=$((hard_failures + 1))
}

summarize_stderr() {
  local file="$1"
  if [[ ! -s "$file" ]]; then
    printf '%s' "no stderr output"
    return
  fi

  tr '\n' ' ' <"$file" |
    sed -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//'
}

echo "== Third-party artifacts audit =="
echo "mode: $([[ "$strict_mode" -eq 1 ]] && echo strict || echo non-strict)"

if [[ -x "$artifact_generator" || -f "$artifact_generator" ]]; then
  pass "generator script present: scripts/generate-third-party-artifacts.sh"
else
  fail "missing generator script: scripts/generate-third-party-artifacts.sh"
fi

for artifact in "${required_artifacts[@]}"; do
  rel_path="${artifact#"$repo_root"/}"
  if [[ -f "$artifact" ]]; then
    pass "artifact present: ${rel_path}"
  else
    warn "artifact missing: ${rel_path} (run: bash scripts/generate-third-party-artifacts.sh --write)"
  fi
done

if [[ "$hard_failures" -eq 0 ]]; then
  tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/third-party-artifacts-audit.XXXXXX")"
  trap 'rm -rf "$tmp_root"' EXIT

  check_stdout="$tmp_root/generator-check.stdout"
  check_stderr="$tmp_root/generator-check.stderr"
  check_rc=0
  if (cd "$repo_root" && bash "$artifact_generator" --check >"$check_stdout" 2>"$check_stderr"); then
    pass "generator --check passed (artifacts are fresh)"
  else
    check_rc=$?
    check_summary="$(summarize_stderr "$check_stderr")"

    if grep -q 'missing output artifact:' "$check_stderr"; then
      warn "generator --check reported missing artifact detail: $check_summary"
    elif grep -q 'FAIL \[check\]' "$check_stderr"; then
      warn "artifact drift detected (run: bash scripts/generate-third-party-artifacts.sh --write)"
      warn "generator --check detail: $check_summary"
    else
      fail "generator --check failed (exit=$check_rc): $check_summary"
    fi
  fi
fi

echo
printf 'Summary: hard_failures=%d warnings=%d strict=%s\n' \
  "$hard_failures" \
  "$warnings" \
  "$([[ "$strict_mode" -eq 1 ]] && echo true || echo false)"

if [[ "$hard_failures" -gt 0 ]]; then
  echo "Result: FAIL (hard failures detected)"
  exit 1
fi

if [[ "$strict_mode" -eq 1 && "$warnings" -gt 0 ]]; then
  echo "FAIL [third-party-artifacts] strict mode treats warnings as failures"
  echo "Result: FAIL (strict mode treats warnings as failures)"
  exit 1
fi

if [[ "$warnings" -gt 0 ]]; then
  echo "Result: PASS with warnings (run with --strict to enforce warnings)"
else
  echo "Result: PASS"
fi
