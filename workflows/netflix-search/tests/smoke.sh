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
require_bin rg

manifest="$workflow_dir/workflow.toml"
[[ "$(toml_string "$manifest" id)" == "netflix-search" ]] || fail "workflow id mismatch"
[[ "$(toml_string "$manifest" rust_binary)" == "brave-cli" ]] || fail "rust_binary must be brave-cli"
[[ "$(toml_string "$manifest" script_filter)" == "script_filter.sh" ]] || fail "script_filter mismatch"
[[ "$(toml_string "$manifest" action)" == "action_open.sh" ]] || fail "action mismatch"

for variable in BRAVE_API_KEY BRAVE_MAX_RESULTS BRAVE_SAFESEARCH NETFLIX_CATALOG_REGION BRAVE_COUNTRY; do
  if ! rg -n "^${variable}[[:space:]]*=" "$manifest" >/dev/null; then
    fail "missing env var in workflow.toml: $variable"
  fi
done

manifest_catalog_line="$(rg -n '^NETFLIX_CATALOG_REGION[[:space:]]*=' "$manifest" | head -n1 | cut -d: -f1)"
manifest_country_line="$(rg -n '^BRAVE_COUNTRY[[:space:]]*=' "$manifest" | head -n1 | cut -d: -f1)"
[[ -n "$manifest_catalog_line" && -n "$manifest_country_line" ]] || fail "manifest variable order check missing NETFLIX_CATALOG_REGION or BRAVE_COUNTRY"
((manifest_catalog_line < manifest_country_line)) || fail "NETFLIX_CATALOG_REGION must appear before BRAVE_COUNTRY in workflow.toml"

tmp_dir="$(mktemp -d)"
export ALFRED_WORKFLOW_CACHE="$tmp_dir/alfred-cache"
export BRAVE_QUERY_CACHE_TTL_SECONDS=0
export BRAVE_QUERY_COALESCE_SETTLE_SECONDS=0
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

release_cli="$repo_root/target/release/brave-cli"
release_backup=""
if [[ -f "$release_cli" ]]; then
  release_backup="$tmp_dir/brave-cli.release.backup"
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

action_arg="https://www.netflix.com/title/81280792"
OPEN_STUB_OUT="$tmp_dir/open-arg.txt" PATH="$tmp_dir/bin:$PATH" \
  "$workflow_dir/scripts/action_open.sh" "$action_arg"
[[ "$(cat "$tmp_dir/open-arg.txt")" == "$action_arg" ]] || fail "action_open.sh must pass URL to open"

cat >"$tmp_dir/stubs/brave-cli-ok" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${BRAVE_STUB_LOG:-}" ]]; then
  printf '%s\n' "$*" >>"$BRAVE_STUB_LOG"
fi
[[ "${1:-}" == "search" ]] || exit 9
[[ "${2:-}" == "--query" ]] || exit 9
query="${3:-}"
printf '{"items":[{"title":"stub-result","subtitle":"query=%s","arg":"https://www.netflix.com/title/80057281","valid":true}]}' "$query"
printf '\n'
EOS
chmod +x "$tmp_dir/stubs/brave-cli-ok"

cat >"$tmp_dir/stubs/brave-cli-rate-limit" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "rate limit exceeded" >&2
exit 7
EOS
chmod +x "$tmp_dir/stubs/brave-cli-rate-limit"

cat >"$tmp_dir/stubs/brave-cli-missing-key" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "error: missing BRAVE_API_KEY" >&2
exit 2
EOS
chmod +x "$tmp_dir/stubs/brave-cli-missing-key"

cat >"$tmp_dir/stubs/brave-cli-unavailable" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "transport error: connection reset by peer" >&2
exit 3
EOS
chmod +x "$tmp_dir/stubs/brave-cli-unavailable"

