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
  TROUBLESHOOTING.md \
  src/info.plist.template \
  src/assets/icon.png \
  scripts/script_filter.sh \
  scripts/script_filter_book.sh \
  scripts/script_filter_anime.sh \
  scripts/script_filter_music.sh \
  scripts/script_filter_game.sh \
  scripts/script_filter_real.sh \
  scripts/action_open.sh \
  scripts/bangumi_scraper.mjs \
  scripts/lib/bangumi_routes.mjs \
  scripts/lib/extract_search.mjs \
  scripts/lib/error_classify.mjs \
  scripts/tests/bangumi_scraper_contract.test.mjs \
  tests/smoke.sh; do
  assert_file "$workflow_dir/$required"
done

for executable in \
  scripts/script_filter.sh \
  scripts/script_filter_book.sh \
  scripts/script_filter_anime.sh \
  scripts/script_filter_music.sh \
  scripts/script_filter_game.sh \
  scripts/script_filter_real.sh \
  scripts/action_open.sh \
  scripts/bangumi_scraper.mjs \
  scripts/tests/bangumi_scraper_contract.test.mjs \
  tests/smoke.sh; do
  assert_exec "$workflow_dir/$executable"
done

require_bin jq
require_bin rg
require_bin node

manifest="$workflow_dir/workflow.toml"
[[ "$(toml_string "$manifest" id)" == "bangumi-search" ]] || fail "workflow id mismatch"
[[ "$(toml_string "$manifest" rust_binary)" == "bangumi-cli" ]] || fail "rust_binary must be bangumi-cli"
[[ "$(toml_string "$manifest" script_filter)" == "script_filter.sh" ]] || fail "script_filter mismatch"
[[ "$(toml_string "$manifest" action)" == "action_open.sh" ]] || fail "action mismatch"

for variable in BANGUMI_API_KEY BANGUMI_MAX_RESULTS BANGUMI_TIMEOUT_MS BANGUMI_USER_AGENT BANGUMI_CACHE_DIR BANGUMI_IMAGE_CACHE_TTL_SECONDS BANGUMI_IMAGE_CACHE_MAX_MB BANGUMI_API_FALLBACK; do
  if ! rg -n "^${variable}[[:space:]]*=" "$manifest" >/dev/null; then
    fail "missing env var in workflow.toml: $variable"
  fi
done

if rg -n "bangumi_scraper" "$workflow_dir/scripts/script_filter.sh" >/dev/null; then
  fail "script_filter must not reference bangumi_scraper"
fi

node --check "$workflow_dir/scripts/bangumi_scraper.mjs" >/dev/null
node --test "$workflow_dir/scripts/tests/bangumi_scraper_contract.test.mjs" >/dev/null

tmp_dir="$(mktemp -d)"
export ALFRED_WORKFLOW_CACHE="$tmp_dir/alfred-cache"
export BANGUMI_QUERY_CACHE_TTL_SECONDS=0
export BANGUMI_QUERY_COALESCE_SETTLE_SECONDS=0
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

release_cli="$repo_root/target/release/bangumi-cli"
release_backup=""
if [[ -f "$release_cli" ]]; then
  release_backup="$tmp_dir/bangumi-cli.release.backup"
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

action_arg="https://bgm.tv/subject/2782"
OPEN_STUB_OUT="$tmp_dir/open-arg.txt" PATH="$tmp_dir/bin:$PATH" \
  "$workflow_dir/scripts/action_open.sh" "$action_arg"
[[ "$(cat "$tmp_dir/open-arg.txt")" == "$action_arg" ]] || fail "action_open.sh must pass URL to open"

cat >"$tmp_dir/stubs/bangumi-cli-ok" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${BANGUMI_STUB_LOG:-}" ]]; then
  printf '%s\n' "$*" >>"$BANGUMI_STUB_LOG"
fi
[[ "${1:-}" == "query" ]] || exit 9
[[ "${2:-}" == "--input" ]] || exit 9
query="${3:-}"
printf '{"items":[{"title":"stub-subject","subtitle":"query=%s","arg":"https://bgm.tv/subject/1","valid":true}]}' "$query"
printf '\n'
EOS
chmod +x "$tmp_dir/stubs/bangumi-cli-ok"

