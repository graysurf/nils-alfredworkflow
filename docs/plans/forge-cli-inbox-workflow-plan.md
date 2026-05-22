# Plan: forge-cli Inbox Alfred Workflow

## Overview

Add a focused Alfred workflow that renders the existing `forge-cli inbox`
JSON contract as a personal work inbox. The workflow should not query GitHub or
GitLab directly; it parses `forge-cli inbox list --format json`, applies Alfred
provider/item/text filters, renders rows, and opens or copies item URLs.

The source design is already settled: provider modes are `gh`, `glab`, and
`all`; item modes are `pr`, `issue`, and `all`; the primary keyword is `fi`;
and v1 uses an external `forge-cli` runtime resolved from `FORGE_CLI_BIN` or
`PATH`.

## Read First

- Primary source: docs/plans/forge-cli-inbox-workflow-discussion-source.md
- Source type: discussion-to-implementation-doc
- Open questions carried into execution: none

## Scope

- In scope:
  - A new `workflows/forge-inbox/` workflow with `workflow.toml`,
    `README.md`, `TROUBLESHOOTING.md`, Script Filter, action script, and smoke
    tests.
  - `FORGE_CLI_BIN` / `PATH` runtime resolution for `forge-cli`.
  - Provider mode parsing and CLI argv construction.
  - Item mode filtering from normalized `source` values and classifiable todo
    URLs.
  - Partial-failure warning rows, host-missing fallback rows, empty rows, and
    invalid/error envelope fallback rows.
  - Focused workflow validation and docs placement/lint checks.
- Out of scope:
  - Changing `forge-cli`.
  - Calling `gh`, `glab`, or provider REST APIs directly from Alfred scripts.
  - Mutating PRs, MRs, issues, todos, labels, assignments, comments, or review
    state.
  - Packaging a `forge-cli` binary in v1.
  - Persistent caching.

## Assumptions

1. `forge-cli inbox list --format json` remains the stable row source.
2. The workflow can rely on a user-installed `forge-cli` from `FORGE_CLI_BIN`
   or `PATH` for v1.
3. Mixed mode without `FORGE_INBOX_GITLAB_HOST` should still be useful by
   showing GitHub-only results plus a GitLab configuration warning row.
4. Shell smoke tests with a stubbed `FORGE_CLI_BIN` are sufficient for CI-safe
   validation; live Alfred acceptance can be reserved for packaging/release.

## Sprint 1: Build Forge Inbox Workflow

**Goal**: Ship a complete Alfred workflow that renders `forge-cli inbox`
results across provider and item modes without duplicating provider logic.
**Demo/Validation**:

- Command(s):
  - `bash workflows/forge-inbox/tests/smoke.sh`
  - `bash scripts/workflow-lint.sh --id forge-inbox`
  - `scripts/workflow-test.sh --id forge-inbox --skip-workspace-tests`
- Verify: all nine provider/item mode combinations are covered by smoke
  fixtures, no direct `gh`/`glab` calls appear in workflow scripts, and error
  states render valid Alfred JSON.

**PR grouping intent**: per-sprint
**Execution Profile**: serial

### Task 1.1: Scaffold workflow surface and docs

- **Location**:
  - `workflows/forge-inbox/workflow.toml`
  - `workflows/forge-inbox/README.md`
  - `workflows/forge-inbox/TROUBLESHOOTING.md`
  - `workflows/forge-inbox/scripts/script_filter.sh`
  - `workflows/forge-inbox/scripts/action_open.sh`
- **Description**: Add the workflow shell and user-facing docs. Define keyword
  `fi`, env vars, external `forge-cli` runtime resolution, and the read-only
  open/copy action model. Omit `rust_binary` from the manifest.
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - `workflow.toml` declares `id = "forge-inbox"` and no `rust_binary`.
  - README documents provider modes, item modes, env vars, and query examples.
  - Troubleshooting doc has the four canonical workflow sections.
  - Script Filter and action script always emit/operator-report useful errors
    when `forge-cli` is missing.
- **Validation**:
  - `bash scripts/docs-placement-audit.sh --strict`

### Task 1.2: Implement Script Filter parsing and row rendering

- **Location**:
  - `workflows/forge-inbox/scripts/script_filter.sh`
- **Description**: Implement mode parsing, `forge-cli inbox list` argv
  construction, JSON envelope parsing, item-type filtering, local text
  filtering, warning rows, and empty/error rows. Preserve CLI row order after
  filtering.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 5
- **Acceptance criteria**:
  - `fi gh pr`, `fi gh issue`, `fi glab pr`, `fi glab issue`, and
    `fi all all` render the expected filtered rows from fixture envelopes.
  - Mixed mode without `FORGE_INBOX_GITLAB_HOST` invokes GitHub-only CLI mode
    and renders a GitLab host warning row.
  - GitLab-only mode without `FORGE_INBOX_GITLAB_HOST` emits a config row and
    does not invoke `forge-cli`.
  - Provider warnings are rendered from `data.providers[].error`, while
    top-level `warnings[]` is tolerated as supplemental text.
  - PR/issue modes never map to `forge-cli --kind pr` or `--kind issue`.
