#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 1 || -z "${1:-}" ]]; then
  echo "usage: action_open.sh <action-token>" >&2
  exit 2
fi

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

resolve_codex_cli() {
  if [[ -n "${CODEX_CLI_BIN:-}" && -x "${CODEX_CLI_BIN}" ]]; then
    clear_quarantine_if_needed "${CODEX_CLI_BIN}"
    printf '%s\n' "${CODEX_CLI_BIN}"
    return 0
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local packaged_cli
  packaged_cli="$script_dir/../bin/codex-cli"
  if [[ -x "$packaged_cli" ]]; then
    clear_quarantine_if_needed "$packaged_cli"
    printf '%s\n' "$packaged_cli"
    return 0
  fi

  local resolved
  resolved="$(command -v codex-cli 2>/dev/null || true)"
  if [[ -n "$resolved" && -x "$resolved" ]]; then
    clear_quarantine_if_needed "$resolved"
    printf '%s\n' "$resolved"
    return 0
  fi

  echo "codex-cli binary not found (re-import workflow bundle, set CODEX_CLI_BIN, or install nils-codex-cli 0.3.2)" >&2
  return 1
}

notify() {
  local message="$1"
  local escaped
  escaped="$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')"

  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$escaped\" with title \"Codex CLI Workflow\"" >/dev/null 2>&1 || true
  fi
}

save_confirmation_enabled() {
  local raw="${CODEX_SAVE_CONFIRM:-1}"
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
  0 | false | no | off)
    return 1
    ;;
  *)
    return 0
    ;;
  esac
}

confirm_save_if_needed() {
  local secret="$1"
  local yes_flag="$2"

  if [[ "$yes_flag" == "1" ]]; then
    return 0
  fi

  if ! save_confirmation_enabled; then
    return 0
  fi

  if ! command -v osascript >/dev/null 2>&1; then
    return 0
  fi

  local escaped_secret
  escaped_secret="$(printf '%s' "$secret" | sed 's/\\/\\\\/g; s/"/\\"/g')"

  if osascript >/dev/null 2>&1 <<EOF; then
tell application "System Events"
  activate
  display dialog "Save current auth to ${escaped_secret}?" buttons {"Cancel", "Save"} default button "Save" with icon caution
end tell
EOF
    return 0
  fi

  notify "Cancelled: auth save ${secret}"
  echo "auth save cancelled by user." >&2
  return 130
}

resolve_default_codex_secret_dir() {
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    printf '%s/codex_secrets\n' "${XDG_CONFIG_HOME%/}"
    return 0
  fi

  if [[ -n "${HOME:-}" ]]; then
    printf '%s/.config/codex_secrets\n' "${HOME%/}"
    return 0
  fi

  return 1
}

ensure_codex_secret_dir_env() {
  local configured="${CODEX_SECRET_DIR:-}"
  configured="$(printf '%s' "$configured" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

  if [[ -z "$configured" ]]; then
    configured="$(resolve_default_codex_secret_dir || true)"
  fi

  if [[ -z "$configured" ]]; then
    return 1
  fi

  export CODEX_SECRET_DIR="$configured"
  printf '%s\n' "$configured"
}

ensure_codex_secret_dir_exists() {
  local resolved
  if ! resolved="$(ensure_codex_secret_dir_env)"; then
    echo "CODEX_SECRET_DIR is not configured and no default path could be derived." >&2
    return 1
  fi

  if mkdir -p "$resolved"; then
    return 0
  fi

  echo "CODEX_SECRET_DIR could not be created: $resolved" >&2
  return 1
}

resolve_workflow_cache_dir() {
  local candidate
  for candidate in \
    "${alfred_workflow_cache:-}" \
    "${ALFRED_WORKFLOW_CACHE:-}" \
    "${alfred_workflow_data:-}" \
    "${ALFRED_WORKFLOW_DATA:-}"; do
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' "${TMPDIR:-/tmp}/nils-codex-cli-workflow"
}

diag_result_meta_path() {
  local cache_dir
  cache_dir="$(resolve_workflow_cache_dir)"
  printf '%s/diag-rate-limits.last.meta\n' "$cache_dir"
}

diag_result_output_path() {
  local cache_dir
  cache_dir="$(resolve_workflow_cache_dir)"
  printf '%s/diag-rate-limits.last.out\n' "$cache_dir"
}

