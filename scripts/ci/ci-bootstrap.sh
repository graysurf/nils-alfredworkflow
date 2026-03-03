#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

context=""
install_codex_cli=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/ci/ci-bootstrap.sh --context <ci|release|publish-crates> [--install-codex-cli]
USAGE
}

die() {
  echo "error: $*" >&2
  exit 2
}

require_cargo() {
  if ! command -v cargo >/dev/null 2>&1; then
    echo "error: missing required binary: cargo" >&2
    exit 1
  fi
}

install_codex_cli_runtime() {
  # shellcheck source=/dev/null
  source "$repo_root/scripts/lib/codex_cli_version.sh"
  cargo install "${CODEX_CLI_CRATE}" --version "${CODEX_CLI_VERSION}" --locked
}

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
  --context)
    [[ $# -ge 2 ]] || die "--context requires a value"
    context="${2:-}"
    shift 2
    ;;
  --install-codex-cli)
    install_codex_cli=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die "unknown argument: ${1:-}"
    ;;
  esac
done

case "$context" in
ci | release | publish-crates) ;;
*)
  die "--context must be one of: ci, release, publish-crates"
  ;;
esac

require_cargo

if [[ "$install_codex_cli" -eq 1 ]]; then
  install_codex_cli_runtime
fi

echo "ok: ci bootstrap complete (context=$context, install_codex_cli=$install_codex_cli)"
