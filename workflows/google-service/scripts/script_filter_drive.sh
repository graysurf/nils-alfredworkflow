#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
helper_loader=""
for candidate in \
  "$script_dir/lib/workflow_helper_loader.sh" \
  "$script_dir/../../../scripts/lib/workflow_helper_loader.sh"; do
  if [[ -f "$candidate" ]]; then
    helper_loader="$candidate"
    break
  fi
done

if [[ -z "$helper_loader" ]]; then
  git_repo_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$git_repo_root" && -f "$git_repo_root/scripts/lib/workflow_helper_loader.sh" ]]; then
    helper_loader="$git_repo_root/scripts/lib/workflow_helper_loader.sh"
  fi
fi

if [[ -z "$helper_loader" ]]; then
  printf '{"items":[{"title":"Workflow helper missing","subtitle":"Cannot locate workflow_helper_loader.sh runtime helper.","valid":false}]}'
  exit 0
fi

# shellcheck disable=SC1090
source "$helper_loader"

load_helper_or_exit() {
  local helper_name="$1"
  if ! wfhl_source_helper "$script_dir" "$helper_name" auto; then
    wfhl_emit_missing_helper_item_json "$helper_name"
    exit 0
  fi
}

load_helper_or_exit "script_filter_error_json.sh"
load_helper_or_exit "workflow_cli_resolver.sh"
load_helper_or_exit "script_filter_query_policy.sh"

if ! declare -F sfqp_trim >/dev/null 2>&1; then
  sfqp_trim() {
    local value="${1-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
  }
fi

if ! declare -F sfqp_resolve_query_input >/dev/null 2>&1; then
  sfqp_resolve_query_input() {
    local query="${1-}"
    if [[ -z "$query" && -n "${alfred_workflow_query:-}" ]]; then
      query="${alfred_workflow_query}"
    elif [[ -z "$query" && -n "${ALFRED_WORKFLOW_QUERY:-}" ]]; then
      query="${ALFRED_WORKFLOW_QUERY}"
    elif [[ -z "$query" && ! -t 0 ]]; then
      query="$(cat)"
    fi
    printf '%s' "$query"
  }
fi

json_escape() {
  local value="${1-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  printf '%s' "$value"
}

begin_items() {
  _items_started=1
  _item_count=0
  printf '{"items":['
}

emit_item() {
  local title="$1"
  local subtitle="$2"
  local arg="${3-}"
  local valid="${4-true}"
  local autocomplete="${5-}"

  [[ "${_items_started:-0}" -eq 1 ]] || return 1

  if [[ "${_item_count:-0}" -gt 0 ]]; then
    printf ','
  fi

  printf '{"title":"%s","subtitle":"%s","valid":%s' \
    "$(json_escape "$title")" \
    "$(json_escape "$subtitle")" \
    "$valid"

  if [[ -n "$arg" ]]; then
    printf ',"arg":"%s"' "$(json_escape "$arg")"
  fi

  if [[ -n "$autocomplete" ]]; then
    printf ',"autocomplete":"%s"' "$(json_escape "$autocomplete")"
  fi

  printf '}'
  _item_count=$((_item_count + 1))
}

emit_drive_download_item() {
  local title="$1"
  local subtitle="$2"
  local arg="$3"
  local search_count="$4"
  local file_id="$5"
  local search_query="$6"
  local modifier_arg="drive-open-search::${search_query}"
  local modifier_subtitle="Open Drive web search for ${search_query}"

  [[ "${_items_started:-0}" -eq 1 ]] || return 1

  if [[ "${_item_count:-0}" -gt 0 ]]; then
    printf ','
  fi

  printf '{"title":"%s","subtitle":"%s","valid":true,"arg":"%s","variables":{"GOOGLE_DRIVE_SEARCH_RESULT_COUNT":"%s","GOOGLE_DRIVE_FILE_ID":"%s"},"mods":{"cmd":{"valid":true,"arg":"%s","subtitle":"%s"}}}' \
    "$(json_escape "$title")" \
    "$(json_escape "$subtitle")" \
    "$(json_escape "$arg")" \
    "$(json_escape "$search_count")" \
    "$(json_escape "$file_id")" \
    "$(json_escape "$modifier_arg")" \
    "$(json_escape "$modifier_subtitle")"

  _item_count=$((_item_count + 1))
}

end_items() {
  if [[ "${_items_started:-0}" -eq 1 ]]; then
    printf ']}'
  else
    printf '{"items":[]}'
  fi
}

to_lower() {
  printf '%s' "${1-}" | tr '[:upper:]' '[:lower:]'
}

