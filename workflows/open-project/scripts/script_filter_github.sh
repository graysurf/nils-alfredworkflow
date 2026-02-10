#!/bin/sh
set -eu

script_dir=$(
  CDPATH=
  cd -- "$(dirname -- "$0")" && pwd
)

exec env OPEN_PROJECT_MODE=github "$script_dir/script_filter.sh" "${1-}"
