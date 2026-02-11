#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

usage() {
  cat <<USAGE
Usage:
  scripts/workflow-pack-install.sh [--id <workflow-id>]

Behavior:
  - Loads $repo_root/.env if present.
  - Uses --id value first.
  - Falls back to WORKFLOW_PACK_ID from environment/.env.
USAGE
}

workflow_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --id)
    workflow_id="${2:-}"
    [[ -n "$workflow_id" ]] || {
      echo "error: --id requires a value" >&2
      exit 2
    }
    shift 2
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

if [[ -f "$repo_root/.env" ]]; then
  # shellcheck disable=SC1091
  source "$repo_root/.env"
fi

if [[ -z "$workflow_id" ]]; then
  workflow_id="${WORKFLOW_PACK_ID:-}"
fi

if [[ -z "$workflow_id" ]]; then
  echo "error: missing workflow id (set WORKFLOW_PACK_ID in .env or pass --id)" >&2
  exit 2
fi

"$repo_root/scripts/workflow-pack.sh" --id "$workflow_id" --install
