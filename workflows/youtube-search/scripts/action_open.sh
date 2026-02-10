#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: action_open.sh <url>" >&2
  exit 2
fi

open "$1"