store_diag_result() {
  local mode="$1"
  local summary="$2"
  local command="$3"
  local rc="$4"
  local output="$5"
  local timestamp
  timestamp="$(date +%s)"

  local meta_path
  meta_path="$(diag_result_meta_path)"
  local output_path
  output_path="$(diag_result_output_path)"
  local output_dir
  output_dir="$(dirname "$output_path")"

  mkdir -p "$output_dir"
  {
    printf 'mode=%s\n' "$mode"
    printf 'summary=%s\n' "$summary"
    printf 'command=%s\n' "$command"
    printf 'exit_code=%s\n' "$rc"
    printf 'timestamp=%s\n' "$timestamp"
  } >"$meta_path"
  printf '%s\n' "$output" >"$output_path"
}

open_alfred_search_best_effort() {
  local query="$1"
  local escaped
  escaped="$(printf '%s' "$query" | sed 's/\\/\\\\/g; s/"/\\"/g')"

  if ! command -v osascript >/dev/null 2>&1; then
    return 1
  fi

  run_with_timeout 2 osascript -e "tell application \"Alfred 5\" to search \"$escaped\"" >/dev/null 2>&1 ||
    run_with_timeout 2 osascript -e "tell application \"Alfred\" to search \"$escaped\"" >/dev/null 2>&1 ||
    true
  return 0
}

resolve_login_timeout_seconds() {
  local raw="${CODEX_LOGIN_TIMEOUT_SECONDS:-60}"
  if [[ "$raw" =~ ^[0-9]+$ ]] && [[ "$raw" -ge 1 ]] && [[ "$raw" -le 3600 ]]; then
    printf '%s\n' "$raw"
    return 0
  fi
  printf '60\n'
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift

  if [[ "$timeout_seconds" -le 0 ]]; then
    "$@"
    return $?
  fi

  "$@" &
  local cmd_pid=$!
  local start_ts=$SECONDS

  while kill -0 "$cmd_pid" >/dev/null 2>&1; do
    if ((SECONDS - start_ts >= timeout_seconds)); then
      kill -TERM "$cmd_pid" >/dev/null 2>&1 || true
      sleep 2
      kill -KILL "$cmd_pid" >/dev/null 2>&1 || true
      wait "$cmd_pid" >/dev/null 2>&1 || true
      return 124
    fi
    sleep 0.2
  done

  wait "$cmd_pid"
  return $?
}

strip_ansi() {
  local line="${1:-}"
  printf '%s' "$line" | sed -E $'s/\\x1B\\[[0-9;]*[A-Za-z]//g'
}

