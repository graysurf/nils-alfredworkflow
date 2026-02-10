#!/usr/bin/env bash
set -euo pipefail

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
  local raw_message="${1:-spotify-cli search failed}"
  local message
  message="$(normalize_error_message "$raw_message")"
  [[ -n "$message" ]] || message="spotify-cli search failed"

  local title="Spotify Search error"
  local subtitle="$message"
  local lower
  lower="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"

  if [[ "$lower" == *"query must not be empty"* || "$lower" == *"query cannot be empty"* || "$lower" == *"empty query"* ]]; then
    title="Enter a search query"
    subtitle="Type keywords after sp to search Spotify tracks."
  elif [[ "$lower" == *"missing spotify_client_id"* || "$lower" == *"missing spotify_client_secret"* || "$lower" == *"spotify_client_id is required"* || "$lower" == *"spotify_client_secret is required"* || "$lower" == *"missing spotify client id"* || "$lower" == *"missing spotify client secret"* || "$lower" == *"missing credentials"* ]]; then
    title="Spotify credentials are missing"
    subtitle="Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET in workflow configuration."
  elif [[ "$lower" == *"invalid_client"* || "$lower" == *"spotify auth error (401)"* || "$lower" == *"spotify auth error (403)"* || "$lower" == *"unauthorized"* || "$lower" == *"forbidden"* ]]; then
    title="Spotify credentials are invalid"
    subtitle="Verify SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET and retry."
  elif [[ "$lower" == *"quota"* || "$lower" == *"rate limit"* || "$lower" == *"rate-limit"* || "$lower" == *"too many requests"* || "$lower" == *"http 429"* || "$lower" == *"status 429"* ]]; then
    title="Spotify API rate limited"
    subtitle="Rate limit reached. Retry later or lower SPOTIFY_MAX_RESULTS."
  elif [[ "$lower" == *"unavailable"* || "$lower" == *"transport"* || "$lower" == *"timed out"* || "$lower" == *"timeout"* || "$lower" == *"connection"* || "$lower" == *"dns"* || "$lower" == *"tls"* || "$lower" == *"5xx"* || "$lower" == *"status 500"* || "$lower" == *"status 502"* || "$lower" == *"status 503"* || "$lower" == *"status 504"* ]]; then
    title="Spotify API unavailable"
    subtitle="Cannot reach Spotify API now. Check network and retry."
  elif [[ "$lower" == *"invalid spotify_max_results"* || "$lower" == *"invalid spotify_market"* || "$lower" == *"invalid config"* || "$lower" == *"invalid configuration"* ]]; then
    title="Invalid Spotify workflow config"
    subtitle="$message"
  elif [[ "$lower" == *"binary not found"* ]]; then
    title="spotify-cli binary not found"
    subtitle="Package workflow or set SPOTIFY_CLI_BIN to a spotify-cli executable."
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

resolve_spotify_cli() {
  if [[ -n "${SPOTIFY_CLI_BIN:-}" && -x "${SPOTIFY_CLI_BIN}" ]]; then
    clear_quarantine_if_needed "${SPOTIFY_CLI_BIN}"
    printf '%s\n' "${SPOTIFY_CLI_BIN}"
    return 0
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local packaged_cli
  packaged_cli="$script_dir/../bin/spotify-cli"
  if [[ -x "$packaged_cli" ]]; then
    clear_quarantine_if_needed "$packaged_cli"
    printf '%s\n' "$packaged_cli"
    return 0
  fi

  local repo_root
  repo_root="$(cd "$script_dir/../../.." && pwd)"

  local release_cli
  release_cli="$repo_root/target/release/spotify-cli"
  if [[ -x "$release_cli" ]]; then
    clear_quarantine_if_needed "$release_cli"
    printf '%s\n' "$release_cli"
    return 0
  fi

  local debug_cli
  debug_cli="$repo_root/target/debug/spotify-cli"
  if [[ -x "$debug_cli" ]]; then
    clear_quarantine_if_needed "$debug_cli"
    printf '%s\n' "$debug_cli"
    return 0
  fi

  echo "spotify-cli binary not found (checked SPOTIFY_CLI_BIN/package/release/debug paths)" >&2
  return 1
}

query="${1:-}"
trimmed_query="$(printf '%s' "$query" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
if [[ -z "$trimmed_query" ]]; then
  emit_error_item "Enter a search query" "Type keywords after sp to search Spotify tracks."
  exit 0
fi

err_file="${TMPDIR:-/tmp}/spotify-search-script-filter.err.$$"
trap 'rm -f "$err_file"' EXIT

spotify_cli=""
if ! spotify_cli="$(resolve_spotify_cli 2>"$err_file")"; then
  err_msg="$(cat "$err_file")"
  print_error_item "$err_msg"
  exit 0
fi

if json_output="$("$spotify_cli" search --query "$query" 2>"$err_file")"; then
  if [[ -z "$json_output" ]]; then
    print_error_item "spotify-cli returned empty response"
    exit 0
  fi

  if command -v jq >/dev/null 2>&1; then
    if ! jq -e '.items | type == "array"' >/dev/null <<<"$json_output"; then
      print_error_item "spotify-cli returned malformed Alfred JSON"
      exit 0
    fi
  fi

  printf '%s\n' "$json_output"
  exit 0
fi

err_msg="$(cat "$err_file")"
print_error_item "$err_msg"
