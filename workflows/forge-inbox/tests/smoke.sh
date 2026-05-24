#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workflow_dir="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$workflow_dir/../.." && pwd)"
smoke_helper="$repo_root/scripts/lib/workflow_smoke_helpers.sh"

if [[ ! -f "$smoke_helper" ]]; then
  echo "missing required helper: $smoke_helper" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$smoke_helper"

for required in \
  workflow.toml \
  README.md \
  TROUBLESHOOTING.md \
  src/info.plist.template \
  src/assets/icon.png \
  src/assets/icon-github.png \
  src/assets/icon-gitlab.png \
  scripts/script_filter.sh \
  scripts/script_filter_github.sh \
  scripts/script_filter_gitlab.sh \
  scripts/action_open.sh \
  tests/smoke.sh; do
  assert_file "$workflow_dir/$required"
done

for executable in \
  scripts/script_filter.sh \
  scripts/script_filter_github.sh \
  scripts/script_filter_gitlab.sh \
  scripts/action_open.sh \
  tests/smoke.sh; do
  assert_exec "$workflow_dir/$executable"
done

require_bin jq
require_bin rg

manifest="$workflow_dir/workflow.toml"
plist_template="$workflow_dir/src/info.plist.template"
script_filter="$workflow_dir/scripts/script_filter.sh"
script_filter_github="$workflow_dir/scripts/script_filter_github.sh"
script_filter_gitlab="$workflow_dir/scripts/script_filter_gitlab.sh"
action_open="$workflow_dir/scripts/action_open.sh"

[[ "$(toml_string "$manifest" id)" == "forge-inbox" ]] || fail "workflow id mismatch"
[[ "$(toml_string "$manifest" script_filter)" == "script_filter.sh" ]] || fail "script_filter mismatch"
[[ "$(toml_string "$manifest" action)" == "action_open.sh" ]] || fail "action mismatch"
if rg -n '^rust_binary[[:space:]]*=' "$manifest" >/dev/null; then
  fail "rust_binary must be omitted for external forge-cli runtime"
fi
if ! rg -n '^FORGE_CLI_BIN[[:space:]]*=[[:space:]]*""' "$manifest" >/dev/null; then
  fail "FORGE_CLI_BIN default must be empty"
fi
if ! rg -n '^FORGE_INBOX_GITLAB_HOST[[:space:]]*=[[:space:]]*""' "$manifest" >/dev/null; then
  fail "FORGE_INBOX_GITLAB_HOST default must be empty"
fi
for empty_env in \
  FORGE_INBOX_GITLAB_VPN \
  FORGE_INBOX_GITLAB_VPN_CHECK \
  FORGE_INBOX_GITLAB_VPN_CHECK_TIMEOUT \
  FORGE_INBOX_GITLAB_OPENVPN_PROFILE \
  FORGE_INBOX_PROVIDER_TIMEOUT \
  FORGE_INBOX_CACHE_MAX_AGE; do
  if ! rg -n "^${empty_env}[[:space:]]*=[[:space:]]*\"\"" "$manifest" >/dev/null; then
    fail "$empty_env default must be empty"
  fi
  if ! rg -n "<string>${empty_env}</string>" "$plist_template" >/dev/null; then
    fail "$empty_env must be exposed in info.plist.template"
  fi
done
for false_env in \
  FORGE_INBOX_STRICT_PROVIDERS \
  FORGE_INBOX_CACHE_FALLBACK \
  FORGE_INBOX_NO_CACHE; do
  if ! rg -n "^${false_env}[[:space:]]*=[[:space:]]*\"false\"" "$manifest" >/dev/null; then
    fail "$false_env default must be false"
  fi
  if ! rg -n "<string>${false_env}</string>" "$plist_template" >/dev/null; then
    fail "$false_env must be exposed in info.plist.template"
  fi
done
if ! rg -n '^FORGE_INBOX_SHOW_CONFIG_WARNINGS[[:space:]]*=[[:space:]]*"false"' "$manifest" >/dev/null; then
  fail "FORGE_INBOX_SHOW_CONFIG_WARNINGS default must be false"
fi
if ! rg -n '<key>readme</key>' "$plist_template" >/dev/null; then
  fail "info.plist.template must include a readme key for package smoke"
fi
if ! rg -n '<string>fi</string>' "$plist_template" >/dev/null; then
  fail "info.plist.template must wire the fi keyword"
