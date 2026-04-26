# Plan: codex-cli Shell Refactor

## Overview

`workflows/codex-cli/scripts/script_filter.sh` (2399 LoC) and
`action_open.sh` (965 LoC) are the two largest shell scripts in the repo.
Their helper inventory has already outgrown an ad-hoc layout — diag cache
state, cxau ranking analysis, and capture utilities each occupy
several hundred lines that are duplicated or near-duplicated across the
two scripts. This plan extracts cohesive helper modules into
`workflows/codex-cli/scripts/lib/` (using the established
`workflow_helper_loader.sh` pattern), keeps both entry scripts on
their existing public surface, and tightens documentation. The
extraction is gated by a baseline behavioural snapshot so we can detect
any regression introduced by the move; nothing about the workflow's
runtime contract changes.

## Scope

- In scope:
  - Decomposition of `workflows/codex-cli/scripts/script_filter.sh` and
    `workflows/codex-cli/scripts/action_open.sh` into per-concern
    helper files under `workflows/codex-cli/scripts/lib/`.
  - Extension of `workflows/codex-cli/tests/smoke.sh` so each
    extraction sprint has a regression net before the move.
  - Documentation cross-links: `ALFRED_WORKFLOW_DEVELOPMENT.md`,
    `DEVELOPMENT.md`, and the workflow's own `README.md` /
    `TROUBLESHOOTING.md` reflect the new layout.
- Out of scope:
  - Any change to the workflow's user-facing keyword set, env vars,
    Alfred Script Filter JSON shape, or `codex-cli` runtime contract.
  - Non-codex-cli workflows.
  - The optional Rust port (Sprint 6) is sized but not scheduled —
    it ships only if the final shell footprint is still above the
    "easy to maintain" threshold after Sprints 1–5 land.

## Assumptions

1. The existing `workflows/codex-cli/tests/smoke.sh` (1317 LoC) covers
   structural assertions but does not snapshot diag-cache or cxau
   ranking outputs — Sprint 1 closes that gap.
2. `workflow_helper_loader.sh` (`scripts/lib/`) and the in-workflow
   `lib/` convention used by other workflows can host codex-cli's
   helpers without changing the loader contract.
3. Extracted helpers can run under `set -euo pipefail` and depend
   only on the same external tools (`jq`, `awk`, `mktemp`, `flock`,
   `codex-cli`) already required by the entry scripts.
