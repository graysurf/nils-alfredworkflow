#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BANGUMI_DEFAULT_TYPE="book"

exec "$script_dir/script_filter.sh" "$@"
