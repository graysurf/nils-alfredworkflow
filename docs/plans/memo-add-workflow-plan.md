# Plan: Add Memo Workflow (nils-memo-cli 0.3.3)

## Overview
This plan adds a new Alfred workflow focused on fast memo capture, backed by `nils-memo-cli@0.3.3`.
The primary user flow is `add`: type memo text in Alfred and commit it to SQLite immediately.
The design also includes explicit `db init` behavior so first-run setup and recovery are deterministic.
Implementation follows existing repo conventions: dedicated Rust CLI crate for workflow domain logic, thin shell adapters in `workflows/`, and packaging/testing through existing `scripts/workflow-*` entrypoints.

## Scope
- In scope: new workflow `memo-add` with Script Filter + action execution.
- In scope: pin and consume `nils-memo-cli` version `0.3.3` via `cargo add`.
- In scope: user-facing `add` flow and explicit `db init` flow from workflow actions.
- In scope: workflow parameter design (DB path/source/confirmation/runtime overrides) with Alfred user config exposure.
- In scope: tests, smoke checks, docs, and packaging integration.
- Out of scope: full memo dashboard UI in Alfred (rich list/search/report screens).
- Out of scope: background enrichment pipeline UX (`fetch/apply`) in this first delivery.
- Out of scope: migration of historical notes from external systems.

## Assumptions (if any)
1. Workflow ID is `memo-add`, and first-release keyword is `mm`.
2. `add` is the only end-user write path in v1; `list/search/report` remain future iterations.
3. `db init` is exposed as an explicit workflow action and remains idempotent.
4. Default DB path should prefer Alfred workflow data directory when available, with `memo-cli` default path as fallback.

## Success Criteria
- `mm buy milk` can create a memo successfully through workflow action flow.
- Empty query never crashes; it returns actionable guidance rows (including `db init`).
- Running `db init` repeatedly is safe and returns deterministic success feedback.
- Workflow parameters are configurable via Alfred UI and validated consistently.
- `scripts/workflow-lint.sh`, `scripts/workflow-test.sh --id memo-add`, and `scripts/workflow-pack.sh --id memo-add` pass.

## Dependency & Parallelization Map
- Critical path:
  - `Task 1.1 -> Task 1.2 -> Task 1.3 -> Task 1.4 -> Task 2.1 -> Task 2.2 -> Task 2.3 -> Task 3.1 -> Task 3.2 -> Task 3.3 -> Task 3.4 -> Task 4.3`.
- Parallel track A:
  - `Task 1.5` can run after `Task 1.1` in parallel with `Task 1.3`/`Task 1.4`.
- Parallel track B:
  - `Task 2.4` can run after `Task 2.1` in parallel with `Task 2.2` and `Task 2.3`.
- Parallel track C:
  - `Task 4.1` can run after `Task 2.3` in parallel with `Task 3.2`/`Task 3.3`.
- Parallel track D:
  - `Task 4.2` can start after `Task 3.4` and run parallel with `Task 4.1`.

