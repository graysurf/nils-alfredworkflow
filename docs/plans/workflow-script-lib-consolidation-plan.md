# Plan: Alfred Workflow Script Lib Consolidation (P1/P2)

## Overview
This plan consolidates only high-frequency, high-risk shell logic into `scripts/lib` to reduce drift across workflows while preserving workflow-specific behavior.  
The target is to standardize shared runtime mechanics (CLI path resolution, quarantine handling, Script Filter error JSON emission, async search flow driver, and Memo query input normalization) without extracting product/domain rules.  
P1 focuses on correctness-critical extraction with direct duplication evidence across multiple workflow scripts; P2 covers low-risk convenience extraction for tiny duplicated action wrappers.  
Implementation will prioritize backwards-compatible adapters and staged rollout to keep existing smoke tests and packaging behavior stable.

## Scope
- In scope:
  - Extract shared helpers for CLI resolver/quarantine logic currently duplicated in workflow scripts.
  - Extract shared helpers for Script Filter error-row JSON formatting and normalized stderr text.
  - Extract a shared async-search Script Filter driver for `google-search`, `wiki-search`, `youtube-search`, and `cambridge-dict`.
  - Extend `script_filter_query_policy.sh` to cover Memo `(null)` + argv/env/stdin normalization and trim helpers.
  - Optionally (P2) extract shared `action_copy`/`action_open` wrappers where semantics are identical.
- Out of scope:
  - Changing per-workflow `print_error_item` domain classification rules.
  - Refactoring weather icon/normalization domain logic.
  - Refactoring `codex-cli` diag/auth domain logic.
  - Introducing cross-workflow abstractions that hide business semantics or reduce debuggability.

## Assumptions (if any)
1. Existing smoke tests for affected workflows are reliable enough to detect behavior regressions from helper extraction.
2. `scripts/workflow-pack.sh` remains the canonical packaging path and continues staging shared helper files.
3. Shared helpers are allowed to be sourced from either packaged `scripts/lib` or repo-level fallback during local development/tests.

## Success Criteria
- Duplicate implementations of the same runtime mechanics are reduced to shared helpers in `scripts/lib`.
- Affected workflows keep user-visible behavior and Script Filter contract compatibility.
- Packaging includes any newly introduced shared helper files for installed workflows.
- `shellcheck`, workflow smoke tests, and packaging checks all pass for touched workflows.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 2.1 -> Task 2.2 -> Task 3.1 -> Task 3.2 -> Task 4.1`.
- Parallel track A: `Task 2.3` can run in parallel with `Task 2.2` after `Task 2.1`.
- Parallel track B: optional P2 tasks `Task 5.1` and `Task 5.2` can run in parallel after `Task 4.1`.
- Atomic execution rule: `Task 2.1` and `Task 2.2` must run in workflow slices (`search`, `utility`, `memo/open-project`), and each slice must pass validation before continuing.

## Sprint 1: Baseline and Guardrails
**Goal**: Lock the extraction boundary and ensure helper-loading/package constraints are explicit before touching runtime code.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/workflow-script-lib-consolidation-plan.md`, `rg -n "scripts/lib|script_filter_query_policy|script_filter_async_coalesce" ALFRED_WORKFLOW_DEVELOPMENT.md scripts/workflow-pack.sh`
- Verify: Plan and development contract both enforce shared-helper-first policy with packaging awareness.

### Task 1.1: Freeze extraction boundary (what to share vs not to share)
- **Location**:
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
  - `docs/plans/workflow-script-lib-consolidation-plan.md`
- **Description**: Record explicit extraction policy for this migration: only runtime mechanics move to shared helpers; workflow-specific domain behavior stays local.
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - Shared-vs-local boundary is documented and references concrete categories.
  - The policy explicitly rejects over-generalization of domain-specific error mapping and rendering logic.
- **Validation**:
  - `rg -n "shared|domain|do not extract|scripts/lib" ALFRED_WORKFLOW_DEVELOPMENT.md docs/plans/workflow-script-lib-consolidation-plan.md`

