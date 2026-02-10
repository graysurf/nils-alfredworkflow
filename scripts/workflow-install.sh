#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "usage: scripts/workflow-install.sh <workflow-id>" >&2
  exit 2
fi

workflow_id="$1"
workflow_dist="$repo_root/dist/$workflow_id"

if [[ ! -d "$workflow_dist" ]]; then
  echo "error: no dist found for workflow: $workflow_id" >&2
  exit 1
fi

artifact="$(find "$workflow_dist" -type f -name '*.alfredworkflow' | sort | tail -n1)"

if [[ -z "$artifact" ]]; then
  echo "error: no .alfredworkflow artifact found for: $workflow_id" >&2
  exit 1
fi

open "$artifact"
echo "ok: installed $artifact"
