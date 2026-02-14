#!/bin/sh
# Shared Script Filter error-row JSON helpers.

sfej_json_escape() {
  value="${1-}"
  value="$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  value="$(printf '%s' "$value" | tr '\n\r' '  ')"
  printf '%s' "$value"
}

sfej_normalize_error_message() {
  value="${1-}"
  value="$(printf '%s' "$value" | tr '\n\r' '  ' | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$value" in
  error:\ *)
    value="${value#error: }"
    ;;
  esac
  case "$value" in
  Error:\ *)
    value="${value#Error: }"
    ;;
  esac
  printf '%s' "$value"
}

sfej_emit_error_item_json() {
  title="${1-Error}"
  subtitle="${2-}"
  printf '{"items":[{"title":"%s","subtitle":"%s","valid":false}]}\n' \
    "$(sfej_json_escape "$title")" \
    "$(sfej_json_escape "$subtitle")"
}

sfej_emit_single_item_json() {
  title="${1-Info}"
  subtitle="${2-}"
  valid="${3-false}"
  printf '{"items":[{"title":"%s","subtitle":"%s","valid":%s}]}\n' \
    "$(sfej_json_escape "$title")" \
    "$(sfej_json_escape "$subtitle")" \
    "$valid"
}
