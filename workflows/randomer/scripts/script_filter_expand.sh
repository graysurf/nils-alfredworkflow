#!/usr/bin/env bash
set -euo pipefail

resolve_helper() {
  local helper_name="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local candidates=(
    "$script_dir/lib/$helper_name"
    "$script_dir/../../../scripts/lib/$helper_name"
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
  local raw_message="${1:-randomer-cli generate failed}"
  local message
  message="$(normalize_error_message "$raw_message")"
  [[ -n "$message" ]] || message="randomer-cli generate failed"

  local title="Randomer expand error"
  local subtitle="$message"
  local lower
  lower="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"

  if [[ "$lower" == *"binary not found"* ]]; then
    title="randomer-cli binary not found"
    subtitle="Package workflow or set RANDOMER_CLI_BIN to a randomer-cli executable."
  elif [[ "$lower" == *"missing format"* || "$lower" == *"format is required"* || "$lower" == *"empty format"* ]]; then
    title="Select a format first"
    subtitle="Use rrv to pick a format, or run rrvv <format>."
  elif [[ "$lower" == *"unknown format"* || "$lower" == *"unsupported format"* ]]; then
    title="Unknown format"
    subtitle="$message"
  elif [[ "$lower" == *"malformed alfred json"* ]]; then
    title="Randomer output format error"
    subtitle="randomer-cli returned malformed Alfred JSON."
  fi

  emit_error_item "$title" "$subtitle"
}

resolve_randomer_cli() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local packaged_cli
  packaged_cli="$script_dir/../bin/randomer-cli"

  local repo_root
  repo_root="$(cd "$script_dir/../../.." && pwd)"

  local release_cli
  release_cli="$repo_root/target/release/randomer-cli"

  local debug_cli
  debug_cli="$repo_root/target/debug/randomer-cli"

  wfcr_resolve_binary \
    "RANDOMER_CLI_BIN" \
    "$packaged_cli" \
    "$release_cli" \
    "$debug_cli" \
    "randomer-cli binary not found (checked RANDOMER_CLI_BIN/package/release/debug paths)"
}

resolve_query() {
  local arg_query="${1:-}"
  if [[ -n "$arg_query" ]]; then
    printf '%s' "$arg_query"
    return 0
  fi

  if [[ -n "${RANDOMER_FORMAT:-}" ]]; then
    printf '%s' "${RANDOMER_FORMAT}"
    return 0
  fi
  if [[ -n "${randomer_format:-}" ]]; then
    printf '%s' "${randomer_format}"
    return 0
  fi

  if [[ -n "${alfred_workflow_query:-}" ]]; then
    printf '%s' "${alfred_workflow_query}"
    return 0
  fi
  if [[ -n "${ALFRED_WORKFLOW_QUERY:-}" ]]; then
    printf '%s' "${ALFRED_WORKFLOW_QUERY}"
    return 0
  fi

  # Some Alfred configurations pass upstream output to stdin instead of argv.
  if [[ ! -t 0 ]]; then
    cat
    return 0
  fi

  printf ''
}

query="$(resolve_query "${1:-}")"
trimmed_query="$(printf '%s' "$query" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
if [[ -z "$trimmed_query" ]]; then
  emit_error_item "Select a format first" "Use rrv to pick a format, or run rrvv <format>."
  exit 0
fi
query="$trimmed_query"

err_file="${TMPDIR:-/tmp}/randomer-expand-script-filter.err.$$"
trap 'rm -f "$err_file"' EXIT

randomer_cli=""
if ! randomer_cli="$(resolve_randomer_cli 2>"$err_file")"; then
  err_msg="$(cat "$err_file")"
  print_error_item "$err_msg"
  exit 0
fi

if json_output="$("$randomer_cli" generate --format "$query" --count 10 --mode alfred 2>"$err_file")"; then
  if [[ -z "$json_output" ]]; then
    print_error_item "randomer-cli returned empty response"
    exit 0
  fi

  if command -v jq >/dev/null 2>&1; then
    if ! jq -e '.items | type == "array"' >/dev/null <<<"$json_output"; then
      print_error_item "randomer-cli returned malformed Alfred JSON"
      exit 0
    fi
  fi

  printf '%s\n' "$json_output"
  exit 0
fi

err_msg="$(cat "$err_file")"
print_error_item "$err_msg"