fi
if ! rg -n '<string>fih</string>' "$plist_template" >/dev/null; then
  fail "info.plist.template must wire the fih keyword"
fi
if ! rg -n '<string>fil</string>' "$plist_template" >/dev/null; then
  fail "info.plist.template must wire the fil keyword"
fi
if ! rg -n '<string>\./scripts/script_filter\.sh</string>' "$plist_template" >/dev/null; then
  fail "info.plist.template must wire the Script Filter script"
fi
if ! rg -n '<string>\./scripts/script_filter_github\.sh</string>' "$plist_template" >/dev/null; then
  fail "info.plist.template must wire the GitHub Script Filter script"
fi
if ! rg -n '<string>\./scripts/script_filter_gitlab\.sh</string>' "$plist_template" >/dev/null; then
  fail "info.plist.template must wire the GitLab Script Filter script"
fi
if ! rg -n '<string>\./scripts/action_open\.sh</string>' "$plist_template" >/dev/null; then
  fail "info.plist.template must wire the action script"
fi

plist_json="$(plist_to_json "$plist_template")"
assert_jq_json "$plist_json" '[.objects[] | select(.type == "alfred.workflow.trigger.hotkey")] | length == 3' "plist must expose three unassigned hotkey triggers"
assert_jq_json "$plist_json" '.objects[] | select(.uid == "8C47B10E-5967-45D5-9642-0C812662F7FA") | .config.hotkey == 0 and .config.hotmod == 0' "fi hotkey must default to empty"
assert_jq_json "$plist_json" '.objects[] | select(.uid == "DE9FE8C7-C965-40C9-8482-43F9CF270223") | .config.hotkey == 0 and .config.hotmod == 0' "fih hotkey must default to empty"
assert_jq_json "$plist_json" '.objects[] | select(.uid == "B42156AB-CDF6-4EF5-93AC-5C99CEFB30FE") | .config.hotkey == 0 and .config.hotmod == 0' "fil hotkey must default to empty"
assert_jq_json "$plist_json" '.connections["8C47B10E-5967-45D5-9642-0C812662F7FA"] | any(.destinationuid == "70EEA820-E77B-42F3-A8D2-1A4D9E8E4A10" and .modifiers == 0)' "fi hotkey must target fi script filter"
assert_jq_json "$plist_json" '.connections["DE9FE8C7-C965-40C9-8482-43F9CF270223"] | any(.destinationuid == "973A6C25-1D02-4A0D-9B6C-F904D31CE5A1" and .modifiers == 0)' "fih hotkey must target fih script filter"
assert_jq_json "$plist_json" '.connections["B42156AB-CDF6-4EF5-93AC-5C99CEFB30FE"] | any(.destinationuid == "8F8B6D19-A047-4CDE-B750-09D6B479DBF1" and .modifiers == 0)' "fil hotkey must target fil script filter"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/stubs"
forge_stub="$tmp_dir/stubs/forge-cli"
forge_log="$tmp_dir/forge-cli.args"

cat >"$forge_stub" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${FORGE_STUB_LOG:-}" ]]; then
  printf '%s\n' "$*" >>"$FORGE_STUB_LOG"
fi

case "${FORGE_STUB_MODE:-ok}" in
nonzero)
  echo "simulated forge failure" >&2
  exit 7
  ;;
malformed)
  echo "{not-json"
  exit 0
  ;;
bad-envelope)
  echo '{"ok":false,"error":{"message":"auth failed"}}'
  exit 0
  ;;
provider-warning)
  cat <<'JSON'
{
  "ok": true,
  "data": {
    "providers": [
      {"provider":"github","ok":true},
      {"provider":"gitlab","ok":false,"error":{"message":"GitLab token expired"}}
    ],
    "items": [
      {"provider":"github","host":"github.com","source":"github_search_prs","repo":"sympoies/nils-cli","number":10,"title":"Review forge inbox PR","url":"https://github.com/sympoies/nils-cli/pull/10","author":"ada","reasons":["review"],"updated_at":"2026-05-22T10:00:00Z"}
    ]
  },
  "warnings": ["supplemental warning"]
}
JSON
  exit 0
  ;;
top-warning)
  cat <<'JSON'
{"ok":true,"data":{"providers":[{"provider":"github","ok":true}],"items":[]},"warnings":[{"message":"rate limit near ceiling"}]}
JSON
  exit 0
  ;;