cat >"$tmp_dir/stubs/bangumi-cli-rate-limit" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "rate limit exceeded: status 429" >&2
exit 7
EOS
chmod +x "$tmp_dir/stubs/bangumi-cli-rate-limit"

cat >"$tmp_dir/stubs/bangumi-cli-missing-key" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "missing BANGUMI_API_KEY" >&2
exit 2
EOS
chmod +x "$tmp_dir/stubs/bangumi-cli-missing-key"

cat >"$tmp_dir/stubs/bangumi-cli-unavailable" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "bangumi api request failed: status 503" >&2
exit 7
EOS
chmod +x "$tmp_dir/stubs/bangumi-cli-unavailable"

cat >"$tmp_dir/stubs/bangumi-cli-invalid-config" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "invalid BANGUMI_MAX_RESULTS: not-an-int" >&2
exit 2
EOS
chmod +x "$tmp_dir/stubs/bangumi-cli-invalid-config"

success_json="$({ BANGUMI_CLI_BIN="$tmp_dir/stubs/bangumi-cli-ok" "$workflow_dir/scripts/script_filter.sh" "anime naruto"; })"
assert_jq_json "$success_json" '.items | type == "array" and length == 1' "script_filter success must output items array"
assert_jq_json "$success_json" '.items[0].title == "stub-subject"' "script_filter should forward successful JSON"

env_query_json="$({ BANGUMI_CLI_BIN="$tmp_dir/stubs/bangumi-cli-ok" alfred_workflow_query="book 三体" "$workflow_dir/scripts/script_filter.sh"; })"
assert_jq_json "$env_query_json" '.items[0].subtitle == "query=book 三体"' "script_filter must support Alfred query via env fallback"

stdin_query_json="$(printf 'music evangelion' | BANGUMI_CLI_BIN="$tmp_dir/stubs/bangumi-cli-ok" "$workflow_dir/scripts/script_filter.sh")"
assert_jq_json "$stdin_query_json" '.items[0].subtitle == "query=music evangelion"' "script_filter must support query via stdin fallback"

rate_limit_json="$({ BANGUMI_CLI_BIN="$tmp_dir/stubs/bangumi-cli-rate-limit" "$workflow_dir/scripts/script_filter.sh" "anime naruto"; })"
assert_jq_json "$rate_limit_json" '.items[0].title == "Bangumi API rate-limited"' "rate-limit title mapping mismatch"

missing_key_json="$({ BANGUMI_CLI_BIN="$tmp_dir/stubs/bangumi-cli-missing-key" "$workflow_dir/scripts/script_filter.sh" "anime naruto"; })"
assert_jq_json "$missing_key_json" '.items[0].title == "Bangumi API key is missing"' "missing-key title mapping mismatch"

unavailable_json="$({ BANGUMI_CLI_BIN="$tmp_dir/stubs/bangumi-cli-unavailable" "$workflow_dir/scripts/script_filter.sh" "anime naruto"; })"
assert_jq_json "$unavailable_json" '.items[0].title == "Bangumi API unavailable"' "API unavailable title mapping mismatch"

invalid_config_json="$({ BANGUMI_CLI_BIN="$tmp_dir/stubs/bangumi-cli-invalid-config" "$workflow_dir/scripts/script_filter.sh" "anime naruto"; })"
assert_jq_json "$invalid_config_json" '.items[0].title == "Invalid Bangumi workflow config"' "invalid config title mapping mismatch"

empty_query_json="$({ BANGUMI_CLI_BIN="$tmp_dir/stubs/bangumi-cli-ok" "$workflow_dir/scripts/script_filter.sh" "   "; })"
assert_jq_json "$empty_query_json" '.items[0].title == "Enter a search query"' "empty query guidance title mismatch"
assert_jq_json "$empty_query_json" '.items[0].valid == false' "empty query item must be invalid"

short_query_log="$tmp_dir/bangumi-short-query.log"
short_query_json="$({ BANGUMI_STUB_LOG="$short_query_log" BANGUMI_CLI_BIN="$tmp_dir/stubs/bangumi-cli-ok" "$workflow_dir/scripts/script_filter.sh" "a"; })"
assert_jq_json "$short_query_json" '.items[0].title == "Keep typing (2+ chars)"' "short query guidance title mismatch"
[[ ! -s "$short_query_log" ]] || fail "short query should not invoke bangumi-cli backend"

