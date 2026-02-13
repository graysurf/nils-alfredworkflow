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
  src/info.plist.template \
  src/assets/icon.png \
  scripts/script_filter.sh \
  scripts/action_open.sh \
  tests/smoke.sh; do
  assert_file "$workflow_dir/$required"
done

for executable in \
  scripts/script_filter.sh \
  scripts/action_open.sh \
  tests/smoke.sh; do
  assert_exec "$workflow_dir/$executable"
done

require_bin jq

manifest="$workflow_dir/workflow.toml"
[[ "$(toml_string "$manifest" id)" == "wiki-search" ]] || fail "workflow id mismatch"
[[ "$(toml_string "$manifest" rust_binary)" == "wiki-cli" ]] || fail "rust_binary must be wiki-cli"
[[ "$(toml_string "$manifest" script_filter)" == "script_filter.sh" ]] || fail "script_filter mismatch"
[[ "$(toml_string "$manifest" action)" == "action_open.sh" ]] || fail "action mismatch"

for variable in WIKI_LANGUAGE WIKI_MAX_RESULTS; do
  if ! rg -n "^${variable}[[:space:]]*=" "$manifest" >/dev/null; then
    fail "missing env var in workflow.toml: $variable"
  fi
done

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

release_cli="$repo_root/target/release/wiki-cli"
release_backup=""
if [[ -f "$release_cli" ]]; then
  release_backup="$tmp_dir/wiki-cli.release.backup"
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

cat >"$tmp_dir/bin/open" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >"$OPEN_STUB_OUT"
EOS
chmod +x "$tmp_dir/bin/open"

set +e
"$workflow_dir/scripts/action_open.sh" >/dev/null 2>&1
action_rc=$?
set -e
[[ "$action_rc" -eq 2 ]] || fail "action_open.sh without args must exit 2"

action_arg="https://en.wikipedia.org/?curid=36192"
OPEN_STUB_OUT="$tmp_dir/open-arg.txt" PATH="$tmp_dir/bin:$PATH" \
  "$workflow_dir/scripts/action_open.sh" "$action_arg"
[[ "$(cat "$tmp_dir/open-arg.txt")" == "$action_arg" ]] || fail "action_open.sh must pass URL to open"

cat >"$tmp_dir/stubs/wiki-cli-ok" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${WIKI_STUB_LOG:-}" ]]; then
  printf '%s\n' "$*" >>"$WIKI_STUB_LOG"
fi
[[ "${1:-}" == "search" ]] || exit 9
[[ "${2:-}" == "--query" ]] || exit 9
query="${3:-}"
printf '{"items":[{"title":"stub-result","subtitle":"query=%s","arg":"https://en.wikipedia.org/?curid=1","valid":true}]}' "$query"
printf '\n'
EOS
chmod +x "$tmp_dir/stubs/wiki-cli-ok"

cat >"$tmp_dir/stubs/wiki-cli-no-results" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
printf '{"items":[{"title":"No articles found","subtitle":"Try broader keywords or switch WIKI_LANGUAGE.","valid":false}]}'
printf '\n'
EOS
chmod +x "$tmp_dir/stubs/wiki-cli-no-results"

cat >"$tmp_dir/stubs/wiki-cli-unavailable" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "wikipedia api request failed" >&2
exit 7
EOS
chmod +x "$tmp_dir/stubs/wiki-cli-unavailable"

cat >"$tmp_dir/stubs/wiki-cli-invalid-config" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "invalid WIKI_LANGUAGE: EN-US!" >&2
exit 2
EOS
chmod +x "$tmp_dir/stubs/wiki-cli-invalid-config"

success_json="$({ WIKI_CLI_BIN="$tmp_dir/stubs/wiki-cli-ok" "$workflow_dir/scripts/script_filter.sh" "rust"; })"
assert_jq_json "$success_json" '.items | type == "array" and length == 1' "script_filter success must output items array"
assert_jq_json "$success_json" '.items[0].title == "stub-result"' "script_filter should forward successful JSON"

env_query_json="$({ WIKI_CLI_BIN="$tmp_dir/stubs/wiki-cli-ok" alfred_workflow_query="rust book" "$workflow_dir/scripts/script_filter.sh"; })"
assert_jq_json "$env_query_json" '.items[0].subtitle == "query=rust book"' "script_filter must support Alfred query via env fallback"

