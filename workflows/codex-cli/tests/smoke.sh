#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workflow_dir="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$workflow_dir/../.." && pwd)"

fail() {
  echo "error: $*" >&2
  exit 1
}

require_bin() {
  local binary="$1"
  command -v "$binary" >/dev/null 2>&1 || fail "missing required binary: $binary"
}

assert_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "missing required file: $path"
}

assert_exec() {
  local path="$1"
  [[ -x "$path" ]] || fail "script must be executable: $path"
}

toml_string() {
  local file="$1"
  local key="$2"
  awk -F'=' -v key="$key" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      value=$2
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

plist_to_json() {
  local plist_file="$1"
  if command -v plutil >/dev/null 2>&1; then
    plutil -convert json -o - "$plist_file"
    return
  fi

  python3 - "$plist_file" <<'PY'
import json
import plistlib
import sys

with open(sys.argv[1], 'rb') as f:
    payload = plistlib.load(f)
print(json.dumps(payload))
PY
}

assert_jq_file() {
  local file="$1"
  local filter="$2"
  local message="$3"
  if ! jq -e "$filter" "$file" >/dev/null; then
    fail "$message (jq: $filter)"
  fi
}

assert_jq_json() {
  local json_payload="$1"
  local filter="$2"
  local message="$3"
  if ! jq -e "$filter" >/dev/null <<<"$json_payload"; then
    fail "$message (jq: $filter)"
  fi
}

wait_for_file_contains() {
  local file="$1"
  local pattern="$2"
  local timeout_seconds="${3:-5}"
  local waited=0
  while [[ "$waited" -lt "$timeout_seconds" ]]; do
    if [[ -f "$file" ]] && rg -n --fixed-strings "$pattern" "$file" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

for required in \
  workflow.toml \
  README.md \
  src/info.plist.template \
  src/assets/icon.png \
  scripts/script_filter.sh \
  scripts/script_filter_auth.sh \
  scripts/script_filter_auth_use.sh \
  scripts/script_filter_diag.sh \
  scripts/script_filter_diag_all.sh \
  scripts/script_filter_save.sh \
  scripts/action_open.sh \
  scripts/prepare_package.sh \
  tests/smoke.sh; do
  assert_file "$workflow_dir/$required"
done

for executable in \
  scripts/script_filter.sh \
  scripts/script_filter_auth.sh \
  scripts/script_filter_auth_use.sh \
  scripts/script_filter_diag.sh \
  scripts/script_filter_diag_all.sh \
  scripts/script_filter_save.sh \
  scripts/action_open.sh \
  scripts/prepare_package.sh \
  tests/smoke.sh; do
  assert_exec "$workflow_dir/$executable"
done

require_bin jq
require_bin rg

manifest="$workflow_dir/workflow.toml"
[[ "$(toml_string "$manifest" id)" == "codex-cli" ]] || fail "workflow id mismatch"
[[ "$(toml_string "$manifest" script_filter)" == "script_filter.sh" ]] || fail "script_filter mismatch"
[[ "$(toml_string "$manifest" action)" == "action_open.sh" ]] || fail "action mismatch"
if rg -n '^rust_binary[[:space:]]*=' "$manifest" >/dev/null; then
  fail "rust_binary must be omitted for external codex-cli runtime"
fi
if ! rg -n '^CODEX_CLI_BIN[[:space:]]*=[[:space:]]*""' "$manifest" >/dev/null; then
  fail "CODEX_CLI_BIN default must be empty"
fi
if ! rg -n '^CODEX_SECRET_DIR[[:space:]]*=[[:space:]]*""' "$manifest" >/dev/null; then
  fail "CODEX_SECRET_DIR default must be empty"
fi
if ! rg -n '^CODEX_SHOW_ASSESSMENT[[:space:]]*=[[:space:]]*"0"' "$manifest" >/dev/null; then
  fail "CODEX_SHOW_ASSESSMENT default must be 0"
fi
if ! rg -n '^CODEX_DIAG_CACHE_TTL_SECONDS[[:space:]]*=[[:space:]]*"300"' "$manifest" >/dev/null; then
  fail "CODEX_DIAG_CACHE_TTL_SECONDS default must be 300"
fi
if ! rg -n '^CODEX_DIAG_CACHE_BLOCK_WAIT_SECONDS[[:space:]]*=[[:space:]]*"15"' "$manifest" >/dev/null; then
  fail "CODEX_DIAG_CACHE_BLOCK_WAIT_SECONDS default must be 15"
fi

tmp_dir="$(mktemp -d)"
artifact_id="$(toml_string "$manifest" id)"
artifact_version="$(toml_string "$manifest" version)"
artifact_name="$(toml_string "$manifest" name)"
artifact_path="$repo_root/dist/$artifact_id/$artifact_version/${artifact_name}.alfredworkflow"
artifact_sha_path="${artifact_path}.sha256"

artifact_backup=""
if [[ -f "$artifact_path" ]]; then
  artifact_backup="$tmp_dir/$(basename "$artifact_path").backup"
  cp "$artifact_path" "$artifact_backup"
fi

artifact_sha_backup=""
if [[ -f "$artifact_sha_path" ]]; then
  artifact_sha_backup="$tmp_dir/$(basename "$artifact_sha_path").backup"
  cp "$artifact_sha_path" "$artifact_sha_backup"
fi

cleanup() {
  if [[ -n "$artifact_backup" && -f "$artifact_backup" ]]; then
    mkdir -p "$(dirname "$artifact_path")"
    cp "$artifact_backup" "$artifact_path"
  else
    rm -f "$artifact_path"
  fi

  if [[ -n "$artifact_sha_backup" && -f "$artifact_sha_backup" ]]; then
    mkdir -p "$(dirname "$artifact_sha_path")"
    cp "$artifact_sha_backup" "$artifact_sha_path"
  else
    rm -f "$artifact_sha_path"
  fi

  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/stubs"

cat >"$tmp_dir/stubs/codex-cli-ok" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${CODEX_STUB_LOG:-}" ]]; then
  printf '%s\n' "$*" >>"$CODEX_STUB_LOG"
fi

if [[ "${1:-}" == "--version" ]]; then
  echo "codex-cli 0.3.2"
  exit 0
fi

case "${1:-}" in
auth)
  case "${2:-}" in
  login)
    printf '{"ok":true,"cmd":"auth login","argv":"%s"}\n' "$*"
    ;;
  current)
    echo "codex: /tmp/auth.json matches beta.json"
    ;;
  save)
    printf '{"ok":true,"cmd":"auth save","argv":"%s"}\n' "$*"
    ;;
  use)
    [[ -n "${3:-}" ]] || {
      echo "missing auth use target" >&2
      exit 64
    }
    printf '{"ok":true,"cmd":"auth use","target":"%s","argv":"%s"}\n' "${3:-}" "$*"
    ;;
  *)
    echo "unexpected auth command: $*" >&2
    exit 9
    ;;
  esac
  ;;
diag)
  [[ "${2:-}" == "rate-limits" ]] || {
    echo "unexpected diag command: $*" >&2
    exit 9
  }
  printf '{"ok":true,"cmd":"diag rate-limits","argv":"%s"}\n' "$*"
  ;;
*)
  echo "unexpected command: $*" >&2
  exit 9
  ;;
esac
EOS
chmod +x "$tmp_dir/stubs/codex-cli-ok"

cat >"$tmp_dir/stubs/codex-cli-fail" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "simulated codex-cli failure: $*" >&2
exit 7
EOS
chmod +x "$tmp_dir/stubs/codex-cli-fail"