cat >"$tmp_dir/stubs/brave-cli-country-422-fallback" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${BRAVE_STUB_LOG:-}" ]]; then
  printf 'country=%s args=%s\n' "${BRAVE_COUNTRY-}" "$*" >>"$BRAVE_STUB_LOG"
fi
[[ "${1:-}" == "search" ]] || exit 9
[[ "${2:-}" == "--query" ]] || exit 9
query="${3:-}"
if [[ -n "${BRAVE_COUNTRY:-}" ]]; then
  echo "HTTP 422 Unable to validate request parameter(s)" >&2
  exit 22
fi
printf '{"items":[{"title":"stub-country-fallback","subtitle":"query=%s","arg":"https://www.netflix.com/title/80057281","valid":true}]}' "$query"
printf '\n'
EOS
chmod +x "$tmp_dir/stubs/brave-cli-country-422-fallback"

success_json="$({ BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" "$workflow_dir/scripts/script_filter.sh" "dark"; })"
assert_jq_json "$success_json" '.items | type == "array" and length == 1' "script_filter success must output items array"
assert_jq_json "$success_json" '.items[0].title == "stub-result"' "script_filter should forward successful JSON"
assert_jq_json "$success_json" '.items[0].subtitle == "query=site:netflix.com/title dark"' "script_filter should prefix query with netflix site filter"

country_success_log="$tmp_dir/netflix-country-success.log"
country_success_json="$({ BRAVE_STUB_LOG="$country_success_log" BRAVE_COUNTRY=TW BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" "$workflow_dir/scripts/script_filter.sh" "dark"; })"
assert_jq_json "$country_success_json" '.items[0].subtitle == "query=site:netflix.com/tw/title dark"' "country-scoped query should use BRAVE_COUNTRY fallback when NETFLIX_CATALOG_REGION is unset"
country_success_hits="$(wc -l <"$country_success_log" | tr -d '[:space:]')"
[[ "$country_success_hits" == "1" ]] || fail "country-scoped success should call backend once"

netflix_catalog_region_override_json="$({ BRAVE_COUNTRY=US NETFLIX_CATALOG_REGION=TW BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" "$workflow_dir/scripts/script_filter.sh" "dark"; })"
assert_jq_json "$netflix_catalog_region_override_json" '.items[0].subtitle == "query=site:netflix.com/tw/title dark"' "NETFLIX_CATALOG_REGION should override BRAVE_COUNTRY for site scope"

netflix_catalog_region_us_override_json="$({ BRAVE_COUNTRY=TW NETFLIX_CATALOG_REGION=US BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" "$workflow_dir/scripts/script_filter.sh" "dark"; })"
assert_jq_json "$netflix_catalog_region_us_override_json" '.items[0].subtitle == "query=site:netflix.com/title dark"' "NETFLIX_CATALOG_REGION=US should force global site scope"

netflix_catalog_region_invalid_fallback_json="$({ BRAVE_COUNTRY=TW NETFLIX_CATALOG_REGION=9Z BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" "$workflow_dir/scripts/script_filter.sh" "dark"; })"
assert_jq_json "$netflix_catalog_region_invalid_fallback_json" '.items[0].subtitle == "query=site:netflix.com/tw/title dark"' "invalid NETFLIX_CATALOG_REGION should fallback to BRAVE_COUNTRY"

netflix_catalog_region_unmapped_json="$({ BRAVE_COUNTRY=TW NETFLIX_CATALOG_REGION=ZZ BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" "$workflow_dir/scripts/script_filter.sh" "dark"; })"
assert_jq_json "$netflix_catalog_region_unmapped_json" '.items[0].subtitle == "query=site:netflix.com/title dark"' "NETFLIX_CATALOG_REGION should control site scope even when unmapped"