stdin_query_json="$(printf 'rustlang' | WIKI_CLI_BIN="$tmp_dir/stubs/wiki-cli-ok" "$workflow_dir/scripts/script_filter.sh")"
assert_jq_json "$stdin_query_json" '.items[0].subtitle == "query=rustlang"' "script_filter must support query via stdin fallback"

no_results_json="$({ WIKI_CLI_BIN="$tmp_dir/stubs/wiki-cli-no-results" "$workflow_dir/scripts/script_filter.sh" "rust"; })"
assert_jq_json "$no_results_json" '.items[0].title == "No articles found"' "script_filter should forward no-results item"
assert_jq_json "$no_results_json" '.items[0].valid == false' "no-results item must remain invalid"

unavailable_json="$({ WIKI_CLI_BIN="$tmp_dir/stubs/wiki-cli-unavailable" "$workflow_dir/scripts/script_filter.sh" "rust"; })"
assert_jq_json "$unavailable_json" '.items | type == "array" and length == 1' "unavailable fallback must output single item"
assert_jq_json "$unavailable_json" '.items[0].title == "Wikipedia API unavailable"' "unavailable title mapping mismatch"
assert_jq_json "$unavailable_json" '.items[0].valid == false' "unavailable item must be invalid"

invalid_config_json="$({ WIKI_CLI_BIN="$tmp_dir/stubs/wiki-cli-invalid-config" "$workflow_dir/scripts/script_filter.sh" "rust"; })"
assert_jq_json "$invalid_config_json" '.items[0].title == "Invalid Wiki workflow config"' "invalid config title mapping mismatch"
assert_jq_json "$invalid_config_json" '.items[0].subtitle | contains("WIKI_LANGUAGE")' "invalid config subtitle should mention WIKI_LANGUAGE"

empty_query_json="$({ WIKI_CLI_BIN="$tmp_dir/stubs/wiki-cli-ok" "$workflow_dir/scripts/script_filter.sh" "   "; })"
assert_jq_json "$empty_query_json" '.items[0].title == "Enter a search query"' "empty query guidance title mismatch"
assert_jq_json "$empty_query_json" '.items[0].valid == false' "empty query item must be invalid"

short_query_log="$tmp_dir/wiki-short-query.log"
short_query_json="$({ WIKI_STUB_LOG="$short_query_log" WIKI_CLI_BIN="$tmp_dir/stubs/wiki-cli-ok" "$workflow_dir/scripts/script_filter.sh" "r"; })"
assert_jq_json "$short_query_json" '.items[0].title == "Keep typing (2+ chars)"' "short query guidance title mismatch"
assert_jq_json "$short_query_json" '.items[0].subtitle | contains("2")' "short query guidance subtitle must mention minimum length"
[[ ! -s "$short_query_log" ]] || fail "short query should not invoke wiki-cli backend"

make_layout_cli() {
  local target="$1"
  local marker="$2"
  mkdir -p "$(dirname "$target")"
  cat >"$target" <<EOS
#!/usr/bin/env bash
set -euo pipefail
printf '{"items":[{"title":"${marker}","subtitle":"ok","arg":"https://example.com","valid":true}]}'
printf '\\n'
EOS
  chmod +x "$target"
}

run_layout_check() {
  local mode="$1"
  local marker="$2"
  local layout="$tmp_dir/layout-$mode"
  local copied_script="$layout/workflows/wiki-search/scripts/script_filter.sh"

  mkdir -p "$(dirname "$copied_script")"
  cp "$workflow_dir/scripts/script_filter.sh" "$copied_script"
  chmod +x "$copied_script"
  mkdir -p "$layout/workflows/wiki-search/scripts/lib"
  cp "$repo_root/scripts/lib/script_filter_query_policy.sh" "$layout/workflows/wiki-search/scripts/lib/script_filter_query_policy.sh"

  case "$mode" in
  packaged)
    make_layout_cli "$layout/workflows/wiki-search/bin/wiki-cli" "$marker"
    ;;
  release)
    make_layout_cli "$layout/target/release/wiki-cli" "$marker"
    ;;
  debug)
    make_layout_cli "$layout/target/debug/wiki-cli" "$marker"
    ;;
  *)
    fail "unsupported layout mode: $mode"
    ;;
  esac

  local output
  output="$($copied_script "demo")"
  assert_jq_json "$output" ".items[0].title == \"$marker\"" "script_filter failed to resolve $mode wiki-cli path"
}

