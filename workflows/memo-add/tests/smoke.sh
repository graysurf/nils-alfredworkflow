#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workflow_dir="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$workflow_dir/../.." && pwd)"

fail() {
  echo "error: $*" >&2
  exit 1
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

assert_jq_json() {
  local json_payload="$1"
  local filter="$2"
  local message="$3"
  if ! jq -e "$filter" >/dev/null <<<"$json_payload"; then
    fail "$message (jq: $filter)"
  fi
}

for required in \
  workflow.toml \
  README.md \
  src/info.plist.template \
  src/assets/icon.png \
  scripts/script_filter.sh \
  scripts/action_run.sh \
  tests/smoke.sh; do
  assert_file "$workflow_dir/$required"
done

for executable in \
  scripts/script_filter.sh \
  scripts/action_run.sh \
  tests/smoke.sh; do
  assert_exec "$workflow_dir/$executable"
done

command -v jq >/dev/null 2>&1 || fail "missing required binary: jq"
command -v rg >/dev/null 2>&1 || fail "missing required binary: rg"

manifest="$workflow_dir/workflow.toml"
[[ "$(toml_string "$manifest" id)" == "memo-add" ]] || fail "workflow id mismatch"
[[ "$(toml_string "$manifest" rust_binary)" == "memo-workflow-cli" ]] || fail "rust_binary mismatch"
[[ "$(toml_string "$manifest" script_filter)" == "script_filter.sh" ]] || fail "script_filter mismatch"
[[ "$(toml_string "$manifest" action)" == "action_run.sh" ]] || fail "action mismatch"

for variable in MEMO_DB_PATH MEMO_SOURCE MEMO_REQUIRE_CONFIRM MEMO_MAX_INPUT_BYTES MEMO_WORKFLOW_CLI_BIN; do
  rg -n "^${variable}[[:space:]]*=" "$manifest" >/dev/null || fail "missing env var: $variable"
done

rg -n '^MEMO_SOURCE[[:space:]]*=[[:space:]]*"alfred"' "$manifest" >/dev/null || fail "MEMO_SOURCE default mismatch"
rg -n '^MEMO_REQUIRE_CONFIRM[[:space:]]*=[[:space:]]*"0"' "$manifest" >/dev/null || fail "MEMO_REQUIRE_CONFIRM default mismatch"
rg -n '^MEMO_MAX_INPUT_BYTES[[:space:]]*=[[:space:]]*"4096"' "$manifest" >/dev/null || fail "MEMO_MAX_INPUT_BYTES default mismatch"

set +e
"$workflow_dir/scripts/action_run.sh" >/dev/null 2>&1
action_rc=$?
set -e
[[ "$action_rc" -eq 2 ]] || fail "action_run.sh without args must exit 2"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/stubs"

cat >"$tmp_dir/stubs/memo-workflow-cli-ok" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "script-filter" ]]; then
  printf '{"items":[{"title":"Add memo: buy milk","subtitle":"ok","arg":"add::buy milk","valid":true}]}'
  printf '\n'
  exit 0
fi
if [[ "${1:-}" == "action" && "${2:-}" == "--token" ]]; then
  printf 'added itm_00000001 at 2026-02-12T12:00:00Z\n'
  exit 0
fi
exit 9
EOS
chmod +x "$tmp_dir/stubs/memo-workflow-cli-ok"

cat >"$tmp_dir/stubs/memo-workflow-cli-invalid" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "invalid MEMO_MAX_INPUT_BYTES" >&2
exit 2
EOS
chmod +x "$tmp_dir/stubs/memo-workflow-cli-invalid"

success_json="$({ MEMO_WORKFLOW_CLI_BIN="$tmp_dir/stubs/memo-workflow-cli-ok" "$workflow_dir/scripts/script_filter.sh" "buy milk"; })"
assert_jq_json "$success_json" '.items | type == "array" and length == 1' "script_filter success must return one item"
assert_jq_json "$success_json" '.items[0].arg == "add::buy milk"' "script_filter add arg mismatch"

invalid_json="$({ MEMO_WORKFLOW_CLI_BIN="$tmp_dir/stubs/memo-workflow-cli-invalid" "$workflow_dir/scripts/script_filter.sh" "buy milk"; })"
assert_jq_json "$invalid_json" '.items[0].title == "Invalid Memo workflow config"' "invalid config title mismatch"

action_output="$({ MEMO_WORKFLOW_CLI_BIN="$tmp_dir/stubs/memo-workflow-cli-ok" "$workflow_dir/scripts/action_run.sh" "add::buy milk"; })"
[[ "$action_output" == *"added itm_00000001"* ]] || fail "action output mismatch"

cat >"$tmp_dir/stubs/cargo" <<EOS
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$#" -eq 4 && "\$1" == "build" && "\$2" == "--release" && "\$3" == "-p" && "\$4" == "nils-memo-workflow-cli" ]]; then
  mkdir -p "$repo_root/target/release"
  cat >"$repo_root/target/release/memo-workflow-cli" <<'EOCLI'
#!/usr/bin/env bash
set -euo pipefail
printf '{"items":[]}\n'
EOCLI
  chmod +x "$repo_root/target/release/memo-workflow-cli"
  exit 0
fi

if [[ "\$#" -ge 4 && "\$1" == "run" && "\$2" == "-p" && "\$3" == "nils-workflow-readme-cli" && "\$4" == "--" ]]; then
  exit 0
fi

echo "unexpected cargo invocation: \$*" >&2
exit 1
EOS
chmod +x "$tmp_dir/stubs/cargo"

PATH="$tmp_dir/stubs:$PATH" "$repo_root/scripts/workflow-pack.sh" --id memo-add >/dev/null

packaged_plist="$repo_root/build/workflows/memo-add/pkg/info.plist"
assert_file "$packaged_plist"
assert_file "$repo_root/build/workflows/memo-add/pkg/bin/memo-workflow-cli"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$packaged_plist" >/dev/null || fail "packaged plist lint failed"
  packaged_json="$(plutil -convert json -o - "$packaged_plist")"
else
  packaged_json="$(
    python3 - "$packaged_plist" <<'PY'
import json
import plistlib
import sys
with open(sys.argv[1], 'rb') as f:
    print(json.dumps(plistlib.load(f)))
PY
  )"
fi

assert_jq_json "$packaged_json" '.objects[] | select(.type == "alfred.workflow.input.scriptfilter") | .config.keyword == "mm"' "keyword wiring mismatch"
assert_jq_json "$packaged_json" '[.userconfigurationconfig[].variable] | sort == ["MEMO_DB_PATH","MEMO_MAX_INPUT_BYTES","MEMO_REQUIRE_CONFIRM","MEMO_SOURCE","MEMO_WORKFLOW_CLI_BIN"]' "plist variable list mismatch"
assert_jq_json "$packaged_json" '.userconfigurationconfig[] | select(.variable == "MEMO_MAX_INPUT_BYTES") | .config.default == "4096"' "plist default mismatch"

echo "ok: memo-add smoke test"
