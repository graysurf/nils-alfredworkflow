# Plan: Shared Script Filter throttling and query guard for gg/yt/wk/cx workflows

## Overview
This plan standardizes Script Filter input behavior across `google-search` (`gg`), `youtube-search` (`yt`), `wiki-search` (`wk`), and `codex-cli` (`cx*`) with a shared implementation-first approach.  
The target behavior is: disable first-character immediate execution, set default queue delay to 1 second, and enforce a minimum query length policy before expensive calls.  
Implementation will extract shared policy/helper layers first, then apply workflow-specific wiring while preserving each workflow's UX contract.  
`codex-cli` keeps command-palette semantics (empty query and help/action rows), but short-query gating is still applied to expensive branches.

## Scope
- In scope: shared policy + helper extraction for Script Filter input throttling and minimum query gating.
- In scope: apply queue settings (`queuedelayimmediatelyinitially`, `queuedelaycustom`) to `google-search`, `youtube-search`, `wiki-search`, and all `codex-cli` Script Filter objects.
- In scope: enforce min query length before remote/expensive execution paths.
- In scope: update contracts/docs/smoke tests for all affected workflows.
- Out of scope: changing result ranking or backend API payload schemas.
- Out of scope: extending the same policy to non-target workflows (`spotify-search`, `weather`, `randomer`, etc.) in this change.
- Out of scope: introducing persistent response caching for `google-search` / `youtube-search` / `wiki-search`.

## Assumptions (if any)
1. User request `cd` refers to `codex-cli` keyword family (`cx`, `cxa`, `cxac`, `cxau`, `cxd`, `cxda`, `cxs`).
2. Minimum query length policy is strict for search workflows (`gg`, `yt`, `wk`) and command-aware for `codex-cli` so empty/default command menus remain available.
3. `queuedelaycustom` encoding for a 1-second delay will be validated from Alfred-exported plist behavior before finalizing values.

## Success Criteria
- Packaged plists for target workflows set `queuedelayimmediatelyinitially=false` and map queue delay to 1 second.
- `gg` / `yt` / `wk` do not call backend CLI/API when normalized query length is `< 2`.
- `cx*` keeps empty/help command palette behavior, while short partial queries avoid expensive branches (`auth current` parsing, diag refresh, all-json refresh).
- Shared abstraction is the single source of truth for query normalization + short-query gating rules.
- Smoke tests explicitly lock queue-delay and immediate-run settings for all touched Script Filter objects.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 1.3 -> Task 2.1 -> Task 3.1 -> Task 3.2 -> Task 4.1`.
- Parallel track A: `Task 2.2` and `Task 2.3` can run in parallel after `Task 1.3`.
- Parallel track B: `Task 3.3` can run in parallel with `Task 3.2` after `Task 3.1`.
- Parallel track C: `Task 4.2` and `Task 4.3` can run in parallel after `Task 4.1`.

## Sprint 1: Shared policy foundation
**Goal**: Define a single policy source and shared helper contracts before touching per-workflow behavior.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/script-filter-input-throttle-shared-plan.md`, `jq -e '.defaults.queue_delay_seconds == 1 and .defaults.min_query_chars == 2' docs/specs/script-filter-input-policy.json`
- Verify: Policy defaults and workflow scope are explicit and machine-readable.

### Task 1.1: Confirm Alfred queue-delay encoding for 1 second
- **Location**:
  - `docs/specs/script-filter-input-policy.md`
  - `docs/specs/script-filter-input-policy.json`
- **Description**: Record canonical mapping from Alfred UI queue delay (1.0s) to plist fields (`queuedelaymode`, `queuedelaycustom`), including evidence notes from official docs/exported plist.
- **Dependencies**:
  - none
- **Complexity**: 4
- **Acceptance criteria**:
  - Policy doc explicitly states exact plist value mapping for 1-second delay.
  - Policy doc states first-character immediate behavior must be disabled.
- **Validation**:
  - `test -f docs/specs/script-filter-input-policy.md`
  - `rg -n "queuedelaycustom|queuedelaymode|queuedelayimmediatelyinitially|1 second" docs/specs/script-filter-input-policy.md`