cat >"$tmp_dir/stubs/codex-cli-browser-url" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "auth" && "${2:-}" == "login" ]]; then
  echo "Starting local login server on http://localhost:1455."
  echo "If your browser did not open, navigate to this URL to authenticate:"
  echo "https://auth.openai.com/oauth/authorize?foo=bar&state=test"
  echo "Successfully logged in"
  exit 0
fi
echo "unexpected command: $*" >&2
exit 9
EOS
chmod +x "$tmp_dir/stubs/codex-cli-browser-url"

cat >"$tmp_dir/stubs/codex-cli-api-key-stdin" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  echo "codex-cli 0.3.2"
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "login" && "${3:-}" == "--api-key" ]]; then
  if [[ -n "${CODEX_STUB_LOG:-}" ]]; then
    printf '%s\n' "$*" >>"$CODEX_STUB_LOG"
  fi
  read -r key || true
  [[ -n "$key" ]] || {
    echo "missing api key from stdin" >&2
    exit 65
  }
  if [[ -n "${CODEX_STDIN_OUT:-}" ]]; then
    printf '%s\n' "$key" >"$CODEX_STDIN_OUT"
  fi
  echo "api-key login ok"
  exit 0
fi
echo "unexpected command: $*" >&2
exit 9
EOS
chmod +x "$tmp_dir/stubs/codex-cli-api-key-stdin"

cat >"$tmp_dir/stubs/codex-cli-device-code" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  echo "codex-cli 0.3.2"
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "login" && "${3:-}" == "--device-code" ]]; then
  echo "Go to https://chatgpt.com/device and enter the one-time code:"
  echo "ABCD-EFGH."
  echo "Done"
  exit 0
fi
echo "unexpected command: $*" >&2
exit 9
EOS
chmod +x "$tmp_dir/stubs/codex-cli-device-code"

cat >"$tmp_dir/stubs/codex-cli-hang" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  echo "codex-cli 0.3.2"
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "login" ]]; then
  sleep 5
  exit 0
fi
echo "unexpected command: $*" >&2
exit 9
EOS
chmod +x "$tmp_dir/stubs/codex-cli-hang"

cat >"$tmp_dir/stubs/codex-cli-capture-secret-dir" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  echo "codex-cli 0.3.2"
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "save" ]]; then
  if [[ -n "${CODEX_SECRET_DIR_OUT:-}" ]]; then
    printf '%s\n' "${CODEX_SECRET_DIR:-}" >"$CODEX_SECRET_DIR_OUT"
  fi
  echo "save ok"
  exit 0
fi
echo "unexpected command: $*" >&2
exit 9
EOS
chmod +x "$tmp_dir/stubs/codex-cli-capture-secret-dir"

cat >"$tmp_dir/stubs/codex-cli-save-requires-yes" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${CODEX_STUB_LOG:-}" ]]; then
  printf '%s\n' "$*" >>"$CODEX_STUB_LOG"
fi
if [[ "${1:-}" == "--version" ]]; then
  echo "codex-cli 0.3.2"
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "save" ]]; then
  force_overwrite=0
  secret="${3:-}"
  if [[ "${3:-}" == "--yes" ]]; then
    force_overwrite=1
    secret="${4:-}"
  fi
  [[ -n "$secret" ]] || {
    echo "missing secret name" >&2
    exit 64
  }
  [[ -n "${CODEX_SECRET_DIR:-}" ]] || {
    echo "missing CODEX_SECRET_DIR" >&2
    exit 65
  }
  target_path="${CODEX_SECRET_DIR%/}/${secret}"
  if [[ "$force_overwrite" -ne 1 && -f "$target_path" ]]; then
    echo "secret exists: $secret (use --yes)" >&2
    exit 73
  fi
  mkdir -p "${CODEX_SECRET_DIR%/}"
  printf '{"saved":"%s"}\n' "$secret" >"$target_path"
  echo "save ok"
  exit 0
fi
echo "unexpected command: $*" >&2
exit 9
EOS
chmod +x "$tmp_dir/stubs/codex-cli-save-requires-yes"

cat >"$tmp_dir/stubs/codex-cli-diag-all-json" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${CODEX_STUB_LOG:-}" ]]; then
  printf '%s\n' "$*" >>"$CODEX_STUB_LOG"
fi
if [[ "${1:-}" == "--version" ]]; then
  echo "codex-cli 0.3.2"
  exit 0
fi
if [[ "${1:-}" == "diag" && "${2:-}" == "rate-limits" && "${3:-}" == "--all" && "${4:-}" == "--json" ]]; then
  cat <<'JSON'
{"schema_version":"1.0","command":"diag rate-limits --all --json","mode":"multi","ok":true,"results":[{"name":"sym","status":"ok","summary":{"non_weekly_label":"5h","non_weekly_remaining":76,"weekly_remaining":88,"weekly_reset_epoch":1771352340,"weekly_reset_local":"2026-02-18 02:19 +08:00"},"source":"sym.json","raw_usage":{"email":"sym@example.com"}},{"name":"poies","status":"ok","summary":{"non_weekly_label":"5h","non_weekly_remaining":48,"weekly_remaining":54,"weekly_reset_epoch":1771265976,"weekly_reset_local":"2026-02-17 02:19 +08:00"},"source":"poies.json","raw_usage":{"email":"poies@example.com"}}]}
JSON
  exit 0
fi
if [[ "${1:-}" == "diag" && "${2:-}" == "rate-limits" && "${3:-}" == "--json" ]]; then
  cat <<'JSON'
{"schema_version":"1.0","command":"diag rate-limits --json","mode":"single","ok":true,"result":{"name":"auth","status":"ok","summary":{"non_weekly_label":"5h","non_weekly_remaining":61,"weekly_remaining":11,"weekly_reset_epoch":1771265976,"weekly_reset_local":"2026-02-17 02:19 +08:00"},"source":"network","raw_usage":{"email":"auth@example.com"}}}
JSON
  exit 0
fi
echo "unexpected command: $*" >&2
exit 9
EOS
chmod +x "$tmp_dir/stubs/codex-cli-diag-all-json"

cat >"$tmp_dir/stubs/codex-cli-diag-plain" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${CODEX_STUB_LOG:-}" ]]; then
  printf '%s\n' "$*" >>"$CODEX_STUB_LOG"
fi
if [[ "${1:-}" == "--version" ]]; then
  echo "codex-cli 0.3.2"
  exit 0
fi
if [[ "${1:-}" == "diag" && "${2:-}" == "rate-limits" && "${3:-}" == "--json" ]]; then
  cat <<'JSON'
{"schema_version":"1.0","command":"diag rate-limits --json","mode":"single","ok":true,"result":{"name":"auth","status":"ok","summary":{"non_weekly_label":"5h","non_weekly_remaining":84,"weekly_remaining":65,"weekly_reset_epoch":1771265976,"weekly_reset_local":"2026-02-19 06:51 +08:00"},"source":"network","raw_usage":{"email":"plain@example.com"}}}
JSON
  exit 0
fi
if [[ "${1:-}" == "diag" && "${2:-}" == "rate-limits" ]]; then
  cat <<'OUT'
Rate limits remaining
5h 84% • 02-12 16:52
Weekly 65% • 02-19 06:51
OUT
  exit 0
fi
echo "unexpected command: $*" >&2
exit 9
EOS
chmod +x "$tmp_dir/stubs/codex-cli-diag-plain"

