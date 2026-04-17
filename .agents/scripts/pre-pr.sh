#!/usr/bin/env bash
#
# nils-alfredworkflow's /pre-pr gate stack. The global dispatcher
# (~/.claude/scripts/pre-pr.sh) execs this when cwd is nils-alfredworkflow.
#
# Mirrors the canonical pre-commit entrypoint from DEVELOPMENT.md:
#   scripts/local-pre-commit.sh
#
# The entrypoint runs workflow-lint, script-filter-policy --check,
# npm run test:cambridge-scraper, and workflow-test. Extra args forward
# straight through (e.g. `--mode ci` for CI-parity order, `--with-package-smoke`
# for release-style package validation).
#
# Note: nils-alfredworkflow does not currently expose a sibling skill for
# the pre-commit stack; codex / opencode users run the entrypoint directly.
# See claude-kit's docs/dispatcher-commands.md for the multi-CLI mirror rule.
#
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  echo "pre-pr: not inside a git work tree" >&2
  exit 2
fi

entrypoint="$repo_root/scripts/local-pre-commit.sh"
if [[ ! -x "$entrypoint" ]]; then
  echo "pre-pr: missing $entrypoint" >&2
  exit 2
fi

exec bash "$entrypoint" "$@"
