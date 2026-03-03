#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: workflow_action_copy.sh <value>" >&2
  exit 2
fi

if ! command -v pbcopy >/dev/null 2>&1; then
  echo "error: pbcopy command is required" >&2
  exit 2
fi

printf '%s' "$1" | pbcopy