book_shortcut_json="$({ BANGUMI_CLI_BIN="$tmp_dir/stubs/bangumi-cli-ok" "$workflow_dir/scripts/script_filter_book.sh" "三体"; })"
assert_jq_json "$book_shortcut_json" '.items[0].subtitle == "query=book 三体"' "book shortcut must inject default type"

anime_shortcut_json="$({ BANGUMI_CLI_BIN="$tmp_dir/stubs/bangumi-cli-ok" "$workflow_dir/scripts/script_filter_anime.sh" "evangelion"; })"
assert_jq_json "$anime_shortcut_json" '.items[0].subtitle == "query=anime evangelion"' "anime shortcut must inject default type"

music_shortcut_json="$({ BANGUMI_CLI_BIN="$tmp_dir/stubs/bangumi-cli-ok" "$workflow_dir/scripts/script_filter_music.sh" "utada"; })"
assert_jq_json "$music_shortcut_json" '.items[0].subtitle == "query=music utada"' "music shortcut must inject default type"

game_shortcut_json="$({ BANGUMI_CLI_BIN="$tmp_dir/stubs/bangumi-cli-ok" "$workflow_dir/scripts/script_filter_game.sh" "zelda"; })"
assert_jq_json "$game_shortcut_json" '.items[0].subtitle == "query=game zelda"' "game shortcut must inject default type"

real_shortcut_json="$({ BANGUMI_CLI_BIN="$tmp_dir/stubs/bangumi-cli-ok" "$workflow_dir/scripts/script_filter_real.sh" "interstellar"; })"
assert_jq_json "$real_shortcut_json" '.items[0].subtitle == "query=real interstellar"' "real shortcut must inject default type"

book_shortcut_override_json="$({ BANGUMI_CLI_BIN="$tmp_dir/stubs/bangumi-cli-ok" "$workflow_dir/scripts/script_filter_book.sh" "anime naruto"; })"
assert_jq_json "$book_shortcut_override_json" '.items[0].subtitle == "query=anime naruto"' "explicit subject type should override shortcut default"

make_layout_cli() {
  local target="$1"
  local marker="$2"
  mkdir -p "$(dirname "$target")"
  cat >"$target" <<EOS
#!/usr/bin/env bash
set -euo pipefail
printf '{"items":[{"title":"${marker}","subtitle":"ok","arg":"https://bgm.tv/subject/1","valid":true}]}'
printf '\\n'
EOS
  chmod +x "$target"
}

run_layout_check() {
  local mode="$1"
  local marker="$2"
  local layout="$tmp_dir/layout-$mode"
  local copied_script="$layout/workflows/bangumi-search/scripts/script_filter.sh"

  mkdir -p "$(dirname "$copied_script")"
  cp "$workflow_dir/scripts/script_filter.sh" "$copied_script"
  chmod +x "$copied_script"
  mkdir -p "$layout/workflows/bangumi-search/scripts/lib"
  cp "$repo_root/scripts/lib/script_filter_query_policy.sh" "$layout/workflows/bangumi-search/scripts/lib/script_filter_query_policy.sh"
  cp "$repo_root/scripts/lib/script_filter_async_coalesce.sh" "$layout/workflows/bangumi-search/scripts/lib/script_filter_async_coalesce.sh"

  case "$mode" in
  packaged)
    make_layout_cli "$layout/workflows/bangumi-search/bin/bangumi-cli" "$marker"
    ;;
  release)
    make_layout_cli "$layout/target/release/bangumi-cli" "$marker"
    ;;
  debug)
    make_layout_cli "$layout/target/debug/bangumi-cli" "$marker"
    ;;
  *)
    fail "unsupported layout mode: $mode"
    ;;
  esac

  local output
  output="$(BANGUMI_QUERY_COALESCE_SETTLE_SECONDS=0 BANGUMI_QUERY_CACHE_TTL_SECONDS=0 "$copied_script" "anime naruto")"
  assert_jq_json "$output" ".items[0].title == \"$marker\"" "script_filter failed to resolve $mode bangumi-cli path"
}