### Task 1.2: Create machine-readable Script Filter input policy
- **Location**:
  - `docs/specs/script-filter-input-policy.json`
- **Description**: Define defaults (`queue_delay_seconds=1`, `min_query_chars=2`, `immediate_initial=false`) and target workflow/object scope (including all seven `codex-cli` script filters).
- **Dependencies**:
  - Task 1.1
- **Complexity**: 3
- **Acceptance criteria**:
  - JSON schema includes defaults and explicit target object list.
  - JSON has no placeholders and can be parsed by `jq`.
- **Validation**:
  - `jq -e '.defaults.queue_delay_seconds == 1 and .defaults.min_query_chars == 2 and .defaults.immediate_initial == false' docs/specs/script-filter-input-policy.json`
  - `jq -e '.targets["codex-cli"].object_uids | length == 7' docs/specs/script-filter-input-policy.json`

### Task 1.3: Add shared shell helper for query normalization and short-query gating
- **Location**:
  - `scripts/lib/script_filter_query_policy.sh`
- **Description**: Implement reusable shell functions for query resolution (argv/env/stdin), trimming, length checks, and standard non-actionable feedback emission for short queries.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Helper exposes deterministic functions consumed by multiple workflows.
  - Helper does not hardcode workflow-specific title/subtitle strings.
- **Validation**:
  - `shellcheck scripts/lib/script_filter_query_policy.sh`
  - `bash -n scripts/lib/script_filter_query_policy.sh`

### Task 1.4: Define packaging strategy for shared runtime helper
- **Location**:
  - `scripts/workflow-pack.sh`
  - `docs/specs/script-filter-input-policy.md`
- **Description**: Ensure packaged workflows can resolve shared helper without repo-relative paths (copy/sync into package stage or provide deterministic fallback path resolution).
- **Dependencies**:
  - Task 1.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Packaging flow guarantees helper availability for installed `.alfredworkflow`.
  - Strategy is documented with explicit source and staged destination paths.
- **Validation**:
  - `rg -n "script_filter_query_policy" scripts/workflow-pack.sh docs/specs/script-filter-input-policy.md`
  - `scripts/workflow-pack.sh --id google-search`
  - `scripts/workflow-pack.sh --id youtube-search`
  - `scripts/workflow-pack.sh --id wiki-search`
  - `scripts/workflow-pack.sh --id codex-cli`
  - `test -f build/workflows/google-search/pkg/scripts/lib/script_filter_query_policy.sh`
  - `test -f build/workflows/youtube-search/pkg/scripts/lib/script_filter_query_policy.sh`
  - `test -f build/workflows/wiki-search/pkg/scripts/lib/script_filter_query_policy.sh`
  - `test -f build/workflows/codex-cli/pkg/scripts/lib/script_filter_query_policy.sh`

## Sprint 2: Workflow behavior migration (shared first, then specialization)
**Goal**: Migrate target script filters to shared helper while preserving each workflow contract and UX.
**Demo/Validation**:
- Command(s): `bash workflows/google-search/tests/smoke.sh`, `bash workflows/youtube-search/tests/smoke.sh`, `bash workflows/wiki-search/tests/smoke.sh`, `bash workflows/codex-cli/tests/smoke.sh`
- Verify: Short-query policy works and no workflow contract regressions occur.

### Task 2.1: Refactor gg/yt/wk script filters to shared query policy helper
- **Location**:
  - `workflows/google-search/scripts/script_filter.sh`
  - `workflows/youtube-search/scripts/script_filter.sh`
  - `workflows/wiki-search/scripts/script_filter.sh`
- **Description**: Replace duplicated query normalization/length checks with shared helper usage, then gate API calls until query length meets the policy minimum (`2`).
- **Dependencies**:
  - Task 1.3
  - Task 1.4
- **Complexity**: 7
- **Acceptance criteria**:
  - For `gg`/`yt`/`wk`, `<2` query characters produce valid non-actionable feedback and no backend CLI invocation.
  - Existing empty-query and error-mapping behaviors remain valid.
