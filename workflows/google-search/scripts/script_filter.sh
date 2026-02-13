#!/usr/bin/env bash
set -euo pipefail

resolve_query_policy_helper() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local candidates=(
    "$script_dir/lib/script_filter_query_policy.sh"
    "$script_dir/../../../scripts/lib/script_filter_query_policy.sh"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

json_escape() {
  local value="${1-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  printf '%s' "$value"
}

normalize_error_message() {
  local value="${1-}"
  value="$(printf '%s' "$value" | tr '\n\r' '  ' | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
  value="${value#error: }"
  value="${value#Error: }"
  printf '%s' "$value"
}

emit_error_item() {
  local title="$1"
  local subtitle="$2"
  printf '{"items":[{"title":"%s","subtitle":"%s","valid":false}]}' \
    "$(json_escape "$title")" \
    "$(json_escape "$subtitle")"
  printf '\n'
}

print_error_item() {
  local raw_message="${1:-brave-cli search failed}"
  local message
  message="$(normalize_error_message "$raw_message")"
  [[ -n "$message" ]] || message="brave-cli search failed"

  local title="Google Search error"
  local subtitle="$message"
  local lower
  lower="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"

  if [[ "$lower" == *"query must not be empty"* || "$lower" == *"query cannot be empty"* || "$lower" == *"empty query"* ]]; then
    title="Enter a search query"
    subtitle="Type keywords after gg to search Google."
  elif [[ "$lower" == *"missing brave_api_key"* || "$lower" == *"brave_api_key is missing"* || "$lower" == *"brave api key is missing"* || "$lower" == *"brave_api_key is required"* ]]; then
    title="Brave API key is missing"
    subtitle="Set BRAVE_API_KEY in workflow configuration and retry."
  elif [[ "$lower" == *"quota"* || "$lower" == *"rate limit"* || "$lower" == *"rate-limit"* || "$lower" == *"too many requests"* || "$lower" == *"http 429"* || "$lower" == *"status 429"* ]]; then
    title="Brave API quota exceeded"
    subtitle="Rate quota is exhausted. Retry later or lower BRAVE_MAX_RESULTS."
  elif [[ "$lower" == *"unavailable"* || "$lower" == *"transport"* || "$lower" == *"timed out"* || "$lower" == *"timeout"* || "$lower" == *"connection"* || "$lower" == *"dns"* || "$lower" == *"tls"* || "$lower" == *"5xx"* || "$lower" == *"status 500"* || "$lower" == *"status 502"* || "$lower" == *"status 503"* || "$lower" == *"status 504"* ]]; then
    title="Brave API unavailable"
    subtitle="Cannot reach Brave API now. Check network and retry."
  elif [[ "$lower" == *"invalid brave_max_results"* || "$lower" == *"invalid brave_safesearch"* || "$lower" == *"invalid brave_country"* ]]; then
    title="Invalid Brave workflow config"
    subtitle="$message"
  fi

  emit_error_item "$title" "$subtitle"
}

clear_quarantine_if_needed() {
  local cli_path="$1"

  if [[ "$(uname -s 2>/dev/null || printf '')" != "Darwin" ]]; then
    return 0
  fi

  if ! command -v xattr >/dev/null 2>&1; then
    return 0
  fi

  # Release artifacts downloaded from GitHub may carry quarantine.
  if xattr -p com.apple.quarantine "$cli_path" >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "$cli_path" >/dev/null 2>&1 || true
  fi
}

resolve_brave_cli() {
  if [[ -n "${BRAVE_CLI_BIN:-}" && -x "${BRAVE_CLI_BIN}" ]]; then
    clear_quarantine_if_needed "${BRAVE_CLI_BIN}"
    printf '%s\n' "${BRAVE_CLI_BIN}"
    return 0
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local packaged_cli
  packaged_cli="$script_dir/../bin/brave-cli"
  if [[ -x "$packaged_cli" ]]; then
    clear_quarantine_if_needed "$packaged_cli"
    printf '%s\n' "$packaged_cli"
    return 0
  fi

  local repo_root
  repo_root="$(cd "$script_dir/../../.." && pwd)"

  local release_cli
  release_cli="$repo_root/target/release/brave-cli"
  if [[ -x "$release_cli" ]]; then
    clear_quarantine_if_needed "$release_cli"
    printf '%s\n' "$release_cli"
    return 0
  fi

  local debug_cli
  debug_cli="$repo_root/target/debug/brave-cli"
  if [[ -x "$debug_cli" ]]; then
    clear_quarantine_if_needed "$debug_cli"
    printf '%s\n' "$debug_cli"
    return 0
  fi

  echo "brave-cli binary not found (checked package/release/debug paths)" >&2
  return 1
}

query_policy_helper="$(resolve_query_policy_helper || true)"
if [[ -z "$query_policy_helper" ]]; then
  emit_error_item "Workflow helper missing" "Cannot locate script_filter_query_policy.sh runtime helper."
  exit 0
fi
# shellcheck disable=SC1090
source "$query_policy_helper"

query="$(sfqp_resolve_query_input "${1:-}")"
trimmed_query="$(sfqp_trim "$query")"

if [[ -z "$trimmed_query" ]]; then
  emit_error_item "Enter a search query" "Type keywords after gg to search Google."
  exit 0
fi

if sfqp_is_short_query "$trimmed_query" 2; then
  sfqp_emit_short_query_item_json \
    2 \
    "Keep typing (2+ chars)" \
    "Type at least %s characters before searching Google."
  exit 0
fi

err_file="${TMPDIR:-/tmp}/google-search-script-filter.err.$$"
trap 'rm -f "$err_file"' EXIT

brave_cli=""
if ! brave_cli="$(resolve_brave_cli 2>"$err_file")"; then
  err_msg="$(cat "$err_file")"
  print_error_item "$err_msg"
  exit 0
fi

if json_output="$("$brave_cli" search --query "$query" --mode alfred 2>"$err_file")"; then
  if [[ -z "$json_output" ]]; then
    print_error_item "brave-cli returned empty response"
    exit 0
  fi
  printf '%s\n' "$json_output"
  exit 0
fi

err_msg="$(cat "$err_file")"
print_error_item "$err_msg"
