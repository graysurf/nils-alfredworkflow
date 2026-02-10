#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

install_browser=0
check_only=0

usage() {
  cat <<USAGE
Usage:
  scripts/setup-node-playwright.sh [--install-browser] [--check-only]

Options:
  --install-browser   Run 'npx playwright install chromium' after npm deps are ready.
  --check-only        Skip npm install/ci and only verify local runtime availability.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --install-browser)
    install_browser=1
    shift
    ;;
  --check-only)
    check_only=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "error: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

command -v node >/dev/null 2>&1 || {
  echo "error: node is required" >&2
  exit 1
}

command -v npm >/dev/null 2>&1 || {
  echo "error: npm is required" >&2
  exit 1
}

cd "$repo_root"

if [[ "$check_only" -eq 0 ]]; then
  if [[ -f package-lock.json ]]; then
    npm ci
  else
    npm install
  fi
fi

node --input-type=module -e "import('playwright').then(() => process.stdout.write('ok: playwright package resolved\\n'))"
npx playwright --version

if [[ "$install_browser" -eq 1 ]]; then
  npx playwright install chromium
  echo "ok: playwright chromium installed"
else
  echo "info: browser install skipped (use --install-browser to install Chromium)"
fi