- **Validation**:
  - `bash workflows/google-search/tests/smoke.sh`
  - `bash workflows/youtube-search/tests/smoke.sh`
  - `bash workflows/wiki-search/tests/smoke.sh`
  - `shellcheck workflows/google-search/scripts/script_filter.sh workflows/youtube-search/scripts/script_filter.sh workflows/wiki-search/scripts/script_filter.sh`

### Task 2.2: Apply command-aware short-query gating in codex-cli
- **Location**:
  - `workflows/codex-cli/scripts/script_filter.sh`
  - `workflows/codex-cli/scripts/script_filter_auth.sh`
  - `workflows/codex-cli/scripts/script_filter_auth_current.sh`
  - `workflows/codex-cli/scripts/script_filter_auth_use.sh`
  - `workflows/codex-cli/scripts/script_filter_diag.sh`
  - `workflows/codex-cli/scripts/script_filter_diag_all.sh`
  - `workflows/codex-cli/scripts/script_filter_save.sh`
- **Description**: Keep empty/help palette rows intact, but avoid expensive sub-operations on short partial tokens (`<2`) for auth/use/save/diag branches until query intent is sufficiently specific.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 8
- **Acceptance criteria**:
  - `cx` with empty query still renders default actionable rows.
  - Short partial tokens no longer trigger expensive `codex-cli` refresh/read branches.
  - Existing alias behavior (`cxa`, `cxac`, `cxau`, `cxd`, `cxda`, `cxs`) remains functionally correct.
- **Validation**:
  - `bash workflows/codex-cli/tests/smoke.sh`
  - `shellcheck workflows/codex-cli/scripts/script_filter.sh workflows/codex-cli/scripts/script_filter_auth.sh workflows/codex-cli/scripts/script_filter_auth_current.sh workflows/codex-cli/scripts/script_filter_auth_use.sh workflows/codex-cli/scripts/script_filter_diag.sh workflows/codex-cli/scripts/script_filter_diag_all.sh workflows/codex-cli/scripts/script_filter_save.sh`

### Task 2.3: Update workflow contracts for new minimum-query behavior
- **Location**:
  - `crates/brave-cli/docs/workflow-contract.md`
  - `crates/youtube-cli/docs/workflow-contract.md`
  - `crates/wiki-cli/docs/workflow-contract.md`
  - `workflows/codex-cli/README.md`
  - `TROUBLESHOOTING.md`
- **Description**: Document `<2` query handling semantics and operator guidance so runtime behavior, docs, and troubleshooting stay aligned.
- **Dependencies**:
  - Task 2.1
  - Task 2.2
- **Complexity**: 4
- **Acceptance criteria**:
  - Contracts mention short-query gating before remote/expensive execution.
  - Troubleshooting includes expected short-query feedback behavior.
- **Validation**:
  - `rg -n "min(imum)? query|<2|short query|keep typing" crates/brave-cli/docs/workflow-contract.md crates/youtube-cli/docs/workflow-contract.md crates/wiki-cli/docs/workflow-contract.md workflows/codex-cli/README.md TROUBLESHOOTING.md`

## Sprint 3: Queue settings rollout and enforcement
**Goal**: Set 1-second delay + disable initial immediate run for all target Script Filter objects, then lock with tests.
**Demo/Validation**:
- Command(s): `scripts/workflow-pack.sh --id google-search`, `scripts/workflow-pack.sh --id youtube-search`, `scripts/workflow-pack.sh --id wiki-search`, `scripts/workflow-pack.sh --id codex-cli`
- Verify: Packaged plists reflect policy values for each target Script Filter object.

### Task 3.1: Build a shared queue-policy sync/check tool
- **Location**:
  - `scripts/workflow-sync-script-filter-policy.sh`
  - `docs/specs/script-filter-input-policy.json`