run_layout_check packaged packaged-cli
run_layout_check release release-cli
run_layout_check debug debug-cli

cat >"$tmp_dir/bin/cargo" <<EOS
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$#" -eq 4 && "\$1" == "build" && "\$2" == "--release" && "\$3" == "-p" && "\$4" == "nils-bangumi-cli" ]]; then
  mkdir -p "$repo_root/target/release"
  cat >"$repo_root/target/release/bangumi-cli" <<'EOCLI'
#!/usr/bin/env bash
set -euo pipefail
printf '{"items":[]}\n'
EOCLI
  chmod +x "$repo_root/target/release/bangumi-cli"
  exit 0
fi

if [[ "\$#" -ge 4 && "\$1" == "run" && "\$2" == "-p" && "\$3" == "nils-workflow-readme-cli" && "\$4" == "--" ]]; then
  exit 0
fi

echo "unexpected cargo invocation: \$*" >&2
exit 1
EOS
chmod +x "$tmp_dir/bin/cargo"

PATH="$tmp_dir/bin:$PATH" "$repo_root/scripts/workflow-pack.sh" --id bangumi-search >/dev/null

packaged_dir="$repo_root/build/workflows/bangumi-search/pkg"
packaged_plist="$packaged_dir/info.plist"
assert_file "$packaged_plist"
assert_file "$packaged_dir/icon.png"
assert_file "$packaged_dir/assets/icon.png"
assert_file "$packaged_dir/bin/bangumi-cli"
assert_file "$packaged_dir/scripts/script_filter.sh"
assert_file "$packaged_dir/scripts/script_filter_book.sh"
assert_file "$packaged_dir/scripts/script_filter_anime.sh"
assert_file "$packaged_dir/scripts/script_filter_music.sh"
assert_file "$packaged_dir/scripts/script_filter_game.sh"
assert_file "$packaged_dir/scripts/script_filter_real.sh"
assert_file "$packaged_dir/scripts/bangumi_scraper.mjs"
assert_file "$packaged_dir/scripts/lib/bangumi_routes.mjs"
assert_file "$packaged_dir/scripts/lib/extract_search.mjs"
assert_file "$packaged_dir/scripts/lib/error_classify.mjs"
assert_file "$packaged_dir/scripts/lib/script_filter_query_policy.sh"
assert_file "$packaged_dir/scripts/lib/script_filter_async_coalesce.sh"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$packaged_plist" >/dev/null || fail "packaged plist lint failed"
fi

packaged_json_file="$tmp_dir/packaged.json"
plist_to_json "$packaged_plist" >"$packaged_json_file"