cat >"$tmp_dir/stubs/codex-cli-current-nonzero" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  echo "codex-cli 0.3.2"
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "current" ]]; then
  echo "codex: /tmp/auth.json matches sym (identity; secret differs)"
  exit 3
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "use" ]]; then
  printf '{"ok":true,"cmd":"auth use","target":"%s","argv":"%s"}\n' "${3:-}" "$*"
  exit 0
fi
echo "unexpected command: $*" >&2
exit 9
EOS
chmod +x "$tmp_dir/stubs/codex-cli-current-nonzero"

cat >"$tmp_dir/stubs/codex-cli-current-mismatch" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  echo "codex-cli 0.3.2"
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "current" ]]; then
  echo "codex: /tmp/auth.json matches sym (identity; secret differs)"
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "use" ]]; then
  printf '{"ok":true,"cmd":"auth use","target":"%s","argv":"%s"}\n' "${3:-}" "$*"
  exit 0
fi
if [[ "${1:-}" == "diag" && "${2:-}" == "rate-limits" ]]; then
  printf '{"ok":true,"cmd":"diag rate-limits","argv":"%s"}\n' "$*"
  exit 0
fi
echo "unexpected command: $*" >&2
exit 9
EOS
chmod +x "$tmp_dir/stubs/codex-cli-current-mismatch"

cat >"$tmp_dir/stubs/codex-cli-current-auth-file-only" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  echo "codex-cli 0.3.2"
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "current" ]]; then
  echo "codex: ${CODEX_AUTH_FILE:-/tmp/auth.json}"
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "use" ]]; then
  printf '{"ok":true,"cmd":"auth use","target":"%s","argv":"%s"}\n' "${3:-}" "$*"
  exit 0
fi
echo "unexpected command: $*" >&2
exit 9
EOS
chmod +x "$tmp_dir/stubs/codex-cli-current-auth-file-only"

cat >"$tmp_dir/stubs/codex-cli-current-json-hint" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  echo "codex-cli 0.3.2"
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "current" && "${3:-}" == "--json" ]]; then
  cat <<JSON
{"schema_version":"codex-cli.auth.v1","command":"auth current","ok":true,"result":{"auth_file":"${CODEX_AUTH_FILE:-/tmp/auth.json}","matched":true,"matched_secret":"plus.json","match_mode":"identity"}}
JSON
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "current" ]]; then
  echo "codex: ${CODEX_AUTH_FILE:-/tmp/auth.json}"
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "use" ]]; then
  printf '{"ok":true,"cmd":"auth use","target":"%s","argv":"%s"}\n' "${3:-}" "$*"
  exit 0
fi
echo "unexpected command: $*" >&2
exit 9
EOS
chmod +x "$tmp_dir/stubs/codex-cli-current-json-hint"

empty_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" ""; })"
assert_jq_json "$empty_json" '.items | type == "array" and length >= 8' "empty query must return action items"
assert_jq_json "$empty_json" '.items | any(.title == "Implemented now: auth login") | not' "assessment items must be hidden by default"
assert_jq_json "$empty_json" '.items | any(.arg == "diag::default" and .valid == true)' "diag action item missing"
assert_jq_json "$empty_json" '.items | any(.title == "codex-cli detected" or (.subtitle | startswith("Runtime ready:"))) | not' "runtime ready row must be hidden when binary exists"

missing_runtime_json="$({ PATH="/usr/bin:/bin" CODEX_CLI_BIN="$tmp_dir/stubs/does-not-exist" "$workflow_dir/scripts/script_filter.sh" ""; })"
assert_jq_json "$missing_runtime_json" '.items[0].title == "codex-cli runtime missing"' "missing binary should show runtime missing item"

help_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "help"; })"
assert_jq_json "$help_json" '.items | any(.title == "Can be added next: auth use/refresh/current/sync") | not' "help should hide extension assessment by default"

help_assessment_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "help --assessment"; })"
assert_jq_json "$help_assessment_json" '.items | any(.title == "Implemented now: auth login")' "help --assessment should include assessment items"

auth_root_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "auth"; })"
assert_jq_json "$auth_root_json" '.items | any(.arg == "login::browser")' "auth root should include login actions"
assert_jq_json "$auth_root_json" '.items | any(.arg == "diag::default") | not' "auth root should hide diag actions"

login_api_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "login --api-key"; })"
assert_jq_json "$login_api_json" '.items[0].arg == "login::api-key"' "login api-key mapping mismatch"
assert_jq_json "$login_api_json" '.items[0].valid == true' "login api-key item must be valid"

login_device_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "auth login device"; })"
assert_jq_json "$login_device_json" '.items[0].arg == "login::device-code"' "login device-code mapping mismatch"

save_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "save team-alpha"; })"
assert_jq_json "$save_json" '.items[0].arg == "save::team-alpha.json::0"' "save command should normalize json suffix"
assert_jq_json "$save_json" '.items[1].arg == "save::team-alpha.json::1"' "save command should offer --yes variant"

save_yes_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "save --yes team-alpha.json"; })"
assert_jq_json "$save_yes_json" '.items[0].arg == "save::team-alpha.json::1"' "save --yes mapping mismatch"

save_yes_short_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "--yes team-alpha.json"; })"
assert_jq_json "$save_yes_short_json" '.items[0].arg == "save::team-alpha.json::1"' "implicit --yes save mapping mismatch"

use_secret_dir="$tmp_dir/secrets"
mkdir -p "$use_secret_dir"
printf '{"email":"alpha@example.com"}\n' >"$use_secret_dir/alpha.json"
printf '{"email":"beta@example.com"}\n' >"$use_secret_dir/beta.json"

auth_use_json="$({ CODEX_SECRET_DIR="$use_secret_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "auth use"; })"
assert_jq_json "$auth_use_json" '.items[0].title == "Current: beta.json"' "auth use should show current secret on first row"
assert_jq_json "$auth_use_json" '.items[0].subtitle | contains("beta@example.com | reset -")' "auth use current row should include email and reset subtitle"
assert_jq_json "$auth_use_json" '.items | any(.title == "alpha.json" and .arg == "use::alpha" and .valid == true)' "auth use should list alpha.json"
assert_jq_json "$auth_use_json" '.items | any(.title == "beta.json" and .arg == "use::beta" and .valid == true)' "auth use should list beta.json"
assert_jq_json "$auth_use_json" '.items | any(.title == "alpha.json" and (.subtitle | contains("alpha@example.com | reset -")))' "auth use list rows should include secret email and reset subtitle"

auth_use_direct_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "auth use alpha"; })"
assert_jq_json "$auth_use_direct_json" '.items[0].arg == "use::alpha"' "auth use alpha should map to use::alpha"
assert_jq_json "$auth_use_direct_json" '.items[0].valid == true' "auth use alpha item must be valid"

auth_use_nonzero_current_json="$({ CODEX_SECRET_DIR="$use_secret_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-current-nonzero" "$workflow_dir/scripts/script_filter.sh" "auth use"; })"
assert_jq_json "$auth_use_nonzero_current_json" '.items[0].title == "Current: sym.json"' "auth use should parse current secret even when auth current exits non-zero"

