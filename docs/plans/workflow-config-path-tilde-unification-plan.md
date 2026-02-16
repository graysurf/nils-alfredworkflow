# Plan: Workflow Config Path `~` Support Unification

## Overview
This plan standardizes path-like workflow configuration handling so users can safely set values with `~` without runtime failures.
The implementation is intentionally cross-layer: shared shell runtime helpers for Alfred adapters, plus Rust-side normalization for crates that consume path env vars directly.
The goal is deterministic, uniform behavior across all workflows, with a regression-proof lint/testing gate and explicit development standards.
No workflow-specific business logic changes are included; this is runtime config consistency hardening.

## Scope
- In scope:
  - Full inventory of path-like workflow config/env variables and their consumers.
  - Unified `~`/home-token expansion behavior for path variables in workflow shell adapters.
  - Shared helper-based adoption for all workflows using `scripts/lib/workflow_cli_resolver.sh`.
  - Path normalization for non-binary path vars (`*_DIR`, `*_FILE`, `*_PATH`, `*_DB_PATH`, auth/secret paths).
  - Rust-side normalization for crates that directly parse path env vars.
  - Development standards + lint guardrails to prevent config-path behavior drift.
- Out of scope:
  - Product feature changes (search ranking, API behavior, UI copy semantics).
  - Non-path config semantics (numeric bounds, API-key validation rules).
  - Platform expansion beyond current repo targets (macOS + Linux CI).

## Assumptions (if any)
1. Workflow users may set path variables in Alfred UI using `~` and expect shell-like expansion.
2. Existing smoke tests are representative enough to detect path-resolution regressions once expanded with `~` cases.
3. `scripts/lib/workflow_cli_resolver.sh` remains the canonical shared shell runtime entrypoint for workflow adapters.
4. Adding shared normalization in both shell and Rust layers is acceptable to avoid behavior split between adapters and direct CLI invocations.

## Success Criteria
- Every path-like workflow config variable accepts `~` without user-facing errors.
- Shared shell resolver handles path token expansion consistently for all `*_CLI_BIN` overrides.
- Non-binary path vars (`BANGUMI_CACHE_DIR`, `QUOTE_DATA_DIR`, `MEMO_DB_PATH`, `VSCODE_PATH`, `CODEX_AUTH_FILE`, `CODEX_SECRET_DIR`, etc.) are normalized consistently.
- Development standards explicitly define the path-expansion contract.
- CI/lint includes a guardrail that fails when path-config behavior drifts from policy.

## Current Inventory Snapshot (Research Baseline)
- Path-like env vars defined in workflow manifests:
  - `BANGUMI_CACHE_DIR`, `CODEX_AUTH_FILE`, `CODEX_CLI_BIN`, `CODEX_SECRET_DIR`, `EPOCH_CLI_BIN`, `MARKET_CLI_BIN`, `MEMO_DB_PATH`, `MEMO_WORKFLOW_CLI_BIN`, `PROJECT_DIRS`, `QUOTE_DATA_DIR`, `TIMEZONE_CLI_BIN`, `USAGE_FILE`, `VSCODE_PATH`, `WEATHER_CLI_BIN`.
- Additional path-like override vars used by adapters (not always declared in manifest):
  - `BANGUMI_CLI_BIN`, `BILIBILI_CLI_BIN`, `BRAVE_CLI_BIN`, `CAMBRIDGE_CLI_BIN`, `QUOTE_CLI_BIN`, `RANDOMER_CLI_BIN`, `SPOTIFY_CLI_BIN`, `WIKI_CLI_BIN`, `WORKFLOW_CLI_BIN`, `YOUTUBE_CLI_BIN`.
- Shared runtime pattern:
  - 20+ scripts resolve binaries through `wfcr_resolve_binary` from `scripts/lib/workflow_cli_resolver.sh`.
