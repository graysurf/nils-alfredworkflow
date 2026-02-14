#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

resolve_helper() {
  local helper_name="$1"
  local candidate
  local cwd_repo_root

  for candidate in \
    "$script_dir/lib/$helper_name" \
    "$script_dir/../../../scripts/lib/$helper_name"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if command -v git >/dev/null 2>&1; then
    cwd_repo_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$cwd_repo_root" ]]; then
      candidate="$cwd_repo_root/scripts/lib/$helper_name"
      if [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  fi

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

print_error_item() {
  local raw_message="${1:-market-cli expr failed}"
  local message
  message="$(sfej_normalize_error_message "$raw_message")"
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

  sfej_emit_error_item_json "$title" "$subtitle"
}

resolve_market_cli() {
  wfcr_resolve_binary \
    "MARKET_CLI_BIN" \
    "$script_dir/../bin/market-cli" \
    "$repo_root/target/release/market-cli" \
    "$repo_root/target/debug/market-cli" \
    "market-cli binary not found (checked MARKET_CLI_BIN/package/release/debug paths)"
}

query="${1:-}"
default_fiat="${MARKET_DEFAULT_FIAT:-USD}"

if [[ -z "$(printf '%s' "$query" | sed 's/[[:space:]]//g')" ]]; then
  sfej_emit_error_item_json \
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
