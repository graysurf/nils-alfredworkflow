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

for required in \
  workflow.toml \
  README.md \
  src/info.plist.template \
  src/assets/icon.png \
  scripts/script_filter.sh \
  scripts/action_copy.sh \
  tests/smoke.sh; do
  assert_file "$workflow_dir/$required"
done

for executable in \
  scripts/script_filter.sh \
  scripts/action_copy.sh \
  tests/smoke.sh; do
  assert_exec "$workflow_dir/$executable"
done

require_bin jq
require_bin rg

manifest="$workflow_dir/workflow.toml"
[[ "$(toml_string "$manifest" id)" == "quote-feed" ]] || fail "workflow id mismatch"
[[ "$(toml_string "$manifest" rust_binary)" == "quote-cli" ]] || fail "rust_binary must be quote-cli"
[[ "$(toml_string "$manifest" script_filter)" == "script_filter.sh" ]] || fail "script_filter mismatch"
[[ "$(toml_string "$manifest" action)" == "action_copy.sh" ]] || fail "action mismatch"

for variable in QUOTE_DISPLAY_COUNT QUOTE_REFRESH_INTERVAL QUOTE_FETCH_COUNT QUOTE_MAX_ENTRIES QUOTE_DATA_DIR; do
  if ! rg -n "^${variable}[[:space:]]*=" "$manifest" >/dev/null; then
    fail "missing env var in workflow.toml: $variable"
  fi
done

if ! rg -n '^QUOTE_DISPLAY_COUNT[[:space:]]*=[[:space:]]*"3"' "$manifest" >/dev/null; then
  fail "QUOTE_DISPLAY_COUNT default must be 3"
fi
if ! rg -n '^QUOTE_REFRESH_INTERVAL[[:space:]]*=[[:space:]]*"1h"' "$manifest" >/dev/null; then
  fail "QUOTE_REFRESH_INTERVAL default must be 1h"
fi
if ! rg -n '^QUOTE_FETCH_COUNT[[:space:]]*=[[:space:]]*"5"' "$manifest" >/dev/null; then
  fail "QUOTE_FETCH_COUNT default must be 5"
fi
if ! rg -n '^QUOTE_MAX_ENTRIES[[:space:]]*=[[:space:]]*"100"' "$manifest" >/dev/null; then
  fail "QUOTE_MAX_ENTRIES default must be 100"
fi
if ! rg -n '^QUOTE_DATA_DIR[[:space:]]*=[[:space:]]*""' "$manifest" >/dev/null; then
  fail "QUOTE_DATA_DIR default must be empty string"
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

release_cli="$repo_root/target/release/quote-cli"
release_backup=""
if [[ -f "$release_cli" ]]; then
  release_backup="$tmp_dir/quote-cli.release.backup"
  cp "$release_cli" "$release_backup"
fi

cleanup() {
  if [[ -n "$release_backup" && -f "$release_backup" ]]; then
    mkdir -p "$(dirname "$release_cli")"
    cp "$release_backup" "$release_cli"
  elif [[ -f "$release_cli" ]]; then
    rm -f "$release_cli"
  fi

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

cat >"$tmp_dir/bin/pbcopy" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cat >"$PBCOPY_STUB_OUT"
EOS
chmod +x "$tmp_dir/bin/pbcopy"

set +e
"$workflow_dir/scripts/action_copy.sh" >/dev/null 2>&1
action_rc=$?
set -e
[[ "$action_rc" -eq 2 ]] || fail "action_copy.sh without args must exit 2"

copy_arg="\"stay hungry\" — steve jobs"
PBCOPY_STUB_OUT="$tmp_dir/pbcopy-out.txt" PATH="$tmp_dir/bin:$PATH" \
  "$workflow_dir/scripts/action_copy.sh" "$copy_arg"
[[ "$(cat "$tmp_dir/pbcopy-out.txt")" == "$copy_arg" ]] || fail "action_copy.sh must pass exact arg to pbcopy"

cat >"$tmp_dir/stubs/quote-cli-ok" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "feed" ]] || exit 9
[[ "${2:-}" == "--query" ]] || exit 9
query="${3:-}"
printf '{"items":[{"title":"stub-quote","subtitle":"query=%s","arg":"stub-quote","valid":true}]}' "$query"
printf '\n'
EOS
chmod +x "$tmp_dir/stubs/quote-cli-ok"