- Known inconsistency hotspots:
  - Shared resolver currently checks `-x` directly on env candidate (no `~` expansion).
  - `workflows/open-project/scripts/action_open.sh` uses `VSCODE_PATH` directly without token expansion.
  - `workflows/bangumi-search/scripts/action_clear_cache_dir.sh` uses `BANGUMI_CACHE_DIR` directly without token expansion.
  - Rust path consumers in `crates/bangumi-cli`, `crates/quote-cli`, `crates/memo-workflow-cli` currently accept raw env path strings.
  - `codex-cli` now has local `~` expansion logic; this should be aligned with shared policy to avoid one-off behavior.

## Dependency & Parallelization Map
- Critical path A (shell): `Task 1.1 -> Task 1.2 -> Task 1.3 -> Task 2.1 -> Task 2.3 -> Task 2.4 -> Task 4.1 -> Task 4.3`.
- Critical path B (Rust): `Task 1.1 -> Task 1.2 -> Task 1.3 -> Task 3.1 -> Task 3.2 -> Task 3.3 -> Task 4.1 -> Task 4.3`.
- Parallel track A: `Task 2.2` can run in parallel with `Task 2.3` after `Task 2.1`.
- Parallel track B: `Task 4.2` can run in parallel with `Task 2.4` and `Task 3.3` after `Task 1.2`.

## Sprint 1: Inventory and Contract Definition
**Goal**: Produce a complete path-config inventory and freeze one cross-workflow expansion contract before code changes.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/workflow-config-path-tilde-unification-plan.md`, `rg -n "(_DIR|_FILE|_PATH|_BIN|_DB_PATH|PROJECT_DIRS|USAGE_FILE|VSCODE_PATH)" workflows/*/workflow.toml workflows/*/scripts/*.sh`
- Verify: Inventory is complete and policy is explicit enough for mechanical enforcement.

### Task 1.1: Build canonical workflow path-config matrix
- **Location**:
  - `docs/reports/workflow-path-config-inventory.md`
- **Description**: Enumerate all workflow path-like config/env vars, consumer entrypoints (shell adapter or Rust crate), current expansion behavior, and target behavior.
- **Dependencies**:
  - none
- **Complexity**: 4
- **Acceptance criteria**:
  - Matrix covers every workflow under `workflows/*`.
  - Each path-like variable is mapped to specific consumer files and a support status (`already supported`, `missing`, `partial`).
  - Each path-like variable row includes explicit `Implementation Task ID` and `Test Task ID` with no unmapped rows.
- **Validation**:
  - `test -f docs/reports/workflow-path-config-inventory.md`
  - `rg -n "BANGUMI_CACHE_DIR|CODEX_AUTH_FILE|MEMO_DB_PATH|PROJECT_DIRS|VSCODE_PATH|WEATHER_CLI_BIN" docs/reports/workflow-path-config-inventory.md`
  - `rg -n "Implementation Task ID|Test Task ID" docs/reports/workflow-path-config-inventory.md`
  - `bash -c 'if rg -n "UNMAPPED" docs/reports/workflow-path-config-inventory.md; then exit 1; fi'`
  - `bash -c 'vars=\"$( { rg -n \"^[A-Z0-9_]+[[:space:]]*=[[:space:]]*\\\"\" workflows/*/workflow.toml | awk -F: \"{split(\\$3,a,\\\"=\\\"); gsub(/[[:space:]]/,\\\"\\\",a[1]); print a[1]}\"; rg -o \"\\$\\{[A-Z0-9_]+(:-[^}]*)?\\}\" workflows/*/scripts/*.sh | sed -E \"s/^\\$\\{([A-Z0-9_]+).*/\\1/\"; rg -o \"\\\"[A-Z0-9_]+\\\"\" workflows/*/scripts/*.sh | tr -d \"\\\"\"; } | rg \"(_DIR|_FILE|_PATH|_BIN|_DB_PATH|_DIRS)$|PROJECT_DIRS|USAGE_FILE|VSCODE_PATH\" | sort -u )\"; for v in $vars; do rg -q \"\\b$v\\b\" docs/reports/workflow-path-config-inventory.md || { echo \"missing inventory row: $v\"; exit 1; }; done'`

### Task 1.2: Define normative path token expansion policy
- **Location**:
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
  - `docs/specs/workflow-path-token-expansion-policy.md`