us_map_log="$tmp_dir/netflix-us-map.log"
us_map_json="$({ BRAVE_STUB_LOG="$us_map_log" BRAVE_COUNTRY=US BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" "$workflow_dir/scripts/script_filter.sh" "dark"; })"
assert_jq_json "$us_map_json" '.items[0].subtitle == "query=site:netflix.com/title dark"' "US country mapping should use global netflix title scope"
[[ "$(grep -c -- '--query site:netflix.com/title dark --mode' "$us_map_log" || true)" -eq 1 ]] || fail "US country mapping should call backend once with global title scope"
[[ "$(wc -l <"$us_map_log" | tr -d '[:space:]')" == "1" ]] || fail "US mapping should not trigger fallback query"

invalid_country_json="$({ BRAVE_COUNTRY=9Z BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" "$workflow_dir/scripts/script_filter.sh" "dark"; })"
assert_jq_json "$invalid_country_json" '.items[0].subtitle == "query=site:netflix.com/title dark"' "invalid BRAVE_COUNTRY should fallback to global scope"

unmapped_country_json="$({ BRAVE_COUNTRY=ZZ BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" "$workflow_dir/scripts/script_filter.sh" "dark"; })"
assert_jq_json "$unmapped_country_json" '.items[0].subtitle == "query=site:netflix.com/title dark"' "unmapped BRAVE_COUNTRY should use global scope"

country_422_log="$tmp_dir/netflix-country-422.log"
country_422_json="$({ BRAVE_STUB_LOG="$country_422_log" BRAVE_COUNTRY=VN BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-country-422-fallback" "$workflow_dir/scripts/script_filter.sh" "dark"; })"
assert_jq_json "$country_422_json" '.items[0].title == "stub-country-fallback"' "country 422 fallback should still return search results"
assert_jq_json "$country_422_json" '.items[0].subtitle == "query=site:netflix.com/vn/title dark"' "country 422 fallback should keep netflix regional site scope"
[[ "$(wc -l <"$country_422_log" | tr -d '[:space:]')" == "2" ]] || fail "country 422 fallback should retry backend once without BRAVE_COUNTRY"
[[ "$(grep -c '^country=VN args=' "$country_422_log" || true)" -eq 1 ]] || fail "country 422 fallback first call must keep BRAVE_COUNTRY"
[[ "$(grep -c '^country= args=' "$country_422_log" || true)" -eq 1 ]] || fail "country 422 fallback second call must unset BRAVE_COUNTRY"

env_query_json="$({ BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" alfred_workflow_query="arcane" "$workflow_dir/scripts/script_filter.sh"; })"
assert_jq_json "$env_query_json" '.items[0].subtitle == "query=site:netflix.com/title arcane"' "script_filter must support env fallback and apply site filter"

stdin_query_json="$(printf 'stranger things' | BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" "$workflow_dir/scripts/script_filter.sh")"
assert_jq_json "$stdin_query_json" '.items[0].subtitle == "query=site:netflix.com/title stranger things"' "script_filter must support stdin fallback and apply site filter"

rate_limit_json="$({ BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-rate-limit" "$workflow_dir/scripts/script_filter.sh" "dark"; })"
assert_jq_json "$rate_limit_json" '.items | type == "array" and length == 1' "rate-limit fallback must output single item"
assert_jq_json "$rate_limit_json" '.items[0].valid == false' "rate-limit fallback item must be invalid"
assert_jq_json "$rate_limit_json" '.items[0].title == "Brave API rate limited"' "rate-limit title mapping mismatch"

missing_key_json="$({ BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-missing-key" "$workflow_dir/scripts/script_filter.sh" "dark"; })"
assert_jq_json "$missing_key_json" '.items[0].title == "Brave API key is missing"' "missing-key title mapping mismatch"
assert_jq_json "$missing_key_json" '.items[0].subtitle | contains("BRAVE_API_KEY")' "missing-key subtitle should mention BRAVE_API_KEY"

unavailable_json="$({ BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-unavailable" "$workflow_dir/scripts/script_filter.sh" "dark"; })"
assert_jq_json "$unavailable_json" '.items[0].title == "Brave API unavailable"' "unavailable title mapping mismatch"