esac

provider="all"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
  --provider)
    provider="${2:-}"
    shift 2
    ;;
  --gitlab-host)
    shift 2
    ;;
  --kind)
    echo "unexpected --kind in forge-cli argv" >&2
    exit 9
    ;;
  *)
    shift
    ;;
  esac
done

case "$provider" in
github)
  cat <<'JSON'
{
  "ok": true,
  "data": {
    "providers": [{"provider":"github","ok":true}],
    "items": [
      {"provider":"github","host":"github.com","source":"github_search_prs","repo":"sympoies/nils-cli","number":10,"title":"Review forge inbox PR","url":"https://github.com/sympoies/nils-cli/pull/10","author":"ada","reasons":["review"],"updated_at":"2026-05-22T10:00:00Z"},
      {"provider":"github","host":"github.com","source":"github_search_issues","repo":"sympoies/nils-cli","number":11,"title":"Fix forge inbox issue","url":"https://github.com/sympoies/nils-cli/issues/11","author":"lin","reasons":["assigned"],"updated_at":"2026-05-22T10:05:00Z"}
    ]
  }
}
JSON
  ;;
gitlab)
  cat <<'JSON'
{
  "ok": true,
  "data": {
    "providers": [{"provider":"gitlab","host":"gitlab.gamania.com","ok":true}],
    "items": [
      {"provider":"gitlab","host":"gitlab.gamania.com","source":"gitlab_merge_requests","repo":"group/app","number":7,"title":"Ship forge inbox MR","url":"https://gitlab.gamania.com/group/app/-/merge_requests/7","author":"mei","reasons":["review"],"updated_at":"2026-05-22T10:10:00Z"},
      {"provider":"gitlab","host":"gitlab.gamania.com","source":"gitlab_issues","repo":"group/app","number":8,"title":"Investigate forge inbox issue","url":"https://gitlab.gamania.com/group/app/-/issues/8","author":"kai","reasons":["assigned"],"updated_at":"2026-05-22T10:15:00Z"},
      {"provider":"gitlab","host":"gitlab.gamania.com","source":"gitlab_todos","repo":"group/app","number":9,"title":"Review MR todo","url":"https://gitlab.gamania.com/group/app/-/merge_requests/9","author":"mei","reasons":["todo"],"updated_at":"2026-05-22T10:20:00Z"},
      {"provider":"gitlab","host":"gitlab.gamania.com","source":"gitlab_todos","repo":"group/app","number":8,"title":"Resolve issue todo","url":"https://gitlab.gamania.com/group/app/-/issues/8","author":"kai","reasons":["todo"],"updated_at":"2026-05-22T10:25:00Z"},
      {"provider":"gitlab","host":"gitlab.gamania.com","source":"gitlab_todos","repo":"group/app","number":"","title":"Read commit todo","url":"https://gitlab.gamania.com/group/app/-/commit/abc123","author":"ren","reasons":["todo"],"updated_at":"2026-05-22T10:30:00Z"}
    ]
  }
}
JSON
  ;;
all)
  cat <<'JSON'
{
  "ok": true,
  "data": {
    "providers": [
      {"provider":"github","host":"github.com","ok":true},
      {"provider":"gitlab","host":"gitlab.gamania.com","ok":true}
    ],
    "items": [
      {"provider":"github","host":"github.com","source":"github_search_prs","repo":"sympoies/nils-cli","number":10,"title":"Review forge inbox PR","url":"https://github.com/sympoies/nils-cli/pull/10","author":"ada","reasons":["review"],"updated_at":"2026-05-22T10:00:00Z"},
      {"provider":"github","host":"github.com","source":"github_search_issues","repo":"sympoies/nils-cli","number":11,"title":"Fix forge inbox issue","url":"https://github.com/sympoies/nils-cli/issues/11","author":"lin","reasons":["assigned"],"updated_at":"2026-05-22T10:05:00Z"},
      {"provider":"gitlab","host":"gitlab.gamania.com","source":"gitlab_merge_requests","repo":"group/app","number":7,"title":"Ship forge inbox MR","url":"https://gitlab.gamania.com/group/app/-/merge_requests/7","author":"mei","reasons":["review"],"updated_at":"2026-05-22T10:10:00Z"},
      {"provider":"gitlab","host":"gitlab.gamania.com","source":"gitlab_issues","repo":"group/app","number":8,"title":"Investigate forge inbox issue","url":"https://gitlab.gamania.com/group/app/-/issues/8","author":"kai","reasons":["assigned"],"updated_at":"2026-05-22T10:15:00Z"},
      {"provider":"gitlab","host":"gitlab.gamania.com","source":"gitlab_todos","repo":"group/app","number":9,"title":"Review MR todo","url":"https://gitlab.gamania.com/group/app/-/merge_requests/9","author":"mei","reasons":["todo"],"updated_at":"2026-05-22T10:20:00Z"},
      {"provider":"gitlab","host":"gitlab.gamania.com","source":"gitlab_todos","repo":"group/app","number":8,"title":"Resolve issue todo","url":"https://gitlab.gamania.com/group/app/-/issues/8","author":"kai","reasons":["todo"],"updated_at":"2026-05-22T10:25:00Z"},
      {"provider":"gitlab","host":"gitlab.gamania.com","source":"gitlab_todos","repo":"group/app","number":"","title":"Read commit todo","url":"https://gitlab.gamania.com/group/app/-/commit/abc123","author":"ren","reasons":["todo"],"updated_at":"2026-05-22T10:30:00Z"}
    ]
  }
}
JSON
  ;;