- **Description**: Implement one command that applies or checks queue-delay/immediate settings in workflow plist templates from the shared policy file.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Tool supports `--check` (non-mutating) and `--apply` (mutating) modes.
  - Tool can target a subset (`google-search`, `youtube-search`, `wiki-search`, `codex-cli`) deterministically.
- **Validation**:
  - `bash scripts/workflow-sync-script-filter-policy.sh --check --workflows google-search,youtube-search,wiki-search,codex-cli`
  - `bash scripts/workflow-sync-script-filter-policy.sh --apply --workflows google-search,youtube-search,wiki-search,codex-cli`

### Task 3.2: Apply queue policy to target plist templates
- **Location**:
  - `workflows/google-search/src/info.plist.template`
  - `workflows/youtube-search/src/info.plist.template`
  - `workflows/wiki-search/src/info.plist.template`
  - `workflows/codex-cli/src/info.plist.template`
- **Description**: Update all target Script Filter nodes to policy values (`delay=1s`, `immediate_initial=false`) through the shared sync pipeline.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Every target Script Filter object in the listed templates uses identical policy-driven queue settings.
  - No non-target object is modified unexpectedly.
- **Validation**:
  - `bash scripts/workflow-sync-script-filter-policy.sh --check --workflows google-search,youtube-search,wiki-search,codex-cli`
  - `rg -n "queuedelaycustom|queuedelayimmediatelyinitially" workflows/google-search/src/info.plist.template workflows/youtube-search/src/info.plist.template workflows/wiki-search/src/info.plist.template workflows/codex-cli/src/info.plist.template`

### Task 3.3: Extend smoke tests to enforce queue policy
- **Location**:
  - `workflows/google-search/tests/smoke.sh`
  - `workflows/youtube-search/tests/smoke.sh`
  - `workflows/wiki-search/tests/smoke.sh`
  - `workflows/codex-cli/tests/smoke.sh`
- **Description**: Add explicit assertions for queue settings (`queuedelaycustom`, `queuedelaymode`, `queuedelayimmediatelyinitially`) for all target Script Filter objects.
- **Dependencies**:
  - Task 3.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Smoke tests fail when queue policy drifts.
  - `codex-cli` test validates all seven Script Filter objects, not only one UID.
- **Validation**:
  - `bash workflows/google-search/tests/smoke.sh`
  - `bash workflows/youtube-search/tests/smoke.sh`
  - `bash workflows/wiki-search/tests/smoke.sh`
  - `bash workflows/codex-cli/tests/smoke.sh`

## Sprint 4: Integrated verification and rollout safety
**Goal**: Prove no regressions in lint/build/test/package and provide operator rollback confidence.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `scripts/workflow-test.sh --id google-search`, `scripts/workflow-test.sh --id youtube-search`, `scripts/workflow-test.sh --id wiki-search`, `scripts/workflow-test.sh --id codex-cli`
- Verify: All quality gates pass with policy and behavior changes in place.

### Task 4.1: Run full quality gates for touched workflows
- **Location**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `workflows/google-search/tests/smoke.sh`
  - `workflows/youtube-search/tests/smoke.sh`
  - `workflows/wiki-search/tests/smoke.sh`
  - `workflows/codex-cli/tests/smoke.sh`
- **Description**: Execute lint + targeted workflow tests and capture any regressions introduced by shared-policy migration.
- **Dependencies**:
  - Task 2.3
  - Task 3.3
- **Complexity**: 4
- **Acceptance criteria**:
  - Lint and all targeted smoke tests pass.
  - No malformed Alfred JSON regressions in script filter outputs.