## Sprint 1: Contract and scaffolding
**Goal**: Freeze v1 behavior and scaffold workflow/crate surfaces aligned with monorepo conventions.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/memo-add-workflow-plan.md`, `test -d workflows/memo-add`, `cargo check -p nils-memo-workflow-cli`
- Verify: workflow skeleton and crate skeleton exist, and memo dependency strategy is pinned and explicit.

### Task 1.1: Write memo workflow contract and parameter matrix
- **Location**:
  - `docs/memo-workflow-contract.md`
- **Description**: Define v1 contract for `add` and `db init`, action-token schema, error mapping, exit-code policy, and parameter semantics.
- **Dependencies**:
  - none
- **Complexity**: 4
- **Acceptance criteria**:
  - Contract explicitly documents `mm buy milk -> add` behavior and empty-query fallback behavior.
  - Contract defines `db init` trigger conditions and idempotent response expectations.
  - Parameter table includes defaults, allowed ranges, and failure handling.
- **Validation**:
  - `test -f docs/memo-workflow-contract.md`
  - `rg -n "add|db init|action token|exit code|MEMO_DB_PATH|MEMO_SOURCE" docs/memo-workflow-contract.md`

### Task 1.2: Scaffold `memo-add` workflow directory
- **Location**:
  - `workflows/memo-add/workflow.toml`
  - `workflows/memo-add/scripts/script_filter.sh`
  - `workflows/memo-add/scripts/action_run.sh`
  - `workflows/memo-add/src/info.plist.template`
  - `workflows/memo-add/src/assets/icon.png`
  - `workflows/memo-add/tests/smoke.sh`
- **Description**: Create workflow skeleton with dedicated script filter/action scripts and packaged icon/plist template.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Workflow folder structure matches existing repo conventions.
  - `workflow.toml` references dedicated binary `memo-workflow-cli`.
  - Scripts are executable and mapped to manifest keys.
- **Validation**:
  - `test -d workflows/memo-add`
  - `test -f workflows/memo-add/workflow.toml`
  - `test -x workflows/memo-add/scripts/script_filter.sh`
  - `test -x workflows/memo-add/scripts/action_run.sh`
  - `rg -n 'rust_binary\\s*=\\s*"memo-workflow-cli"' workflows/memo-add/workflow.toml`

### Task 1.3: Add dedicated crate `nils-memo-workflow-cli`
- **Location**:
  - `Cargo.toml`
  - `crates/memo-workflow-cli/Cargo.toml`
  - `crates/memo-workflow-cli/src/main.rs`
  - `crates/memo-workflow-cli/src/lib.rs`
- **Description**: Create workflow-specific Rust crate to own Alfred JSON rendering, env parsing, and delegation to memo domain operations.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Workspace includes `crates/memo-workflow-cli`.
  - `cargo run -p nils-memo-workflow-cli -- --help` succeeds.
- **Validation**:
  - `cargo check -p nils-memo-workflow-cli`
  - `cargo run -p nils-memo-workflow-cli -- --help`

### Task 1.4: Pin `nils-memo-cli` to `0.3.3` with cargo add
- **Location**:
  - `crates/memo-workflow-cli/Cargo.toml`
  - `Cargo.lock`
- **Description**: Execute `cargo add nils-memo-cli@0.3.3` from `crates/memo-workflow-cli` and keep lockfile deterministic.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 2
- **Acceptance criteria**:
  - Crate dependency list includes `nils-memo-cli = "0.3.3"`.
  - Build graph resolves without version conflict errors.
- **Validation**:
  - `rg -n '^nils-memo-cli\\s*=\\s*\"0\\.3\\.3\"' crates/memo-workflow-cli/Cargo.toml`
  - `cargo check -p nils-memo-workflow-cli`
  - `cargo tree -p nils-memo-workflow-cli | rg 'nils-memo-cli v0.3.3'`

### Task 1.5: Define Alfred workflow parameters and defaults
- **Location**:
  - `workflows/memo-add/workflow.toml`
  - `workflows/memo-add/src/info.plist.template`
  - `docs/memo-workflow-contract.md`
- **Description**: Define and align workflow variables: `MEMO_DB_PATH`, `MEMO_SOURCE`, `MEMO_REQUIRE_CONFIRM`, `MEMO_MAX_INPUT_BYTES`, and optional `MEMO_WORKFLOW_CLI_BIN`.
- **Dependencies**:
  - Task 1.1
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Same defaults/constraints are consistent across manifest, plist, and contract docs.
  - Alfred `userconfigurationconfig` exposes all required variables.
  - Parameter defaults are pinned for v1: `MEMO_DB_PATH=""`, `MEMO_SOURCE="alfred"`, `MEMO_REQUIRE_CONFIRM="0"`, `MEMO_MAX_INPUT_BYTES="4096"`, `MEMO_WORKFLOW_CLI_BIN=""`.
- **Validation**:
  - `rg -n "MEMO_DB_PATH|MEMO_SOURCE|MEMO_REQUIRE_CONFIRM|MEMO_MAX_INPUT_BYTES|MEMO_WORKFLOW_CLI_BIN" workflows/memo-add/workflow.toml workflows/memo-add/src/info.plist.template docs/memo-workflow-contract.md`
  - `scripts/workflow-pack.sh --id memo-add`
  - `plutil -convert json -o - build/workflows/memo-add/pkg/info.plist | jq -e '[.userconfigurationconfig[].variable] | sort == ["MEMO_DB_PATH","MEMO_MAX_INPUT_BYTES","MEMO_REQUIRE_CONFIRM","MEMO_SOURCE","MEMO_WORKFLOW_CLI_BIN"]'`
  - `plutil -convert json -o - build/workflows/memo-add/pkg/info.plist | jq -e '(.userconfigurationconfig | map({key: .variable, value: .config.default}) | from_entries) == {"MEMO_DB_PATH":"","MEMO_MAX_INPUT_BYTES":"4096","MEMO_REQUIRE_CONFIRM":"0","MEMO_SOURCE":"alfred","MEMO_WORKFLOW_CLI_BIN":""}'`

## Sprint 2: Memo adapter logic (`add` + `db init`)
**Goal**: Implement robust Rust-side command handling and deterministic Alfred JSON responses.
**Demo/Validation**:
- Command(s): `cargo test -p nils-memo-workflow-cli`, `cargo run -p nils-memo-workflow-cli -- script-filter --query "buy milk"`
- Verify: script-filter/add/db-init paths are valid and contract-compliant.

### Task 2.1: Implement runtime config parsing and guardrails
- **Location**:
  - `crates/memo-workflow-cli/src/config.rs`
  - `crates/memo-workflow-cli/src/lib.rs`
- **Description**: Parse env/config defaults, validate bounds (including max input bytes), and normalize DB path/source semantics.
- **Dependencies**:
  - Task 1.4
  - Task 1.5
- **Complexity**: 6
- **Acceptance criteria**:
  - Missing env values fall back to documented defaults.
  - Invalid values produce actionable user errors instead of panic.
  - Path resolution order is deterministic and test-covered.
- **Validation**:
  - `cargo test -p nils-memo-workflow-cli`
  - `cargo test -p nils-memo-workflow-cli -- --list | rg "config_|env_|path_|bounds_"`

### Task 2.2: Implement explicit `db init` command path
- **Location**:
  - `crates/memo-workflow-cli/src/commands/db_init.rs`
  - `crates/memo-workflow-cli/src/commands/mod.rs`
- **Description**: Add explicit DB initialization command that creates parent dirs and initializes schema using memo storage/migration behavior.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 5
- **Acceptance criteria**:
  - First run creates DB and schema successfully.
  - Repeated runs stay idempotent and return success.
  - Failures map to deterministic error codes/messages for Alfred scripts.
- **Validation**:
  - `tmpdir="$(mktemp -d)" && db="$tmpdir/memo.db" && cargo run -p nils-memo-workflow-cli -- db-init --db "$db" && cargo run -p nils-memo-workflow-cli -- db-init --db "$db"`
  - `sqlite3 "$db" "select name from sqlite_master where type='table' and name='inbox_items';" | rg '^inbox_items$'`

### Task 2.3: Implement `add` execution path using memo-cli contract
- **Location**:
  - `crates/memo-workflow-cli/src/commands/add.rs`
  - `crates/memo-workflow-cli/src/commands/mod.rs`
  - `crates/memo-workflow-cli/src/output.rs`
- **Description**: Implement add flow that validates query text, enforces configured limits, passes source/timestamp/DB path, and returns clear success/failure payloads.
- **Dependencies**:
  - Task 2.1
  - Task 2.2
- **Complexity**: 8
- **Acceptance criteria**:
  - Non-empty text creates one new memo row.
  - Empty/oversize text is rejected with non-crashing user feedback.
  - Success payload includes item id and created timestamp for UX confirmation.
  - `MEMO_DB_PATH` and `MEMO_SOURCE` overrides are honored by persisted records.
- **Validation**:
  - `tmpdir="$(mktemp -d)" && db="$tmpdir/memo.db" && cargo run -p nils-memo-workflow-cli -- add --text "buy milk" --db "$db" --source "alfred"`
  - `sqlite3 "$db" "select count(*) from inbox_items;" | rg '^1$'`
  - `bash -c 'set +e; cargo run -p nils-memo-workflow-cli -- add --text "   " >/dev/null 2>&1; test $? -ne 0'`
  - `tmpdir="$(mktemp -d)" && export MEMO_DB_PATH="$tmpdir/override.db" MEMO_SOURCE="alfred-test" && cargo run -p nils-memo-workflow-cli -- add --text "env override check" && sqlite3 "$tmpdir/override.db" "select source from inbox_items order by item_id desc limit 1;" | rg '^alfred-test$'`

### Task 2.4: Implement Script Filter JSON builder for add/init actions
- **Location**:
  - `crates/memo-workflow-cli/src/commands/script_filter.rs`
  - `crates/memo-workflow-cli/src/alfred.rs`
- **Description**: Build Alfred items for empty query guidance (`db init`) and non-empty query add action tokenization (`add::raw-query` style).
- **Dependencies**:
  - Task 2.1
  - Task 2.3
- **Complexity**: 6
- **Acceptance criteria**:
  - Empty query returns non-actionable guidance + actionable init row.
  - Non-empty query returns actionable add row with correct arg token.
  - Output is always valid Alfred JSON.
- **Validation**:
  - `cargo run -p nils-memo-workflow-cli -- script-filter --query "" | jq -e '.items | type == "array" and length >= 1'`
  - `cargo run -p nils-memo-workflow-cli -- script-filter --query "buy milk" | jq -e '.items[0].arg | startswith("add::")'`

### Task 2.5: Finalize CLI command surface and contract tests
- **Location**:
  - `crates/memo-workflow-cli/src/main.rs`
  - `crates/memo-workflow-cli/tests/cli_contract.rs`
- **Description**: Finalize command interface (`script-filter`, `add`, `db-init`) and verify stdout/stderr/exit-code behavior with deterministic contract tests.
- **Dependencies**:
  - Task 2.2
  - Task 2.3
  - Task 2.4
- **Complexity**: 6
- **Acceptance criteria**:
  - `--help` reflects all command options and env behavior.
  - Success paths return expected payload formats.
  - Usage/runtime failures return stable non-zero exit codes.
- **Validation**:
  - `cargo run -p nils-memo-workflow-cli -- --help`
  - `cargo test -p nils-memo-workflow-cli`
  - `cargo clippy -p nils-memo-workflow-cli --all-targets -- -D warnings`

## Sprint 3: Alfred wiring and packaging
**Goal**: Wire shell adapters/plist for stable runtime behavior in both packaged and local development modes.
**Demo/Validation**:
- Command(s): `bash workflows/memo-add/tests/smoke.sh`, `scripts/workflow-pack.sh --id memo-add`
- Verify: workflow package is installable and action paths execute add/init correctly.

### Task 3.1: Implement robust `script_filter.sh` adapter
- **Location**:
  - `workflows/memo-add/scripts/script_filter.sh`
- **Description**: Resolve workflow binary path (env/package/release/debug), call `script-filter`, and provide error-item fallback on failures.
- **Dependencies**:
  - Task 2.5
- **Complexity**: 5
- **Acceptance criteria**:
  - Adapter supports packaged and local development execution paths.
  - On failure, script returns valid Alfred JSON error items.
- **Validation**:
  - `shellcheck workflows/memo-add/scripts/script_filter.sh`
  - `shfmt -d workflows/memo-add/scripts/script_filter.sh`
  - `bash workflows/memo-add/scripts/script_filter.sh "buy milk" | jq -e '.items | type == "array"'`

### Task 3.2: Implement action script for `add` and `db init`
- **Location**:
  - `workflows/memo-add/scripts/action_run.sh`
- **Description**: Parse action token (`add::...` / `db-init`), execute corresponding CLI command, and provide user feedback/exit codes.
- **Dependencies**:
  - Task 2.5
- **Complexity**: 6
- **Acceptance criteria**:
  - `add` token path writes memo and exits 0 on success.
  - `db-init` token path is idempotent and exits 0 on success.
  - Invalid tokens return usage-style errors without undefined behavior.
- **Validation**:
  - `shellcheck workflows/memo-add/scripts/action_run.sh`
  - `bash -c 'set +e; workflows/memo-add/scripts/action_run.sh >/dev/null 2>&1; test $? -eq 2'`
  - `tmpdir="$(mktemp -d)" && export MEMO_DB_PATH="$tmpdir/memo.db" && workflows/memo-add/scripts/action_run.sh "db-init" && workflows/memo-add/scripts/action_run.sh "add::buy milk" && sqlite3 "$tmpdir/memo.db" "select count(*) from inbox_items;" | rg "^1$"`

### Task 3.3: Wire `info.plist.template` object graph and parameter UI
- **Location**:
  - `workflows/memo-add/src/info.plist.template`
- **Description**: Add keyword trigger, script filter/action wiring, and `userconfigurationconfig` entries for memo workflow parameters.
- **Dependencies**:
  - Task 1.5
  - Task 3.1
  - Task 3.2
- **Complexity**: 7
- **Acceptance criteria**:
  - Plist has valid script filter and action object connections.
  - User config fields match contract variable list and defaults.
- **Validation**:
  - `scripts/workflow-pack.sh --id memo-add`
  - `plutil -lint build/workflows/memo-add/pkg/info.plist`
  - `plutil -convert json -o - build/workflows/memo-add/pkg/info.plist | jq -e '(.objects[] | select(.type == "alfred.workflow.input.scriptfilter") | .config.keyword) == "mm"'`

### Task 3.4: Add deterministic smoke test coverage for workflow runtime
- **Location**:
  - `workflows/memo-add/tests/smoke.sh`
- **Description**: Add smoke checks for required files, script executability, script-filter JSON, action token handling, and packaged plist wiring.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
  - Task 3.3
- **Complexity**: 6
- **Acceptance criteria**:
  - Smoke test fails on missing files, malformed JSON, or broken action paths.
  - Smoke test does not require live network dependencies.
- **Validation**:
  - `bash workflows/memo-add/tests/smoke.sh`
  - `scripts/workflow-test.sh --id memo-add`

### Task 3.5: Verify packaging integration and artifact integrity
- **Location**:
  - `workflows/memo-add/workflow.toml`
  - `scripts/workflow-pack.sh`
- **Description**: Ensure workflow packaging places binary/scripts/assets correctly and does not regress global `--all` packaging.
- **Dependencies**:
  - Task 3.4
- **Complexity**: 4
- **Acceptance criteria**:
  - `memo-add` package and checksum are generated.
  - `scripts/workflow-pack.sh --all` remains successful.
- **Validation**:
  - `scripts/workflow-pack.sh --id memo-add`
  - `scripts/workflow-pack.sh --all`

## Sprint 4: Quality gates, docs, and rollout safety
**Goal**: Finish with test depth, operator docs, and executable rollback procedures.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `scripts/workflow-test.sh --id memo-add`, `scripts/workflow-pack.sh --id memo-add --install`
- Verify: quality gates pass and maintainers can operate or roll back safely.

### Task 4.1: Add focused tests for add/init edge cases
- **Location**:
  - `crates/memo-workflow-cli/src/commands/add.rs`
  - `crates/memo-workflow-cli/src/commands/db_init.rs`
  - `crates/memo-workflow-cli/tests/cli_contract.rs`
- **Description**: Cover edge cases: empty text, over-limit text, invalid source, db path creation failures, and repeated init/add idempotency boundaries.
- **Dependencies**:
  - Task 2.5
- **Complexity**: 7
- **Acceptance criteria**:
  - Edge cases return deterministic error contracts.
  - Init/add behavior remains stable under repeated execution.
- **Validation**:
  - `cargo test -p nils-memo-workflow-cli`
  - `cargo test -p nils-memo-workflow-cli -- --list | rg "add_|db_init_|contract_"`

### Task 4.2: Document workflow usage and parameters
- **Location**:
  - `workflows/memo-add/README.md`
  - `README.md`
  - `docs/WORKFLOW_GUIDE.md`
  - `TROUBLESHOOTING.md`
- **Description**: Document keyword usage, add/init flows, parameter meanings, and troubleshooting for DB-path/config/permission failures.
- **Dependencies**:
  - Task 3.5
- **Complexity**: 4
- **Acceptance criteria**:
  - Workflow README includes quick-start and parameter table.
  - Root docs include memo-add entry and operator validation checklist.
- **Validation**:
  - `rg -n "memo-add|mm|MEMO_DB_PATH|MEMO_SOURCE|db init|add" workflows/memo-add/README.md README.md docs/WORKFLOW_GUIDE.md TROUBLESHOOTING.md`

### Task 4.3: Execute final quality gates required by project policy
- **Location**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh`
- **Description**: Run full required checks before merge/release to ensure no regressions in workflow and workspace quality gates.
- **Dependencies**:
  - Task 4.1
  - Task 4.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Lint/test/pack pipelines pass for both targeted and aggregate modes.
  - Generated artifact is installable and stable.
