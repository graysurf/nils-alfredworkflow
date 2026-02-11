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

trim() {
  local value="${1-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

to_lower() {
  local value="${1-}"
  printf '%s' "$value" | tr '[:upper:]' '[:lower:]'
}

strip_ansi() {
  local line="${1:-}"
  printf '%s' "$line" | sed -E $'s/\\x1B\\[[0-9;]*[A-Za-z]//g'
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

read_meta_value() {
  local file="$1"
  local key="$2"
  sed -n "s/^${key}=//p" "$file" | head -n1
}

format_epoch() {
  local ts="${1:-}"
  if [[ -z "$ts" || ! "$ts" =~ ^[0-9]+$ ]]; then
    printf 'unknown time\n'
    return 0
  fi

  if date -r "$ts" '+%Y-%m-%d %H:%M:%S' >/dev/null 2>&1; then
    date -r "$ts" '+%Y-%m-%d %H:%M:%S'
    return 0
  fi

  if date -d "@$ts" '+%Y-%m-%d %H:%M:%S' >/dev/null 2>&1; then
    date -d "@$ts" '+%Y-%m-%d %H:%M:%S'
    return 0
  fi

  printf 'epoch:%s\n' "$ts"
}

emit_diag_all_json_account_items() {
  local lower_query="$1"
  local output_path="$2"

  if ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  if ! jq -e '.results | type == "array"' "$output_path" >/dev/null 2>&1; then
    return 1
  fi

  local max_rows=24
  if [[ "$lower_query" == *" raw"* || "$lower_query" == *"--raw"* ]]; then
    max_rows=200
  fi

  local row_count=0
  local truncated=0
  local row
  while IFS= read -r row || [[ -n "$row" ]]; do
    row_count=$((row_count + 1))
    if [[ "$row_count" -gt "$max_rows" ]]; then
      truncated=1
      break
    fi

    local name status label non_weekly weekly weekly_reset source email
    IFS=$'\t' read -r name status label non_weekly weekly weekly_reset source email <<<"$row"
    [[ -n "$name" ]] || name="(unknown)"
    [[ -n "$status" ]] || status="unknown"
    [[ -n "$label" ]] || label="5h"
    [[ -n "$weekly_reset" ]] || weekly_reset="-"
    [[ -n "$source" ]] || source="-"
    [[ -n "$email" ]] || email="-"

    if [[ "$status" == "ok" ]]; then
      local non_weekly_text="${label} n/a"
      local weekly_text="weekly n/a"
      if [[ -n "$non_weekly" && "$non_weekly" != "null" ]]; then
        non_weekly_text="${label} ${non_weekly}%"
      fi
      if [[ -n "$weekly" && "$weekly" != "null" ]]; then
        weekly_text="weekly ${weekly}%"
      fi
      emit_item \
        "${name} | ${non_weekly_text} | ${weekly_text}" \
        "${email} | reset ${weekly_reset} | source ${source}" \
        "" \
        false \
        ""
    else
      emit_item \
        "${name} | status=${status}" \
        "${email} | source ${source}" \
        "" \
        false \
        ""
    fi
  done < <(jq -r '.results // [] | sort_by((.summary.weekly_reset_epoch // 9999999999), (.name // ""))[]? | [(.name // "(unknown)"), (.status // "unknown"), (.summary.non_weekly_label // "5h"), (.summary.non_weekly_remaining // "null"), (.summary.weekly_remaining // "null"), (.summary.weekly_reset_local // "-"), (.source // "-"), (.raw_usage.email // "-")] | @tsv' "$output_path")

  if [[ "$row_count" -eq 0 ]]; then
    emit_item \
      "No accounts in JSON result" \
      "diag --all returned zero entries." \
      "" \
      false \
      ""
  fi

  if [[ "$truncated" -eq 1 ]]; then
    emit_item \
      "Account list truncated (${max_rows} rows shown)" \
      "Type: cxda result raw" \
      "" \
      false \
      "diag result all-json raw"
  fi

  return 0
}

emit_diag_result_items() {
  local lower_query="$1"
  local meta_path
  meta_path="$(diag_result_meta_path)"
  local output_path
  output_path="$(diag_result_output_path)"
  local run_alias="cxd"
  local result_alias="cxd result"

  if [[ "$lower_query" == *"all-json"* || "$lower_query" == *"--all-json"* ]]; then
    run_alias="cxda"
    result_alias="cxda result"
  fi

  if [[ ! -f "$meta_path" || ! -f "$output_path" ]]; then
    emit_item \
      "No diag result yet" \
      "Run ${run_alias} and press Enter once. Then use ${result_alias}." \
      "" \
      false \
      "diag"
    return
  fi

  local mode rc timestamp command summary
  mode="$(read_meta_value "$meta_path" mode)"
  rc="$(read_meta_value "$meta_path" exit_code)"
  timestamp="$(read_meta_value "$meta_path" timestamp)"
  command="$(read_meta_value "$meta_path" command)"
  summary="$(read_meta_value "$meta_path" summary)"

  [[ -n "$mode" ]] || mode="unknown"
  [[ -n "$rc" ]] || rc="1"
  [[ -n "$command" ]] || command="diag rate-limits"
  [[ -n "$summary" ]] || summary="$command"
  local formatted_time
  formatted_time="$(format_epoch "$timestamp")"

  if [[ "$rc" == "0" ]]; then
    emit_item \
      "Diag result ready (${mode})" \
      "${summary} | ${formatted_time}" \
      "" \
      false \
      "diag result"
  else
    emit_item \
      "Diag failed (${mode}, rc=${rc})" \
      "${summary} | ${formatted_time}" \
      "" \
      false \
      "diag result"
  fi

  if [[ "$mode" == "all-json" && "$rc" == "0" ]]; then
    if emit_diag_all_json_account_items "$lower_query" "$output_path"; then
      return
    fi
  fi

  local max_lines=12
  local raw_hint_title="Type: cxd result raw"
  local raw_hint_autocomplete="diag result raw"
  if [[ "$mode" == "all-json" ]]; then
    raw_hint_title="Type: cxda result raw"
    raw_hint_autocomplete="diag result all-json raw"
  fi
  if [[ "$lower_query" == *" raw"* || "$lower_query" == *"--raw"* ]]; then
    max_lines=60
  fi

  local line_count=0
  local truncated=0
  local line clean
  while IFS= read -r line || [[ -n "$line" ]]; do
    clean="$(trim "$(strip_ansi "$line")")"
    [[ -z "$clean" ]] && continue

    line_count=$((line_count + 1))
    if [[ "$line_count" -gt "$max_lines" ]]; then
      truncated=1
      break
    fi

    emit_item \
      "$clean" \
      "diag output" \
      "" \
      false \
      ""
  done <"$output_path"

  if [[ "$line_count" -eq 0 ]]; then
    emit_item \
      "(no output)" \
      "diag command finished without stdout/stderr." \
      "" \
      false \
      ""
  fi

  if [[ "$truncated" -eq 1 ]]; then
    emit_item \
      "Output truncated (${max_lines} lines shown)" \
      "$raw_hint_title" \
      "" \
      false \
      "$raw_hint_autocomplete"
  fi
}

is_truthy() {
  local value
  value="$(to_lower "${1:-}")"
  case "$value" in
  1 | true | yes | on)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

query_has_assessment_flag() {
  local lower_query="${1:-}"
  [[ "$lower_query" == *"--assessment"* || "$lower_query" == *"--show-assessment"* ]]
}

strip_assessment_flags() {
  local raw_query="${1:-}"
  local token
  local output=()

  # shellcheck disable=SC2206
  local parts=($raw_query)
  for token in "${parts[@]}"; do
    case "$(to_lower "$token")" in
    --assessment | --show-assessment)
      continue
      ;;
    *)
      output+=("$token")
      ;;
    esac
  done

  printf '%s\n' "$(trim "${output[*]:-}")"
}