- **Validation**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh --id google-search`
  - `scripts/workflow-test.sh --id youtube-search`
  - `scripts/workflow-test.sh --id wiki-search`
  - `scripts/workflow-test.sh --id codex-cli`

### Task 4.2: Package-level verification for all target workflows
- **Location**:
  - `scripts/workflow-pack.sh`
  - `build/workflows/google-search/pkg/info.plist`
  - `build/workflows/youtube-search/pkg/info.plist`
  - `build/workflows/wiki-search/pkg/info.plist`
  - `build/workflows/codex-cli/pkg/info.plist`
- **Description**: Build packaged artifacts and validate rendered plist values are consistent with policy (not only source templates).
- **Dependencies**:
  - Task 4.1
- **Complexity**: 3
- **Acceptance criteria**:
  - Packaged plist values match policy for all target objects.
  - Artifacts are generated without packaging regressions.
- **Validation**:
  - `scripts/workflow-pack.sh --id google-search`
  - `scripts/workflow-pack.sh --id youtube-search`
  - `scripts/workflow-pack.sh --id wiki-search`
  - `scripts/workflow-pack.sh --id codex-cli`
  - `plutil -convert json -o - build/workflows/google-search/pkg/info.plist | jq -e '[.objects[] | select(.type=="alfred.workflow.input.scriptfilter") | .config.queuedelayimmediatelyinitially] | all(. == false)'`
  - `plutil -convert json -o - build/workflows/youtube-search/pkg/info.plist | jq -e '[.objects[] | select(.type=="alfred.workflow.input.scriptfilter") | .config.queuedelayimmediatelyinitially] | all(. == false)'`
  - `plutil -convert json -o - build/workflows/wiki-search/pkg/info.plist | jq -e '[.objects[] | select(.type=="alfred.workflow.input.scriptfilter") | .config.queuedelayimmediatelyinitially] | all(. == false)'`
  - `plutil -convert json -o - build/workflows/codex-cli/pkg/info.plist | jq -e '[.objects[] | select(.type=="alfred.workflow.input.scriptfilter") | .config.queuedelayimmediatelyinitially] | all(. == false)'`

### Task 4.3: Manual UX regression pass in Alfred
- **Location**:
  - `TROUBLESHOOTING.md`
  - `workflows/google-search/README.md`
  - `workflows/youtube-search/README.md`
  - `workflows/wiki-search/README.md`
  - `workflows/codex-cli/README.md`
- **Description**: Run manual checks for typing cadence and UX messaging (`<2 chars`, empty query, known commands, diag aliases), and document expected behavior.
- **Dependencies**:
  - Task 4.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Manual checklist confirms no broken command path for `cx*`.
  - User-facing docs describe the new 1-second delay and short-query behavior clearly.
- **Validation**:
  - `rg -n "1 second|short query|min query|<2" workflows/google-search/README.md workflows/youtube-search/README.md workflows/wiki-search/README.md workflows/codex-cli/README.md TROUBLESHOOTING.md`

## Testing Strategy
- Unit:
  - Add helper-level tests (where practical) for query normalization and minimum-length decisions.
  - Keep existing CLI crate tests unchanged unless contract text changes require updates.
- Integration:
  - Use per-workflow smoke tests to verify Script Filter JSON output and packaged plist keys.
  - Add assertions ensuring short queries do not dispatch expensive backend calls.
- E2E/manual:
  - Install packaged workflows and verify typing behavior in Alfred for `gg`, `yt`, `wk`, `cx`, `cxau`, `cxd`, `cxda`.

## Risks & gotchas
- `queuedelaycustom` numeric mapping may be misinterpreted without explicit Alfred-export validation.
- Applying `<2` query gating too broadly in `codex-cli` can break legitimate command discovery/use flows.
- Shared helper packaging path errors can pass local tests but fail in installed `.alfredworkflow`.
- Policy drift risk remains if new workflows add Script Filters without policy-tool enforcement.

## Rollback plan
- Revert policy-enforcement commits for:
  - `scripts/workflow-sync-script-filter-policy.sh`
  - `scripts/lib/script_filter_query_policy.sh`
  - target `info.plist.template` queue changes
  - short-query gating changes in target script filters
  - smoke-test assertions added for new policy
- Re-run pre-change validation baseline:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh --id google-search`
  - `scripts/workflow-test.sh --id youtube-search`
  - `scripts/workflow-test.sh --id wiki-search`
  - `scripts/workflow-test.sh --id codex-cli`
- Confirm packaged artifacts return to prior behavior by rebuilding all four target workflows.