- **Description**: Define one repository-wide rule for path config token expansion, including at minimum `~`, `~/...`, `$HOME`, `${HOME}`, empty handling, and when expansion must occur (adapter boundary and/or crate config parse).
- **Dependencies**:
  - Task 1.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Policy explicitly states which variable classes must be treated as paths.
  - Policy documents required helper usage and test expectations for every new path variable.
- **Validation**:
  - `rg -n "^## Supported Tokens$|^## Variable Classes$|^## Required Integration Points$|^## Validation Requirements$" docs/specs/workflow-path-token-expansion-policy.md`
  - `rg -n "^### Path Config Token Expansion Standard$|workflow-path-token-expansion-policy.md" ALFRED_WORKFLOW_DEVELOPMENT.md`

### Task 1.3: Define shared helper API contract (shell + Rust)
- **Location**:
  - `scripts/lib/workflow_cli_resolver.sh`
  - `crates/workflow-common/src/config.rs`
  - `docs/specs/workflow-path-token-expansion-policy.md`
- **Description**: Freeze helper API surface (function names, input/output behavior, edge-case semantics) before implementing, so each workflow does not invent divergent expansion behavior.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 4
- **Acceptance criteria**:
  - Shell helper contract and Rust helper contract are documented and non-conflicting.
  - Explicit examples include `~/.config`, `~/bin/tool`, `$HOME/.cache`, `${HOME}/.local/share`.
- **Validation**:
  - `rg -n "helper contract|wfcr_|expand_home_tokens|example" docs/specs/workflow-path-token-expansion-policy.md`

## Sprint 2: Shared Shell Runtime Unification
**Goal**: Guarantee uniform `~` path behavior at workflow adapter boundaries using shared shell helpers.
**Demo/Validation**:
- Command(s): `shellcheck scripts/lib/workflow_cli_resolver.sh`, `scripts/workflow-test.sh --id codex-cli`, `scripts/workflow-test.sh --id open-project`
- Verify: Path expansion behavior is consistent across adapters and direct action scripts.

### Task 2.1: Extend shared resolver with path expansion primitives
- **Location**:
  - `scripts/lib/workflow_cli_resolver.sh`
  - `scripts/lib/tests/workflow_cli_resolver_tilde_smoke.sh`
- **Description**: Add shared expansion functions (for example `wfcr_expand_home_tokens`, `wfcr_expand_env_path_var`) and integrate them into `wfcr_resolve_binary` before executable checks.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 6
- **Acceptance criteria**:
  - All `*_CLI_BIN` overrides support `~` seamlessly through shared resolver.
  - Expansion behavior is deterministic and shell-safe.
- **Validation**:
  - `shellcheck scripts/lib/workflow_cli_resolver.sh`
  - `bash -n scripts/lib/workflow_cli_resolver.sh`
  - `bash scripts/lib/tests/workflow_cli_resolver_tilde_smoke.sh`

### Task 2.2: Roll shared resolver behavior through all CLI-bin workflows
- **Location**:
  - `scripts/lib/workflow_cli_resolver.sh`
  - `workflows`
- **Description**: Validate and adjust callers as needed so they rely on shared expanded behavior without local ad-hoc path parsing.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 5
- **Acceptance criteria**:
  - No workflow script duplicates binary path token expansion logic locally.
  - Representative workflows (`google-search`, `weather`, `memo-add`, `open-project`, `youtube-search`) pass smoke with `~` binary override cases.
- **Validation**:
  - `rg -n "wfcr_resolve_binary" workflows/*/scripts/*.sh`
  - `bash -c 'if rg -n "(-x .*_CLI_BIN|_CLI_BIN.*-x|command -v .*_CLI_BIN|_CLI_BIN.*command -v)" workflows/*/scripts/*.sh; then exit 1; fi'`
  - `cargo test --workspace`
  - `for id in google-search weather memo-add open-project youtube-search; do bash "workflows/$id/tests/smoke.sh"; done`