begin_items() {
  ITEM_COUNT=0
  printf '{"items":['
}

emit_item() {
  local title="$1"
  local subtitle="$2"
  local arg="${3-}"
  local valid="${4:-false}"
  local autocomplete="${5-}"

  if [[ "$ITEM_COUNT" -gt 0 ]]; then
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
  ITEM_COUNT=$((ITEM_COUNT + 1))
}

end_items() {
  printf ']}\n'
}

resolve_codex_cli_path() {
  if [[ -n "${CODEX_CLI_BIN:-}" && -x "${CODEX_CLI_BIN}" ]]; then
    printf '%s\n' "${CODEX_CLI_BIN}"
    return 0
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local packaged_cli
  packaged_cli="$script_dir/../bin/codex-cli"
  if [[ -x "$packaged_cli" ]]; then
    printf '%s\n' "$packaged_cli"
    return 0
  fi

  local resolved
  resolved="$(command -v codex-cli 2>/dev/null || true)"
  if [[ -n "$resolved" && -x "$resolved" ]]; then
    printf '%s\n' "$resolved"
    return 0
  fi

  return 1
}

emit_runtime_status() {
  if resolve_codex_cli_path >/dev/null 2>&1; then
    return
  fi

  emit_item \
    "codex-cli runtime missing" \
    "Re-import workflow, set CODEX_CLI_BIN, or install nils-codex-cli 0.3.2 manually." \
    "" \
    false \
    ""
}

