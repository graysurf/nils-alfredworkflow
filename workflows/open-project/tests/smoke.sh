#!/usr/bin/env bash
set -euo pipefail

workflow_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for required in workflow.toml src/info.plist.template scripts/script_filter.sh scripts/action_open.sh; do
  if [[ ! -f "$workflow_dir/$required" ]]; then
    echo "missing required file: $workflow_dir/$required" >&2
    exit 1
  fi
done

echo "ok: open-project skeleton smoke test"