- **Validation**:
  - `bash workflows/forge-inbox/tests/smoke.sh`

### Task 1.3: Implement actions and smoke coverage

- **Location**:
  - `workflows/forge-inbox/scripts/action_open.sh`
  - `workflows/forge-inbox/tests/smoke.sh`
- **Description**: Implement URL open and copy-style action tokens, then add
  fixture-backed smoke tests for mode combinations, host handling, warning
  parsing, empty results, malformed JSON, and action token behavior.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 4
- **Acceptance criteria**:
  - Enter opens the selected URL through stubbed opener commands in smoke.
  - Copy URL and markdown reference actions are newline-safe.
  - Smoke tests assert no direct `gh` or `glab` calls appear in workflow
    scripts.
  - Smoke tests prove GitLab `gitlab_todos` URL classification:
    `/-/merge_requests/9` appears in PR mode, `/-/issues/8` appears in issue mode, and
    `/-/commit/abc123` appears only in all mode.
- **Validation**:
  - `bash workflows/forge-inbox/tests/smoke.sh`

### Task 1.4: Run workflow and repository gates

- **Location**:
  - `workflows/forge-inbox/workflow.toml`
  - `workflows/forge-inbox/README.md`
  - `workflows/forge-inbox/TROUBLESHOOTING.md`
  - `workflows/forge-inbox/scripts/script_filter.sh`
  - `workflows/forge-inbox/scripts/action_open.sh`
  - `workflows/forge-inbox/tests/smoke.sh`
  - `docs/plans/forge-cli-inbox-workflow-discussion-source.md`
  - `docs/plans/forge-cli-inbox-workflow-plan.md`
  - `docs/plans/forge-cli-inbox-workflow-execution-state.md`
- **Description**: Run focused workflow gates, plan/docs checks, specialist
  review, and final repository validation appropriate for the changed scope.
  Update execution state and issue evidence with commands and outcomes.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 2
- **Acceptance criteria**:
  - `plan-tooling validate` passes for the plan bundle.
  - `bash scripts/ci/markdownlint-audit.sh --strict` passes.
  - `bash scripts/docs-placement-audit.sh --strict` passes.
  - `bash scripts/workflow-lint.sh --id forge-inbox` passes.
  - `scripts/workflow-test.sh --id forge-inbox --skip-workspace-tests` passes.
  - Mandatory delivery specialist review has no unresolved concrete findings.
- **Validation**:
  - `plan-tooling validate --file docs/plans/forge-cli-inbox-workflow-plan.md --format text --explain`
  - `bash scripts/ci/markdownlint-audit.sh --strict`
  - `bash scripts/docs-placement-audit.sh --strict`
  - `bash scripts/workflow-lint.sh --id forge-inbox`
  - `scripts/workflow-test.sh --id forge-inbox --skip-workspace-tests`

## Testing Strategy

- Unit-like shell coverage: `bash workflows/forge-inbox/tests/smoke.sh` with a
  stubbed `FORGE_CLI_BIN`.
- Workflow lint: `bash scripts/workflow-lint.sh --id forge-inbox`.
- Workflow gate: `scripts/workflow-test.sh --id forge-inbox --skip-workspace-tests`.
- Docs and plan checks:
  - `plan-tooling validate --file docs/plans/forge-cli-inbox-workflow-plan.md --format text --explain`
  - `bash scripts/ci/markdownlint-audit.sh --strict`
  - `bash scripts/docs-placement-audit.sh --strict`
  - `git diff --check`
- Live smoke: optional during implementation, using
  `forge-cli inbox status --gitlab-host gitlab.gamania.com`; user already
  reported a successful command on 2026-05-22.

## Risks & gotchas

- Mapping PR/issue mode to `forge-cli --kind` would be wrong because `--kind`
  is a reason filter. Smoke tests must assert this never happens.
- GitLab host defaults are dangerous outside a Git repository. Mixed mode
  without `FORGE_INBOX_GITLAB_HOST` must degrade to GitHub-only plus a warning;
  GitLab-only mode must avoid calling `forge-cli`.
- GitLab todos do not currently expose a normalized target type. URL
  classification must be conservative and unclassified todos should appear only
  in `all` mode.
- Live provider queries can be slow. Keep `FORGE_INBOX_LIMIT` bounded and defer
  persistent cache until measured latency justifies it.
- `forge-cli` is external in v1, so package validation should not expect a
  bundled binary.

## Rollback plan

- Remove `workflows/forge-inbox/` and any generated package/build artifacts.
- Revert plan/source/execution-state updates for this feature.
- Re-run `bash scripts/docs-placement-audit.sh --strict` and
  `bash scripts/ci/markdownlint-audit.sh --strict`.