run_layout_check packaged packaged-cli
run_layout_check release release-cli
run_layout_check debug debug-cli

cat >"$tmp_dir/bin/cargo" <<EOS
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$#" -eq 4 && "\$1" == "build" && "\$2" == "--release" && "\$3" == "-p" && "\$4" == "nils-wiki-cli" ]]; then
  mkdir -p "$repo_root/target/release"
  cat >"$repo_root/target/release/wiki-cli" <<'EOCLI'
#!/usr/bin/env bash
set -euo pipefail
printf '{"items":[]}\n'
EOCLI
  chmod +x "$repo_root/target/release/wiki-cli"
  exit 0
fi

if [[ "\$#" -ge 4 && "\$1" == "run" && "\$2" == "-p" && "\$3" == "nils-workflow-readme-cli" && "\$4" == "--" ]]; then
  exit 0
fi

echo "unexpected cargo invocation: \$*" >&2
exit 1
EOS
chmod +x "$tmp_dir/bin/cargo"

PATH="$tmp_dir/bin:$PATH" "$repo_root/scripts/workflow-pack.sh" --id wiki-search >/dev/null

packaged_dir="$repo_root/build/workflows/wiki-search/pkg"
packaged_plist="$packaged_dir/info.plist"
assert_file "$packaged_plist"
assert_file "$packaged_dir/icon.png"
assert_file "$packaged_dir/assets/icon.png"
assert_file "$packaged_dir/bin/wiki-cli"
assert_file "$packaged_dir/scripts/lib/script_filter_query_policy.sh"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$packaged_plist" >/dev/null || fail "packaged plist lint failed"
fi

packaged_json_file="$tmp_dir/packaged.json"
plist_to_json "$packaged_plist" >"$packaged_json_file"

assert_jq_file "$packaged_json_file" '.objects | length > 0' "packaged plist missing objects"
assert_jq_file "$packaged_json_file" '.connections | length > 0' "packaged plist missing connections"
assert_jq_file "$packaged_json_file" '[.objects[] | select(.type=="alfred.workflow.input.scriptfilter") | .config.type] | all(. == 8)' "script filter objects must be external script type=8"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.scriptfile == "./scripts/script_filter.sh"' "script filter scriptfile wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.keyword == "wk"' "keyword trigger must be wk"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.argumenttype == 1' "keyword argument type must accept optional query"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.scriptargtype == 1' "script filter must pass query via argv"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.alfredfiltersresults == false' "script filter must disable Alfred local filtering"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.queuedelaycustom == 1' "script filter queue delay custom must be 1 second"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.queuedelaymode == 0' "script filter queue delay mode must be custom seconds"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.queuedelayimmediatelyinitially == false' "script filter must disable immediate initial run"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="D7E624DB-D4AB-4D53-8C03-D051A1A97A4A") | .config.scriptfile == "./scripts/action_open.sh"' "action scriptfile wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="D7E624DB-D4AB-4D53-8C03-D051A1A97A4A") | .config.type == 8' "action node must be external script type=8"
assert_jq_file "$packaged_json_file" '.connections["70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10"] | any(.destinationuid == "D7E624DB-D4AB-4D53-8C03-D051A1A97A4A" and .modifiers == 0)' "missing script-filter to action connection"
assert_jq_file "$packaged_json_file" '[.userconfigurationconfig[] | .variable] | sort == ["WIKI_LANGUAGE","WIKI_MAX_RESULTS"]' "user configuration variables mismatch"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="WIKI_LANGUAGE") | .config.default == "en"' "WIKI_LANGUAGE default must be en"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="WIKI_LANGUAGE") | .config.required == false' "WIKI_LANGUAGE must be optional"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="WIKI_MAX_RESULTS") | .config.default == "10"' "WIKI_MAX_RESULTS default must be 10"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="WIKI_MAX_RESULTS") | .config.required == false' "WIKI_MAX_RESULTS must be optional"

echo "ok: wiki-search smoke test"