emit_assessment_items() {
  emit_item \
    "Implemented now: auth login" \
    "Supports browser (default), --api-key, and --device-code from Alfred." \
    "" \
    false \
    ""
  emit_item \
    "Implemented now: auth save" \
    "Use save <secret> and optional --yes for non-interactive overwrite." \
    "" \
    false \
    ""
  emit_item \
    "Implemented now: diag rate-limits" \
    "Quick presets included: default, --cached, --one-line, --all, --all --async." \
    "" \
    false \
    ""
  emit_item \
    "Can be added next: auth use/refresh/current/sync" \
    "0.3.2 already supports these auth commands; straightforward to map." \
    "" \
    false \
    ""
  emit_item \
    "Can be added next: config / starship / agent" \
    "config show/set, starship render, and agent wrappers are available in the crate." \
    "" \
    false \
    ""
}

emit_auth_action_items() {
  emit_item \
    "auth login (browser)" \
    "Run codex-cli auth login" \
    "login::browser" \
    true \
    "login"
  emit_item \
    "auth login --api-key" \
    "Run codex-cli auth login --api-key" \
    "login::api-key" \
    true \
    "login --api-key"
  emit_item \
    "auth login --device-code" \
    "Run codex-cli auth login --device-code" \
    "login::device-code" \
    true \
    "login --device-code"
  emit_item \
    "auth save <secret.json>" \
    "Type: save team-alpha.json (or save --yes team-alpha.json)" \
    "" \
    false \
    "save "
}

emit_diag_action_items() {
  emit_item \
    "diag rate-limits" \
    "Run default diagnostics." \
    "diag::default" \
    true \
    "diag"
  emit_item \
    "diag rate-limits --cached" \
    "Use cache only; no network." \
    "diag::cached" \
    true \
    "diag cached"
  emit_item \
    "diag rate-limits --one-line" \
    "Compact one-line diagnostics output." \
    "diag::one-line" \
    true \
    "diag one-line"
  emit_item \
    "diag rate-limits --all" \
    "Query all secrets under CODEX_SECRET_DIR." \
    "diag::all" \
    true \
    "diag all"
  emit_item \
    "diag rate-limits --all --async --jobs 4" \
    "Concurrent diagnostics for all secrets." \
    "diag::async" \
    true \
    "diag async"
}

emit_default_action_items() {
  emit_auth_action_items
  emit_diag_action_items
}