*)
  echo "unexpected provider: $provider" >&2
  exit 9
  ;;
esac
EOS
chmod +x "$forge_stub"

run_filter_with_script() {
  local filter_script="$1"
  local query="$2"
  local host="gitlab.gamania.com"
  local mode="ok"
  local show_config_warnings="false"

  if [[ $# -ge 3 ]]; then
    host="$3"
  fi
  if [[ $# -ge 4 ]]; then
    mode="$4"
  fi
  if [[ $# -ge 5 ]]; then
    show_config_warnings="$5"
  fi

  : >"$forge_log"
  FORGE_STUB_LOG="$forge_log" \
    FORGE_STUB_MODE="$mode" \
    FORGE_CLI_BIN="$forge_stub" \
    FORGE_INBOX_GITLAB_HOST="$host" \
    FORGE_INBOX_GITLAB_VPN="${FORGE_INBOX_GITLAB_VPN:-}" \
    FORGE_INBOX_GITLAB_VPN_CHECK="${FORGE_INBOX_GITLAB_VPN_CHECK:-}" \
    FORGE_INBOX_GITLAB_VPN_CHECK_TIMEOUT="${FORGE_INBOX_GITLAB_VPN_CHECK_TIMEOUT:-}" \
    FORGE_INBOX_GITLAB_OPENVPN_PROFILE="${FORGE_INBOX_GITLAB_OPENVPN_PROFILE:-}" \
    FORGE_INBOX_PROVIDER_TIMEOUT="${FORGE_INBOX_PROVIDER_TIMEOUT:-}" \
    FORGE_INBOX_STRICT_PROVIDERS="${FORGE_INBOX_STRICT_PROVIDERS:-}" \
    FORGE_INBOX_CACHE_FALLBACK="${FORGE_INBOX_CACHE_FALLBACK:-}" \
    FORGE_INBOX_CACHE_MAX_AGE="${FORGE_INBOX_CACHE_MAX_AGE:-}" \
    FORGE_INBOX_NO_CACHE="${FORGE_INBOX_NO_CACHE:-}" \
    FORGE_CLI_INBOX_GITLAB_HOST="" \
    FORGE_CLI_INBOX_GITLAB_VPN="" \
    FORGE_CLI_INBOX_GITLAB_VPN_CHECK="" \
    FORGE_CLI_INBOX_GITLAB_VPN_CHECK_TIMEOUT="" \
    FORGE_CLI_INBOX_GITLAB_OPENVPN_PROFILE="" \
    FORGE_CLI_INBOX_PROVIDER_TIMEOUT="" \
    FORGE_CLI_INBOX_STRICT_PROVIDERS="" \
    FORGE_CLI_INBOX_CACHE_FALLBACK="" \
    FORGE_CLI_INBOX_CACHE_MAX_AGE="" \
    FORGE_CLI_INBOX_NO_CACHE="" \
    FORGE_INBOX_SHOW_CONFIG_WARNINGS="$show_config_warnings" \
    "$filter_script" "$query"
}

run_filter() {
  run_filter_with_script "$script_filter" "$@"
}

assert_valid_count() {
  local payload="$1"
  local expected="$2"
  assert_jq_json "$payload" "([.items[] | select(.valid == true)] | length) == $expected" "valid row count mismatch"
}

assert_has_source() {
  local payload="$1"
  local source="$2"
  if ! jq -e --arg source "$source" \
    '[.items[] | select(.valid == true) | .arg | fromjson | .source] | index($source) != null' \
    >/dev/null <<<"$payload"; then
    fail "missing source $source"
  fi
}

assert_not_has_url_fragment() {
  local payload="$1"
  local fragment="$2"
  if ! jq -e --arg fragment "$fragment" \
    '[.items[] | select(.valid == true) | .arg | fromjson | .url] | map(contains($fragment)) | any | not' \
    >/dev/null <<<"$payload"; then
    fail "unexpected URL fragment $fragment"
  fi
}

assert_log_contains() {
  local pattern="$1"
  rg -n --fixed-strings -- "$pattern" "$forge_log" >/dev/null || fail "missing forge argv fragment: $pattern"
}

assert_log_not_contains() {
  local pattern="$1"
  if rg -n --fixed-strings -- "$pattern" "$forge_log" >/dev/null; then
    fail "unexpected forge argv fragment: $pattern"
  fi
}

json="$(run_filter "gh pr")"
assert_valid_count "$json" 1
assert_has_source "$json" "github_search_prs"
assert_jq_json "$json" '.items[0].title == "#10 Review forge inbox PR"' "repo must not be duplicated in title"
assert_jq_json "$json" '.items[0].subtitle | startswith("sympoies/nils-cli | GitHub PR | review")' "repo must be shown in subtitle"
assert_jq_json "$json" '.items[0].icon.path == "assets/icon-github.png"' "GitHub row icon mismatch"
assert_log_contains "--provider github"
assert_log_not_contains "--kind pr"

json="$(run_filter "gh issue")"
assert_valid_count "$json" 1
assert_has_source "$json" "github_search_issues"

json="$(run_filter "gh all")"
assert_valid_count "$json" 2
assert_has_source "$json" "github_search_prs"
assert_has_source "$json" "github_search_issues"

json="$(run_filter "glab pr")"
assert_valid_count "$json" 2
assert_has_source "$json" "gitlab_merge_requests"
assert_has_source "$json" "gitlab_todos"
assert_jq_json "$json" '[.items[] | select(.valid == true) | .icon.path] | unique == ["assets/icon-gitlab.png"]' "GitLab row icon mismatch"
assert_jq_json "$json" '[.items[] | select(.valid == true) | .arg | fromjson | .url] | index("https://gitlab.gamania.com/group/app/-/merge_requests/9") != null' "MR todo URL missing from PR mode"
assert_not_has_url_fragment "$json" "/-/issues/8"
assert_not_has_url_fragment "$json" "/-/commit/abc123"
assert_log_contains "--provider gitlab"
assert_log_contains "--gitlab-host gitlab.gamania.com"
assert_log_not_contains "--kind pr"

json="$(run_filter "glab issue")"
assert_valid_count "$json" 2
assert_has_source "$json" "gitlab_issues"
assert_jq_json "$json" '[.items[] | select(.valid == true) | .arg | fromjson | .url] | index("https://gitlab.gamania.com/group/app/-/issues/8") != null' "issue todo URL missing from issue mode"
assert_not_has_url_fragment "$json" "/-/merge_requests/9"
assert_not_has_url_fragment "$json" "/-/commit/abc123"

json="$(run_filter "glab all")"
assert_valid_count "$json" 5
assert_jq_json "$json" '[.items[] | select(.valid == true) | .arg | fromjson | .url] | index("https://gitlab.gamania.com/group/app/-/commit/abc123") != null' "commit todo URL missing from all mode"

json="$(
  FORGE_INBOX_GITLAB_VPN=required \
    FORGE_INBOX_GITLAB_VPN_CHECK=tcp:gitlab.gamania.com:443 \
    FORGE_INBOX_GITLAB_VPN_CHECK_TIMEOUT=5s \
    FORGE_INBOX_PROVIDER_TIMEOUT=20s \
    FORGE_INBOX_STRICT_PROVIDERS=true \
    FORGE_INBOX_CACHE_FALLBACK=true \
    FORGE_INBOX_CACHE_MAX_AGE=30m \
    run_filter "glab all"
)"
assert_valid_count "$json" 5
assert_log_contains "--gitlab-vpn required"
assert_log_contains "--gitlab-vpn-check tcp:gitlab.gamania.com:443"
assert_log_contains "--gitlab-vpn-check-timeout 5s"
assert_log_contains "--provider-timeout 20s"
assert_log_contains "--strict-providers"
assert_log_contains "--cache-fallback"
assert_log_contains "--cache-max-age 30m"

json="$(
  FORGE_INBOX_GITLAB_VPN=required \
    FORGE_INBOX_GITLAB_VPN_CHECK=tcp:gitlab.gamania.com:443 \
    run_filter "gh all"
)"
assert_valid_count "$json" 2
assert_log_not_contains "--gitlab-vpn"
assert_log_not_contains "--gitlab-vpn-check"

json="$(
  FORGE_INBOX_CACHE_FALLBACK=maybe \
    run_filter "glab all"
)"
assert_jq_json "$json" '.items[0].title == "Invalid FORGE_INBOX_CACHE_FALLBACK"' "invalid cache bool row mismatch"

json="$(run_filter "all pr")"
assert_valid_count "$json" 3
assert_has_source "$json" "github_search_prs"
assert_has_source "$json" "gitlab_merge_requests"
assert_log_not_contains "--provider"
assert_log_contains "--gitlab-host gitlab.gamania.com"

json="$(run_filter "all issue")"
assert_valid_count "$json" 3
assert_has_source "$json" "github_search_issues"
assert_has_source "$json" "gitlab_issues"

json="$(run_filter "all all")"
assert_valid_count "$json" 7
assert_jq_json "$json" '[.items[] | select(.valid == true) | .arg | fromjson | .url] | index("https://gitlab.gamania.com/group/app/-/commit/abc123") != null' "all mode should keep unclassified todo URL"

json="$(run_filter "pr review")"
assert_valid_count "$json" 3

json="$(run_filter "all all nils-cli")"
assert_valid_count "$json" 2
assert_has_source "$json" "github_search_prs"
assert_has_source "$json" "github_search_issues"

json="$(run_filter "all all" "")"
assert_valid_count "$json" 2
assert_jq_json "$json" '[.items[].title] | index("Set FORGE_INBOX_GITLAB_HOST") == null' "mixed-mode host warning should be hidden by default"
assert_log_contains "--provider github"

json="$(run_filter "all all" "" "ok" "true")"
assert_valid_count "$json" 2
assert_jq_json "$json" '.items[0].title == "Set FORGE_INBOX_GITLAB_HOST"' "missing opt-in mixed-mode host warning"
assert_jq_json "$json" '.items[0].icon.path == "assets/icon-gitlab.png"' "mixed-mode GitLab host warning icon mismatch"
assert_log_contains "--provider github"

json="$(run_filter "glab issue" "")"
assert_valid_count "$json" 0
assert_jq_json "$json" '.items == []' "gitlab-only missing-host mode should hide config row by default"
if [[ -s "$forge_log" ]]; then
  fail "gitlab-only missing-host mode must not invoke forge-cli"
fi

json="$(run_filter "glab issue" "" "ok" "true")"
assert_valid_count "$json" 0
assert_jq_json "$json" '.items[0].title == "Set FORGE_INBOX_GITLAB_HOST"' "missing gitlab-only host config row"
assert_jq_json "$json" '.items[0].icon.path == "assets/icon-gitlab.png"' "gitlab-only host config row icon mismatch"
if [[ -s "$forge_log" ]]; then
  fail "gitlab-only missing-host warning mode must not invoke forge-cli"
fi

json="$(run_filter "glab all no-match")"
assert_valid_count "$json" 0
assert_jq_json "$json" '.items[0].title == "No inbox items"' "missing gitlab empty-result row"
assert_jq_json "$json" '.items[0].icon.path == "assets/icon-gitlab.png"' "gitlab empty-result row icon mismatch"

json="$(run_filter "all all" "gitlab.gamania.com" "provider-warning")"
assert_valid_count "$json" 1
assert_jq_json "$json" '[.items[] | select(.valid == false) | .title] | index("GitLab query failed") != null' "provider warning row missing"
assert_jq_json "$json" '[.items[] | select(.valid == false) | .subtitle] | any(contains("GitLab token expired"))' "provider warning message missing"
assert_jq_json "$json" '[.items[] | select(.valid == false) | .subtitle] | any(contains("supplemental warning"))' "top-level warning row missing"
assert_jq_json "$json" '.items[] | select(.title == "GitLab query failed") | .icon.path == "assets/icon-gitlab.png"' "provider warning icon mismatch"

json="$(run_filter "all all" "gitlab.gamania.com" "top-warning")"
assert_valid_count "$json" 0
assert_jq_json "$json" '[.items[] | select(.valid == false) | .subtitle] | any(contains("rate limit near ceiling"))' "structured warning row missing"

json="$(run_filter "gh pr" "gitlab.gamania.com" "nonzero")"
assert_jq_json "$json" '.items[0].title == "forge-cli inbox failed"' "nonzero CLI failure row mismatch"

json="$(run_filter "gh pr" "gitlab.gamania.com" "malformed")"
assert_jq_json "$json" '.items[0].title == "forge-cli returned invalid JSON"' "malformed JSON row mismatch"

json="$(run_filter "gh pr" "gitlab.gamania.com" "bad-envelope")"
assert_jq_json "$json" '.items[0].title == "forge-cli inbox failed" and (.items[0].subtitle | contains("auth failed"))' "unsuccessful envelope row mismatch"

json="$(run_filter_with_script "$script_filter_github" "glab issue")"
assert_valid_count "$json" 1
assert_has_source "$json" "github_search_issues"
assert_log_contains "--provider github"
assert_log_not_contains "--provider gitlab"

json="$(run_filter_with_script "$script_filter_gitlab" "gh pr")"
assert_valid_count "$json" 2
assert_has_source "$json" "gitlab_merge_requests"
assert_has_source "$json" "gitlab_todos"
assert_log_contains "--provider gitlab"
assert_log_contains "--gitlab-host gitlab.gamania.com"
assert_log_not_contains "--provider github"

json="$(FORGE_CLI_BIN="$tmp_dir/missing-forge-cli" "$script_filter" "gh pr" 2>/dev/null)"
assert_jq_json "$json" '.items[0].title == "forge-cli binary not found"' "missing binary row mismatch"

if rg -n 'command -v[[:space:]]+(gh|glab)|exec[[:space:]]+(gh|glab)|(^|[;&|])[[:space:]]*(gh|glab)[[:space:]]+(api|auth|issue|mr|pr|repo|search|status)' \
  "$workflow_dir/scripts/script_filter.sh" \
  "$workflow_dir/scripts/script_filter_github.sh" \
  "$workflow_dir/scripts/script_filter_gitlab.sh" \
  "$workflow_dir/scripts/action_open.sh" >/dev/null; then
  fail "workflow scripts must not call gh or glab directly"
fi

workflow_smoke_write_open_stub "$tmp_dir/bin/open"
workflow_smoke_write_pbcopy_stub "$tmp_dir/bin/pbcopy"
export OPEN_STUB_OUT="$tmp_dir/open.out"
export PBCOPY_STUB_OUT="$tmp_dir/pbcopy.out"

open_token="$(jq -nc --arg url "https://example.com/repo/pull/1" '{action:"open",url:$url}')"
PATH="$tmp_dir/bin:$PATH" "$action_open" "$open_token"
[[ "$(cat "$OPEN_STUB_OUT")" == "https://example.com/repo/pull/1" ]] || fail "open action URL mismatch"

copy_url_token="$(jq -nc --arg url "https://example.com/repo/issues/2" '{action:"copy-url",url:$url}')"
PATH="$tmp_dir/bin:$PATH" "$action_open" "$copy_url_token"
[[ "$(cat "$PBCOPY_STUB_OUT")" == "https://example.com/repo/issues/2" ]] || fail "copy-url action mismatch"

copy_md_token="$(jq -nc \
  --arg url "https://example.com/repo/issues/3" \
  --arg title $'Line\nTitle' \
  '{action:"copy-md",url:$url,repo:"group/app",number:3,title:$title}')"
PATH="$tmp_dir/bin:$PATH" "$action_open" "$copy_md_token"
[[ "$(cat "$PBCOPY_STUB_OUT")" == "[group/app#3 Line Title](https://example.com/repo/issues/3)" ]] || fail "copy-md action mismatch"

workflow_smoke_assert_action_requires_arg "$action_open" 2

echo "ok: forge-inbox smoke test passed"