### Task 2.3: Normalize non-binary path vars in shell adapters/actions
- **Location**:
  - `workflows/open-project/scripts/action_open.sh`
  - `workflows/bangumi-search/scripts/action_clear_cache_dir.sh`
  - `workflows/codex-cli/scripts/action_open.sh`
  - `workflows/codex-cli/scripts/script_filter.sh`
  - `workflows/codex-cli/scripts/script_filter_auth_current.sh`
  - `workflows/memo-add/scripts/script_filter.sh`
  - `workflows/memo-add/scripts/action_run.sh`
  - `workflows/quote-feed/scripts/script_filter.sh`
  - `workflows/bangumi-search/scripts/script_filter.sh`
  - `docs/reports/workflow-path-shell-normalization-coverage.md`
- **Description**: Apply shared path normalization to non-binary path variables before use/export, especially `VSCODE_PATH`, `BANGUMI_CACHE_DIR`, `MEMO_DB_PATH`, `QUOTE_DATA_DIR`, `CODEX_AUTH_FILE`, `CODEX_SECRET_DIR`.
- **Dependencies**:
  - Task 1.1
  - Task 2.1
- **Complexity**: 8
- **Acceptance criteria**:
  - Every non-binary path variable row from `docs/reports/workflow-path-config-inventory.md` is mapped to either shell normalization code in this task or an explicit Rust-owner note.
  - Existing safety checks (for example unsafe delete path guards) still hold after expansion.
  - Coverage report `docs/reports/workflow-path-shell-normalization-coverage.md` includes all `shell-non-binary` rows from inventory with no `MISSING` status.
- **Validation**:
  - `rg -n "wfcr_expand_env_path_var|wfcr_expand_home_tokens" workflows/open-project/scripts/action_open.sh workflows/bangumi-search/scripts/action_clear_cache_dir.sh workflows/codex-cli/scripts/action_open.sh workflows/codex-cli/scripts/script_filter.sh workflows/codex-cli/scripts/script_filter_auth_current.sh workflows/memo-add/scripts/script_filter.sh workflows/memo-add/scripts/action_run.sh workflows/quote-feed/scripts/script_filter.sh workflows/bangumi-search/scripts/script_filter.sh`
  - `bash -c 'if rg -n "UNMAPPED" docs/reports/workflow-path-config-inventory.md; then exit 1; fi'`
  - `test -f docs/reports/workflow-path-shell-normalization-coverage.md`
  - `bash -c 'if rg -n "shell-non-binary.*MISSING" docs/reports/workflow-path-shell-normalization-coverage.md; then exit 1; fi'`
  - `cargo test --workspace`
  - `for id in bangumi-search open-project memo-add quote-feed codex-cli; do bash "workflows/$id/tests/smoke.sh"; done`

### Task 2.4: Add shell-level regression tests for tilde behavior
- **Location**:
  - `workflows/open-project/tests/smoke.sh`
  - `workflows/bangumi-search/tests/smoke.sh`
  - `workflows/memo-add/tests/smoke.sh`
  - `workflows/quote-feed/tests/smoke.sh`
  - `workflows/codex-cli/tests/smoke.sh`
- **Description**: Add explicit smoke assertions proving `~` config values are expanded correctly and do not regress.
- **Dependencies**:
  - Task 2.3
- **Complexity**: 7
- **Acceptance criteria**:
  - Each touched workflow has at least one `~`-input assertion for its path variables.
  - Test failures clearly indicate expansion regressions.
- **Validation**:
  - `cargo test --workspace`
  - `for id in open-project bangumi-search memo-add quote-feed codex-cli; do bash "workflows/$id/tests/smoke.sh"; done`

## Sprint 3: Rust Config Parser Normalization
**Goal**: Ensure crate-level path env parsing is also consistent, independent of shell adapters.
**Demo/Validation**:
- Command(s): `cargo test -p nils-bangumi-cli`, `cargo test -p nils-quote-cli`, `cargo test -p nils-memo-workflow-cli`
- Verify: Rust parsers normalize `~`/home tokens for path env vars and preserve current defaults.

