#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export FORGE_INBOX_FIXED_PROVIDER_MODE="glab"
exec "$script_dir/script_filter.sh" "$@"