account_match_secret_dir="$tmp_dir/secrets-account-match"
mkdir -p "$account_match_secret_dir"
printf '{"tokens":{"account_id":"account-plus"}}\n' >"$account_match_secret_dir/plus.json"
printf '{"tokens":{"account_id":"account-sym"}}\n' >"$account_match_secret_dir/sym.json"
account_match_auth_file="$tmp_dir/auth-account-match.json"
printf '{"tokens":{"account_id":"account-plus"}}\n' >"$account_match_auth_file"
auth_use_account_match_json="$({ CODEX_SECRET_DIR="$account_match_secret_dir" CODEX_AUTH_FILE="$account_match_auth_file" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-current-mismatch" "$workflow_dir/scripts/script_filter.sh" "auth use"; })"
assert_jq_json "$auth_use_account_match_json" '.items[0].title == "Current: plus.json"' "auth use should prefer account_id match over stale auth current label"

auth_file_only_secret_dir="$tmp_dir/secrets-auth-file-only"
mkdir -p "$auth_file_only_secret_dir"
printf '{"email":"alpha-fallback@example.com","token":"a"}\n' >"$auth_file_only_secret_dir/alpha.json"
printf '{"email":"beta-fallback@example.com","token":"b"}\n' >"$auth_file_only_secret_dir/beta.json"
auth_file_only_path="$tmp_dir/auth.json"
printf '{"email":"alpha-fallback@example.com","token":"live-rotated"}\n' >"$auth_file_only_path"
auth_use_auth_file_only_json="$({ CODEX_SECRET_DIR="$auth_file_only_secret_dir" CODEX_AUTH_FILE="$auth_file_only_path" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-current-auth-file-only" "$workflow_dir/scripts/script_filter.sh" "auth use"; })"
assert_jq_json "$auth_use_auth_file_only_json" '.items[0].title == "Current: alpha.json"' "auth use should resolve matched secret instead of showing auth.json"

auth_only_home="$tmp_dir/home-auth-only"
mkdir -p "$auth_only_home/.config/codex-kit"
printf '{"email":"auth-only@example.com","token":"x"}\n' >"$auth_only_home/.config/codex-kit/auth.json"
auth_use_without_secret_dir_json="$({ HOME="$auth_only_home" CODEX_SECRET_DIR="$tmp_dir/missing-secrets" CODEX_AUTH_FILE="$auth_only_home/.config/codex-kit/auth.json" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-current-auth-file-only" "$workflow_dir/scripts/script_filter_auth_use.sh" ""; })"
assert_jq_json "$auth_use_without_secret_dir_json" '.items[0].title == "Current: auth.json"' "cxau should show auth.json current row when no saved secrets directory"
assert_jq_json "$auth_use_without_secret_dir_json" '.items[0].subtitle | contains("auth-only@example.com")' "cxau auth.json row should include auth email"

json_hint_secret_dir="$tmp_dir/secrets-json-hint"
mkdir -p "$json_hint_secret_dir"
printf '{"token":"live-plus"}\n' >"$json_hint_secret_dir/plus.json"
printf '{"token":"live-poies"}\n' >"$json_hint_secret_dir/poies.json"
json_hint_auth_file="$tmp_dir/auth-json-hint.json"
printf '{"token":"rotated"}\n' >"$json_hint_auth_file"
auth_use_json_hint_json="$({ CODEX_SECRET_DIR="$json_hint_secret_dir" CODEX_AUTH_FILE="$json_hint_auth_file" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-current-json-hint" "$workflow_dir/scripts/script_filter.sh" "auth use"; })"
assert_jq_json "$auth_use_json_hint_json" '.items[0].title == "Current: plus.json"' "auth use should use auth current --json matched_secret when text output lacks matches"

invalid_save_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "save ../bad"; })"
assert_jq_json "$invalid_save_json" '.items[0].title == "Invalid secret file name"' "invalid save file name should be rejected"
assert_jq_json "$invalid_save_json" '.items[0].valid == false' "invalid save item must be invalid"

diag_menu_cache_dir="$tmp_dir/diag-menu-cache"

diag_async_json="$({ ALFRED_WORKFLOW_CACHE="$diag_menu_cache_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "diag async"; })"
assert_jq_json "$diag_async_json" '.items[0].arg == "diag::async"' "diag async mapping mismatch"
assert_jq_json "$diag_async_json" '.items | any(.title == "Also available: --cached / --one-line / --all / all-json / async")' "diag alternatives hint missing"
assert_jq_json "$diag_async_json" '.items | any(.title == "Latest diag result unavailable")' "diag menu should show latest-result availability row"

diag_all_json_query_json="$({ ALFRED_WORKFLOW_CACHE="$diag_menu_cache_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "diag all-json"; })"
assert_jq_json "$diag_all_json_query_json" '.items[0].arg == "diag::all-json"' "diag all-json mapping mismatch"
assert_jq_json "$diag_all_json_query_json" '.items | any(.title == "Diag result ready (all-json)")' "diag all-json menu should block-refresh and show ready result"

alias_auth_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter_auth.sh" "login --device-code"; })"
assert_jq_json "$alias_auth_json" '.items[0].arg == "login::device-code"' "cxa wrapper should map to auth login device-code"

alias_auth_use_json="$({ CODEX_SECRET_DIR="$use_secret_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter_auth_use.sh" ""; })"
assert_jq_json "$alias_auth_use_json" '.items[0].title == "Current: beta.json"' "cxau wrapper should show current secret first"
assert_jq_json "$alias_auth_use_json" '.items | any(.arg == "use::alpha")' "cxau wrapper should list use::alpha selection"

alias_auth_use_direct_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter_auth_use.sh" "alpha"; })"
assert_jq_json "$alias_auth_use_direct_json" '.items[0].arg == "use::alpha"' "cxau alpha should map to use::alpha"

alias_diag_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter_diag.sh" ""; })"
assert_jq_json "$alias_diag_json" '.items[0].arg == "diag::default"' "cxd wrapper should map empty query to diag default"
assert_jq_json "$alias_diag_json" '(.items | any(.title == "Also available: --cached / --one-line / --all / all-json / async")) | not' "cxd wrapper should hide alternatives hint row"
assert_jq_json "$alias_diag_json" '(.items | map(.subtitle // "") | any(contains("diag rate-limits --json")))' "cxd wrapper should include diag command in subtitle text"

alias_diag_plain_cache_dir="$tmp_dir/diag-plain-cache"
alias_diag_plain_log="$tmp_dir/diag-plain.log"
alias_diag_plain_json="$({ CODEX_STUB_LOG="$alias_diag_plain_log" ALFRED_WORKFLOW_CACHE="$alias_diag_plain_cache_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-diag-plain" "$workflow_dir/scripts/script_filter_diag.sh" ""; })"
assert_jq_json "$alias_diag_plain_json" '(.items | any(.title == "Rate limits remaining")) | not' "cxd wrapper should hide plain-text rate-limits heading row"
assert_jq_json "$alias_diag_plain_json" '.items | any(.title | test("^auth \\| 5h 84% \\([^)]*\\) \\| weekly 65% \\([^)]*\\)$"))' "cxd wrapper should parse single-account json rows"
wait_for_file_contains "$alias_diag_plain_log" "diag rate-limits --json" 5 || fail "cxd wrapper should refresh default diag cache via --json"

alias_diag_all_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter_diag_all.sh" ""; })"
assert_jq_json "$alias_diag_all_json" '.items[0].arg == "diag::all-json"' "cxda wrapper should map empty query to diag all-json"
assert_jq_json "$alias_diag_all_json" '(.items | any(.title == "Also available: --cached / --one-line / --all / all-json / async")) | not' "cxda wrapper should hide alternatives hint row"