### Task 3.1: Add reusable Rust path-token expansion helper
- **Location**:
  - `crates/workflow-common/src/path_tokens.rs` (or equivalent shared module)
  - `crates/workflow-common/src/lib.rs`
  - `crates/workflow-common/src/config.rs`
- **Description**: Extract reusable Rust helper for path token expansion and align existing open-project helper logic with the shared implementation.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 6
- **Acceptance criteria**:
  - One canonical Rust helper handles `~`, `~/...`, `$HOME`, `${HOME}`.
  - Existing open-project behavior remains backward compatible.
- **Validation**:
  - `cargo test -p nils-workflow-common`
  - `cargo test -p nils-workflow-common -- --nocapture`

### Task 3.2: Apply helper to crate path env consumers
- **Location**:
  - `crates/bangumi-cli/src/config.rs`
  - `crates/quote-cli/src/config.rs`
  - `crates/memo-workflow-cli/src/lib.rs`
- **Description**: Normalize explicit path envs using shared helper (`BANGUMI_CACHE_DIR`, `QUOTE_DATA_DIR`, `MEMO_DB_PATH`) before `PathBuf` conversion.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 8
- **Acceptance criteria**:
  - Crate runtime config resolves `~` path variables correctly under test.
  - Existing fallback resolution order remains unchanged.
- **Validation**:
  - `cargo test -p nils-bangumi-cli`
  - `cargo test -p nils-quote-cli`
  - `cargo test -p nils-memo-workflow-cli`

### Task 3.3: Add crate-level tilde regression tests
- **Location**:
  - `crates/bangumi-cli/src/config.rs` tests
  - `crates/quote-cli/src/config.rs` tests
  - `crates/memo-workflow-cli/tests/cli_contract.rs`
- **Description**: Add explicit tests proving `~`/home tokens are expanded for path env vars and do not produce literal `~` paths.
- **Dependencies**:
  - Task 3.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Tests fail if any path parser returns unexpanded `~` prefix.
  - Test cases are OS-agnostic by asserting normalized string outputs from synthetic `HOME` values (no platform-specific path separators/hardcoded absolute paths).
- **Validation**:
  - `cargo test -p nils-bangumi-cli -- --nocapture`
  - `cargo test -p nils-quote-cli -- --nocapture`
  - `cargo test -p nils-memo-workflow-cli -- --nocapture`
  - `rg -n "HOME|~|\\$HOME|\\${HOME}" crates/bangumi-cli/src/config.rs crates/quote-cli/src/config.rs crates/memo-workflow-cli/tests/cli_contract.rs`

## Sprint 4: Governance, Lint Guardrail, and Rollout
**Goal**: Prevent reintroduction of inconsistent path behavior and make policy discoverable for all contributors.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `scripts/workflow-test.sh`, `scripts/workflow-pack.sh --all`
- Verify: New policy is enforced and all workflows remain packageable/testable.

### Task 4.1: Add automated path-config audit check
- **Location**:
  - `scripts/workflow-config-path-audit.sh`
  - `scripts/workflow-lint.sh`
- **Description**: Add a lightweight audit that detects path-like workflow vars and enforces required support markers (shared helper usage, documented policy linkage, and test coverage markers).
- **Dependencies**:
  - Task 2.4
  - Task 3.3
- **Complexity**: 7
- **Acceptance criteria**:
  - `scripts/workflow-lint.sh` fails when a new path var lacks policy-compliant handling.
  - Audit output identifies offending variable and expected remediation.
- **Validation**:
  - `bash scripts/workflow-config-path-audit.sh`
  - `scripts/workflow-lint.sh`

### Task 4.2: Write and link development standards
- **Location**:
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
  - `DEVELOPMENT.md`
  - `docs/WORKFLOW_GUIDE.md`
- **Description**: Add explicit “path config must support `~`” standard, required helper usage, and mandatory validation commands for contributors.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Global standards clearly state path-token requirements and where to implement them.
  - Contributor workflow includes a concrete validation command before commit.
