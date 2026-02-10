#!/usr/bin/env bash

set -euo pipefail

alfred_feedback_single_item() {
  local title="$1"
  local subtitle="${2:-}"
  local arg="${3:-}"

  cat <<JSON
{"items":[{"title":"$title","subtitle":"$subtitle","arg":"$arg"}]}
JSON
}