diag_auto_cache_dir="$tmp_dir/diag-auto-cache"
diag_auto_log="$tmp_dir/diag-auto.log"
rm -f "$diag_auto_log"

CODEX_STUB_LOG="$diag_auto_log" ALFRED_WORKFLOW_CACHE="$diag_auto_cache_dir" CODEX_DIAG_CACHE_TTL_SECONDS=300 CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" \
  "$workflow_dir/scripts/script_filter_diag.sh" "" >/dev/null

diag_auto_meta="$diag_auto_cache_dir/diag-rate-limits.last.meta"
wait_for_file_contains "$diag_auto_meta" "mode=default" 5 || fail "cxd should block-refresh default diag cache"
wait_for_file_contains "$diag_auto_log" "diag rate-limits --json" 5 || fail "cxd block-refresh should run diag rate-limits --json"

diag_auto_diag_count_before="$(rg -c '^diag rate-limits --json$' "$diag_auto_log" 2>/dev/null || true)"
CODEX_STUB_LOG="$diag_auto_log" ALFRED_WORKFLOW_CACHE="$diag_auto_cache_dir" CODEX_DIAG_CACHE_TTL_SECONDS=300 CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" \
  "$workflow_dir/scripts/script_filter_diag.sh" "" >/dev/null
sleep 1
diag_auto_diag_count_after="$(rg -c '^diag rate-limits --json$' "$diag_auto_log" 2>/dev/null || true)"
[[ "$diag_auto_diag_count_after" == "$diag_auto_diag_count_before" ]] || fail "fresh cxd cache should skip repeated block-refresh"

diag_auto_all_cache_dir="$tmp_dir/diag-auto-all-cache"
diag_auto_all_log="$tmp_dir/diag-auto-all.log"
rm -f "$diag_auto_all_log"

CODEX_SECRET_DIR="$use_secret_dir" CODEX_STUB_LOG="$diag_auto_all_log" ALFRED_WORKFLOW_CACHE="$diag_auto_all_cache_dir" CODEX_DIAG_CACHE_TTL_SECONDS=300 CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" \
  "$workflow_dir/scripts/script_filter_diag_all.sh" "" >/dev/null

diag_auto_all_meta="$diag_auto_all_cache_dir/diag-rate-limits.last.meta"
wait_for_file_contains "$diag_auto_all_meta" "mode=all-json" 5 || fail "cxda should block-refresh all-json cache"
wait_for_file_contains "$diag_auto_all_log" "diag rate-limits --all --json" 5 || fail "cxda block-refresh should run diag rate-limits --all --json"

diag_auto_all_fallback_cache_dir="$tmp_dir/diag-auto-all-fallback-cache"
diag_auto_all_fallback_log="$tmp_dir/diag-auto-all-fallback.log"
rm -f "$diag_auto_all_fallback_log"

CODEX_SECRET_DIR="$tmp_dir/missing-secrets-for-diag" CODEX_STUB_LOG="$diag_auto_all_fallback_log" ALFRED_WORKFLOW_CACHE="$diag_auto_all_fallback_cache_dir" CODEX_DIAG_CACHE_TTL_SECONDS=300 CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-diag-all-json" \
  "$workflow_dir/scripts/script_filter_diag_all.sh" "" >/dev/null

diag_auto_all_fallback_meta="$diag_auto_all_fallback_cache_dir/diag-rate-limits.last.meta"
wait_for_file_contains "$diag_auto_all_fallback_meta" "command=diag rate-limits --json" 5 || fail "cxda block-refresh should fallback to current-auth --json when no saved secrets"
wait_for_file_contains "$diag_auto_all_fallback_log" "diag rate-limits --json" 5 || fail "cxda fallback should run diag rate-limits --json"

auth_only_cache_home="$tmp_dir/home-auth-cache"
mkdir -p "$auth_only_cache_home/.config/codex-kit"
printf '{"token":"x"}\n' >"$auth_only_cache_home/.config/codex-kit/auth.json"
auth_use_with_diag_cache_json="$({ HOME="$auth_only_cache_home" CODEX_SECRET_DIR="$tmp_dir/missing-secrets-for-diag" CODEX_AUTH_FILE="$auth_only_cache_home/.config/codex-kit/auth.json" ALFRED_WORKFLOW_CACHE="$diag_auto_all_fallback_cache_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-current-auth-file-only" "$workflow_dir/scripts/script_filter_auth_use.sh" ""; })"
assert_jq_json "$auth_use_with_diag_cache_json" '.items[0].title == "Current: auth.json"' "cxau auth.json current row should keep simple current title"
assert_jq_json "$auth_use_with_diag_cache_json" '.items[0].subtitle | contains("auth@example.com | reset 2026-02-17 02:19 +08:00")' "cxau auth.json current row should include latest cached email/reset"

diag_all_with_auth_cache_json="$({ HOME="$auth_only_cache_home" CODEX_SECRET_DIR="$tmp_dir/missing-secrets-for-diag" CODEX_AUTH_FILE="$auth_only_cache_home/.config/codex-kit/auth.json" ALFRED_WORKFLOW_CACHE="$diag_auto_all_fallback_cache_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-current-auth-file-only" "$workflow_dir/scripts/script_filter_diag_all.sh" ""; })"
assert_jq_json "$diag_all_with_auth_cache_json" '.items | any(.title == "Current auth: auth.json" and (.subtitle | contains("auth@example.com | reset 2026-02-17 02:19 +08:00")))' "cxda current auth row should include cached email/reset when auth.json lacks email"

alias_save_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter_save.sh" "team-alpha"; })"
assert_jq_json "$alias_save_json" '.items[0].arg == "save::team-alpha.json::0"' "cxs wrapper should map to save command"
assert_jq_json "$alias_save_json" '.items[1].arg == "save::team-alpha.json::1"' "cxs wrapper should expose --yes variant"

alias_save_yes_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter_save.sh" "--yes team-alpha.json"; })"
assert_jq_json "$alias_save_yes_json" '.items[0].arg == "save::team-alpha.json::1"' "cxs --yes should map to save::...::1"

unknown_json="$({ CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "totally-unknown-command"; })"
assert_jq_json "$unknown_json" '.items[0].title | startswith("Unknown command:")' "unknown query should show guidance"

set +e
CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/action_open.sh" >/dev/null 2>&1
action_noarg_rc=$?
set -e
[[ "$action_noarg_rc" -eq 2 ]] || fail "action_open.sh without args must exit 2"

action_log="$tmp_dir/action.log"
cat >"$tmp_dir/bin/osascript" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$OSASCRIPT_STUB_LOG"
if [[ "${OSASCRIPT_STUB_FORCE_FAIL:-0}" == "1" ]]; then
  exit 1
fi
exit 0
EOS
chmod +x "$tmp_dir/bin/osascript"
export PATH="$tmp_dir/bin:$PATH"
export OSASCRIPT_STUB_LOG="$tmp_dir/osascript.log"

CODEX_STUB_LOG="$action_log" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" \
  "$workflow_dir/scripts/action_open.sh" "login::browser" >/dev/null
[[ "$(tail -n1 "$action_log")" == "auth login" ]] || fail "login::browser should execute auth login"

CODEX_API_KEY="sk-smoke-bootstrap" CODEX_STUB_LOG="$action_log" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" \
  "$workflow_dir/scripts/action_open.sh" "login::api-key" >/dev/null
[[ "$(tail -n1 "$action_log")" == "auth login --api-key" ]] || fail "login::api-key should execute auth login --api-key"

