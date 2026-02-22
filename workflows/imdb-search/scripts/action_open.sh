#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

loader_path=""
for candidate in \
  "$script_dir/lib/workflow_helper_loader.sh" \
  "$script_dir/../../../scripts/lib/workflow_helper_loader.sh"; do
  if [[ -f "$candidate" ]]; then
    loader_path="$candidate"
    break
  fi
done

if [[ -z "$loader_path" ]]; then
  echo "Workflow helper missing: Cannot locate workflow_helper_loader.sh runtime helper." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$loader_path"

helper="$(wfhl_resolve_helper_path "$script_dir" "workflow_action_open_url.sh" off || true)"
if [[ -z "$helper" ]]; then
  wfhl_print_missing_helper_stderr "workflow_action_open_url.sh"
  exit 1
fi

exec "$helper" "$@"