### Task 1.2: Prepare shared helper loading and packaging contract for new libs
- **Location**:
  - `scripts/workflow-pack.sh`
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
- **Description**: Define and implement deterministic staging rules for any new `scripts/lib/*.sh` helper files so packaged workflows can source them reliably.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Packaging uses a deterministic pattern-based rule to stage `scripts/lib/*.sh` into packaged workflow `scripts/lib` (not per-file ad hoc copy).
  - Docs state packaged path precedence and repo fallback path for dev/test.
- **Validation**:
  - `bash -n scripts/workflow-pack.sh`
  - `rg -n "scripts/lib" scripts/workflow-pack.sh`
  - `bash scripts/workflow-pack.sh --id google-search`
  - `test -d build/workflows/google-search/pkg/scripts/lib`

## Sprint 2: P1 Core Helper Extraction (Runtime Mechanics)
**Goal**: Extract highest-risk duplicated mechanics into reusable helpers without changing workflow business semantics.
**Demo/Validation**:
- Command(s): `shellcheck scripts/lib/*.sh`, `bash workflows/google-search/tests/smoke.sh`, `bash workflows/wiki-search/tests/smoke.sh`, `bash workflows/youtube-search/tests/smoke.sh`
- Verify: Shared helpers are used by target workflows and behavior remains stable.

### Task 2.1: Add shared CLI resolver/quarantine helper library
- **Location**:
  - `scripts/lib/workflow_cli_resolver.sh`
  - `workflows/google-search/scripts/script_filter.sh`
  - `workflows/wiki-search/scripts/script_filter.sh`
  - `workflows/youtube-search/scripts/script_filter.sh`
  - `workflows/cambridge-dict/scripts/script_filter.sh`
  - `workflows/spotify-search/scripts/script_filter.sh`
  - `workflows/randomer/scripts/script_filter.sh`
  - `workflows/randomer/scripts/script_filter_types.sh`
  - `workflows/randomer/scripts/script_filter_expand.sh`
  - `workflows/epoch-converter/scripts/script_filter.sh`
  - `workflows/market-expression/scripts/script_filter.sh`
  - `workflows/multi-timezone/scripts/script_filter.sh`
  - `workflows/quote-feed/scripts/script_filter.sh`
  - `workflows/weather/scripts/script_filter_common.sh`
  - `workflows/memo-add/scripts/script_filter.sh`
  - `workflows/memo-add/scripts/action_run.sh`
  - `workflows/open-project/scripts/script_filter.sh`
  - `workflows/open-project/scripts/action_open_github.sh`
  - `workflows/open-project/scripts/action_record_usage.sh`
- **Description**: Introduce helper functions for Darwin quarantine cleanup and deterministic CLI resolution order (workflow env-var override, packaged binary, release binary, debug binary). Migrate target workflows to source helper while preserving workflow-specific binary names/env variable names.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 8
- **Acceptance criteria**:
  - Migration is executed in slices: `search` -> `utility` -> `memo/open-project`.
  - Duplicated resolver/quarantine functions are removed from migrated scripts.
  - Each migrated workflow preserves candidate priority: env override -> packaged -> release -> debug.
  - Runtime error messages remain workflow-specific where needed.
- **Validation**:
  - `shellcheck scripts/lib/workflow_cli_resolver.sh`
  - `for id in google-search wiki-search youtube-search cambridge-dict spotify-search randomer epoch-converter market-expression multi-timezone quote-feed weather memo-add open-project; do bash "workflows/$id/tests/smoke.sh"; done`