extract_login_url() {
  local line="${1:-}"
  local clean
  clean="$(strip_ansi "$line")"
  local urls
  urls="$(printf '%s\n' "$clean" | grep -Eo 'https?://[^[:space:]<>()"]+' || true)"

  if [[ -z "$urls" ]]; then
    return 1
  fi

  local url
  while IFS= read -r url || [[ -n "$url" ]]; do
    url="${url%%[.,;:!?)]}"
    if [[ "$url" =~ ^https?://(localhost|127\.0\.0\.1)(:[0-9]+)?(/|$) ]]; then
      continue
    fi
    if [[ "$url" =~ ^https://(auth\.openai\.com|chatgpt\.com|openai\.com)(/|$) ]]; then
      printf '%s\n' "$url"
      return 0
    fi
  done <<<"$urls"

  while IFS= read -r url || [[ -n "$url" ]]; do
    url="${url%%[.,;:!?)]}"
    if [[ "$url" =~ ^https?://(localhost|127\.0\.0\.1)(:[0-9]+)?(/|$) ]]; then
      continue
    fi
    printf '%s\n' "$url"
    return 0
  done <<<"$urls"

  return 1
}

extract_device_code() {
  local line="${1:-}"
  local clean
  clean="$(strip_ansi "$line")"
  local code
  code="$(printf '%s\n' "$clean" | grep -Eo '[A-Z0-9]{3,8}-[A-Z0-9]{3,8}' | head -n1 || true)"
  if [[ -z "$code" ]]; then
    code="$(printf '%s\n' "$clean" | grep -Eo '[A-Z0-9]{6,12}' | head -n1 || true)"
  fi
  [[ -n "$code" ]] || return 1
  printf '%s\n' "$code"
}

open_url_best_effort() {
  local url="$1"
  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 || true
    return 0
  fi
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 || true
    return 0
  fi
  return 1
}

copy_to_clipboard_best_effort() {
  local value="$1"
  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$value" | pbcopy
    return 0
  fi
  if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$value" | wl-copy
    return 0
  fi
  if command -v xclip >/dev/null 2>&1; then
    printf '%s' "$value" | xclip -selection clipboard
    return 0
  fi
  return 1
}

run_codex_command() {
  local codex_cli="$1"
  local summary="$2"
  shift 2

  local output
  if output="$("$codex_cli" "$@" 2>&1)"; then
    notify "Success: ${summary}"
    if [[ -n "$output" ]]; then
      printf '%s\n' "$output"
    fi
    return 0
  else
    local rc=$?
    notify "Failed(${rc}): ${summary}"
    printf '%s\n' "$output" >&2
    return "$rc"
  fi
}

run_codex_diag_command() {
  local codex_cli="$1"
  local mode="$2"
  local summary="$3"
  local result_query="$4"
  shift 4

  local output=""
  local rc=0

  set +e
  output="$("$codex_cli" "$@" 2>&1)"
  rc=$?
  set -e

  store_diag_result "$mode" "$summary" "$*" "$rc" "$output"
  open_alfred_search_best_effort "$result_query"

  if [[ "$rc" -eq 0 ]]; then
    notify "Diag ready: ${mode}"
    [[ -n "$output" ]] && printf '%s\n' "$output"
    return 0
  fi

  notify "Diag failed(${rc}): ${mode}"
  [[ -n "$output" ]] && printf '%s\n' "$output" >&2
  return "$rc"
}

run_codex_login_api_key() {
  local codex_cli="$1"
  local summary="auth login --api-key"
  local api_key="${CODEX_API_KEY:-}"
  local timeout_seconds
  timeout_seconds="$(resolve_login_timeout_seconds)"
  local output=""
  local rc=0

  if [[ -z "$api_key" ]]; then
    notify "Waiting: enter API key"
    if command -v osascript >/dev/null 2>&1; then
      if ! api_key="$(
        osascript <<'EOF'
tell application "System Events"
  activate
  display dialog "Enter OpenAI API key for codex-cli login" default answer "" with hidden answer buttons {"Cancel", "Login"} default button "Login"
  text returned of result
end tell
EOF
      )"; then
        notify "Cancelled: ${summary}"
        echo "codex-cli api-key login cancelled." >&2
        return 130
      fi
    fi
  fi

  api_key="$(printf '%s' "$api_key" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  if [[ -z "$api_key" ]]; then
    notify "Failed(64): ${summary}"
    echo "No API key provided. Set CODEX_API_KEY or enter key when prompted." >&2
    return 64
  fi

  set +e
  output="$(printf '%s\n' "$api_key" | run_with_timeout "$timeout_seconds" "$codex_cli" auth login --api-key 2>&1)"
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    notify "Success: ${summary}"
    [[ -n "$output" ]] && printf '%s\n' "$output"
    return 0
  fi

  if [[ "$rc" -eq 124 ]]; then
    notify "Timed out(${timeout_seconds}s): ${summary}"
    echo "Login timed out after ${timeout_seconds}s. Set CODEX_LOGIN_TIMEOUT_SECONDS to adjust." >&2
    return 124
  fi

  notify "Failed(${rc}): ${summary}"
  [[ -n "$output" ]] && printf '%s\n' "$output" >&2
  return "$rc"
}

run_codex_login_browser() {
  local codex_cli="$1"
  local summary="auth login"
  local timeout_seconds
  timeout_seconds="$(resolve_login_timeout_seconds)"
  local browser_opened="0"

  notify "Starting: browser login (${timeout_seconds}s timeout)"
  set +e
  run_with_timeout "$timeout_seconds" "$codex_cli" auth login 2>&1 | while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line"
    if [[ "$browser_opened" == "0" ]]; then
      local login_url
      login_url="$(extract_login_url "$line" || true)"
      if [[ -n "$login_url" ]]; then
        open_url_best_effort "$login_url"
        browser_opened="1"
      fi
    fi
  done
  local rc=${PIPESTATUS[0]}
  set -e

  if [[ "$rc" -eq 0 ]]; then
    notify "Success: ${summary}"
    return 0
  fi

  if [[ "$rc" -eq 124 ]]; then
    notify "Timed out(${timeout_seconds}s): ${summary}"
    echo "Login timed out after ${timeout_seconds}s. Set CODEX_LOGIN_TIMEOUT_SECONDS to adjust." >&2
    return 124
  fi

  notify "Failed(${rc}): ${summary}"
  return "$rc"
}

run_codex_login_device_code() {
  local codex_cli="$1"
  local summary="auth login --device-code"
  local timeout_seconds
  timeout_seconds="$(resolve_login_timeout_seconds)"
  local browser_opened="0"
  local code_copied="0"

  notify "Starting: device-code login (${timeout_seconds}s timeout)"
  set +e
  run_with_timeout "$timeout_seconds" "$codex_cli" auth login --device-code 2>&1 | while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line"

    if [[ "$browser_opened" == "0" ]]; then
      local login_url
      login_url="$(extract_login_url "$line" || true)"
      if [[ -n "$login_url" ]]; then
        open_url_best_effort "$login_url"
        browser_opened="1"
      fi
    fi

    if [[ "$code_copied" == "0" ]]; then
      local device_code
      device_code="$(extract_device_code "$line" || true)"
      if [[ -n "$device_code" ]]; then
        copy_to_clipboard_best_effort "$device_code" || true
        notify "Device code copied: ${device_code}"
        code_copied="1"
      fi
    fi
  done
  local rc=${PIPESTATUS[0]}
  set -e

  if [[ "$rc" -eq 0 ]]; then
    notify "Success: ${summary}"
    return 0
  fi

  if [[ "$rc" -eq 124 ]]; then
    notify "Timed out(${timeout_seconds}s): ${summary}"
    echo "Login timed out after ${timeout_seconds}s. Set CODEX_LOGIN_TIMEOUT_SECONDS to adjust." >&2
    return 124
  fi

  notify "Failed(${rc}): ${summary}"
  return "$rc"
}

action_token="$1"
codex_cli=""
if ! codex_cli="$(resolve_codex_cli)"; then
  exit 1
fi
ensure_codex_secret_dir_env >/dev/null 2>&1 || true

case "$action_token" in
login::browser)
  run_codex_login_browser "$codex_cli"
  exit $?
  ;;
login::api-key)
  run_codex_login_api_key "$codex_cli"
  exit $?
  ;;
login::device-code)
  run_codex_login_device_code "$codex_cli"
  exit $?
  ;;
save::*)
  payload="${action_token#save::}"
  secret="${payload%::*}"
  yes_flag="${payload##*::}"

  if [[ -z "$secret" || -z "$yes_flag" ]]; then
    echo "invalid save action token: $action_token" >&2
    exit 2
  fi

  if confirm_save_if_needed "$secret" "$yes_flag"; then
    :
  else
    exit $?
  fi

  if ! ensure_codex_secret_dir_exists; then
    notify "Failed: CODEX_SECRET_DIR missing"
    exit 1
  fi

  if [[ "$yes_flag" == "1" ]]; then
    run_codex_command "$codex_cli" "auth save --yes $secret" auth save --yes "$secret"
  else
    run_codex_command "$codex_cli" "auth save $secret" auth save "$secret"
  fi
  exit $?
  ;;
diag::default)
  run_codex_diag_command "$codex_cli" "default" "diag rate-limits" "cxd result" diag rate-limits
  exit $?
  ;;
diag::cached)
  run_codex_diag_command "$codex_cli" "cached" "diag rate-limits --cached" "cxd result" diag rate-limits --cached
  exit $?
  ;;
diag::one-line)
  run_codex_diag_command "$codex_cli" "one-line" "diag rate-limits --one-line" "cxd result" diag rate-limits --one-line
  exit $?
  ;;
diag::all)
  run_codex_diag_command "$codex_cli" "all" "diag rate-limits --all" "cxd result" diag rate-limits --all
  exit $?
  ;;
diag::all-json)
  run_codex_diag_command "$codex_cli" "all-json" "diag rate-limits --all --json" "cxda result" diag rate-limits --all --json
  exit $?
  ;;
diag::async)
  run_codex_diag_command "$codex_cli" "async" "diag rate-limits --all --async --jobs 4" "cxd result" diag rate-limits --all --async --jobs 4
  exit $?
  ;;
*)
  echo "unknown action token: $action_token" >&2
  exit 2
  ;;
esac