empty_query_json="$({ BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" "$workflow_dir/scripts/script_filter.sh" "   "; })"
assert_jq_json "$empty_query_json" '.items[0].title == "Enter a search query"' "empty query guidance title mismatch"
assert_jq_json "$empty_query_json" '.items[0].valid == false' "empty query guidance item must be invalid"

short_query_log="$tmp_dir/netflix-short-query.log"
short_query_json="$({ BRAVE_STUB_LOG="$short_query_log" BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" "$workflow_dir/scripts/script_filter.sh" "n"; })"
assert_jq_json "$short_query_json" '.items[0].title == "Keep typing (2+ chars)"' "short query guidance title mismatch"
assert_jq_json "$short_query_json" '.items[0].subtitle | contains("2")' "short query guidance subtitle must mention minimum length"
[[ ! -s "$short_query_log" ]] || fail "short query should not invoke brave-cli backend"

default_cache_log="$tmp_dir/netflix-default-cache.log"
{
  BRAVE_STUB_LOG="$default_cache_log" BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" \
    env -u BRAVE_QUERY_CACHE_TTL_SECONDS "$workflow_dir/scripts/script_filter.sh" "dark" >/dev/null
  BRAVE_STUB_LOG="$default_cache_log" BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" \
    env -u BRAVE_QUERY_CACHE_TTL_SECONDS "$workflow_dir/scripts/script_filter.sh" "dark" >/dev/null
}
default_cache_hits="$(wc -l <"$default_cache_log" | tr -d '[:space:]')"
[[ "$default_cache_hits" == "2" ]] || fail "default query cache must be disabled for netflix-search"

opt_in_cache_log="$tmp_dir/netflix-opt-in-cache.log"
{
  BRAVE_STUB_LOG="$opt_in_cache_log" BRAVE_QUERY_CACHE_TTL_SECONDS=10 BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" \
    "$workflow_dir/scripts/script_filter.sh" "dark" >/dev/null
  BRAVE_STUB_LOG="$opt_in_cache_log" BRAVE_QUERY_CACHE_TTL_SECONDS=10 BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" \
    "$workflow_dir/scripts/script_filter.sh" "dark" >/dev/null
}
opt_in_cache_hits="$(wc -l <"$opt_in_cache_log" | tr -d '[:space:]')"
[[ "$opt_in_cache_hits" == "1" ]] || fail "query cache should work when BRAVE_QUERY_CACHE_TTL_SECONDS is explicitly set"

coalesce_probe_log="$tmp_dir/netflix-coalesce.log"
coalesce_pending_a="$({ BRAVE_STUB_LOG="$coalesce_probe_log" BRAVE_QUERY_CACHE_TTL_SECONDS=0 BRAVE_QUERY_COALESCE_SETTLE_SECONDS=1 BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" "$workflow_dir/scripts/script_filter.sh" "mayda"; })"
coalesce_pending_b="$({ BRAVE_STUB_LOG="$coalesce_probe_log" BRAVE_QUERY_CACHE_TTL_SECONDS=0 BRAVE_QUERY_COALESCE_SETTLE_SECONDS=1 BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" "$workflow_dir/scripts/script_filter.sh" "mayday"; })"
sleep 1
coalesce_result="$({ BRAVE_STUB_LOG="$coalesce_probe_log" BRAVE_QUERY_CACHE_TTL_SECONDS=0 BRAVE_QUERY_COALESCE_SETTLE_SECONDS=1 BRAVE_CLI_BIN="$tmp_dir/stubs/brave-cli-ok" "$workflow_dir/scripts/script_filter.sh" "mayday"; })"
assert_jq_json "$coalesce_pending_a" '.items[0].title == "Searching Netflix titles..."' "coalesce first pending title mismatch"
assert_jq_json "$coalesce_pending_b" '.items[0].title == "Searching Netflix titles..."' "coalesce second pending title mismatch"
assert_jq_json "$coalesce_result" '.items[0].subtitle == "query=site:netflix.com/title mayday"' "coalesce final query mismatch"
[[ "$(grep -c -- '--query site:netflix.com/title mayda --mode' "$coalesce_probe_log" || true)" -eq 0 ]] || fail "coalesce should avoid mayda backend invocation"
[[ "$(grep -c -- '--query site:netflix.com/title mayday --mode' "$coalesce_probe_log" || true)" -eq 1 ]] || fail "coalesce should invoke mayday exactly once"

