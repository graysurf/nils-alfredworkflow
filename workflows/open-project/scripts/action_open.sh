#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: action_open.sh <path-or-url>" >&2
  exit 2
fi

open "$1"