### Task 2.2: Add shared Script Filter error JSON helper library
- **Location**:
  - `scripts/lib/script_filter_error_json.sh`
  - `workflows/google-search/scripts/script_filter.sh`
  - `workflows/wiki-search/scripts/script_filter.sh`
  - `workflows/youtube-search/scripts/script_filter.sh`
  - `workflows/cambridge-dict/scripts/script_filter.sh`
  - `workflows/spotify-search/scripts/script_filter.sh`
  - `workflows/randomer/scripts/script_filter.sh`
  - `workflows/randomer/scripts/script_filter_types.sh`
  - `workflows/randomer/scripts/script_filter_expand.sh`
  - `workflows/epoch-converter/scripts/script_filter.sh`
  - `workflows/market-expression/scripts/script_filter.sh`
  - `workflows/multi-timezone/scripts/script_filter.sh`
  - `workflows/quote-feed/scripts/script_filter.sh`
  - `workflows/weather/scripts/script_filter_common.sh`
  - `workflows/memo-add/scripts/script_filter.sh`
- **Description**: Extract shared JSON escaping, normalized stderr compaction, and generic non-actionable error-row emitters. Keep per-workflow error classification and copy local.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Migration is executed in slices: `search` -> `utility+memo`.
  - `json_escape`, `normalize_error_message`, and base emitters are sourced from shared helper in migrated scripts.
  - Workflow-specific titles/subtitles and classification branches remain unchanged.
- **Validation**:
  - `shellcheck scripts/lib/script_filter_error_json.sh`
  - `for id in google-search wiki-search youtube-search cambridge-dict spotify-search randomer epoch-converter market-expression multi-timezone quote-feed weather memo-add; do bash "workflows/$id/tests/smoke.sh"; done`

### Task 2.3: Extend query-policy helper for Memo-specific input edge cases
- **Location**:
  - `scripts/lib/script_filter_query_policy.sh`
  - `workflows/memo-add/scripts/script_filter.sh`
  - `workflows/memo-add/scripts/script_filter_copy.sh`
  - `workflows/memo-add/scripts/script_filter_delete.sh`
  - `workflows/memo-add/scripts/script_filter_recent.sh`
  - `workflows/memo-add/scripts/script_filter_search.sh`
  - `workflows/memo-add/scripts/script_filter_update.sh`
- **Description**: Add helper utilities for `(null)` sentinel handling, robust argv/env/stdin query resolve, and safe trim behavior for Memo wrappers. Replace wrapper-local duplicated query parsing and remove `xargs`-based trim usage.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 6
- **Acceptance criteria**:
  - Memo wrappers use shared helper input parsing path.
  - Empty/whitespace handling matches existing behavior expectations without `xargs` side effects.
  - `(null)` debug artifact is normalized consistently.
- **Validation**:
  - `shellcheck scripts/lib/script_filter_query_policy.sh workflows/memo-add/scripts/script_filter.sh workflows/memo-add/scripts/script_filter_*.sh`
  - `bash workflows/memo-add/tests/smoke.sh`

## Sprint 3: P1 Search Workflow Flow Driver Consolidation
**Goal**: Consolidate duplicated async/coalesce/cache/fetch orchestration across the four search-style workflows while preserving workflow-specific semantics.
**Demo/Validation**:
- Command(s): `bash workflows/google-search/tests/smoke.sh`, `bash workflows/wiki-search/tests/smoke.sh`, `bash workflows/youtube-search/tests/smoke.sh`, `bash workflows/cambridge-dict/tests/smoke.sh`
- Verify: Shared orchestration is in place; per-workflow UX and backend invocation rules remain intact.

### Task 3.1: Add shared async-search Script Filter flow driver
- **Location**:
  - `scripts/lib/script_filter_search_driver.sh`
  - `workflows/google-search/scripts/script_filter.sh`
  - `workflows/wiki-search/scripts/script_filter.sh`
  - `workflows/youtube-search/scripts/script_filter.sh`
  - `workflows/cambridge-dict/scripts/script_filter.sh`
- **Description**: Implement shared orchestration for query resolve, minimum-char gate, cache read/write, settle-window handling, pending-item emission, and final fetch execution. Expose callback-style hooks so each workflow provides only backend fetch command, env key prefixes, and UI copy tokens.
- **Dependencies**:
  - Task 2.2
  - Task 2.3
