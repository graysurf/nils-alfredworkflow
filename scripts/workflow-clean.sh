#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

rm -rf "$repo_root/build"
mkdir -p "$repo_root/build"

echo "ok: cleaned build/"