assert_jq_file "$packaged_json_file" '.objects | length > 0' "packaged plist missing objects"
assert_jq_file "$packaged_json_file" '.connections | length > 0' "packaged plist missing connections"
assert_jq_file "$packaged_json_file" '[.objects[] | select(.type=="alfred.workflow.input.scriptfilter") | .config.type] | all(. == 8)' "script filter objects must be external script type=8"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.scriptfile == "./scripts/script_filter.sh"' "script filter scriptfile wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.keyword == "bgm"' "keyword trigger must be bgm"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="B48A5D8C-5F5E-4709-A8A2-1BDB89E4E201") | .config.scriptfile == "./scripts/script_filter_book.sh"' "book script filter scriptfile wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="B48A5D8C-5F5E-4709-A8A2-1BDB89E4E201") | .config.keyword == "bgmb"' "keyword trigger must be bgmb"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="912ADAAE-E70D-4B1E-A138-E7F3D0D670F2") | .config.scriptfile == "./scripts/script_filter_anime.sh"' "anime script filter scriptfile wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="912ADAAE-E70D-4B1E-A138-E7F3D0D670F2") | .config.keyword == "bgma"' "keyword trigger must be bgma"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="8C8FD5A4-4C37-4ED4-A8E8-3D613F2CE8B9") | .config.scriptfile == "./scripts/script_filter_music.sh"' "music script filter scriptfile wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="8C8FD5A4-4C37-4ED4-A8E8-3D613F2CE8B9") | .config.keyword == "bgmm"' "keyword trigger must be bgmm"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="D9C69B12-6594-4A0A-B0AA-4F6B3DEFD5A6") | .config.scriptfile == "./scripts/script_filter_game.sh"' "game script filter scriptfile wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="D9C69B12-6594-4A0A-B0AA-4F6B3DEFD5A6") | .config.keyword == "bgmg"' "keyword trigger must be bgmg"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="F3F8745F-C75C-4058-BCE5-7F95A77A9C3E") | .config.scriptfile == "./scripts/script_filter_real.sh"' "real script filter scriptfile wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="F3F8745F-C75C-4058-BCE5-7F95A77A9C3E") | .config.keyword == "bgmr"' "keyword trigger must be bgmr"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.queuedelaycustom == 1' "script filter queue delay custom must be 1 second"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.queuedelayimmediatelyinitially == false' "script filter must disable immediate initial run"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="D7E624DB-D4AB-4D53-8C03-D051A1A97A4A") | .config.scriptfile == "./scripts/action_open.sh"' "action scriptfile wiring mismatch"
assert_jq_file "$packaged_json_file" '.connections["70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10"] | any(.destinationuid == "D7E624DB-D4AB-4D53-8C03-D051A1A97A4A" and .modifiers == 0)' "missing script-filter to action connection"
assert_jq_file "$packaged_json_file" '.connections["B48A5D8C-5F5E-4709-A8A2-1BDB89E4E201"] | any(.destinationuid == "D7E624DB-D4AB-4D53-8C03-D051A1A97A4A" and .modifiers == 0)' "missing book script-filter to action connection"
assert_jq_file "$packaged_json_file" '.connections["912ADAAE-E70D-4B1E-A138-E7F3D0D670F2"] | any(.destinationuid == "D7E624DB-D4AB-4D53-8C03-D051A1A97A4A" and .modifiers == 0)' "missing anime script-filter to action connection"
assert_jq_file "$packaged_json_file" '.connections["8C8FD5A4-4C37-4ED4-A8E8-3D613F2CE8B9"] | any(.destinationuid == "D7E624DB-D4AB-4D53-8C03-D051A1A97A4A" and .modifiers == 0)' "missing music script-filter to action connection"
assert_jq_file "$packaged_json_file" '.connections["D9C69B12-6594-4A0A-B0AA-4F6B3DEFD5A6"] | any(.destinationuid == "D7E624DB-D4AB-4D53-8C03-D051A1A97A4A" and .modifiers == 0)' "missing game script-filter to action connection"
assert_jq_file "$packaged_json_file" '.connections["F3F8745F-C75C-4058-BCE5-7F95A77A9C3E"] | any(.destinationuid == "D7E624DB-D4AB-4D53-8C03-D051A1A97A4A" and .modifiers == 0)' "missing real script-filter to action connection"
assert_jq_file "$packaged_json_file" '[.userconfigurationconfig[].variable] | sort == ["BANGUMI_API_FALLBACK","BANGUMI_API_KEY","BANGUMI_CACHE_DIR","BANGUMI_IMAGE_CACHE_MAX_MB","BANGUMI_IMAGE_CACHE_TTL_SECONDS","BANGUMI_MAX_RESULTS","BANGUMI_TIMEOUT_MS","BANGUMI_USER_AGENT"]' "user configuration variables mismatch"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="BANGUMI_MAX_RESULTS") | .config.default == "10"' "BANGUMI_MAX_RESULTS default must be 10"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="BANGUMI_TIMEOUT_MS") | .config.default == "8000"' "BANGUMI_TIMEOUT_MS default must be 8000"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="BANGUMI_API_FALLBACK") | .config.default == "auto"' "BANGUMI_API_FALLBACK default must be auto"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="BANGUMI_API_KEY") | .config.default == ""' "BANGUMI_API_KEY default must be empty"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="BANGUMI_CACHE_DIR") | .config.default == ""' "BANGUMI_CACHE_DIR default must be empty"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="BANGUMI_IMAGE_CACHE_TTL_SECONDS") | .config.default == "86400"' "BANGUMI_IMAGE_CACHE_TTL_SECONDS default must be 86400"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="BANGUMI_IMAGE_CACHE_MAX_MB") | .config.default == "128"' "BANGUMI_IMAGE_CACHE_MAX_MB default must be 128"

echo "ok: bangumi-search smoke test"
