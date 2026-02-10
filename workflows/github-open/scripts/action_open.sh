#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: action_open.sh <repo-or-url>" >&2
  exit 2
fi

input="$1"
if [[ "$input" == http://* || "$input" == https://* ]]; then
  open "$input"
else
  open "https://github.com/$input"
fi