api_key_stdin_out="$tmp_dir/api-key-stdin.out"
CODEX_API_KEY="sk-test-smoke-key" CODEX_STUB_LOG="$action_log" CODEX_STDIN_OUT="$api_key_stdin_out" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-api-key-stdin" \
  "$workflow_dir/scripts/action_open.sh" "login::api-key" >/dev/null
[[ "$(tail -n1 "$action_log")" == "auth login --api-key" ]] || fail "api-key login should keep command mapping"
[[ "$(cat "$api_key_stdin_out")" == "sk-test-smoke-key" ]] || fail "api-key login must pass CODEX_API_KEY via stdin"

CODEX_STUB_LOG="$action_log" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" \
  "$workflow_dir/scripts/action_open.sh" "use::alpha" >/dev/null
[[ "$(tail -n1 "$action_log")" == "auth use alpha" ]] || fail "use mapping mismatch"

CODEX_STUB_LOG="$action_log" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" \
  "$workflow_dir/scripts/action_open.sh" "save::team-alpha.json::0" >/dev/null
[[ "$(tail -n1 "$action_log")" == "auth save team-alpha.json" ]] || fail "save without yes mapping mismatch"

CODEX_STUB_LOG="$action_log" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" \
  "$workflow_dir/scripts/action_open.sh" "save::team-alpha.json::1" >/dev/null
[[ "$(tail -n1 "$action_log")" == "auth save --yes team-alpha.json" ]] || fail "save --yes mapping mismatch"

save_overwrite_secret_dir="$tmp_dir/save-overwrite-secrets"
mkdir -p "$save_overwrite_secret_dir"
printf '{"old":"value"}\n' >"$save_overwrite_secret_dir/team-alpha.json"
CODEX_SECRET_DIR="$save_overwrite_secret_dir" CODEX_STUB_LOG="$action_log" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-save-requires-yes" \
  "$workflow_dir/scripts/action_open.sh" "save::team-alpha.json::0" >/dev/null
[[ "$(tail -n1 "$action_log")" == "auth save --yes team-alpha.json" ]] || fail "save confirmation should promote existing file overwrite to --yes"
if ! rg -n --fixed-strings '"saved":"team-alpha.json"' "$save_overwrite_secret_dir/team-alpha.json" >/dev/null; then
  fail "save overwrite should update existing secret file after confirmation"
fi

CODEX_SECRET_DIR="$save_overwrite_secret_dir" CODEX_STUB_LOG="$action_log" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-save-requires-yes" \
  "$workflow_dir/scripts/action_open.sh" "save::team-new.json::0" >/dev/null
[[ "$(tail -n1 "$action_log")" == "auth save team-new.json" ]] || fail "save for non-existing file should keep non-yes command"
if ! rg -n --fixed-strings '"saved":"team-new.json"' "$save_overwrite_secret_dir/team-new.json" >/dev/null; then
  fail "save should create new secret file without --yes when target does not exist"
fi

save_log_before="$(wc -l <"$action_log" | tr -d ' ')"
set +e
OSASCRIPT_STUB_FORCE_FAIL=1 CODEX_SAVE_CONFIRM=1 CODEX_STUB_LOG="$action_log" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" \
  "$workflow_dir/scripts/action_open.sh" "save::team-cancel.json::0" >/dev/null 2>&1
save_cancel_rc=$?
set -e
[[ "$save_cancel_rc" -eq 130 ]] || fail "save cancellation should return 130"
save_log_after="$(wc -l <"$action_log" | tr -d ' ')"
[[ "$save_log_after" == "$save_log_before" ]] || fail "cancelled save should not execute codex-cli auth save"

secret_home="$tmp_dir/home"
mkdir -p "$secret_home"
secret_dir_out="$tmp_dir/secret-dir.out"
CODEX_SECRET_DIR="" XDG_CONFIG_HOME="" HOME="$secret_home" CODEX_SECRET_DIR_OUT="$secret_dir_out" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-capture-secret-dir" \
  "$workflow_dir/scripts/action_open.sh" "save::team-alpha.json::0" >/dev/null
[[ "$(cat "$secret_dir_out")" == "$secret_home/.config/codex_secrets" ]] || fail "save should fallback CODEX_SECRET_DIR to ~/.config/codex_secrets"
[[ -d "$secret_home/.config/codex_secrets" ]] || fail "save should create fallback CODEX_SECRET_DIR"

diag_cache_dir="$tmp_dir/cache"

CODEX_STUB_LOG="$action_log" ALFRED_WORKFLOW_CACHE="$diag_cache_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" \
  "$workflow_dir/scripts/action_open.sh" "diag::cached" >/dev/null
[[ "$(tail -n1 "$action_log")" == "diag rate-limits --cached" ]] || fail "diag::cached mapping mismatch"

CODEX_SECRET_DIR="$use_secret_dir" CODEX_STUB_LOG="$action_log" ALFRED_WORKFLOW_CACHE="$diag_cache_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" \
  "$workflow_dir/scripts/action_open.sh" "diag::async" >/dev/null
[[ "$(tail -n1 "$action_log")" == "diag rate-limits --all --async --jobs 4" ]] || fail "diag::async mapping mismatch"

CODEX_SECRET_DIR="$use_secret_dir" CODEX_STUB_LOG="$action_log" ALFRED_WORKFLOW_CACHE="$diag_cache_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-diag-all-json" \
  "$workflow_dir/scripts/action_open.sh" "diag::all-json" >/dev/null
[[ "$(tail -n1 "$action_log")" == "diag rate-limits --all --json" ]] || fail "diag::all-json mapping mismatch"

CODEX_SECRET_DIR="$tmp_dir/missing-secrets-action" CODEX_STUB_LOG="$action_log" ALFRED_WORKFLOW_CACHE="$tmp_dir/cache-fallback" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-diag-all-json" \
  "$workflow_dir/scripts/action_open.sh" "diag::all-json" >/dev/null
[[ "$(tail -n1 "$action_log")" == "diag rate-limits --json" ]] || fail "diag::all-json should fallback to current auth json when no saved secrets"

diag_meta="$diag_cache_dir/diag-rate-limits.last.meta"
diag_output="$diag_cache_dir/diag-rate-limits.last.out"
diag_all_json_meta="$diag_cache_dir/diag-rate-limits.all-json.meta"
diag_all_json_output="$diag_cache_dir/diag-rate-limits.all-json.out"
diag_cached_meta="$diag_cache_dir/diag-rate-limits.cached.meta"
diag_default_meta="$diag_cache_dir/diag-rate-limits.default.meta"
[[ -f "$diag_meta" ]] || fail "diag action should write result metadata"
[[ -f "$diag_output" ]] || fail "diag action should write result output"
[[ -f "$diag_all_json_meta" ]] || fail "diag action should write all-json metadata cache"
[[ -f "$diag_all_json_output" ]] || fail "diag action should write all-json output cache"
[[ ! -f "$diag_cached_meta" ]] || fail "diag action should not persist cached mode-specific metadata"
[[ ! -f "$diag_default_meta" ]] || fail "diag action should not persist default mode-specific metadata"
if ! rg -n '^mode=all-json$' "$diag_meta" >/dev/null; then
  fail "diag metadata should track latest mode"
fi
if ! rg -n '^exit_code=0$' "$diag_meta" >/dev/null; then
  fail "diag metadata should store successful exit status"
fi
if ! rg -n '^command=diag rate-limits --all --json$' "$diag_meta" >/dev/null; then
  fail "diag metadata should store executed command"