make_layout_cli() {
  local target="$1"
  local marker="$2"
  mkdir -p "$(dirname "$target")"
  cat >"$target" <<EOS
#!/usr/bin/env bash
set -euo pipefail
printf '{"items":[{"title":"${marker}","subtitle":"ok","arg":"https://example.com","valid":true}]}'
printf '\n'
EOS
  chmod +x "$target"
}

run_layout_check() {
  local mode="$1"
  local marker="$2"
  local layout="$tmp_dir/layout-$mode"
  local copied_script="$layout/workflows/netflix-search/scripts/script_filter.sh"

  mkdir -p "$(dirname "$copied_script")"
  cp "$workflow_dir/scripts/script_filter.sh" "$copied_script"
  chmod +x "$copied_script"
  mkdir -p "$layout/workflows/netflix-search/scripts/lib"
  cp "$repo_root/scripts/lib/script_filter_error_json.sh" "$layout/workflows/netflix-search/scripts/lib/script_filter_error_json.sh"
  cp "$repo_root/scripts/lib/workflow_cli_resolver.sh" "$layout/workflows/netflix-search/scripts/lib/workflow_cli_resolver.sh"
  cp "$repo_root/scripts/lib/script_filter_query_policy.sh" "$layout/workflows/netflix-search/scripts/lib/script_filter_query_policy.sh"
  cp "$repo_root/scripts/lib/script_filter_async_coalesce.sh" "$layout/workflows/netflix-search/scripts/lib/script_filter_async_coalesce.sh"
  cp "$repo_root/scripts/lib/script_filter_search_driver.sh" "$layout/workflows/netflix-search/scripts/lib/script_filter_search_driver.sh"

  case "$mode" in
  packaged)
    make_layout_cli "$layout/workflows/netflix-search/bin/brave-cli" "$marker"
    ;;
  release)
    make_layout_cli "$layout/target/release/brave-cli" "$marker"
    ;;
  debug)
    make_layout_cli "$layout/target/debug/brave-cli" "$marker"
    ;;
  *)
    fail "unsupported layout mode: $mode"
    ;;
  esac

  local output
  output="$(BRAVE_QUERY_COALESCE_SETTLE_SECONDS=0 BRAVE_QUERY_CACHE_TTL_SECONDS=0 "$copied_script" "demo")"
  assert_jq_json "$output" ".items[0].title == \"$marker\"" "script_filter failed to resolve $mode brave-cli path"
}

run_layout_check packaged packaged-cli
run_layout_check release release-cli
run_layout_check debug debug-cli

cat >"$tmp_dir/bin/cargo" <<EOS
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$#" -eq 4 && "\$1" == "build" && "\$2" == "--release" && "\$3" == "-p" && "\$4" == "nils-brave-cli" ]]; then
  mkdir -p "$repo_root/target/release"
  cat >"$repo_root/target/release/brave-cli" <<'EOCLI'
#!/usr/bin/env bash
set -euo pipefail
printf '{"items":[]}\n'
EOCLI
  chmod +x "$repo_root/target/release/brave-cli"
  exit 0
fi

if [[ "\$#" -ge 4 && "\$1" == "run" && "\$2" == "-p" && "\$3" == "nils-workflow-readme-cli" && "\$4" == "--" ]]; then
  exit 0
fi

echo "unexpected cargo invocation: \$*" >&2
exit 1
EOS
chmod +x "$tmp_dir/bin/cargo"

