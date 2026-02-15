#!/usr/bin/env bash
set -euo pipefail

cache_dir_raw="${BANGUMI_CACHE_DIR:-}"
cache_dir="$(printf '%s' "$cache_dir_raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

if [[ -z "$cache_dir" ]]; then
  exit 0
fi

case "$cache_dir" in
"/" | "." | "..")
  echo "refusing to clear unsafe BANGUMI_CACHE_DIR value: $cache_dir" >&2
  exit 1
  ;;
esac

if [[ -d "$cache_dir" ]]; then
  find "$cache_dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
fi