normalize_save_secret() {
  local raw_secret="$1"
  local secret
  secret="$(trim "$raw_secret")"

  if [[ -z "$secret" ]]; then
    return 1
  fi

  if [[ "$secret" == */* ]]; then
    return 1
  fi

  if [[ "$secret" != *.json ]]; then
    secret="${secret}.json"
  fi

  if [[ ! "$secret" =~ ^[A-Za-z0-9._@-]+\.json$ ]]; then
    return 1
  fi

  printf '%s\n' "$secret"
}

handle_login_query() {
  local lower_query="$1"
  local mode="browser"

  local has_api=0
  local has_device=0

  if [[ "$lower_query" == *"--api-key"* || "$lower_query" == *" api-key"* || "$lower_query" == *" apikey"* || "$lower_query" == *" api"* ]]; then
    has_api=1
  fi

  if [[ "$lower_query" == *"--device-code"* || "$lower_query" == *" device-code"* || "$lower_query" == *" device"* ]]; then
    has_device=1
  fi

  if [[ "$has_api" -eq 1 && "$has_device" -eq 1 ]]; then
    emit_item \
      "Invalid login mode selection" \
      "Use either --api-key or --device-code, not both." \
      "" \
      false \
      "login"
    return
  fi

  if [[ "$has_api" -eq 1 ]]; then
    mode="api-key"
  elif [[ "$has_device" -eq 1 ]]; then
    mode="device-code"
  fi

  case "$mode" in
  api-key)
    emit_item \
      "Run auth login --api-key" \
      "Login using API key flow." \
      "login::api-key" \
      true \
      "login --api-key"
    ;;
  device-code)
    emit_item \
      "Run auth login --device-code" \
      "Login using ChatGPT device-code flow." \
      "login::device-code" \
      true \
      "login --device-code"
    ;;
  *)
    emit_item \
      "Run auth login (browser)" \
      "Login using ChatGPT browser flow." \
      "login::browser" \
      true \
      "login"
    ;;
  esac
}

handle_save_query() {
  local raw_query="$1"
  local remainder
  local yes_flag=0
  local secret=""
  local token
  local seen_extra=0

  remainder="$(printf '%s' "$raw_query" | sed -E 's/^[[:space:]]*(auth[[:space:]]+)?save[[:space:]]*//I')"

  # shellcheck disable=SC2206
  local parts=($remainder)
  for token in "${parts[@]}"; do
    case "$token" in
    --yes | -y)
      yes_flag=1
      ;;
    *)
      if [[ -z "$secret" ]]; then
        secret="$token"
      else
        seen_extra=1
      fi
      ;;
    esac
  done

  if [[ "$seen_extra" -eq 1 ]]; then
    emit_item \
      "Invalid auth save arguments" \
      "Usage: save [--yes] <secret.json>" \
      "" \
      false \
      "save "
    return
  fi

  if [[ -z "$secret" ]]; then
    emit_item \
      "Missing secret file name" \
      "Usage: save [--yes] <secret.json> (example: save team-alpha.json)" \
      "" \
      false \
      "save "
    return
  fi

  local normalized_secret
  if ! normalized_secret="$(normalize_save_secret "$secret")"; then
    emit_item \
      "Invalid secret file name" \
      "Use basename only, allowed chars: A-Z a-z 0-9 . _ @ - and suffix .json" \
      "" \
      false \
      "save "
    return
  fi

  emit_item \
    "Run auth save ${normalized_secret}" \
    "Save active auth into CODEX_SECRET_DIR/${normalized_secret}" \
    "save::${normalized_secret}::${yes_flag}" \
    true \
    "save ${normalized_secret}"

  if [[ "$yes_flag" -eq 0 ]]; then
    emit_item \
      "Run auth save --yes ${normalized_secret}" \
      "Force overwrite if file already exists." \
      "save::${normalized_secret}::1" \
      true \
      "save --yes ${normalized_secret}"
  fi
}

emit_latest_diag_result_items_inline() {
  local meta_path
  meta_path="$(diag_result_meta_path)"
  local output_path
  output_path="$(diag_result_output_path)"

  if [[ ! -f "$meta_path" || ! -f "$output_path" ]]; then
    emit_item \
      "Latest diag result unavailable" \
      "Run cxd/cxda once, then open result again." \
      "" \
      false \
      "diag result"
    return
  fi

  local mode
  mode="$(read_meta_value "$meta_path" mode)"
  [[ -n "$mode" ]] || mode="unknown"
  local preview_query="diag result"
  if [[ "$mode" == "all-json" ]]; then
    preview_query="diag result all-json"
  fi

  emit_diag_result_items "$preview_query"
}