4. The clippy unwrap/expect gate (PR #155) and cargo-deny gate
   (PR #154) catch downstream regressions; this plan does not need
   to add Rust-side gates of its own.
5. `bash scripts/script-tests.sh` plus `bash scripts/local-pre-commit.sh`
   stay the canonical local pre-push gate. Behavioural snapshots
   added here run inside `tests/smoke.sh` so `workflow-test.sh`
   exercises them automatically.

## Sprint 1: Baseline Snapshot and Smoke Extension

**Goal**: Lock down the current observable behaviour of `script_filter.sh`
and `action_open.sh` so any later extraction is a true refactor, not a
silent rewrite.
**Demo/Validation**:

- Command(s):
  - `bash workflows/codex-cli/tests/smoke.sh`
  - `bash scripts/workflow-test.sh --id codex-cli --skip-third-party-audit --skip-workspace-tests`
- Verify: smoke run prints `ok: smoke passed` and the four new
  snapshot fixtures under `workflows/codex-cli/tests/fixtures/`
  match byte-for-byte after a second run on an unchanged tree.

**PR grouping intent**: group
**Execution Profile**: parallel-x2
**TotalComplexity**: 14
**CriticalPathComplexity**: 9
**MaxBatchWidth**: 2
**OverlapHotspots**: `tests/smoke.sh` is touched by 1.1 and 1.2; merge
sequence `1.1 → 1.2 → 1.3` keeps writes serial.

### Task 1.1: Capture diag-cache snapshot fixtures

- **Location**:
  - `workflows/codex-cli/tests/fixtures/diag_cache_empty.expected.json`
    (new)
  - `workflows/codex-cli/tests/fixtures/diag_cache_all_json.expected.json`
    (new)
  - `workflows/codex-cli/tests/smoke.sh`
- **Description**: Add fixture-driven assertions that drive
  `script_filter.sh` against an empty diag cache and a primed
  `all-json` cache. Capture the rendered Alfred Script Filter JSON
  via `jq -S` (sort keys) into golden files under
  `workflows/codex-cli/tests/fixtures/` and assert byte-equality on
  every smoke run. Use `mktemp -d` + a `trap` to seed the cache
  state so tests stay self-contained.
- **Dependencies**:
  - none
- **Complexity**: 5
- **Acceptance criteria**:
  - Two golden files committed; `tests/smoke.sh` exits 0 against
    them on a clean working tree.
  - Mutating any of the candidate diag-cache helpers (e.g. renaming
    `diag_result_meta_path`) produces a `diff` failure with a
    line-level pointer.
- **Validation**:
  - `bash workflows/codex-cli/tests/smoke.sh` (first run primes
    fixtures; second run must match).
  - `git diff workflows/codex-cli/tests/fixtures/` is empty after the
    second run.

### Task 1.2: Capture cxau ranking snapshot fixtures

- **Location**:
  - `workflows/codex-cli/tests/fixtures/cxau_sort_input.tsv` (new)
  - `workflows/codex-cli/tests/fixtures/cxau_rank_expected.txt` (new)
  - `workflows/codex-cli/tests/smoke.sh`
- **Description**: Mirror Task 1.1 for the cxau analysis path.
  Drive `emit_diag_all_json_account_items` (and the awk pipeline
  it feeds) with a fixed TSV of synthetic accounts and snapshot
  the deterministic ordering plus rendered Alfred items. Choose
  inputs that exercise the weekly/non-weekly fork, the
  `9999999999` epoch fallback, and at least one tied score path.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Two fixtures committed; smoke run reproduces them exactly.
- **Validation**:
  - `bash workflows/codex-cli/tests/smoke.sh` (golden compare).
  - Mutation experiment: drop the `LC_ALL=C sort -t$'\t' -k1,1n -k2,2`
    line in `script_filter.sh:1808`, rerun smoke, confirm a `diff`
    failure that points at the cxau snapshot. Capture the failing
    smoke output path in the PR description before reverting.

### Task 1.3: Extend smoke harness with `capture_command_output_with_stdout_priority` test

- **Location**:
  - `workflows/codex-cli/tests/fixtures/capture_priority_cases.tsv`
    (new)
  - `workflows/codex-cli/tests/smoke.sh`
- **Description**: The `capture_command_output_with_stdout_priority`
  helper exists in both `script_filter.sh:391` and
  `action_open.sh:580` with identical bodies. Add a smoke block that
  sources each script in a subshell and asserts the helper's stdout-
  vs-stderr precedence (stderr-only, stdout-only, mixed) so Sprint
  3's de-duplication has a regression net.
- **Dependencies**:
  - none
- **Complexity**: 5
- **Acceptance criteria**:
  - 3 cases (stdout-priority, stderr-fallback, mixed) all pass.
  - Smoke fails if either copy of the helper changes its precedence
    rule.
- **Validation**:
  - `bash workflows/codex-cli/tests/smoke.sh`.

## Sprint 2: Extract diag-cache module

**Goal**: Move the ~22-function diag-cache state machine out of
`script_filter.sh` into a single sourced helper without changing public
behaviour.
**Demo/Validation**:

- Command(s):
  - `bash workflows/codex-cli/tests/smoke.sh`
  - `wc -l workflows/codex-cli/scripts/script_filter.sh`
- Verify: smoke continues to pass (Sprint 1 fixtures unchanged);
  `script_filter.sh` shrinks by ≥600 LoC; `lib/codex_diag_cache.sh`
  ~650 LoC.

**PR grouping intent**: group
**Execution Profile**: parallel-x2
**TotalComplexity**: 18
**CriticalPathComplexity**: 13
**MaxBatchWidth**: 2
**OverlapHotspots**: 2.1 creates the new helper file; 2.2 rewires the
loader; 2.3 deletes the original bodies. 2.2 and 2.3 both edit
`script_filter.sh` and must merge serial.

### Task 2.1: Create `lib/codex_diag_cache.sh` with verbatim function bodies

- **Location**:
  - `workflows/codex-cli/scripts/lib/codex_diag_cache.sh` (new)
- **Description**: Copy the 22 diag-cache helpers
  (`resolve_workflow_cache_dir`, `sanitize_diag_mode`,
  `canonical_diag_cache_mode`, the 6 path resolvers, the lock /
  freshness / refresh helpers, `store_diag_result`,
  `capture_command_output_with_stdout_priority`,
  `run_diag_cache_refresh_for_mode`, `wait_for_diag_refresh_completion_for_mode`,
  `refresh_diag_cache_blocking_for_mode`,
  `ensure_diag_cache_ready_for_mode`,
  `resolve_diag_auto_refresh_mode_for_query`,
  `resolve_diag_cache_block_wait_seconds`,
  `diag_cache_exists_for_mode`,
  `resolve_diag_display_cache_paths_for_mode`) into the new helper
  with byte-identical bodies and a header that mirrors
  `scripts/lib/script_filter_async_coalesce.sh` (purpose,
  `set -euo pipefail` reminder, no top-level side effects).
- **Dependencies**:
  - Task 1.1
- **Complexity**: 5
- **Acceptance criteria**:
  - File compiles under `bash -n` and `shellcheck -e SC1091 -e SC2317`.
  - `diff <(grep '^[a-z_]*()' lib/codex_diag_cache.sh) ...` lists the
    expected 22 helpers, no more, no less.
- **Validation**:
  - `bash -n workflows/codex-cli/scripts/lib/codex_diag_cache.sh`.
  - `shellcheck workflows/codex-cli/scripts/lib/codex_diag_cache.sh`.

### Task 2.2: Wire helper loader to source the new module

- **Location**:
  - `workflows/codex-cli/scripts/script_filter.sh`
  - `workflows/codex-cli/scripts/action_open.sh`
- **Description**: Add a `wfhl_source_helper "$workflow_script_dir"
  "codex_diag_cache.sh" off || true` line in the existing helper-
  loader block of both entry scripts (right after the existing
  `workflow_cli_resolver.sh` source). Keep the original in-script
  bodies in place for now — Task 2.3 removes them once the loader
  is verified.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 3
- **Acceptance criteria**:
  - Smoke continues to pass with helper loaded twice (defensive
    confirmation that double-source is a no-op).
- **Validation**:
  - `bash workflows/codex-cli/tests/smoke.sh`.

### Task 2.3: Delete moved bodies from `script_filter.sh`

- **Location**:
  - `workflows/codex-cli/scripts/script_filter.sh`
- **Description**: Remove the 22 function definitions now provided by
  `lib/codex_diag_cache.sh`. Verify call sites resolve via the
  loader instead. Update the file's top-of-script comment block to
  point at the helper.
- **Dependencies**:
  - Task 2.2
- **Complexity**: 5
- **Acceptance criteria**:
  - `wc -l script_filter.sh` decreases by ≥600.
  - Sprint 1 golden snapshots still match (no behavioural change).
- **Validation**:
  - `bash workflows/codex-cli/tests/smoke.sh`.
  - `bash scripts/workflow-test.sh --id codex-cli --skip-third-party-audit --skip-workspace-tests`.

### Task 2.4: Add focused unit tests for the new helper

- **Location**:
  - `scripts/tests/codex_diag_cache.test.sh` (new)
- **Description**: Mirror the existing `scripts/tests/*.test.sh`
  pattern (sourced helper plus assertion functions). Cover at minimum
  `canonical_diag_cache_mode` (positive, fallback), the path
  resolvers (TMPDIR override, default), and
  `is_diag_cache_fresh_for_mode` (TTL boundary). Depends only on the
  helper file (2.1), so it can land in the same batch as the loader
  wiring (2.2).
- **Dependencies**:
  - Task 2.1
- **Complexity**: 5
- **Acceptance criteria**:
  - `bash scripts/script-tests.sh` lists the new test and passes.
- **Validation**:
  - `bash scripts/script-tests.sh`.

## Sprint 3: Extract cxau ranking module

**Goal**: Move the ~600-LoC `cxau-sort` / `cxau-rank` analysis path
(awk pipeline, normalization helpers, ranking emit) out of
`script_filter.sh`.
**Demo/Validation**:

- Command(s):
  - `bash workflows/codex-cli/tests/smoke.sh`
- Verify: cxau snapshot from Sprint 1 still matches; `script_filter.sh`
  drops by ≥600 LoC; new `lib/codex_diag_account_ranking.sh` lands
  with `bash -n` + shellcheck clean.

**PR grouping intent**: group
**Execution Profile**: serial
**TotalComplexity**: 13
**CriticalPathComplexity**: 13
**MaxBatchWidth**: 1
**OverlapHotspots**: 3.1 → 3.2 → 3.3 form a strict chain on
`script_filter.sh`; no parallel lane available.

### Task 3.1: Create `lib/codex_diag_account_ranking.sh`

- **Location**:
  - `workflows/codex-cli/scripts/lib/codex_diag_account_ranking.sh`
    (new)
- **Description**: Move
  `lookup_diag_account_meta`,
  `emit_diag_all_json_account_items`,
  the awk normalization block, and the `LC_ALL=C sort` ranking
  pipeline (script_filter.sh ~ L729–L1820 contiguous block) into a
  dedicated helper file. Include the `__codex_tmp_files` register
  contract — helper must use the array if defined by the caller,
  otherwise fall back to a local trap (defense-in-depth, mirrors
  the cleanup PR #156).
- **Dependencies**:
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - File loads via `wfhl_source_helper`; behavioural snapshot from
    1.2 still matches.
- **Validation**:
  - `bash -n workflows/codex-cli/scripts/lib/codex_diag_account_ranking.sh`.
  - `shellcheck workflows/codex-cli/scripts/lib/codex_diag_account_ranking.sh`.

### Task 3.2: Wire loader entry

- **Location**:
  - `workflows/codex-cli/scripts/script_filter.sh`
- **Description**: Add the `wfhl_source_helper` line for the new
  module in the existing loader block; keep the inline bodies in
  place for one PR cycle.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 3
- **Acceptance criteria**:
  - Smoke passes with helper double-loaded (idempotent).
- **Validation**:
  - `bash workflows/codex-cli/tests/smoke.sh`.

### Task 3.3: Remove inline bodies and the awk normalization block

- **Location**:
  - `workflows/codex-cli/scripts/script_filter.sh`
- **Description**: Delete the now-duplicated inline definitions of
  `lookup_diag_account_meta` and `emit_diag_all_json_account_items`
  plus the awk pipeline. Leave only the call sites.
- **Dependencies**:
  - Task 3.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Sprint 1 cxau snapshot unchanged; total `script_filter.sh`
    shrinkage from Sprints 2 + 3 ≥1200 LoC.
- **Validation**:
  - `bash workflows/codex-cli/tests/smoke.sh`.

## Sprint 4: Dedupe `action_open.sh` shared helpers

**Goal**: Consolidate helpers that are present in both entry scripts so
`action_open.sh` shrinks and shared logic lives in exactly one place.
**Demo/Validation**:

- Command(s):
  - `bash workflows/codex-cli/tests/smoke.sh`
  - `wc -l workflows/codex-cli/scripts/action_open.sh`
- Verify: `capture_command_output_with_stdout_priority` exists only in
  `lib/codex_diag_cache.sh`; `action_open.sh` shrinks by ≥80 LoC.

**PR grouping intent**: group
**Execution Profile**: serial
**TotalComplexity**: 13
**CriticalPathComplexity**: 13
**MaxBatchWidth**: 1
**OverlapHotspots**: 4.1 → 4.2 → 4.3 form a strict chain on
`action_open.sh`; no parallel lane available. Cross-sprint guard:
4.2 also waits on 2.3 (Sprint 2 must merge first so the diag-cache
helper is on disk before `action_open.sh` sources it).

### Task 4.1: Move `secret_dir` and `confirm_*` helpers into `lib/codex_secret_dir.sh`

- **Location**:
  - `workflows/codex-cli/scripts/lib/codex_secret_dir.sh` (new)
- **Description**: Extract `confirm_save_if_needed`,
  `confirm_remove_if_needed`, the `resolve_default_codex_secret_dir`
  / `resolve_codex_auth_file_env_value` /
  `ensure_codex_auth_file_env` / `ensure_codex_secret_dir_env` /
  `ensure_codex_secret_dir_exists` / `ensure_remove_secret_exists`
  cluster, plus `secret_dir_has_saved_json` and
  `resolve_diag_scope_for_all`. These are only used by
  `action_open.sh` today but logically belong to the same secret-
  dir surface that the auth Script Filter scripts will eventually
  share.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 5
- **Acceptance criteria**:
  - `bash -n` clean; shellcheck clean; double-load idempotent.
- **Validation**:
  - `bash -n workflows/codex-cli/scripts/lib/codex_secret_dir.sh`.
  - `shellcheck workflows/codex-cli/scripts/lib/codex_secret_dir.sh`.

### Task 4.2: Wire loader for `codex_secret_dir.sh` and remove duplicate `capture_command_output_with_stdout_priority`

- **Location**:
  - `workflows/codex-cli/scripts/action_open.sh`
- **Description**: Add the `wfhl_source_helper` lines for both
  `codex_diag_cache.sh` (provides `capture_command_output_*`) and
  `codex_secret_dir.sh`. Delete the inline copies of
  `capture_command_output_with_stdout_priority` and
  `store_diag_result` already migrated in Sprint 2 / Task 4.1.
- **Dependencies**:
  - Task 2.3
  - Task 4.1
- **Complexity**: 5
- **Acceptance criteria**:
  - `action_open.sh` shrinks by ≥80 LoC; smoke + capture-priority
    snapshot still pass.
- **Validation**:
  - `bash workflows/codex-cli/tests/smoke.sh`.

### Task 4.3: Prune leftover `action_open.sh` helpers superseded by Sprint 4.1

- **Location**:
  - `workflows/codex-cli/scripts/action_open.sh`
- **Description**: Remove the now-duplicate `confirm_*` /
  `resolve_default_codex_secret_dir` definitions from
  `action_open.sh`; verify the loader-sourced versions are picked
  up.
- **Dependencies**:
  - Task 4.2
- **Complexity**: 3
- **Acceptance criteria**:
  - Smoke passes; `wc -l action_open.sh` ≤ 600.
- **Validation**:
  - `bash workflows/codex-cli/tests/smoke.sh`.

## Sprint 5: Documentation refresh

**Goal**: Bring `ALFRED_WORKFLOW_DEVELOPMENT.md`, `DEVELOPMENT.md`, and
the workflow's own README up to date with the new helper inventory; add
a one-page "extracted-helper map" so future contributors do not re-
inline.
**Demo/Validation**:

- Command(s):
  - `bash scripts/ci/markdownlint-audit.sh --strict`
  - `bash scripts/docs-placement-audit.sh --strict`
- Verify: both gates pass; new diagram / table present in
  `ALFRED_WORKFLOW_DEVELOPMENT.md` describing the codex-cli helper
  surface.

**PR grouping intent**: per-sprint
**Execution Profile**: serial
**TotalComplexity**: 8
**CriticalPathComplexity**: 8
**MaxBatchWidth**: 1
**OverlapHotspots**: docs only — three files edited in sequence;
single-PR per sprint convention.

### Task 5.1: Update `ALFRED_WORKFLOW_DEVELOPMENT.md` helper inventory

- **Location**:
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
- **Description**: Add a "codex-cli helper map" table listing the new
  `lib/*.sh` files plus their public functions, parallel to the
  existing `workflow_helper_loader.sh` description. Cross-link to
  `docs/specs/cli-shared-runtime-contract.md` and
  `docs/specs/script-filter-input-policy.md`.
- **Dependencies**:
  - Task 4.3
- **Complexity**: 3
- **Acceptance criteria**:
  - Table lists every helper file added in Sprints 2–4.
  - `bash scripts/ci/markdownlint-audit.sh --strict` passes.
- **Validation**:
  - `bash scripts/ci/markdownlint-audit.sh --strict`.

### Task 5.2: Update `workflows/codex-cli/README.md` runtime layout section

- **Location**:
  - `workflows/codex-cli/README.md`
  - `workflows/codex-cli/TROUBLESHOOTING.md`
- **Description**: Add a brief "Runtime layout" subsection in the
  README pointing at the new `lib/` files; mention helper-loader
  failure modes in TROUBLESHOOTING (`wfhl_source_helper` returning
  non-zero is non-fatal; double-source is safe).
- **Dependencies**:
  - Task 5.1
- **Complexity**: 2
- **Acceptance criteria**:
  - Both files lint clean; cross-link to the helper map lands in
    `ALFRED_WORKFLOW_DEVELOPMENT.md`.
- **Validation**:
  - `bash scripts/ci/markdownlint-audit.sh --strict`.

### Task 5.3: Note the refactor in `DEVELOPMENT.md` testing section

- **Location**:
  - `DEVELOPMENT.md`
- **Description**: Add a one-line bullet under "Testing > Required
  before committing" telling contributors to run
  `bash workflows/codex-cli/tests/smoke.sh` directly when changing
  any `workflows/codex-cli/scripts/lib/*.sh` file. Keeps reviewers
  from accidentally landing helper-only edits without smoke.
- **Dependencies**:
  - Task 5.2
- **Complexity**: 3
- **Acceptance criteria**:
  - Markdown lint clean; reference to the smoke entry uses the
    canonical relative path.
- **Validation**:
  - `bash scripts/ci/markdownlint-audit.sh --strict`.

## Sprint 6: Optional Rust port assessment (deferred)

**Goal**: After Sprints 1–5 land, evaluate whether the remaining
shell footprint is acceptable or whether a partial Rust port pays for
itself. **Do not schedule until the prior sprints are merged and the
post-refactor LoC is measured.**
**Demo/Validation**:

- Command(s):
  - Sizing report: `wc -l workflows/codex-cli/scripts/*.sh
    workflows/codex-cli/scripts/lib/*.sh`
- Verify: post-Sprint-5 entry-script LoC under 1000 each. If true,
  Sprint 6 is closed without action; if false, scope a Rust port
  via `crates/codex-cli/` mirroring the shape of the other
  `*-workflow-cli` crates.

**PR grouping intent**: per-sprint
**Execution Profile**: serial
**TotalComplexity**: 5
**CriticalPathComplexity**: 5
**MaxBatchWidth**: 1
**OverlapHotspots**: planning artifact only — no code edits.

### Task 6.1: Post-refactor sizing assessment + decision

- **Location**:
  - `docs/reports/codex-cli-shell-refactor-assessment.md` (new)
- **Description**: Snapshot the final LoC footprint of every codex-cli
  `scripts/*.sh` and `scripts/lib/*.sh` file. Compare against the
  pre-Sprint-1 baseline (`script_filter.sh` 2399 / `action_open.sh`
  965). Either close the deferred sprint with a recommendation
  ("shell footprint manageable, no port"), or open a follow-up
  `create-plan-rigorous` invocation that scopes a `nils-codex-cli`
  Rust crate in line with `crates/memo-workflow-cli/`.
- **Dependencies**:
  - Task 5.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Assessment doc lands under `docs/reports/` (the canonical
    "report" home, mirrors PR #153).
  - Decision is binary (port vs no-port) with explicit rationale.
- **Validation**:
  - `bash scripts/docs-placement-audit.sh --strict`.

## Testing Strategy

- Unit (shell): `bash scripts/script-tests.sh` runs the existing
  `scripts/tests/*.test.sh` suites plus the new
  `codex_diag_cache.test.sh` (Task 2.4); each helper file is
  testable in isolation by sourcing it inside the test runner.
- Integration: `bash workflows/codex-cli/tests/smoke.sh` is the
  primary regression gate. Sprint 1 lands three new fixture-driven
  blocks (diag-cache rendering, cxau ranking determinism,
  capture-priority precedence) that every later sprint must keep
  green.
- Workspace gate: `bash scripts/local-pre-commit.sh` (default
  mode) chains `workflow-lint.sh` → policy check → node scraper →
  `workflow-test.sh`. CI parity is `bash scripts/local-pre-commit.sh
  --mode ci`.
- Manual: smoke does not exercise the live `codex` binary in CI;
  before merging Sprints 2–4, run `bash
  workflows/codex-cli/scripts/script_filter.sh` against a real
  installed workflow once to confirm the diag refresh path still
  populates the cache (manual checklist captured in each sprint
  PR's `## Testing` section).

## Risks & gotchas

- **Risk**: Diag-cache concurrency surface (`flock`-style refresh
  lock at `script_filter.sh:548`) is subtle; moving its body into a
  helper while preserving the subshell trap requires the helper
  caller — not the helper itself — to own the trap. Sprint 2 keeps
  the trap setup at the call site to mirror the existing pattern.
- **Risk**: Sprint 1 fixtures depend on jq's deterministic ordering;
  use `jq -S` in golden generation and verification, never raw
  `jq .`. Tied scores in the cxau path also depend on the fallback
  epoch `9999999999`; pin that explicitly in the fixture's
  generation comment.
- **Risk**: `action_open.sh` and `script_filter.sh` will both source
  `codex_diag_cache.sh` (Sprint 2 Task 2.2) — double-source must be
  idempotent. Helper file must avoid top-level state and rely only
  on caller-owned arrays / env vars (mirrors the existing
  `script_filter_async_coalesce.sh` pattern).
- **Bottleneck**: Sprint 2 and Sprint 3 each have a single-file edit
  chain (2.2 → 2.3 and 3.2 → 3.3) on `script_filter.sh`. Cannot
  parallelize within sprint — keep the dep edges as the scorecard
  reflects.
- **Compatibility**: Workflow contract docs (`README.md`,
  `TROUBLESHOOTING.md`, `workflow.toml`) describe user-visible
  surface; nothing in this plan changes any of them.
  `ALFRED_WORKFLOW_DEVELOPMENT.md` only gains a new helper-map
  section, no contract change.
- **Rollout**: Each sprint ships its own PR via the standard
  `create-feature-pr` skill; helper-loader changes are forward-
  compatible (loader entry that fails to find the helper logs and
  continues), so partial rollback is safe.

## Rollback plan

- Sprint 1: `git revert <merge-sha>` removes fixtures + smoke
  blocks; entry scripts unchanged.
- Sprints 2–4: each is a 3-task PR (`new helper file` → `wire
  loader` → `delete inline body`). Reverting the third task's PR
  re-introduces the inline definition; the helper file stays on
  disk but is harmless. Reverting all three PRs in the sprint
  fully restores the original layout.
- Sprint 5: docs-only revert, no runtime impact.
- Sprint 6: assessment doc only; no rollback work.
- Catastrophic: revert the merge SHAs in reverse order
  (Sprint 4 → 3 → 2 → 1). The clippy/cargo-deny gates from PR

  #154/#155 will still run against the restored tree.