fi

diag_all_json_menu_with_latest="$({ ALFRED_WORKFLOW_CACHE="$diag_cache_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "diag all-json"; })"
assert_jq_json "$diag_all_json_menu_with_latest" '.items | any(.title == "Diag result ready (all-json)")' "diag all-json menu should render latest result rows from cache"
assert_jq_json "$diag_all_json_menu_with_latest" '.items | any(.title | test("^sym \\| 5h 76% \\([^)]*\\) \\| weekly 88% \\([^)]*\\)$"))' "diag all-json menu should include parsed account rows"
# shellcheck disable=SC2016
assert_jq_json "$diag_all_json_menu_with_latest" '.items | map(.title) as $titles | (($titles | map(startswith("poies | 5h 48%")) | index(true)) < ($titles | map(startswith("sym | 5h 76%")) | index(true)))' "diag all-json menu should sort by earliest weekly reset first"

diag_result_json="$({ ALFRED_WORKFLOW_CACHE="$diag_cache_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter.sh" "diag result"; })"
assert_jq_json "$diag_result_json" '.items[0].title | startswith("Diag result ready")' "diag result should show summary item"
assert_jq_json "$diag_result_json" '.items | any(.title | test("^sym \\| 5h 76% \\([^)]*\\) \\| weekly 88% \\([^)]*\\)$"))' "diag result should include sym account row"
assert_jq_json "$diag_result_json" '.items | any(.title | test("^poies \\| 5h 48% \\([^)]*\\) \\| weekly 54% \\([^)]*\\)$"))' "diag result should include poies account row"
# shellcheck disable=SC2016
assert_jq_json "$diag_result_json" '.items | map(.title) as $titles | (($titles | map(startswith("poies | 5h 48%")) | index(true)) < ($titles | map(startswith("sym | 5h 76%")) | index(true)))' "diag result should sort by earliest weekly reset first"
assert_jq_json "$diag_result_json" '.items | any(.subtitle == "sym@example.com | reset 2026-02-18 02:19 +08:00")' "diag result should include email/reset subtitle"

CODEX_STUB_LOG="$action_log" ALFRED_WORKFLOW_CACHE="$diag_cache_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" \
  "$workflow_dir/scripts/action_open.sh" "diag::default" >/dev/null
[[ "$(tail -n1 "$action_log")" == "diag rate-limits --json" ]] || fail "diag::default mapping mismatch"
[[ ! -f "$diag_default_meta" ]] || fail "diag default action should keep cache in last.meta only"

alias_diag_result_json="$({ ALFRED_WORKFLOW_CACHE="$diag_cache_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter_diag.sh" "result"; })"
assert_jq_json "$alias_diag_result_json" '.items[0].title | startswith("Diag result ready")' "cxd result should map to diag result view"

alias_diag_all_result_json="$({ ALFRED_WORKFLOW_CACHE="$diag_cache_dir" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter_diag_all.sh" "result"; })"
assert_jq_json "$alias_diag_all_result_json" '.items[0].title == "Diag result ready (all-json)"' "cxda result should keep all-json mode summary"
assert_jq_json "$alias_diag_all_result_json" '.items | any(.title | test("^sym \\| 5h 76% \\([^)]*\\) \\| weekly 88% \\([^)]*\\)$"))' "cxda result should parse per-account rows"
# shellcheck disable=SC2016
assert_jq_json "$alias_diag_all_result_json" '.items | map(.title) as $titles | (($titles | map(startswith("poies | 5h 48%")) | index(true)) < ($titles | map(startswith("sym | 5h 76%")) | index(true)))' "cxda result should sort by earliest weekly reset first"

use_secret_dir_ranked="$tmp_dir/secrets-ranked"
mkdir -p "$use_secret_dir_ranked"
printf '{"email":"beta-ranked@example.com"}\n' >"$use_secret_dir_ranked/beta.json"
printf '{"email":"poies-ranked@example.com"}\n' >"$use_secret_dir_ranked/poies.json"
printf '{"email":"sym-ranked@example.com"}\n' >"$use_secret_dir_ranked/sym.json"

alias_auth_use_ranked_json="$({ ALFRED_WORKFLOW_CACHE="$diag_cache_dir" CODEX_SECRET_DIR="$use_secret_dir_ranked" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/script_filter_auth_use.sh" ""; })"
assert_jq_json "$alias_auth_use_ranked_json" '.items[0].title == "Current: beta.json"' "cxau should keep current auth summary row"
assert_jq_json "$alias_auth_use_ranked_json" '.items[0].subtitle | contains("beta-ranked@example.com | reset -")' "cxau current row should include email and reset subtitle"
assert_jq_json "$alias_auth_use_ranked_json" '.items | any(.title | test("^poies\\.json \\| 5h 48% \\([^)]*\\) \\| weekly 54% \\([^)]*\\)$"))' "cxau should show cxda-style usage metrics in title"
assert_jq_json "$alias_auth_use_ranked_json" '.items | any(.title | test("^sym\\.json \\| 5h 76% \\([^)]*\\) \\| weekly 88% \\([^)]*\\)$"))' "cxau should show cxda-style usage metrics for sym"
# shellcheck disable=SC2016
assert_jq_json "$alias_auth_use_ranked_json" '.items | map(.title) as $titles | (($titles | map(startswith("poies.json | 5h 48%")) | index(true)) < ($titles | map(startswith("sym.json | 5h 76%")) | index(true)))' "cxau should sort secrets by earliest weekly reset from latest cxda result"
assert_jq_json "$alias_auth_use_ranked_json" '.items | any((.title | test("^poies\\.json \\| 5h 48% \\([^)]*\\) \\| weekly 54% \\([^)]*\\)$")) and (.subtitle | contains("poies@example.com | reset 2026-02-17 02:19 +08:00")))' "cxau rows should show cached email and reset subtitle"

cat >"$tmp_dir/bin/open" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >"$OPEN_STUB_OUT"
EOS
chmod +x "$tmp_dir/bin/open"
OPEN_STUB_OUT="$tmp_dir/open-url.out" PATH="$tmp_dir/bin:$PATH" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-browser-url" \
  "$workflow_dir/scripts/action_open.sh" "login::browser" >/dev/null
[[ "$(cat "$tmp_dir/open-url.out")" == "https://auth.openai.com/oauth/authorize?foo=bar&state=test" ]] || fail "login::browser should open parsed auth URL"

cat >"$tmp_dir/bin/pbcopy" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cat >"$PBCOPY_STUB_OUT"
EOS
chmod +x "$tmp_dir/bin/pbcopy"
OPEN_STUB_OUT="$tmp_dir/open-device-url.out" PBCOPY_STUB_OUT="$tmp_dir/device-code.out" PATH="$tmp_dir/bin:$PATH" CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-device-code" \
  "$workflow_dir/scripts/action_open.sh" "login::device-code" >/dev/null
[[ "$(cat "$tmp_dir/open-device-url.out")" == "https://chatgpt.com/device" ]] || fail "device-code login should open parsed auth URL"
[[ "$(cat "$tmp_dir/device-code.out")" == "ABCD-EFGH" ]] || fail "device-code login should copy parsed one-time code"

set +e
CODEX_LOGIN_TIMEOUT_SECONDS=1 CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-hang" \
  "$workflow_dir/scripts/action_open.sh" "login::browser" >/dev/null 2>&1
