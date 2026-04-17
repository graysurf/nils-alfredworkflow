#!/usr/bin/env bash
#
# nils-alfredworkflow's /release — thin wrapper over the canonical skill
# script. Kept here so the global dispatcher (~/.claude/scripts/release.sh)
# finds this repo's release flow under the dispatcher convention
# (<repo>/.agents/scripts/release.sh). The real logic still lives in
# .agents/skills/nils-alfredworkflow-release-workflow/ so codex / opencode
# discover it through their skill-indexing mechanism — per the multi-CLI
# mirror rule in claude-kit's docs/dispatcher-commands.md.
#
# All args forward unchanged to the skill script; behaviour is identical
# whether you reach it via /release or via the skill directly.
#
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  echo "release: not inside a git work tree" >&2
  exit 2
fi

canonical="$repo_root/.agents/skills/nils-alfredworkflow-release-workflow/scripts/nils-alfredworkflow-release-workflow.sh"
if [[ ! -x "$canonical" ]]; then
  echo "release: missing $canonical" >&2
  exit 2
fi

exec bash "$canonical" "$@"