cat >"$tmp_dir/stubs/quote-cli-invalid" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "invalid QUOTE_REFRESH_INTERVAL: 90x" >&2
exit 2
EOS
chmod +x "$tmp_dir/stubs/quote-cli-invalid"

cat >"$tmp_dir/stubs/quote-cli-runtime" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "zenquotes request failed" >&2
exit 3
EOS
chmod +x "$tmp_dir/stubs/quote-cli-runtime"

cat >"$tmp_dir/stubs/quote-cli-malformed" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
printf '{"unexpected":"shape"}\n'
EOS
chmod +x "$tmp_dir/stubs/quote-cli-malformed"

success_json="$({ QUOTE_CLI_BIN="$tmp_dir/stubs/quote-cli-ok" "$workflow_dir/scripts/script_filter.sh" "focus"; })"
assert_jq_json "$success_json" '.items | type == "array" and length == 1' "script_filter success must output items array"
assert_jq_json "$success_json" '.items[0].title == "stub-quote"' "script_filter should forward successful JSON"

invalid_json="$({ QUOTE_CLI_BIN="$tmp_dir/stubs/quote-cli-invalid" "$workflow_dir/scripts/script_filter.sh" "focus"; })"
assert_jq_json "$invalid_json" '.items[0].title == "Invalid Quote workflow config"' "invalid config title mapping mismatch"
assert_jq_json "$invalid_json" '.items[0].valid == false' "invalid config item must be invalid"

runtime_json="$({ QUOTE_CLI_BIN="$tmp_dir/stubs/quote-cli-runtime" "$workflow_dir/scripts/script_filter.sh" "focus"; })"
assert_jq_json "$runtime_json" '.items[0].title == "Quote refresh unavailable"' "runtime failure title mapping mismatch"
assert_jq_json "$runtime_json" '.items[0].valid == false' "runtime fallback must be invalid"

malformed_json="$({ QUOTE_CLI_BIN="$tmp_dir/stubs/quote-cli-malformed" "$workflow_dir/scripts/script_filter.sh" "focus"; })"
assert_jq_json "$malformed_json" '.items[0].title == "Quote Feed error"' "malformed JSON should fallback to generic error"
assert_jq_json "$malformed_json" '.items[0].subtitle | contains("malformed Alfred JSON")' "malformed JSON subtitle mismatch"

missing_layout="$tmp_dir/layout-missing"
copied_missing_script="$missing_layout/workflows/quote-feed/scripts/script_filter.sh"
mkdir -p "$(dirname "$copied_missing_script")"
cp "$workflow_dir/scripts/script_filter.sh" "$copied_missing_script"
chmod +x "$copied_missing_script"
missing_binary_json="$({ QUOTE_CLI_BIN="$missing_layout/does-not-exist/quote-cli" "$copied_missing_script" "focus"; })"
assert_jq_json "$missing_binary_json" '.items[0].title == "quote-cli binary not found"' "missing binary fallback title mismatch"
assert_jq_json "$missing_binary_json" '.items[0].valid == false' "missing binary fallback item must be invalid"

make_layout_cli() {
  local target="$1"
  local marker="$2"
  mkdir -p "$(dirname "$target")"
  cat >"$target" <<EOS
#!/usr/bin/env bash
set -euo pipefail
[[ "\${1:-}" == "feed" ]] || exit 9
[[ "\${2:-}" == "--query" ]] || exit 9
printf '{"items":[{"title":"${marker}","subtitle":"ok","arg":"copy-me","valid":true}]}'
printf '\\n'
EOS
  chmod +x "$target"
}