login_timeout_rc=$?
set -e
[[ "$login_timeout_rc" -eq 124 ]] || fail "login should return 124 when timeout is reached"

set +e
CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-fail" "$workflow_dir/scripts/action_open.sh" "diag::default" >/dev/null 2>&1
action_fail_rc=$?
set -e
[[ "$action_fail_rc" -eq 7 ]] || fail "failing codex-cli command should keep non-zero status"

set +e
PATH="/usr/bin:/bin" CODEX_CLI_BIN="$tmp_dir/stubs/does-not-exist" \
  "$workflow_dir/scripts/action_open.sh" "diag::default" >/dev/null 2>&1
missing_bin_rc=$?
set -e
[[ "$missing_bin_rc" -eq 1 ]] || fail "missing codex-cli should exit 1"

set +e
CODEX_CLI_BIN="$tmp_dir/stubs/codex-cli-ok" "$workflow_dir/scripts/action_open.sh" "unknown::token" >/dev/null 2>&1
unknown_token_rc=$?
set -e
[[ "$unknown_token_rc" -eq 2 ]] || fail "unknown token should exit 2"

set +e
PATH="/usr/bin:/bin" \
  "$workflow_dir/scripts/prepare_package.sh" --stage-dir "$tmp_dir/stage-missing-bin" --workflow-root "$workflow_dir" >/dev/null 2>&1
prepare_missing_rc=$?
set -e
[[ "$prepare_missing_rc" -eq 1 ]] || fail "prepare_package should fail when codex-cli is unavailable"

set +e
CODEX_CLI_PACK_BIN="$tmp_dir/stubs/codex-cli-fail" \
  "$workflow_dir/scripts/prepare_package.sh" --stage-dir "$tmp_dir/stage-bad-version" --workflow-root "$workflow_dir" >/dev/null 2>&1
prepare_bad_version_rc=$?
set -e
[[ "$prepare_bad_version_rc" -eq 1 ]] || fail "prepare_package should fail on version mismatch"

CODEX_CLI_PACK_BIN="$tmp_dir/stubs/codex-cli-ok" CODEX_CLI_PACK_SKIP_ARCH_CHECK=1 \
  "$repo_root/scripts/workflow-pack.sh" --id codex-cli >/dev/null

packaged_dir="$repo_root/build/workflows/codex-cli/pkg"
packaged_plist="$packaged_dir/info.plist"
assert_file "$packaged_plist"
assert_file "$packaged_dir/icon.png"
assert_file "$packaged_dir/assets/icon.png"
assert_file "$packaged_dir/screenshot.png"
assert_file "$packaged_dir/scripts/script_filter.sh"
assert_file "$packaged_dir/scripts/script_filter_auth.sh"
assert_file "$packaged_dir/scripts/script_filter_auth_use.sh"
assert_file "$packaged_dir/scripts/script_filter_diag.sh"
assert_file "$packaged_dir/scripts/script_filter_diag_all.sh"
assert_file "$packaged_dir/scripts/script_filter_save.sh"
assert_file "$packaged_dir/scripts/action_open.sh"
assert_file "$packaged_dir/scripts/prepare_package.sh"
assert_file "$packaged_dir/bin/codex-cli"
assert_exec "$packaged_dir/scripts/script_filter.sh"
assert_exec "$packaged_dir/scripts/script_filter_auth.sh"
assert_exec "$packaged_dir/scripts/script_filter_auth_use.sh"
assert_exec "$packaged_dir/scripts/script_filter_diag.sh"
assert_exec "$packaged_dir/scripts/script_filter_diag_all.sh"
assert_exec "$packaged_dir/scripts/script_filter_save.sh"
assert_exec "$packaged_dir/bin/codex-cli"
assert_file "$artifact_path"
assert_file "$artifact_sha_path"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$packaged_plist" >/dev/null || fail "packaged plist lint failed"
fi

packaged_json_file="$tmp_dir/packaged.json"
plist_to_json "$packaged_plist" >"$packaged_json_file"

assert_jq_file "$packaged_json_file" '.objects | length == 7' "plist must contain six script filters and one action object"
assert_jq_file "$packaged_json_file" '[.objects[] | select(.type=="alfred.workflow.input.scriptfilter")] | length == 6' "plist must expose six script filter triggers"
assert_jq_file "$packaged_json_file" '[.objects[] | select(.type=="alfred.workflow.input.scriptfilter") | .config.keyword] | sort == ["cx","cxa","cxau","cxd","cxda","cxs"]' "workflow keywords must include cx/cxa/cxau/cxd/cxda/cxs"
assert_jq_file "$packaged_json_file" '.connections | length == 6' "plist must include six scriptfilter-to-action connections"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig | length >= 4' "plist must expose codex workflow config variables"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="CODEX_CLI_BIN") | .config.default == ""' "CODEX_CLI_BIN config row missing"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="CODEX_SECRET_DIR") | .config.default == ""' "CODEX_SECRET_DIR config row missing"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="CODEX_SHOW_ASSESSMENT") | .config.default == "0"' "CODEX_SHOW_ASSESSMENT config row missing"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="CODEX_DIAG_CACHE_TTL_SECONDS") | .config.default == "300"' "CODEX_DIAG_CACHE_TTL_SECONDS config row missing"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.keyword == "cx"' "keyword trigger must be cx"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.scriptfile == "./scripts/script_filter.sh"' "script filter wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="D927D71A-8CB2-4CE7-9D4D-4A57D2A7A8F1") | .config.keyword == "cxa"' "keyword trigger must include cxa"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="D927D71A-8CB2-4CE7-9D4D-4A57D2A7A8F1") | .config.scriptfile == "./scripts/script_filter_auth.sh"' "cxa script filter wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="B7D3A21F-6B44-4CF9-9CC3-3CE9D9F4E9D7") | .config.keyword == "cxau"' "keyword trigger must include cxau"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="B7D3A21F-6B44-4CF9-9CC3-3CE9D9F4E9D7") | .config.scriptfile == "./scripts/script_filter_auth_use.sh"' "cxau script filter wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="1B2C2CF8-9C9E-4E5E-AE2D-6F911B3A9D63") | .config.keyword == "cxd"' "keyword trigger must include cxd"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="1B2C2CF8-9C9E-4E5E-AE2D-6F911B3A9D63") | .config.scriptfile == "./scripts/script_filter_diag.sh"' "cxd script filter wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="C4A6E4D4-4C89-4F8E-B6F8-2F1A7A5E6D09") | .config.keyword == "cxda"' "keyword trigger must include cxda"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="C4A6E4D4-4C89-4F8E-B6F8-2F1A7A5E6D09") | .config.scriptfile == "./scripts/script_filter_diag_all.sh"' "cxda script filter wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="A9F12D4E-1D99-4D7B-A950-6E84A583A9C2") | .config.keyword == "cxs"' "keyword trigger must include cxs"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="A9F12D4E-1D99-4D7B-A950-6E84A583A9C2") | .config.scriptfile == "./scripts/script_filter_save.sh"' "cxs script filter wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="D7E624DB-D4AB-4D53-8C03-D051A1A97A4A") | .config.scriptfile == "./scripts/action_open.sh"' "action wiring mismatch"
assert_jq_file "$packaged_json_file" '.readme | contains("# Codex CLI - Alfred Workflow")' "readme heading should be synced from README.md"
assert_jq_file "$packaged_json_file" '.readme | test("\\|\\s*-{3,}\\s*\\|") | not' "readme table separators must be downgraded"

echo "ok: codex-cli smoke test"
