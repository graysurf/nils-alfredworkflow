#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "${script_dir}/.." && pwd)"
repo_root="$(cd "${skill_root}/../../.." && pwd)"
entrypoint="${skill_root}/scripts/pin-crates.sh"

if [[ ! -f "${skill_root}/SKILL.md" ]]; then
  echo "error: missing SKILL.md" >&2
  exit 1
fi
if [[ ! -f "${entrypoint}" ]]; then
  echo "error: missing scripts/pin-crates.sh" >&2
  exit 1
fi

if [[ ! -d "${repo_root}/workflows/codex-cli" ]]; then
  echo "error: missing expected workflow path in repo" >&2
  exit 1
fi

targets_out="$("${entrypoint}" --list-targets)"
echo "$targets_out" | rg -n "^codex-cli$" >/dev/null
echo "$targets_out" | rg -n "nils-codex-cli" >/dev/null
echo "$targets_out" | rg -n "^memo-cli$" >/dev/null
echo "$targets_out" | rg -n "nils-memo-cli" >/dev/null

"${entrypoint}" --version 0.3.7 --dry-run >/dev/null
"${entrypoint}" --version 0.3.7 --targets nils-codex-cli,nils-memo-cli --dry-run >/dev/null

if "${entrypoint}" --version 0.3.7 --targets unknown-target --dry-run >/dev/null 2>&1; then
  echo "error: unknown target must fail" >&2
  exit 1
fi

echo "ok: project skill smoke checks passed"
