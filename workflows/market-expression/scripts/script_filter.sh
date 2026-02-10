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
  local raw_message="${1:-market-cli expr failed}"
  local message
  message="$(normalize_error_message "$raw_message")"
  [[ -n "$message" ]] || message="market-cli expr failed"

  local title="Market Expression error"
  local subtitle="$message"
  local lower
  lower="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"

  if [[ "$lower" == *"binary not found"* ]]; then
    title="market-cli binary not found"
    subtitle="Package workflow or set MARKET_CLI_BIN to an executable market-cli path."
  elif [[ "$lower" == *"unsupported operator"* || "$lower" == *"operator '*'"* || "$lower" == *"operator '/'"* || "$lower" == *"operator *"* || "$lower" == *"operator /"* || "$lower" == *"unsupported *"* || "$lower" == *"unsupported /"* ]]; then
    title="Unsupported operator"
    subtitle="Asset expressions support +/-. Numeric-only expressions support + - * /."
  elif [[ "$lower" == *"mixed asset and numeric"* || "$lower" == *"mixed numeric and asset"* || "$lower" == *"cannot mix asset and numeric"* || "$lower" == *"cannot mix numeric and asset"* || "$lower" == *"asset and numeric terms"* || "$lower" == *"numeric and asset terms"* ]]; then
    title="Invalid expression terms"
    subtitle="Do not mix asset symbols and raw numeric-only terms in the same side of expression."
  elif [[ "$lower" == *"invalid to clause"* || "$lower" == *"incomplete to clause"* || "$lower" == *"invalid to-clause"* || "$lower" == *"incomplete to-clause"* || "$lower" == *"missing target after to"* || "$lower" == *"expected target after to"* ]]; then
    title="Invalid to-clause"
    subtitle="Use a complete target clause, for example: 1 BTC + 2 ETH to USD."
  elif [[ "$lower" == *"invalid expression"* || "$lower" == *"parse error"* || "$lower" == *"syntax error"* || "$lower" == *"expected expression"* || "$lower" == *"unexpected token"* || "$lower" == *"invalid token"* ]]; then
    title="Invalid expression"
    subtitle="Use market terms with + or -, for example: 1 BTC + 2 ETH to USD."
  elif [[ "$lower" == *"provider"* || "$lower" == *"upstream"* || "$lower" == *"rate limit"* || "$lower" == *"429"* ]]; then
    title="Market Expression provider failure"
    subtitle="Failed to fetch market data from provider. Retry shortly."
  elif [[ "$lower" == *"timeout"* || "$lower" == *"timed out"* || "$lower" == *"io error"* || "$lower" == *"internal error"* || "$lower" == *"panic"* ]]; then
    title="Market Expression runtime failure"
    subtitle="market-cli failed while evaluating expression. Retry or inspect stderr details."
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

  if xattr -p com.apple.quarantine "$cli_path" >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "$cli_path" >/dev/null 2>&1 || true
  fi
}

resolve_market_cli() {
  if [[ -n "${MARKET_CLI_BIN:-}" && -x "${MARKET_CLI_BIN}" ]]; then
    clear_quarantine_if_needed "${MARKET_CLI_BIN}"
    printf '%s\n' "${MARKET_CLI_BIN}"
    return 0
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local packaged_cli
  packaged_cli="$script_dir/../bin/market-cli"
  if [[ -x "$packaged_cli" ]]; then
    clear_quarantine_if_needed "$packaged_cli"
    printf '%s\n' "$packaged_cli"
    return 0
  fi

  local repo_root
  repo_root="$(cd "$script_dir/../../.." && pwd)"

  local release_cli
  release_cli="$repo_root/target/release/market-cli"
  if [[ -x "$release_cli" ]]; then
    clear_quarantine_if_needed "$release_cli"
    printf '%s\n' "$release_cli"
    return 0
  fi

  local debug_cli
  debug_cli="$repo_root/target/debug/market-cli"
  if [[ -x "$debug_cli" ]]; then
    clear_quarantine_if_needed "$debug_cli"
    printf '%s\n' "$debug_cli"
    return 0
  fi

  echo "market-cli binary not found (checked MARKET_CLI_BIN/package/release/debug paths)" >&2
  return 1
}

query="${1:-}"
default_fiat="${MARKET_DEFAULT_FIAT:-USD}"

if [[ -z "$(printf '%s' "$query" | sed 's/[[:space:]]//g')" ]]; then
  emit_error_item \
    "Enter a market expression" \
    "Example: 1 BTC + 3 ETH to JPY (default fiat: ${default_fiat})"
  exit 0
fi

err_file="${TMPDIR:-/tmp}/market-expression-script-filter.err.$$"
trap 'rm -f "$err_file"' EXIT

market_cli=""
if ! market_cli="$(resolve_market_cli 2>"$err_file")"; then
  err_msg="$(cat "$err_file")"
  print_error_item "$err_msg"
  exit 0
fi

if json_output="$("$market_cli" expr --query "$query" --default-fiat "$default_fiat" 2>"$err_file")"; then
  if [[ -z "$json_output" ]]; then
    print_error_item "market-cli returned empty response"
    exit 0
  fi

  if command -v jq >/dev/null 2>&1; then
    if ! jq -e '.items | type == "array"' >/dev/null <<<"$json_output"; then
      print_error_item "market-cli returned malformed Alfred JSON"
      exit 0
    fi
  fi

  printf '%s\n' "$json_output"
  exit 0
fi

err_msg="$(cat "$err_file")"
print_error_item "$err_msg"
