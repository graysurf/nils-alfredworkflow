# Plan: Memo Workflow Update/Delete Support (nils-memo-cli 0.3.5)

## Overview
This plan extends `memo-add` from append-only capture to full raw memo mutation support in Alfred:
`create(add)`, `update`, and `delete`.
The implementation keeps existing `mm <text>` add behavior intact, while adding explicit query intents
for update/delete and new action-token handling in `memo-workflow-cli`.
Testing is centered on isolated SQLite databases created per test case so CRUD behavior can be validated
without cross-test contamination or dependence on user/local memo state.

## Scope
- In scope: add workflow-side support for `update` and `delete` backed by `nils-memo-cli@0.3.5`.
- In scope: keep existing `add`, `db-init`, and recent-list behavior backward compatible.
- In scope: extend action token contract and parser for update/delete operations.
- In scope: add deterministic CRUD tests using a fresh standalone test DB for each run/case.
- In scope: update workflow docs/contract/testing checklists to include update/delete flows.
- Out of scope: soft delete, undo/restore UX, or historical version browsing.
- Out of scope: bulk operations (multi-row update/delete) from Alfred UI.
- Out of scope: schema redesign inside `nils-memo-cli`; workflow remains an adapter layer.

## Assumptions (if any)
1. Workflow ID and keyword remain unchanged (`memo-add`, `mm`).
2. `nils-memo-cli = "=0.3.5"` remains pinned and already includes stable `update`/`delete` commands.
3. Workflow delete behavior follows upstream hard-delete semantics (no soft-delete fallback).
4. Query-to-action mapping is explicit: add remains default, update/delete require command prefixes.
5. CI/dev environments can create temporary directories and run SQLite-backed tests.

## Success Criteria
- Users can execute add/create, update, and delete from one workflow without breaking existing add flow.
- `memo-workflow-cli action --token ...` can execute three mutation paths (`add`, `update`, `delete`) deterministically.
- CRUD integration tests pass using an isolated brand-new test DB per test.
- Workflow docs and operator checklist clearly describe update/delete syntax and safety semantics.
- Required repo checks pass for changed scope (`workflow-lint`, `cargo test`, `workflow-test`, `workflow-pack`).

## Dependency & Parallelization Map
- Critical path:
  - `Task 1.1 -> Task 1.2 -> Task 2.1 -> Task 2.2 -> Task 2.3 -> Task 3.1 -> Task 3.3 -> Task 4.1`.
- Parallel track A:
  - `Task 1.3` can run after `Task 1.1` and in parallel with `Task 2.1`.
- Parallel track B:
  - `Task 2.4` can run after `Task 2.2` in parallel with `Task 3.2`.
- Parallel track C:
  - `Task 3.4` can run after `Task 3.1` in parallel with `Task 4.1`.

