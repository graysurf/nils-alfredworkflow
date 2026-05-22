# Plan: Google Service UI Smoke Isolation

## Overview

Make the `google-service` workflow smoke test deterministic by stubbing local UI
commands before exercising action paths. The runtime behavior should remain
unchanged: Gmail/Drive open actions still open URLs, prompt actions still
requery Alfred, and auth actions still notify/copy when run by a user. The plan
narrows the implementation to test harness isolation and validation.

## Read First

- Primary source: docs/plans/google-service-ui-smoke-isolation/google-service-ui-smoke-isolation-review-source.md
- Source type: review-to-improvement-doc
- Open questions carried into execution: none

## Scope

- In scope: smoke-test stubs for `google-service` action paths; focused
  assertions for intercepted Alfred/browser/clipboard behavior; helper tests
  when shared helpers are added.
- Out of scope: changing Google API behavior, changing user-facing action
  behavior, redesigning `google-service` auth/Gmail/Drive flows, or adding live
  Alfred acceptance automation.

## Assumptions

1. The desired runtime behavior is unchanged: selected Gmail and Drive rows may open browser URLs, and prompt rows may requery Alfred.
2. The smoke test should be safe to run from CI, local terminal sessions, and developer machines where Alfred is installed.
3. Existing smoke helper patterns are preferred over workflow-local ad hoc stubs when a helper is generally reusable.

## Sprint 1: Isolate UI Side Effects

**Goal**: Replace local UI side effects in the `google-service` smoke test with deterministic stub logs.
**Demo/Validation**:

- Command(s): `bash workflows/google-service/tests/smoke.sh`
- Verify: the smoke passes without opening Alfred, browser windows, notifications, dialogs, or changing the real clipboard.

**PR grouping intent**: per-sprint
**Execution Profile**: serial

### Task 1.1: Add reusable UI smoke stubs

- **Location**:
  - `scripts/lib/workflow_smoke_helpers.sh`
  - `scripts/tests/workflow_smoke_helpers.test.sh`
- **Description**: Add shared helpers, or extend existing helpers, so smoke
  tests can stub `osascript`, `pbcopy`, and optional URL opener fallbacks with
  log files. Keep the existing `workflow_smoke_write_open_stub` behavior
  compatible.
- **Dependencies**:
  - none
- **Complexity**: 2
- **Acceptance criteria**:
  - A smoke helper can intercept AppleScript invocations and record the requested script text.
  - A smoke helper can intercept clipboard writes and record copied content.
  - Helper tests cover the new stub behavior without invoking local UI commands.
- **Validation**:
  - `bash scripts/tests/workflow_smoke_helpers.test.sh`

### Task 1.2: Wire stubs into Google Service smoke actions

- **Location**:
  - `workflows/google-service/tests/smoke.sh`
- **Description**: Ensure every `action_open.sh` invocation in the Google
  Service smoke runs with a stubbed `PATH` that catches `open`, `xdg-open`,
  `osascript`, and `pbcopy`. Keep the existing `google-cli` fixture and
  isolated `GOOGLE_CLI_CONFIG_DIR`, `ALFRED_WORKFLOW_DATA`, and `HOME` setup.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 3
- **Acceptance criteria**:
  - Prompt action tokens record expected Alfred search text instead of controlling local Alfred.
  - Gmail and Drive open action tokens record expected URLs instead of opening a real browser.
  - Remote login step 1 records copied state through a stub instead of writing to the real clipboard.
  - Existing Gmail unread/latest/search fixture assertions still pass.
- **Validation**:
  - `bash workflows/google-service/tests/smoke.sh`

### Task 1.3: Validate focused workflow gate

- **Location**:
  - `scripts/workflow-test.sh`
  - `DEVELOPMENT.md`
  - `workflows/google-service/README.md`
- **Description**: Run the focused workflow gate and update docs only if the
  validation command list needs to mention the new isolation assumption. Avoid
  broad documentation churn when the existing validation docs remain accurate.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 1
- **Acceptance criteria**:
  - Focused workflow validation passes for `google-service`.
  - Documentation remains accurate about smoke validation.
  - No runtime behavior is removed to make the test pass.
- **Validation**:
  - `scripts/workflow-test.sh --id google-service --skip-third-party-audit --skip-workspace-tests`

## Testing Strategy

- Unit: `bash scripts/tests/workflow_smoke_helpers.test.sh` if shared helper behavior changes.
- Integration: `bash workflows/google-service/tests/smoke.sh`.
- Workflow gate: `scripts/workflow-test.sh --id google-service --skip-third-party-audit --skip-workspace-tests`.
- Manual: not required for the test-harness fix; manual Alfred acceptance can be reserved for release/package validation.

## Risks & gotchas

- Stubbing `osascript` must not accidentally mask command failures in non-UI
  code paths; assertions should check the expected AppleScript payloads.
- `action_open.sh` also uses `osascript` for notifications and confirmation dialogs, so logs may include multiple AppleScript shapes.
- `open_url_best_effort` can fall back to `xdg-open`; local and CI environments should both be covered by the stubbed `PATH`.
- Keep generated or temporary stub logs under the smoke temp directory, not under repo paths.

## Rollback plan

- Revert changes to the smoke harness and helper tests.
- Re-run `bash workflows/google-service/tests/smoke.sh` to confirm the previous
  behavior is restored, while noting that the restored behavior may again touch
  local UI.
