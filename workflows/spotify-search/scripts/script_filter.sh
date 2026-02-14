#!/usr/bin/env bash
set -euo pipefail

resolve_helper() {
  local helper_name="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local git_repo_root=""
  git_repo_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"

  local candidates=(
    "$script_dir/lib/$helper_name"
    "$script_dir/../../../scripts/lib/$helper_name"
  )
  if [[ -n "$git_repo_root" ]]; then
    candidates+=("$git_repo_root/scripts/lib/$helper_name")
  fi
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

error_json_helper="$(resolve_helper "script_filter_error_json.sh" || true)"
if [[ -z "$error_json_helper" ]]; then
  printf '{"items":[{"title":"Workflow helper missing","subtitle":"Cannot locate script_filter_error_json.sh runtime helper.","valid":false}]}\n'
  exit 0
fi
# shellcheck disable=SC1090
source "$error_json_helper"

cli_resolver_helper="$(resolve_helper "workflow_cli_resolver.sh" || true)"
if [[ -z "$cli_resolver_helper" ]]; then
  sfej_emit_error_item_json "Workflow helper missing" "Cannot locate workflow_cli_resolver.sh runtime helper."
  exit 0
fi
# shellcheck disable=SC1090
source "$cli_resolver_helper"

normalize_error_message() {
  sfej_normalize_error_message "${1-}"
}

emit_error_item() {
  local title="$1"
  local subtitle="$2"
  sfej_emit_error_item_json "$title" "$subtitle"
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

resolve_spotify_cli() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local packaged_cli
  packaged_cli="$script_dir/../bin/spotify-cli"

  local repo_root
  repo_root="$(cd "$script_dir/../../.." && pwd)"

  local release_cli
  release_cli="$repo_root/target/release/spotify-cli"

  local debug_cli
  debug_cli="$repo_root/target/debug/spotify-cli"

  wfcr_resolve_binary \
    "SPOTIFY_CLI_BIN" \
    "$packaged_cli" \
    "$release_cli" \
    "$debug_cli" \
    "spotify-cli binary not found (checked SPOTIFY_CLI_BIN/package/release/debug paths)"
}

query="${1:-}"
if [[ -z "$query" && -n "${alfred_workflow_query:-}" ]]; then
  query="${alfred_workflow_query}"
elif [[ -z "$query" && -n "${ALFRED_WORKFLOW_QUERY:-}" ]]; then
  query="${ALFRED_WORKFLOW_QUERY}"
elif [[ -z "$query" && ! -t 0 ]]; then
  stdin_query="$(cat)"
  query="$stdin_query"
fi

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

if json_output="$("$spotify_cli" search --query "$query" --mode alfred 2>"$err_file")"; then
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