## Sprint 1: Contract and interaction design
**Goal**: Freeze user-visible mutation contract and define safe token/query grammar before code changes.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/memo-workflow-update-delete-plan.md`, `rg -n "update|delete|db init|token" crates/memo-workflow-cli/docs/workflow-contract.md`
- Verify: contract documents update/delete behavior, token schema, and failure mapping.

### Task 1.1: Update memo workflow contract for CRUD behavior
- **Location**:
  - `crates/memo-workflow-cli/docs/workflow-contract.md`
  - `docs/WORKFLOW_GUIDE.md`
  - `workflows/memo-add/README.md`
- **Description**: Replace append-only limitation notes with explicit `add/update/delete` contract, including hard-delete semantics and usage examples.
- **Dependencies**:
  - none
- **Complexity**: 4
- **Acceptance criteria**:
  - Runtime commands section includes `update` and `delete`.
  - Action token contract includes token names and payload format for update/delete.
  - Delete behavior clearly states hard-delete and expected user error for invalid `item_id`.
- **Validation**:
  - `rg -n "Runtime commands|Action token contract|update|delete|hard-delete" crates/memo-workflow-cli/docs/workflow-contract.md`
  - `rg -n "Memo Add workflow details|update|delete" docs/WORKFLOW_GUIDE.md workflows/memo-add/README.md`

### Task 1.2: Define query-intent grammar and token encoding strategy
- **Location**:
  - `crates/memo-workflow-cli/src/lib.rs`
  - `crates/memo-workflow-cli/docs/workflow-contract.md`
- **Description**: Define deterministic grammar (`add` default, `update`/`delete` prefixed intents) and token encoding rules that avoid delimiter ambiguity for update text payloads.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 6
- **Acceptance criteria**:
  - Query parser can disambiguate add vs update vs delete without hidden heuristics.
  - Token format is documented and reversible for all valid UTF-8 text inputs.
  - Invalid mutation syntax yields non-actionable Alfred guidance rows instead of crashes.
- **Validation**:
  - `cargo test -p nils-memo-workflow-cli -- --list | rg "token|intent|parse"`
  - `cargo test -p nils-memo-workflow-cli token_`

### Task 1.3: Define isolated test-DB protocol for CRUD
- **Location**:
  - `crates/memo-workflow-cli/tests/cli_contract.rs`
  - `workflows/memo-add/tests/smoke.sh`
- **Description**: Specify and codify per-test DB creation policy (`mktemp`/`tempdir`) and teardown rules to ensure create/update/delete tests never share state.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Every CRUD test creates a new DB file under a unique temp directory.
  - No test reads/writes default user DB path.
  - Test helper names and docs make DB isolation intent explicit.
- **Validation**:
  - `rg -n "tempdir|mktemp|MEMO_DB_PATH|isolated|unique" crates/memo-workflow-cli/tests/cli_contract.rs workflows/memo-add/tests/smoke.sh`
  - `rg -n "tempfile::tempdir|MEMO_DB_PATH" crates/memo-workflow-cli/tests/cli_contract.rs`
  - `cargo test -p nils-memo-workflow-cli crud_create_update_delete`

## Sprint 2: Rust adapter implementation (`update` + `delete`)
**Goal**: Add first-class update/delete command execution in `memo-workflow-cli` and wire action token routing.
**Demo/Validation**:
- Command(s): `cargo check -p nils-memo-workflow-cli`, `cargo run -p nils-memo-workflow-cli -- --help`
- Verify: CLI surface exposes update/delete and compiles with deterministic error mapping.

### Task 2.1: Extend CLI subcommands and result payloads
- **Location**:
  - `crates/memo-workflow-cli/src/main.rs`
- **Description**: Add `Update` and `Delete` subcommands (with `--item-id` and mode/db flags), plus text/json renderers aligned with existing envelope behavior.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 6
- **Acceptance criteria**:
  - `--help` shows `update` and `delete` commands.
  - JSON response envelopes remain `{ok,result,error}` for both new commands.
  - Exit codes preserve user/runtime split (`2` usage-like, `1` runtime).
- **Validation**:
  - `cargo run -p nils-memo-workflow-cli -- --help | rg "update|delete"`
  - `cargo test -p nils-memo-workflow-cli`

### Task 2.2: Implement `execute_update` and `execute_delete` domain paths
- **Location**:
  - `crates/memo-workflow-cli/src/lib.rs`
- **Description**: Add adapter functions that call `nils-memo-cli` storage/repository update/delete behavior, normalize item IDs, and map errors to workflow-safe messages.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 8
- **Acceptance criteria**:
  - Update rejects empty text and invalid item IDs with user-error exit semantics.
  - Delete path enforces hard-delete behavior and returns deterministic deleted metadata.
  - Successful update transitions item state back to pending semantics expected by upstream.
- **Validation**:
  - `tmpdir="$(mktemp -d)" && db="$tmpdir/memo.db" && add_json="$(cargo run -p nils-memo-workflow-cli -- add --db "$db" --text "before" --mode json)" && item_id="$(jq -r '.result.item_id' <<<"$add_json")" && cargo run -p nils-memo-workflow-cli -- update --db "$db" --item-id "$item_id" --text "after" --mode json | jq -e '.ok == true and .result.text == "after"'`
  - `tmpdir="$(mktemp -d)" && db="$tmpdir/memo.db" && add_json="$(cargo run -p nils-memo-workflow-cli -- add --db "$db" --text "to-delete" --mode json)" && item_id="$(jq -r '.result.item_id' <<<"$add_json")" && cargo run -p nils-memo-workflow-cli -- delete --db "$db" --item-id "$item_id" --mode json | jq -e '.ok == true and .result.deleted == true'`

### Task 2.3: Extend action token dispatcher for update/delete
- **Location**:
  - `crates/memo-workflow-cli/src/main.rs`
  - `crates/memo-workflow-cli/src/lib.rs`
- **Description**: Add token parser/dispatcher that routes `update` and `delete` tokens to new execution paths while preserving existing `add::` and `db-init` behavior.
- **Dependencies**:
  - Task 2.2
- **Complexity**: 7
- **Acceptance criteria**:
  - `action --token` supports add, db-init, update, and delete.
  - Unknown/malformed mutation token returns user-facing guidance error (not panic).
  - Existing add token roundtrip remains backward compatible.
- **Validation**:
  - `cargo test -p nils-memo-workflow-cli action_`
  - `cargo test -p nils-memo-workflow-cli token_`

### Task 2.4: Extend script-filter builder for update/delete intents
- **Location**:
  - `crates/memo-workflow-cli/src/lib.rs`
- **Description**: Map query prefixes to actionable Alfred rows for update/delete, including preview subtitles and guardrail messaging for missing arguments.
- **Dependencies**:
  - Task 2.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Update intent query produces actionable row with update token.
  - Delete intent query produces actionable row with delete token and safety subtitle.
  - Non-intent query remains default add behavior.
- **Validation**:
  - `cargo run -p nils-memo-workflow-cli -- script-filter --query "update itm_00000001 revised text" | jq -e '.items[0].arg | startswith("update::")'`
  - `cargo run -p nils-memo-workflow-cli -- script-filter --query "delete itm_00000001" | jq -e '.items[0].arg | startswith("delete::")'`
  - `cargo run -p nils-memo-workflow-cli -- script-filter --query "buy milk" | jq -e '.items[0].arg | startswith("add::")'`

## Sprint 3: CRUD test implementation with isolated DBs
**Goal**: Make CRUD correctness verifiable and repeatable with independent per-test databases.
**Demo/Validation**:
- Command(s): `cargo test -p nils-memo-workflow-cli`, `bash workflows/memo-add/tests/smoke.sh`
- Verify: create/update/delete workflows pass in isolated DB paths with no shared-state leakage.

### Task 3.1: Add end-to-end CRUD integration test (create -> update -> delete)
- **Location**:
  - `crates/memo-workflow-cli/tests/cli_contract.rs`
- **Description**: Add one deterministic integration test that creates a new temp DB, inserts a memo, updates text, deletes the same item, and verifies final absence.
- **Dependencies**:
  - Task 2.3
- **Complexity**: 8
- **Acceptance criteria**:
  - Test provisions a fresh DB path via `tempfile::tempdir`.
  - Test asserts add success, update text mutation, and delete removal in one flow.
  - Test verifies post-delete list does not contain deleted `item_id`.
- **Validation**:
  - `cargo test -p nils-memo-workflow-cli crud_create_update_delete`
  - `cargo test -p nils-memo-workflow-cli -- --nocapture`

### Task 3.2: Add negative-path integration tests for mutation errors
- **Location**:
  - `crates/memo-workflow-cli/tests/cli_contract.rs`
- **Description**: Add isolated-DB tests for invalid `item_id`, missing update text, and deleting non-existent items to lock down expected exit codes/messages.
- **Dependencies**:
  - Task 2.2
- **Complexity**: 7
- **Acceptance criteria**:
  - Invalid/missing inputs return exit code `2`.
  - Runtime/storage failures remain exit code `1` where applicable.
  - Error text remains concise and Alfred-safe.
- **Validation**:
  - `cargo test -p nils-memo-workflow-cli mutation_error_`
  - `cargo test -p nils-memo-workflow-cli invalid_item_id_`

### Task 3.3: Add shell-level CRUD smoke using dedicated ephemeral DB
- **Location**:
  - `workflows/memo-add/tests/smoke.sh`
- **Description**: Add a smoke section that creates a unique temp DB, runs `add/update/delete` through `memo-workflow-cli` command/action paths, and asserts results with `jq`/`sqlite3`.
- **Dependencies**:
  - Task 2.4
  - Task 3.1
- **Complexity**: 6
- **Acceptance criteria**:
  - Smoke test creates and cleans a unique temp directory per run.
  - CRUD assertions run against only that temp DB.
  - Existing packaging checks remain intact.
- **Validation**:
  - `tmpdir="$(mktemp -d)" && MEMO_DB_PATH="$tmpdir/memo.db" bash workflows/memo-add/tests/smoke.sh`
  - `tmpdir="$(mktemp -d)" && MEMO_DB_PATH="$tmpdir/memo.db" scripts/workflow-test.sh --id memo-add`

### Task 3.4: Document CRUD verification recipe for operators
- **Location**:
  - `crates/memo-workflow-cli/docs/workflow-contract.md`
  - `workflows/memo-add/README.md`
- **Description**: Add copy-paste operator commands that create a new temp DB and verify create/update/delete semantics end-to-end.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 3
- **Acceptance criteria**:
  - README includes one explicit CRUD verification block with temporary DB setup.
  - Contract checklist includes add/update/delete validation commands.
- **Validation**:
  - `rg -n "mktemp|add|update|delete|MEMO_DB_PATH" workflows/memo-add/README.md crates/memo-workflow-cli/docs/workflow-contract.md`

## Sprint 4: Integration hardening and release safety
**Goal**: Ensure the new mutation capabilities are stable, documented, and reversible.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `cargo test --workspace`, `scripts/workflow-test.sh --id memo-add`, `scripts/workflow-pack.sh --id memo-add`
- Verify: repo quality gates pass and packaged workflow includes updated behavior/docs.

### Task 4.1: Update workflow shell adapters and notifications for mutation outcomes
- **Location**:
  - `workflows/memo-add/scripts/action_run.sh`
  - `workflows/memo-add/scripts/script_filter.sh`
- **Description**: Ensure shell adapters surface update/delete success/failure clearly (including notification text) and continue returning valid Alfred feedback on errors.
- **Dependencies**:
  - Task 2.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Action script emits distinct success notifications/messages for add/update/delete/db-init.
  - Script filter still degrades to non-actionable error JSON on CLI failures.
  - No regression on add/db-init flows.
- **Validation**:
  - `shellcheck workflows/memo-add/scripts/action_run.sh workflows/memo-add/scripts/script_filter.sh`
  - `bash workflows/memo-add/tests/smoke.sh`

### Task 4.2: Update top-level docs and troubleshooting notes
- **Location**:
  - `docs/WORKFLOW_GUIDE.md`
  - `TROUBLESHOOTING.md`
- **Description**: Add/update sections for mutation command syntax, common failure cases (invalid `item_id`, malformed update/delete queries), and remediation steps.
- **Dependencies**:
  - Task 3.4
- **Complexity**: 4
- **Acceptance criteria**:
  - Workflow guide reflects new update/delete runtime behavior.
  - Troubleshooting includes at least one item-id-related and one malformed-token-related case.
- **Validation**:
  - `rg -n "memo-add|update|delete|item_id|token" docs/WORKFLOW_GUIDE.md TROUBLESHOOTING.md`

### Task 4.3: Final gate pass and release-readiness check
- **Location**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh`
- **Description**: Run full quality gates and ensure no regressions in unrelated workflows while packaging `memo-add`.
- **Dependencies**:
  - Task 4.1
  - Task 4.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Lint/test/pack commands pass.
  - `memo-add` package is generated with updated scripts/docs.
  - No failing workspace tests introduced by new mutation support.
