# Google Service UI Smoke Isolation Improvement Record

- Status: ready for planning
- Date: 2026-05-22
- Source type: review-to-improvement-doc
- Retention intent: temporary plan source; clean up or promote after execution

## Purpose

Preserve the review finding that the `google-service` smoke test can invoke
local UI integrations while validating Gmail-related actions. The future fix
should keep the runtime behavior intact, but make the smoke harness
deterministic and side-effect-free.

## Current judgment

This is a test isolation bug, not a runtime bug. The Google Service workflow
intentionally opens Gmail, Drive, and Alfred requery surfaces at runtime. The
smoke test already stubs `google-cli` and test data, but it does not stub macOS
UI commands used by `action_open.sh`. Running the smoke test can therefore
touch the developer's real Alfred, browser, notifications, and clipboard.

## Findings

### P1: Action tokens lack UI stubs

- Issue: `google-service` smoke invokes action tokens without stubbing local UI
  commands.
- Evidence: `workflows/google-service/tests/smoke.sh` creates a stub
  `google-cli` and isolated config/data, then invokes `action_open.sh` for
  prompt, Drive open, and Gmail open tokens.
- Gap: the test environment does not prepend a bin directory containing `open`,
  `osascript`, `pbcopy`, or `xdg-open` stubs for those calls.
- Fix location: `workflows/google-service/tests/smoke.sh`.
- Acceptance: smoke test runs without opening Alfred, browser windows,
  notifications, dialogs, or changing the real clipboard.

### P1: Gmail prompt rows can trigger Alfred

- Issue: Gmail prompt rows can trigger real Alfred search during tests.
- Evidence: `prompt::mail-unread` and `prompt::mail-unread-account::*` in
  `workflows/google-service/scripts/action_open.sh` call
  `open_alfred_search_best_effort`, which uses `osascript`.
- Fix location: `workflows/google-service/tests/smoke.sh`, optionally
  `scripts/lib/workflow_smoke_helpers.sh`.
- Acceptance: test asserts the intended Alfred query through an `osascript` stub
  log instead of executing AppleScript against local Alfred.

### P2: Open actions can trigger the real browser

- Issue: Gmail and Drive open actions can open real browser URLs during tests.
- Evidence: `gmail-open-home`, `gmail-open-search::*`,
  `gmail-open-message::*`, `drive-open-home`, and `drive-open-search::*` call
  `open_url_best_effort`.
- Runtime detail: `open_url_best_effort` prefers `open` and falls back to
  `xdg-open`.
- Fix location: `workflows/google-service/tests/smoke.sh`.
- Acceptance: test asserts expected Gmail/Drive URLs through opener stub logs.

### P2: Existing repo pattern should be reused

- Issue: the repo already has an isolation pattern that this smoke test should
  follow.
- Evidence: other workflow smoke tests use `workflow_smoke_write_open_stub` and
  `PATH="$tmp_dir/bin:$PATH"`; `workflow_action_requery` tests stub
  `osascript`.
- Fix location: `scripts/lib/workflow_smoke_helpers.sh` and
  `scripts/tests/workflow_smoke_helpers.test.sh`.
- Acceptance: Google Service smoke uses the shared helper pattern or an
  equivalent local stub pattern consistently.

## Ownership boundary

- Runtime behavior: keep. Alfred requery, URL opening, notifications,
  confirmation dialogs, and clipboard operations are part of user-facing action
  behavior.
- Test harness behavior: fix. Smoke tests must replace UI commands with stubs before invoking action paths.
- Google API behavior: already isolated in this smoke test through a stub
  `google-cli`; do not change native Gmail/Drive client behavior for this
  issue.

## Backlog

1. Add or reuse smoke helper stubs for UI command isolation:
   - `open`
   - `xdg-open`
   - `osascript`
   - `pbcopy`
2. Update `workflows/google-service/tests/smoke.sh` so every `action_open.sh` invocation that can hit UI runs with the stubbed `PATH`.
3. Assert meaningful side effects through stub logs:
   - Alfred requery text for prompt rows.
   - Gmail/Drive URLs for open rows.
   - copied remote state for login step 1 when relevant.
   - notification/dialog invocations are intercepted and do not require user interaction.
4. Run focused and repo-appropriate validation.

## Execution

- Recommended plan: docs/plans/google-service-ui-smoke-isolation/google-service-ui-smoke-isolation-plan.md
- Recommended execution state: docs/plans/google-service-ui-smoke-isolation/google-service-ui-smoke-isolation-execution-state.md
- Next-task source: fix the smoke harness only; do not remove runtime Alfred/Gmail open behavior.

## Validation gate

Minimum validation after implementation:

- `bash workflows/google-service/tests/smoke.sh`
- `bash scripts/tests/workflow_smoke_helpers.test.sh`
- `scripts/workflow-test.sh --id google-service --skip-third-party-audit --skip-workspace-tests`

Broader validation when preparing the final commit or PR:

- `scripts/local-pre-commit.sh`

## Guardrails

- Do not disable `open_alfred_search_best_effort` or `open_url_best_effort` in runtime code just to satisfy the smoke test.
- Do not make the test depend on whether Alfred, a browser, or a desktop session is available.
- Do not write to real `$HOME`, real Alfred workflow data, or real Google CLI config.
- Do not include credentials, OAuth tokens, local account secrets, or raw private logs in test fixtures or issue snapshots.

## Open questions

- None. The observed behavior is sufficiently classified for a small test-harness fix.
