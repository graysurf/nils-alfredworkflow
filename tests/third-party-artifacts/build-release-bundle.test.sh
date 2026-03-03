#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

test_root="$(mktemp -d "${TMPDIR:-/tmp}/build-release-bundle.test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

tests_total=0
tests_failed=0

last_rc=0
last_stdout=""
last_stderr=""

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

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'assert failed: %s\nmissing substring: %s\n' "$label" "$needle" >&2
    return 1
  fi
  return 0
}

dump_last_run() {
  printf 'last exit code: %s\n' "$last_rc" >&2
  if [[ -f "$last_stdout" ]]; then
    printf '%s\n' '--- stdout ---' >&2
    cat "$last_stdout" >&2 || true
  fi
  if [[ -f "$last_stderr" ]]; then
    printf '%s\n' '--- stderr ---' >&2
    cat "$last_stderr" >&2 || true
  fi
}

setup_fixture() {
  local fixture="$test_root/fixture-$RANDOM-$RANDOM"
  local dist_dir="$fixture/dist"

  mkdir -p "$fixture/scripts/ci" "$dist_dir/bangumi-search/1.0.0"

  cp "$repo_root/scripts/ci/build-release-bundle.sh" "$fixture/scripts/ci/build-release-bundle.sh"
  chmod +x "$fixture/scripts/ci/build-release-bundle.sh"

  cat >"$fixture/scripts/workflow-clear-quarantine-standalone.sh" <<'__SCRIPT__'
#!/usr/bin/env bash
echo fixture
__SCRIPT__
  chmod +x "$fixture/scripts/workflow-clear-quarantine-standalone.sh"

  cat >"$fixture/THIRD_PARTY_LICENSES.md" <<'__LICENSE__'
# Fixture Third-Party Licenses
__LICENSE__

  cat >"$fixture/THIRD_PARTY_NOTICES.md" <<'__NOTICE__'
# Fixture Third-Party Notices
__NOTICE__

  cat >"$dist_dir/bangumi-search/1.0.0/Bangumi Search.alfredworkflow" <<'__ARTIFACT__'
fixture-workflow
__ARTIFACT__
  cat >"$dist_dir/bangumi-search/1.0.0/Bangumi Search.alfredworkflow.sha256" <<'__ARTIFACT_SHA__'
fixture-sha
__ARTIFACT_SHA__

  fixture="$(cd "$fixture" && pwd)"
  printf '%s\n' "$fixture"
}

run_builder() {
  local fixture="$1"
  shift

  last_stdout="$fixture/stdout.log"
  last_stderr="$fixture/stderr.log"
  last_rc=0

  (
    cd "$fixture"
    bash "$fixture/scripts/ci/build-release-bundle.sh" "$@"
  ) >"$last_stdout" 2>"$last_stderr" || last_rc=$?
}

read_combined_output() {
  local fixture="$1"
  cat "$fixture/stdout.log" "$fixture/stderr.log"
}

test_builder_writes_bundle_and_required_assets() {
  local fixture
  fixture="$(setup_fixture)"

  run_builder "$fixture" --tag v0.0.0-test --repo-root "$fixture"
  if ! assert_eq "0" "$last_rc" "build release bundle exit code"; then
    dump_last_run
    return 1
  fi

  local bundle_dir="$fixture/dist/release-bundles"
  local bundle_zip="$bundle_dir/workflows-v0.0.0-test.zip"

  for required in \
    "$bundle_zip" \
    "$bundle_zip.sha256" \
    "$bundle_dir/workflow-clear-quarantine-standalone.sh" \
    "$bundle_dir/workflow-clear-quarantine-standalone.sh.sha256" \
    "$bundle_dir/THIRD_PARTY_LICENSES.md" \
    "$bundle_dir/THIRD_PARTY_LICENSES.md.sha256" \
    "$bundle_dir/THIRD_PARTY_NOTICES.md" \
    "$bundle_dir/THIRD_PARTY_NOTICES.md.sha256"; do
    if [[ ! -f "$required" ]]; then
      printf 'missing expected output: %s\n' "$required" >&2
      dump_last_run
      return 1
    fi
  done

  local zip_entries
  zip_entries="$(unzip -Z1 "$bundle_zip")"
  if ! assert_contains "$zip_entries" "bangumi-search/1.0.0/Bangumi Search.alfredworkflow" "bundle zip contains workflow"; then
    dump_last_run
    return 1
  fi
  if ! assert_contains "$zip_entries" "bangumi-search/1.0.0/Bangumi Search.alfredworkflow.sha256" "bundle zip contains workflow checksum"; then
    dump_last_run
    return 1
  fi

  return 0
}

test_builder_fails_when_notices_is_missing() {
  local fixture
  fixture="$(setup_fixture)"
  rm -f "$fixture/THIRD_PARTY_NOTICES.md"

  run_builder "$fixture" --tag v0.0.0-test --repo-root "$fixture"
  if ! assert_eq "1" "$last_rc" "missing notices exit code"; then
    dump_last_run
    return 1
  fi

  local output
  output="$(read_combined_output "$fixture")"
  if ! assert_contains "$output" "missing required notices artifact" "missing notices error message"; then
    dump_last_run
    return 1
  fi

  return 0
}

test_builder_fails_when_no_workflow_artifacts_exist() {
  local fixture
  fixture="$(setup_fixture)"
  find "$fixture/dist" -type f \( -name '*.alfredworkflow' -o -name '*.alfredworkflow.sha256' \) -delete

  run_builder "$fixture" --tag v0.0.0-test --repo-root "$fixture"
  if ! assert_eq "1" "$last_rc" "missing workflow artifacts exit code"; then
    dump_last_run
    return 1
  fi

  local output
  output="$(read_combined_output "$fixture")"
  if ! assert_contains "$output" "no workflow artifacts found under" "missing workflow artifacts message"; then
    dump_last_run
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

run_test test_builder_writes_bundle_and_required_assets
run_test test_builder_fails_when_notices_is_missing
run_test test_builder_fails_when_no_workflow_artifacts_exist

if [[ "$tests_failed" -ne 0 ]]; then
  printf 'FAIL: %d/%d tests failed\n' "$tests_failed" "$tests_total" >&2
  exit 1
fi

printf 'PASS: %d tests\n' "$tests_total"