- **Complexity**: 9
- **Acceptance criteria**:
  - Shared driver handles common control flow now duplicated across four scripts.
  - Workflow adapters retain workflow-specific error mapping and backend options.
  - No regression in pending rerun behavior or cache semantics.
- **Validation**:
  - `shellcheck scripts/lib/script_filter_search_driver.sh workflows/google-search/scripts/script_filter.sh workflows/wiki-search/scripts/script_filter.sh workflows/youtube-search/scripts/script_filter.sh workflows/cambridge-dict/scripts/script_filter.sh`
  - `bash workflows/google-search/tests/smoke.sh`
  - `bash workflows/wiki-search/tests/smoke.sh`
  - `bash workflows/youtube-search/tests/smoke.sh`
  - `bash workflows/cambridge-dict/tests/smoke.sh`

### Task 3.2: Keep workflow-specific semantics explicit after driver migration
- **Location**:
  - `workflows/google-search/scripts/script_filter.sh`
  - `workflows/wiki-search/scripts/script_filter.sh`
  - `workflows/youtube-search/scripts/script_filter.sh`
  - `workflows/cambridge-dict/scripts/script_filter.sh`
  - `workflows/google-search/README.md`
  - `workflows/wiki-search/README.md`
  - `workflows/youtube-search/README.md`
  - `workflows/cambridge-dict/README.md`
- **Description**: Add concise adapter-layer comments/docs clarifying that only orchestration is shared; per-workflow API and error policy remains local and intentional.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Adapter scripts are readable and show clear extension points.
  - Workflow docs mention shared runtime driver usage without claiming shared domain behavior.
- **Validation**:
  - `rg -n "shared driver|orchestration|workflow-specific" workflows/google-search/scripts/script_filter.sh workflows/wiki-search/scripts/script_filter.sh workflows/youtube-search/scripts/script_filter.sh workflows/cambridge-dict/scripts/script_filter.sh workflows/google-search/README.md workflows/wiki-search/README.md workflows/youtube-search/README.md workflows/cambridge-dict/README.md`

## Sprint 4: Cross-Workflow Hardening and Quality Gates
**Goal**: Ensure extracted helpers are stable in both source tree and packaged workflow runtime.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `scripts/workflow-test.sh`, `scripts/workflow-pack.sh --all`
- Verify: Lint, tests, and package artifacts pass with helper extraction in place.

### Task 4.1: Run full validation matrix for touched workflows
- **Location**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `workflows/google-search/tests/smoke.sh`
  - `workflows/wiki-search/tests/smoke.sh`
  - `workflows/youtube-search/tests/smoke.sh`
  - `workflows/cambridge-dict/tests/smoke.sh`
  - `workflows/memo-add/tests/smoke.sh`
  - `workflows/spotify-search/tests/smoke.sh`
  - `workflows/randomer/tests/smoke.sh`
  - `workflows/epoch-converter/tests/smoke.sh`
  - `workflows/market-expression/tests/smoke.sh`
- **Description**: Execute lint and targeted smoke suites, capturing regressions caused by helper extraction and fixing drift before optional P2 extraction.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
- **Complexity**: 5
- **Acceptance criteria**:
  - All touched-workflow smoke tests pass.
  - No malformed Alfred JSON regressions in error/success paths.