handle_diag_query() {
  local lower_query="$1"
  if [[ "$lower_query" == "diag result"* ]]; then
    emit_diag_result_items "$lower_query"
    return
  fi

  local mode="default"

  if [[ "$lower_query" == *"all-json"* || "$lower_query" == *"--all-json"* ]]; then
    mode="all-json"
  elif [[ "$lower_query" == *"async"* ]]; then
    mode="async"
  elif [[ "$lower_query" == *"one-line"* || "$lower_query" == *" oneline"* || "$lower_query" == *" one line"* ]]; then
    mode="one-line"
  elif [[ "$lower_query" == *"cached"* ]]; then
    mode="cached"
  elif [[ "$lower_query" == *" all"* || "$lower_query" == *"--all"* ]]; then
    mode="all"
  fi

  case "$mode" in
  all-json)
    emit_item \
      "Run diag rate-limits --all --json (parsed)" \
      "Parse JSON and render one row per account." \
      "diag::all-json" \
      true \
      "diag all-json"
    ;;
  cached)
    emit_item \
      "Run diag rate-limits --cached" \
      "Cached diagnostics only; no network refresh." \
      "diag::cached" \
      true \
      "diag cached"
    ;;
  one-line)
    emit_item \
      "Run diag rate-limits --one-line" \
      "Compact one-line diagnostics output." \
      "diag::one-line" \
      true \
      "diag one-line"
    ;;
  all)
    emit_item \
      "Run diag rate-limits --all" \
      "Query all secrets under CODEX_SECRET_DIR." \
      "diag::all" \
      true \
      "diag all"
    ;;
  async)
    emit_item \
      "Run diag rate-limits --all --async --jobs 4" \
      "Concurrent diagnostics across secrets." \
      "diag::async" \
      true \
      "diag async"
    ;;
  *)
    emit_item \
      "Run diag rate-limits" \
      "Default diagnostics for current secret." \
      "diag::default" \
      true \
      "diag"
    ;;
  esac

  emit_item \
    "Also available: --cached / --one-line / --all / all-json / async" \
    "Type diag cached, diag one-line, diag all, diag all-json, or diag async." \
    "" \
    false \
    "diag "

  emit_latest_diag_result_items_inline
}

query="${1:-}"
trimmed_query="$(trim "$query")"
lower_query_raw="$(to_lower "$trimmed_query")"

show_assessment=0
if is_truthy "${CODEX_SHOW_ASSESSMENT:-0}"; then
  show_assessment=1
fi

if query_has_assessment_flag "$lower_query_raw"; then
  show_assessment=1
  trimmed_query="$(strip_assessment_flags "$trimmed_query")"
fi

lower_query="$(to_lower "$trimmed_query")"

begin_items
emit_runtime_status

if [[ -z "$trimmed_query" ]]; then
  if [[ "$show_assessment" -eq 1 ]]; then
    emit_assessment_items
  fi
  emit_default_action_items
  end_items
  exit 0
fi

if [[ "$lower_query" == "help" || "$lower_query" == "?" || "$lower_query" == "eval" || "$lower_query" == "assessment" || "$lower_query" == "features" ]]; then
  if [[ "$show_assessment" -eq 1 || "$lower_query" == "eval" || "$lower_query" == "assessment" || "$lower_query" == "features" ]]; then
    emit_assessment_items
  fi
  emit_default_action_items
  end_items
  exit 0
fi

if [[ "$lower_query" == "auth" ]]; then
  emit_auth_action_items
  end_items
  exit 0
fi

if [[ "$lower_query" == login* || "$lower_query" == auth\ login* ]]; then
  handle_login_query "$lower_query"
  end_items
  exit 0
fi

if [[ "$lower_query" == save* || "$lower_query" == auth\ save* ]]; then
  handle_save_query "$trimmed_query"
  end_items
  exit 0
fi

if [[ "$lower_query" == --yes* || "$lower_query" == -y* ]]; then
  handle_save_query "save ${trimmed_query}"
  end_items
  exit 0
fi

if [[ "$lower_query" == diag* ]]; then
  handle_diag_query "$lower_query"
  end_items
  exit 0
fi

emit_item \
  "Unknown command: ${trimmed_query}" \
  "Try: login, save <secret.json>, diag, or type help (--assessment optional)." \
  "" \
  false \
  "help"
emit_default_action_items
end_items
