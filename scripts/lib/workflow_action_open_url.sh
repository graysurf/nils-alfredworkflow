#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: workflow_action_open_url.sh <url>" >&2
  exit 2
fi

if ! command -v open >/dev/null 2>&1; then
  echo "error: open command is required" >&2
  exit 2
fi

open "$1"