run_layout_check() {
  local mode="$1"
  local marker="$2"
  local layout="$tmp_dir/layout-$mode"
  local copied_script="$layout/workflows/quote-feed/scripts/script_filter.sh"

  mkdir -p "$(dirname "$copied_script")"
  cp "$workflow_dir/scripts/script_filter.sh" "$copied_script"
  chmod +x "$copied_script"

  case "$mode" in
  packaged)
    make_layout_cli "$layout/workflows/quote-feed/bin/quote-cli" "$marker"
    ;;
  release)
    make_layout_cli "$layout/target/release/quote-cli" "$marker"
    ;;
  debug)
    make_layout_cli "$layout/target/debug/quote-cli" "$marker"
    ;;
  *)
    fail "unsupported layout mode: $mode"
    ;;
  esac

  local output
  output="$($copied_script "demo")"
  assert_jq_json "$output" ".items[0].title == \"$marker\"" "script_filter failed to resolve $mode quote-cli path"
}

run_layout_check packaged packaged-cli
run_layout_check release release-cli
run_layout_check debug debug-cli

cat >"$tmp_dir/bin/cargo" <<EOS
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$#" -eq 4 && "\$1" == "build" && "\$2" == "--release" && "\$3" == "-p" && "\$4" == "quote-cli" ]]; then
  mkdir -p "$repo_root/target/release"
  cat >"$repo_root/target/release/quote-cli" <<'EOCLI'
#!/usr/bin/env bash
set -euo pipefail
printf '{"items":[]}\n'
EOCLI
  chmod +x "$repo_root/target/release/quote-cli"
  exit 0
fi

echo "unexpected cargo invocation: \$*" >&2
exit 1
EOS
chmod +x "$tmp_dir/bin/cargo"

PATH="$tmp_dir/bin:$PATH" "$repo_root/scripts/workflow-pack.sh" --id quote-feed >/dev/null

packaged_dir="$repo_root/build/workflows/quote-feed/pkg"
packaged_plist="$packaged_dir/info.plist"
assert_file "$packaged_plist"
assert_file "$packaged_dir/icon.png"
assert_file "$packaged_dir/assets/icon.png"
assert_file "$packaged_dir/bin/quote-cli"
assert_file "$artifact_path"
assert_file "$artifact_sha_path"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$packaged_plist" >/dev/null || fail "packaged plist lint failed"
fi

packaged_json_file="$tmp_dir/packaged.json"
plist_to_json "$packaged_plist" >"$packaged_json_file"

assert_jq_file "$packaged_json_file" '.objects | length > 0' "packaged plist missing objects"
assert_jq_file "$packaged_json_file" '.connections | length > 0' "packaged plist missing connections"
assert_jq_file "$packaged_json_file" '[.objects[] | select(.type=="alfred.workflow.input.scriptfilter") | .config.type] | all(. == 8)' "script filter objects must be external script type=8"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.scriptfile == "./scripts/script_filter.sh"' "script filter scriptfile wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.keyword == "qq"' "keyword trigger must be qq"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.scriptargtype == 1' "script filter must pass query via argv"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="D7E624DB-D4AB-4D53-8C03-D051A1A97A4A") | .config.scriptfile == "./scripts/action_copy.sh"' "action scriptfile wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="D7E624DB-D4AB-4D53-8C03-D051A1A97A4A") | .config.type == 8' "action node must be external script type=8"
assert_jq_file "$packaged_json_file" '.connections["70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10"] | any(.destinationuid == "D7E624DB-D4AB-4D53-8C03-D051A1A97A4A" and .modifiers == 0)' "missing script-filter to action connection"
assert_jq_file "$packaged_json_file" '[.userconfigurationconfig[] | .variable] | sort == ["QUOTE_DATA_DIR","QUOTE_DISPLAY_COUNT","QUOTE_FETCH_COUNT","QUOTE_MAX_ENTRIES","QUOTE_REFRESH_INTERVAL"]' "user configuration variables mismatch"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="QUOTE_DISPLAY_COUNT") | .config.default == "3"' "QUOTE_DISPLAY_COUNT default must be 3"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="QUOTE_REFRESH_INTERVAL") | .config.default == "1h"' "QUOTE_REFRESH_INTERVAL default must be 1h"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="QUOTE_FETCH_COUNT") | .config.default == "5"' "QUOTE_FETCH_COUNT default must be 5"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="QUOTE_MAX_ENTRIES") | .config.default == "100"' "QUOTE_MAX_ENTRIES default must be 100"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="QUOTE_DATA_DIR") | .config.default == ""' "QUOTE_DATA_DIR default must be empty string"

echo "ok: quote-feed smoke test"