PATH="$tmp_dir/bin:$PATH" "$repo_root/scripts/workflow-pack.sh" --id netflix-search >/dev/null

packaged_dir="$repo_root/build/workflows/netflix-search/pkg"
packaged_plist="$packaged_dir/info.plist"
assert_file "$packaged_plist"
assert_file "$packaged_dir/icon.png"
assert_file "$packaged_dir/assets/icon.png"
assert_file "$packaged_dir/bin/brave-cli"
assert_file "$packaged_dir/scripts/lib/script_filter_error_json.sh"
assert_file "$packaged_dir/scripts/lib/workflow_cli_resolver.sh"
assert_file "$packaged_dir/scripts/lib/script_filter_query_policy.sh"
assert_file "$packaged_dir/scripts/lib/script_filter_async_coalesce.sh"
assert_file "$packaged_dir/scripts/lib/script_filter_search_driver.sh"
assert_file "$packaged_dir/scripts/lib/workflow_action_open_url.sh"
assert_file "$packaged_dir/scripts/country_map.sh"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$packaged_plist" >/dev/null || fail "packaged plist lint failed"
fi

packaged_json_file="$tmp_dir/packaged.json"
plist_to_json "$packaged_plist" >"$packaged_json_file"

assert_jq_file "$packaged_json_file" '.objects | length > 0' "packaged plist missing objects"
assert_jq_file "$packaged_json_file" '.connections | length > 0' "packaged plist missing connections"
assert_jq_file "$packaged_json_file" '[.objects[] | select(.type=="alfred.workflow.input.scriptfilter") | .config.type] | all(. == 8)' "script filter objects must be external script type=8"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.scriptfile == "./scripts/script_filter.sh"' "script filter scriptfile wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.keyword == "nf||netflix"' "keyword trigger must be nf||netflix"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.scriptargtype == 1' "script filter must pass query via argv"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.alfredfiltersresults == false' "script filter must disable Alfred local filtering"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.queuedelaycustom == 1' "script filter queue delay custom must be 1 second"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.queuedelaymode == 0' "script filter queue delay mode must be custom seconds"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10") | .config.queuedelayimmediatelyinitially == false' "script filter must disable immediate initial run"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="D7E624DB-D4AB-4D53-8C03-D051A1A97A4A") | .config.scriptfile == "./scripts/action_open.sh"' "action scriptfile wiring mismatch"
assert_jq_file "$packaged_json_file" '.objects[] | select(.uid=="D7E624DB-D4AB-4D53-8C03-D051A1A97A4A") | .config.type == 8' "action node must be external script type=8"
assert_jq_file "$packaged_json_file" '.connections["70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10"] | any(.destinationuid == "D7E624DB-D4AB-4D53-8C03-D051A1A97A4A" and .modifiers == 0)' "missing script-filter to action connection"
assert_jq_file "$packaged_json_file" '[.userconfigurationconfig[] | .variable] == ["BRAVE_API_KEY","BRAVE_MAX_RESULTS","BRAVE_SAFESEARCH","NETFLIX_CATALOG_REGION","BRAVE_COUNTRY"]' "user configuration variable order mismatch"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="BRAVE_API_KEY") | .config.required == true' "BRAVE_API_KEY must be required"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="BRAVE_MAX_RESULTS") | .config.default == "10"' "BRAVE_MAX_RESULTS default must be 10"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="BRAVE_SAFESEARCH") | .config.default == "off"' "BRAVE_SAFESEARCH default must be off"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="BRAVE_COUNTRY") | .config.required == false' "BRAVE_COUNTRY must be optional"
assert_jq_file "$packaged_json_file" '.userconfigurationconfig[] | select(.variable=="NETFLIX_CATALOG_REGION") | .config.required == false' "NETFLIX_CATALOG_REGION must be optional"

echo "ok: netflix-search smoke test"