- **Validation**:
  - `rg -n "^### Path Config Token Expansion Standard$|workflow-path-token-expansion-policy.md|workflow-config-path-audit.sh" ALFRED_WORKFLOW_DEVELOPMENT.md`
  - `rg -n "workflow-config-path-audit.sh|path config.*~" DEVELOPMENT.md docs/WORKFLOW_GUIDE.md`

### Task 4.3: End-to-end validation and staged rollout
- **Location**:
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh`
  - `workflows`
  - `docs/reports/path-rollout-manual-checklist.md`
- **Description**: Run full validation matrix and stage rollout workflow-by-workflow, starting from high-risk adapters (`codex-cli`, `open-project`, `memo-add`, `bangumi-search`, `quote-feed`) then all remaining workflows.
- **Dependencies**:
  - Task 4.1
  - Task 4.2
- **Complexity**: 6
- **Acceptance criteria**:
  - All affected workflow smoke tests pass.
  - Packaging succeeds for all workflows.
  - Manual checklist is completed for `codex-cli`, `open-project`, `memo-add`, `bangumi-search`, and `quote-feed` with per-workflow line format such as `- [x] codex-cli status:DONE`.
- **Validation**:
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh --all`
  - `test -f docs/reports/path-rollout-manual-checklist.md`
  - `rg -n "^- \\[x\\] codex-cli status:DONE$" docs/reports/path-rollout-manual-checklist.md`
  - `rg -n "^- \\[x\\] open-project status:DONE$" docs/reports/path-rollout-manual-checklist.md`
  - `rg -n "^- \\[x\\] memo-add status:DONE$" docs/reports/path-rollout-manual-checklist.md`
  - `rg -n "^- \\[x\\] bangumi-search status:DONE$" docs/reports/path-rollout-manual-checklist.md`
  - `rg -n "^- \\[x\\] quote-feed status:DONE$" docs/reports/path-rollout-manual-checklist.md`

## Testing Strategy
- Unit:
  - Rust helper tests for token expansion in `nils-workflow-common`.
  - Crate config tests for `BANGUMI_CACHE_DIR`, `QUOTE_DATA_DIR`, `MEMO_DB_PATH`.
- Integration:
  - Workflow smoke tests with `~` path overrides for each path-config workflow.
  - Shared resolver behavior tests via representative workflows using `wfcr_resolve_binary`.
- E2E/manual:
  - Alfred imported-workflow checks for `codex-cli`, `open-project`, `memo-add`, `bangumi-search`, `quote-feed`.
  - Verify that entering `~` in Alfred Workflow Variables no longer causes binary/path lookup errors.

## Risks & gotchas
- Over-expansion risk: literal strings intended to include `~` could be interpreted as paths.
- Behavior divergence risk if some adapters bypass shared helper in future changes.
- Mixed shell differences (bash/sh) may introduce subtle token-handling differences unless helper API remains POSIX-safe.
- Backward compatibility risk for workflows currently depending on unexpanded raw values in niche local setups.

## Rollback plan
- Rollback trigger conditions:
  - Any P0/P1 regression where workflow launch fails due to path resolution.
  - Any reproducible data-loss risk in path-targeted actions (for example cache clear/remove flow).
- Fast rollback path (incident mode):
  - Revert the latest path-normalization commits in reverse order: Sprint 4 -> Sprint 3 -> Sprint 2.
  - Rebuild and repack only affected workflows first (`scripts/workflow-pack.sh --id <workflow-id>`), then publish hotfix artifact.
- Full rollback path (stabilization mode):
  - Revert shared helper changes in `scripts/lib/workflow_cli_resolver.sh` and `scripts/workflow-config-path-audit.sh`.
  - Revert adapter-level normalization changes workflow-by-workflow if regressions are isolated.
  - Revert Rust helper adoption in affected crates while preserving non-path config behavior.
  - Re-run baseline validation:
    - `scripts/workflow-lint.sh`
    - `scripts/workflow-test.sh`
    - `scripts/workflow-pack.sh --all`
- Publish a known-good artifact set and document temporary guidance: use absolute paths in workflow variables until fix is reintroduced.
