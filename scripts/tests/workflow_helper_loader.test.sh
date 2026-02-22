#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
loader_path="$repo_root/scripts/lib/workflow_helper_loader.sh"

# shellcheck disable=SC1090
source "$loader_path"

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

tests_total=0
tests_failed=0

pass() {
  local name="$1"
  printf 'ok - %s\n' "$name"
}

fail() {
  local name="$1"
  printf 'not ok - %s\n' "$name"
  tests_failed=$((tests_failed + 1))
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'assert failed: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
    return 1
  fi
  return 0
}

assert_empty_file() {
  local path="$1"
  local label="$2"

  if [[ -s "$path" ]]; then
    printf 'assert failed: %s\nexpected empty file: %s\n' "$label" "$path" >&2
    cat "$path" >&2 || true
    return 1
  fi
  return 0
}

canonical_path() {
  local path="$1"
  local dir=""

  dir="$(cd "$(dirname "$path")" && pwd)"
  printf '%s/%s\n' "$dir" "$(basename "$path")"
}

write_helper() {
  local path="$1"
  local source_name="$2"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
WFHL_TEST_HELPER_SOURCE="$source_name"
EOF
}

write_fake_git() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == "-C" ]]; then
  shift 2
fi

if [[ "${1-}" == "rev-parse" && "${2-}" == "--show-toplevel" ]]; then
  printf '%s\n' "${WFHL_TEST_GIT_ROOT:-}"
  exit 0
fi

exit 1
EOF
  chmod +x "$path"
}

test_packaged_path_precedes_repo_and_git() {
  local root="$tmp_root/packaged-order"
  local wf_script_dir="$root/workflows/demo/scripts"
  local helper_name="helper.sh"
  local git_root="$root/fallback-git-root"
  local resolved=""

  write_helper "$wf_script_dir/lib/$helper_name" "packaged"
  write_helper "$root/scripts/lib/$helper_name" "repo-relative"
  write_helper "$git_root/scripts/lib/$helper_name" "git-root"

  resolved="$(wfhl_resolve_helper_path "$wf_script_dir" "$helper_name" "$git_root")"
  if ! assert_eq \
    "$(canonical_path "$wf_script_dir/lib/$helper_name")" \
    "$(canonical_path "$resolved")" \
    "packaged helper precedence"; then
    return 1
  fi

  unset WFHL_TEST_HELPER_SOURCE || true
  wfhl_source_helper "$wf_script_dir" "$helper_name" "$git_root"
  if ! assert_eq "packaged" "${WFHL_TEST_HELPER_SOURCE-}" "packaged helper sourced"; then
    return 1
  fi

  return 0
}

test_repo_path_precedes_git_when_packaged_missing() {
  local root="$tmp_root/repo-order"
  local wf_script_dir="$root/workflows/demo/scripts"
  local helper_name="helper.sh"
  local git_root="$root/fallback-git-root"
  local resolved=""

  mkdir -p "$wf_script_dir"
  write_helper "$root/scripts/lib/$helper_name" "repo-relative"
  write_helper "$git_root/scripts/lib/$helper_name" "git-root"

  resolved="$(wfhl_resolve_helper_path "$wf_script_dir" "$helper_name" "$git_root")"
  if ! assert_eq \
    "$(canonical_path "$root/scripts/lib/$helper_name")" \
    "$(canonical_path "$resolved")" \
    "repo helper precedence over git fallback"; then
    return 1
  fi

  unset WFHL_TEST_HELPER_SOURCE || true
  wfhl_source_helper "$wf_script_dir" "$helper_name" "$git_root"
  if ! assert_eq "repo-relative" "${WFHL_TEST_HELPER_SOURCE-}" "repo-relative helper sourced"; then
    return 1
  fi

  return 0
}

test_git_root_fallback_branch() {
  local root="$tmp_root/git-fallback"
  local wf_script_dir="$root/workflows/demo/scripts"
  local helper_name="helper.sh"
  local git_root="$root/detected-git-root"
  local fake_git="$root/bin/git"
  local probe_dir="$root/pwd"
  local resolved=""

  mkdir -p "$wf_script_dir" "$probe_dir"
  write_helper "$git_root/scripts/lib/$helper_name" "git-root"
  write_fake_git "$fake_git"

  resolved="$(
    cd "$probe_dir"
    PATH="$(dirname "$fake_git"):$PATH" \
    WFHL_TEST_GIT_ROOT="$git_root" \
      wfhl_resolve_helper_path "$wf_script_dir" "$helper_name" auto
  )"
  if ! assert_eq \
    "$(canonical_path "$git_root/scripts/lib/$helper_name")" \
    "$(canonical_path "$resolved")" \
    "git-root fallback resolution"; then
    return 1
  fi

  return 0
}

test_missing_helper_error_contract() {
  local root="$tmp_root/missing-helper"
  local wf_script_dir="$root/workflows/demo/scripts"
  local helper_name="missing_helper.sh"
  local stdout_file="$root/stdout.txt"
  local stderr_file="$root/stderr.txt"
  local msg=""
  local json=""

  mkdir -p "$wf_script_dir"

  if wfhl_resolve_helper_path "$wf_script_dir" "$helper_name" off >"$stdout_file"; then
    echo "expected wfhl_resolve_helper_path to fail for missing helper" >&2
    return 1
  fi
  if ! assert_empty_file "$stdout_file" "missing helper should not print path"; then
    return 1
  fi

  msg="$(wfhl_missing_helper_message "$helper_name")"
  if ! assert_eq "Cannot locate ${helper_name} runtime helper." "$msg" "missing helper message"; then
    return 1
  fi

  wfhl_print_missing_helper_stderr "$helper_name" 2>"$stderr_file"
  if ! assert_eq "Workflow helper missing: Cannot locate ${helper_name} runtime helper." "$(cat "$stderr_file")" "missing helper stderr contract"; then
    return 1
  fi

  json="$(wfhl_emit_missing_helper_item_json "$helper_name")"
  if ! assert_eq '{"items":[{"title":"Workflow helper missing","subtitle":"Cannot locate missing_helper.sh runtime helper.","valid":false}]}' "$json" "missing helper JSON contract"; then
    return 1
  fi

  return 0
}

run_test() {
  local test_name="$1"
  tests_total=$((tests_total + 1))
  if "$test_name"; then
    pass "$test_name"
  else
    fail "$test_name"
  fi
}

run_test test_packaged_path_precedes_repo_and_git
run_test test_repo_path_precedes_git_when_packaged_missing
run_test test_git_root_fallback_branch
run_test test_missing_helper_error_contract

if [[ "$tests_failed" -ne 0 ]]; then
  printf 'FAIL: %d/%d tests failed\n' "$tests_failed" "$tests_total" >&2
  exit 1
fi

printf 'PASS: %d tests\n' "$tests_total"
