#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

workflow_id=""

usage() {
  cat <<USAGE
Usage:
  scripts/workflow-new.sh --id <workflow-id>
USAGE
}

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

if [[ -z "$workflow_id" ]]; then
  usage >&2
  exit 2
fi

template_dir="$repo_root/workflows/_template"
target_dir="$repo_root/workflows/$workflow_id"

if [[ -e "$target_dir" ]]; then
  echo "error: workflow already exists: $workflow_id" >&2
  exit 1
fi

cp -R "$template_dir" "$target_dir"

name="$(echo "$workflow_id" | tr '-' ' ' | awk '{for (i=1; i<=NF; ++i) {$i=toupper(substr($i,1,1)) substr($i,2)}; print}')"

sed -i.bak \
  -e "s|__WORKFLOW_ID__|$workflow_id|g" \
  -e "s|__WORKFLOW_NAME__|$name|g" \
  "$target_dir/workflow.toml"
rm -f "$target_dir/workflow.toml.bak"

echo "ok: created workflow skeleton at workflows/$workflow_id"