- **Validation**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh --all`

## Sprint 5: P2 Optional Thin Wrapper Consolidation
**Goal**: Consolidate tiny duplicated action wrappers only after P1 is stable.
**Demo/Validation**:
- Command(s): `bash workflows/epoch-converter/tests/smoke.sh`, `bash workflows/google-search/tests/smoke.sh`, `bash workflows/wiki-search/tests/smoke.sh`, `bash workflows/youtube-search/tests/smoke.sh`
- Verify: Copy/open wrapper behavior is unchanged after deduplication.

### Task 5.1: Consolidate `action_copy.sh` duplicates
- **Location**:
  - `scripts/lib/workflow_action_copy.sh`
  - `workflows/epoch-converter/scripts/action_copy.sh`
  - `workflows/market-expression/scripts/action_copy.sh`
  - `workflows/multi-timezone/scripts/action_copy.sh`
  - `workflows/weather/scripts/action_copy.sh`
- **Description**: Replace byte-identical copy-to-clipboard scripts with a shared helper or shared wrapper source pattern, retaining existing usage/exit behavior.
- **Dependencies**:
  - Task 4.1
- **Complexity**: 3
- **Acceptance criteria**:
  - Four duplicate `action_copy.sh` scripts no longer diverge in implementation.
  - Clipboard failure/usage behavior remains unchanged.
- **Validation**:
  - `shellcheck scripts/lib/workflow_action_copy.sh workflows/epoch-converter/scripts/action_copy.sh workflows/market-expression/scripts/action_copy.sh workflows/multi-timezone/scripts/action_copy.sh workflows/weather/scripts/action_copy.sh`
  - `bash workflows/epoch-converter/tests/smoke.sh`
  - `bash workflows/market-expression/tests/smoke.sh`
  - `bash workflows/multi-timezone/tests/smoke.sh`
  - `bash workflows/weather/tests/smoke.sh`

### Task 5.2: Consolidate identical URL open action wrappers
- **Location**:
  - `scripts/lib/workflow_action_open_url.sh`
  - `workflows/google-search/scripts/action_open.sh`
  - `workflows/wiki-search/scripts/action_open.sh`
  - `workflows/youtube-search/scripts/action_open.sh`
  - `workflows/cambridge-dict/scripts/action_open.sh`
- **Description**: Extract shared open-URL wrapper for the four byte-identical scripts, preserving argument validation and current `open` behavior.
- **Dependencies**:
  - Task 4.1
- **Complexity**: 3
- **Acceptance criteria**:
  - The four open scripts use shared implementation and stay behaviorally equivalent.
  - No impact on workflow action-chain wiring.
- **Validation**:
  - `shellcheck scripts/lib/workflow_action_open_url.sh workflows/google-search/scripts/action_open.sh workflows/wiki-search/scripts/action_open.sh workflows/youtube-search/scripts/action_open.sh workflows/cambridge-dict/scripts/action_open.sh`
  - `bash workflows/google-search/tests/smoke.sh`
  - `bash workflows/wiki-search/tests/smoke.sh`
  - `bash workflows/youtube-search/tests/smoke.sh`
  - `bash workflows/cambridge-dict/tests/smoke.sh`

## Testing Strategy
- Unit:
  - Add helper-level shell tests for resolver fallback order, error JSON escaping, and query normalization edge cases.
  - Keep helper APIs small and deterministic to maximize unit-test coverage.
- Integration:
  - Use existing workflow smoke suites to verify Script Filter output contracts and action behavior after migration.
  - Add focused assertions for staged helper file existence inside packaged artifacts where relevant.
- E2E/manual:
  - Install affected workflows via packaging scripts and verify interactive Alfred behavior for key keywords (`gg`, `wk`, `yt`, `cd`, `mm*`).

## Risks & gotchas
- Over-abstraction risk: helper API can become too generic and harder to debug than local scripts.
- Packaging drift risk: new helpers may work in repo tests but be missing in installed workflow bundles if staging rules are incomplete.
- Behavior drift risk: query normalization differences (especially Memo wrappers) can change token routing unexpectedly.
- Search-flow consolidation risk: coalesce/cache timing differences can alter user-perceived responsiveness.

## Rollback plan
1. Revert helper extraction commits per sprint scope (P1 first, P2 separately) to isolate fault domains.
2. Restore prior workflow-local implementations for the impacted scripts.
3. Re-run lint/smoke/package checks for affected workflows to confirm rollback integrity.
4. Repackage and reinstall known-good artifacts for affected workflow IDs.
5. Keep helper files in tree only if referenced by active scripts; otherwise remove dead helper files in the rollback patch.
