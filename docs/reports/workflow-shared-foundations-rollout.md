# Workflow Shared Foundations Rollout

Date: 2026-02-22
Scope: Shared workflow runtime/test foundations (helper loader, script-filter guard driver, smoke helper, policy/audit enforcement).

## Rollout Strategy

### Stage 1: Canary

Canary workflows:

- `google-search`
- `weather`
- `codex-cli`

Canary checklist:

1. `scripts/workflow-lint.sh`
2. `scripts/workflow-test.sh`
3. `CODEX_CLI_PACK_SKIP_ARCH_CHECK=1 scripts/workflow-pack.sh --all`
4. `scripts/workflow-install.sh google-search`
5. `scripts/workflow-install.sh weather`
6. `scripts/workflow-install.sh codex-cli`

### Stage 2: Search-Family Promotion

Targets:

- `youtube-search`, `netflix-search`, `wiki-search`, `bangumi-search`, `cambridge-dict`, `spotify-search`, `bilibili-search`, `imdb-search`

Promotion criteria:

- All Stage 1 canary checks stable for one full package/test cycle.
- No shared-foundation audit drift (`bash scripts/workflow-shared-foundation-audit.sh --check`).
- No policy-check drift (`bash scripts/workflow-sync-script-filter-policy.sh --check`).

### Stage 3: Utility Workflow Promotion

Targets:

- `epoch-converter`, `multi-timezone`, `market-expression`, `quote-feed`, plus remaining workflows packaged by `--all`.

Promotion criteria:

- Stage 2 passed with no regressions.
- Full `workflow-test.sh` smoke suite remains green after package refresh.

## Stop Conditions

Stop rollout immediately if any stop condition is observed:

1. Script Filter output regression (missing/invalid `.items` array, or helper-missing runtime rows in healthy environments).
2. Shared foundation policy check failure for migrated workflows.
3. Shared foundation audit failure (reintroduced duplicate loader blocks or missing required guard wiring).
4. Packaging/install failure for canary workflows.

## Emergency Recovery

### Revert Workflow Family Paths

Use an explicit known-good ref (`<known_good_ref>`) and only revert impacted paths:

```bash
git checkout <known_good_ref> -- scripts/lib/workflow_helper_loader.sh
git checkout <known_good_ref> -- scripts/lib/script_filter_cli_driver.sh
git checkout <known_good_ref> -- scripts/lib/workflow_smoke_helpers.sh
git checkout <known_good_ref> -- workflows/<workflow-id>/scripts
git checkout <known_good_ref> -- workflows/<workflow-id>/tests
```

### Re-validate After Revert

```bash
scripts/workflow-lint.sh
scripts/workflow-test.sh
CODEX_CLI_PACK_SKIP_ARCH_CHECK=1 scripts/workflow-pack.sh --all
```

### Reinstall Last Known-Good Artifacts

```bash
scripts/workflow-install.sh <workflow-id>
```

This command installs the latest `.alfredworkflow` from `dist/<workflow-id>/` and should point to the last known-good artifact after revert/package.

## Owner Checklist

1. Confirm canary pass/fail decision and record timestamp.
2. Confirm promotion criteria before each stage transition.
3. If a stop condition triggers, execute revert + re-validate commands before re-attempting rollout.
4. Record final known-good ref and packaged artifact version in release notes.