expand_home_path() {
  local value="${1-}"

  case "$value" in
  "~")
    if [[ -n "${HOME:-}" ]]; then
      printf '%s\n' "${HOME%/}"
      return 0
    fi
    ;;
  \~/*)
    if [[ -n "${HOME:-}" ]]; then
      printf '%s/%s\n' "${HOME%/}" "${value#\~/}"
      return 0
    fi
    ;;
  esac

  printf '%s\n' "$value"
}

resolve_google_cli_override() {
  local configured="${GOOGLE_CLI_BIN:-}"
  configured="$(sfqp_trim "$configured")"
  configured="$(expand_home_path "$configured")"
  [[ -n "$configured" ]] || return 1
  printf '%s\n' "$configured"
}

resolve_google_cli() {
  local repo_root
  repo_root="$(cd "$script_dir/../../.." && pwd)"

  local configured
  configured="$(resolve_google_cli_override || true)"

  local packaged_cli
  packaged_cli="$script_dir/../bin/google-cli"

  local release_cli
  release_cli="$repo_root/target/release/google-cli"

  local debug_cli
  debug_cli="$repo_root/target/debug/google-cli"

  if declare -F wfcr_resolve_binary >/dev/null 2>&1; then
    wfcr_resolve_binary \
      "GOOGLE_CLI_BIN" \
      "$packaged_cli" \
      "$release_cli" \
      "$debug_cli" \
      "google-cli binary not found (set GOOGLE_CLI_BIN, install nils-google-cli, or build local target)"
    return $?
  fi

  if [[ -n "$configured" && -x "$configured" ]]; then
    printf '%s\n' "$configured"
    return 0
  fi

  if [[ -x "$packaged_cli" ]]; then
    printf '%s\n' "$packaged_cli"
    return 0
  fi

  if [[ -x "$release_cli" ]]; then
    printf '%s\n' "$release_cli"
    return 0
  fi

  if [[ -x "$debug_cli" ]]; then
    printf '%s\n' "$debug_cli"
    return 0
  fi

  return 1
}

resolve_workflow_data_dir() {
  local candidate
  for candidate in \
    "${ALFRED_WORKFLOW_DATA:-}" \
    "${ALFRED_WORKFLOW_CACHE:-}"; do
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' "${TMPDIR:-/tmp}/nils-google-service-workflow"
}

resolve_active_account_file() {
  local data_dir
  data_dir="$(resolve_workflow_data_dir)"
  printf '%s/active-account.v1.json\n' "$data_dir"
}

read_active_account() {
  local active_file
  active_file="$(resolve_active_account_file)"
  [[ -f "$active_file" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  local account
  account="$(jq -r '.active_account // empty' "$active_file" 2>/dev/null || true)"
  [[ -n "$account" ]] || return 1
  printf '%s\n' "$account"
}

resolve_google_cli_config_dir_env() {
  local configured="${GOOGLE_CLI_CONFIG_DIR:-}"
  configured="$(sfqp_trim "$configured")"
  configured="$(expand_home_path "$configured")"

  if [[ -n "$configured" ]]; then
    printf '%s\n' "$configured"
    return 0
  fi

  if [[ -n "${HOME:-}" ]]; then
    local legacy_config_dir
    legacy_config_dir="${HOME%/}/.config/google/credentials"
    if [[ -d "$legacy_config_dir" ]]; then
      printf '%s\n' "$legacy_config_dir"
      return 0
    fi
  fi

  return 1
}

apply_google_cli_env_overrides() {
  local resolved_config_dir=""
  resolved_config_dir="$(resolve_google_cli_config_dir_env || true)"
  if [[ -n "$resolved_config_dir" ]]; then
    export GOOGLE_CLI_CONFIG_DIR="$resolved_config_dir"
  fi

  if [[ -n "${GOOGLE_CLI_KEYRING_MODE:-}" ]]; then
    export GOOGLE_CLI_KEYRING_MODE
  fi
}

run_google_json_capture() {
  local __out_var="$1"
  local __rc_var="$2"
  local google_cli="$3"
  shift 3

  apply_google_cli_env_overrides

  local captured_output=""
  local captured_rc=0
  set +e
  captured_output="$("$google_cli" --json "$@" 2>&1)"
  captured_rc=$?
  set -e

  printf -v "$__out_var" '%s' "$captured_output"
  printf -v "$__rc_var" '%s' "$captured_rc"
}

format_size_label() {
  local raw_size="${1-0}"
  if ! [[ "$raw_size" =~ ^[0-9]+$ ]]; then
    printf 'size unknown'
    return 0
  fi

  if ((raw_size >= 1048576)); then
    awk -v bytes="$raw_size" 'BEGIN { printf "%.2f MB", bytes / 1048576.0 }'
    return 0
  fi

  awk -v bytes="$raw_size" 'BEGIN { printf "%.2f KB", bytes / 1024.0 }'
}

emit_help_items() {
  emit_item \
    "Open Google Drive Home" \
    "Open https://drive.google.com/drive/home" \
    "drive-open-home" \
    true \
    "open"

  emit_item \
    "Google Drive Search" \
    "Type: search <query>" \
    "" \
    false \
    "search "
}

handle_drive_search() {
  local search_query="$1"

  if ! command -v jq >/dev/null 2>&1; then
    emit_item \
      "Drive search unavailable" \
      "jq is required to parse google-cli JSON output" \
      "" \
      false \
      "search "
    return
  fi

  local google_cli
  if ! google_cli="$(resolve_google_cli 2>/dev/null)"; then
    emit_item \
      "Drive search unavailable" \
      "google-cli binary not found (set GOOGLE_CLI_BIN or install nils-google-cli)" \
      "" \
      false \
      "search "
    return
  fi

  local active_account=""
  active_account="$(read_active_account || true)"

  local -a command_args=()
  if [[ -n "$active_account" ]]; then
    command_args+=(-a "$active_account")
  fi
  command_args+=(drive search --max 25 "$search_query")

  local output rc
  run_google_json_capture output rc "$google_cli" "${command_args[@]}"

  if [[ "$rc" -ne 0 ]]; then
    local message
    message="$(printf '%s\n' "$output" | jq -r '.error.message // empty' 2>/dev/null || true)"
    if [[ -z "$message" ]]; then
      message="$(sfej_normalize_error_message "$output")"
    fi
    [[ -n "$message" ]] || message="google-cli drive search failed"
    emit_item "Drive search failed" "$message" "" false "search "
    return
  fi

  if ! printf '%s\n' "$output" | jq -e '.ok == true and (.result | type == "object")' >/dev/null 2>&1; then
    local message
    message="$(printf '%s\n' "$output" | jq -r '.error.message // empty' 2>/dev/null || true)"
    [[ -n "$message" ]] || message="unexpected drive search response format"
    emit_item "Drive search failed" "$message" "" false "search "
    return
  fi

  local result_count
  result_count="$(printf '%s\n' "$output" | jq -r '.result.count // ((.result.files // []) | length) // 0' 2>/dev/null || true)"
  if ! [[ "$result_count" =~ ^[0-9]+$ ]]; then
    result_count="0"
  fi

  local emitted=0
  while IFS=$'\t' read -r file_id file_name mime_type size_bytes; do
    [[ -n "$file_id" ]] || continue
    [[ -n "$file_name" ]] || file_name="$file_id"
    [[ -n "$mime_type" ]] || mime_type="unknown type"

    local size_label
    size_label="$(format_size_label "$size_bytes")"

    local action_token
    action_token="drive-download::${file_id}::${result_count}"

    emit_drive_download_item \
      "$file_name" \
      "${size_label} · ${mime_type} · result.count=${result_count}" \
      "$action_token" \
      "$result_count" \
      "$file_id" \
      "$search_query"
    emitted=1
  done < <(printf '%s\n' "$output" | jq -r '.result.files[]? | [.id // "", .name // "", .mime_type // "", ((.size_bytes // 0) | tostring)] | @tsv')

  if [[ "$emitted" -eq 0 ]]; then
    emit_item \
      "No Drive files found" \
      "query=${search_query} · result.count=${result_count}" \
      "" \
      false \
      "search "
  fi
}

query="$(sfqp_resolve_query_input "${1:-}")"
trimmed_query="$(sfqp_trim "$query")"
lower_query="$(to_lower "$trimmed_query")"

begin_items

if [[ -z "$trimmed_query" || "$lower_query" == "help" || "$lower_query" == "?" ]]; then
  emit_help_items
  end_items
  exit 0
fi

if [[ "$lower_query" == "open" || "$lower_query" == "home" || "$lower_query" == "open home" || "$lower_query" == "open drive" || "$lower_query" == "drive home" ]]; then
  emit_item \
    "Open Google Drive Home" \
    "Open https://drive.google.com/drive/home" \
    "drive-open-home" \
    true \
    "open"
  end_items
  exit 0
fi

search_query="$trimmed_query"
if [[ "$lower_query" == search* ]]; then
  search_query="$(printf '%s' "$trimmed_query" | sed -E 's/^[[:space:]]*search[[:space:]]*//I')"
fi
search_query="$(sfqp_trim "$search_query")"

if [[ -z "$search_query" ]]; then
  emit_help_items
  end_items
  exit 0
fi

handle_drive_search "$search_query"
end_items