- **Validation**:
  - `scripts/workflow-lint.sh`
  - `cargo test --workspace`
  - `scripts/workflow-test.sh --id memo-add`
  - `scripts/workflow-pack.sh --id memo-add`

## Testing Strategy
- Unit:
  - Add token/query parser unit tests for add/update/delete intent decoding and malformed input handling.
  - Add result-rendering tests for text/json envelopes for update/delete.
- Integration:
  - Extend `crates/memo-workflow-cli/tests/cli_contract.rs` with CRUD sequence tests using `tempfile::tempdir`.
  - Include negative-path tests (invalid `item_id`, empty update text, deleting non-existent rows).
- E2E/manual:
  - Run workflow smoke and packaged workflow tests with explicit temp DB override.
  - Example: `tmpdir="$(mktemp -d)" && MEMO_DB_PATH="$tmpdir/memo.db" bash workflows/memo-add/tests/smoke.sh`.
  - Example: `tmpdir="$(mktemp -d)" && MEMO_DB_PATH="$tmpdir/memo.db" scripts/workflow-test.sh --id memo-add`.
  - Verify Alfred action token path (`action --token ...`) for each mutation command.
- Isolated test DB protocol (required):
  - Every CRUD test must create a brand-new directory with `mktemp -d` (shell) or `tempfile::tempdir` (Rust).
  - DB path must be explicit (`$tmpdir/memo.db`) and never default to user/global memo DB.
  - Cleanup is mandatory via trap/RAII to avoid stale files influencing later runs.

## Risks & gotchas
- Hard delete is irreversible; ambiguous query parsing can cause destructive mistakes if not constrained.
- Token encoding bugs can corrupt update text payloads (especially spaces/symbols/multibyte chars).
- Shared DB usage during tests can create flaky ordering/results; strict isolation is mandatory.
- Upstream `nils-memo-cli` behavior changes could break adapter assumptions if future version is unpinned.

## Rollback plan
1. Disable update/delete intent parsing in `script-filter` and action token dispatch, keeping add/db-init only.
2. Revert `memo-workflow-cli` update/delete subcommands and related token helpers in one rollback commit.
3. Restore docs to append-only contract wording for `memo-add`.
4. Run `scripts/workflow-test.sh --id memo-add` and `scripts/workflow-pack.sh --id memo-add` to verify stable fallback.
5. Publish maintenance note: workflow temporarily reverted to add-only while mutation support is stabilized.