- **Validation**:
  - `scripts/workflow-lint.sh`
  - `cargo test --workspace`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh --id memo-add`

### Task 4.4: Add rollout and rollback runbook notes
- **Location**:
  - `docs/memo-workflow-contract.md`
  - `docs/plans/memo-add-workflow-plan.md`
- **Description**: Document release checklist, disable triggers, and rollback sequence for fast recovery when runtime/storage issues occur.
- **Dependencies**:
  - Task 4.3
- **Complexity**: 3
- **Acceptance criteria**:
  - Rollout/rollback steps are explicit and executable.
  - Support notes include objective disable triggers and fallback behavior.
- **Validation**:
  - `rg -n "rollback|disable|fallback|memo-add" docs/memo-workflow-contract.md docs/plans/memo-add-workflow-plan.md`

## Testing Strategy
- Unit:
  - `memo-workflow-cli` config parsing, token parsing, add/init command semantics, and error mapping.
- Integration:
  - Script adapter + action script tests with temporary DB paths and deterministic token inputs.
- E2E/manual:
  - Package/install workflow, run `mm` with and without text, verify `db init` and `add` behavior from Alfred UI.
- Non-functional:
  - Validate that repeated add/init operations do not corrupt DB state and keep latency acceptable for Alfred interaction.

## Risks & gotchas
- `nils-memo-cli` API surface may evolve; wrapper should minimize dependence on unstable internals.
- DB path permission issues can cause first-run failures unless error messaging is explicit.
- Alfred action token parsing is brittle if delimiters are not escaped/validated rigorously.
- Overly permissive input size can hurt UX or storage quality; limits must be documented and enforced.

## Rollback plan
1. Stop distributing `memo-add` artifacts in release output.
2. Revert `workflows/memo-add/`, `crates/memo-workflow-cli/`, workspace membership changes, and memo docs updates in one rollback commit.
3. Re-run baseline quality gates:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
4. Publish maintenance note: memo capture workflow temporarily removed; existing workflows unaffected.
