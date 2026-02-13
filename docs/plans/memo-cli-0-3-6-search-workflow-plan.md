# Plan: Memo CLI 0.3.6 Pin + Memo Search Workflow

## Overview
This plan upgrades `memo-add` workflow runtime dependency from `nils-memo-cli@0.3.5` to `0.3.6`
and introduces workflow-level memo search.
The design keeps existing add/update/delete/copy behavior intact while adding a dedicated
search intent and keyword path (`mmq`) for lookup-first usage.
Implementation is split across dependency pinning, Rust runtime command additions, Alfred keyword
wiring, and regression-safe tests/docs updates.

## Scope
- In scope: pin `nils-memo-cli` to exact version `=0.3.6` in memo workflow runtime crate.
- In scope: add `memo-workflow-cli` search capability (`search` subcommand + script-filter intent).
- In scope: add memo search keyword flow in `workflows/memo-add` (`mmq`).
- In scope: update tests/smoke/package assertions for new search behavior.
- In scope: update memo workflow docs/contracts/operator checklists for new version and search UX.
- Out of scope: schema migration or behavior changes inside upstream `nils-memo-cli`.
- Out of scope: ranking algorithm redesign beyond upstream `nils-memo-cli` search semantics.
- Out of scope: bulk actions from search result rows.

## Assumptions (if any)
1. `nils-memo-cli@0.3.6` exposes stable search primitives consumable by `memo-workflow-cli`.
2. Existing keyword behavior (`mm`, `mmr`, `mma`, `mmu`, `mmd`, `mmc`) must remain backward compatible.
3. `mmq` (currently reserved) can be promoted to an official search keyword without conflict.
4. Search results can reuse existing item management flow via `autocomplete: item ITEM_ID`.
5. Current CI/dev environment already satisfies required binaries (`cargo`, `jq`, `rg`, `plutil` or python fallback).

## Success Criteria
- `crates/memo-workflow-cli/Cargo.toml` pins `nils-memo-cli = "=0.3.6"` and lockfile resolves cleanly.
- `memo-workflow-cli --help` exposes `search` command with deterministic text/json outputs.
- `memo-workflow-cli script-filter --query "search QUERY_TEXT"` returns actionable/inspectable Alfred items.
- `mmq QUERY_TEXT` route works from workflow script wrappers and packaged plist keyword wiring.
- Existing add/update/delete/copy paths remain green in contract and smoke tests.

## Dependency & Parallelization Map
- Critical path:
  - `Task 1.1 -> Task 1.2 -> Task 2.1 -> Task 2.2 -> Task 2.3 -> Task 3.1 -> Task 3.2 -> Task 3.3 -> Task 4.1 -> Task 4.3`.
- Parallel track A:
  - `Task 1.3` can start after `Task 1.2` in parallel with `Task 2.1`.
- Parallel track B:
  - `Task 2.4` can run after `Task 2.3` in parallel with `Task 3.1`.
- Parallel track C:
  - `Task 4.1` can run after `Task 2.4` in parallel with `Task 3.1 -> Task 3.2 -> Task 3.3`.
- Parallel track D:
  - `Task 4.2` can run after `Task 3.2` in parallel with `Task 4.1`.

## Sprint 1: Dependency + contract alignment
**Goal**: Lock version upgrade and freeze user-visible search contract before runtime wiring.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/memo-cli-0-3-6-search-workflow-plan.md`, `cargo check -p nils-memo-workflow-cli`
- Verify: dependency pin, search contract, and keyword scope are explicit and conflict-free.

### Task 1.1: Pin `nils-memo-cli` to `0.3.6`
- **Location**:
  - `crates/memo-workflow-cli/Cargo.toml`
  - `Cargo.lock`
- **Description**: Update memo workflow runtime dependency from `=0.3.5` to `=0.3.6` using exact pin policy and refresh lockfile.
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - `crates/memo-workflow-cli/Cargo.toml` contains `nils-memo-cli = "=0.3.6"`.
  - Lockfile resolves to `nils-memo-cli 0.3.6` without duplicate conflicting versions in runtime path.
- **Validation**:
  - `rg -n '^nils-memo-cli\\s*=\\s*"=0\\.3\\.6"' crates/memo-workflow-cli/Cargo.toml`
  - `cargo tree -p nils-memo-workflow-cli | rg 'nils-memo-cli v0.3.6'`
  - `! cargo tree -p nils-memo-workflow-cli | rg 'nils-memo-cli v0.3.5'`

### Task 1.2: Freeze search interaction contract (`mmq` + intent grammar)
- **Location**:
  - `crates/memo-workflow-cli/docs/workflow-contract.md`
  - `workflows/memo-add/README.md`
  - `docs/WORKFLOW_GUIDE.md`
- **Description**: Define search behavior end-to-end: keyword, accepted query shape, empty-query behavior, result row semantics, and fallback/error behavior.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Docs define `mmq QUERY_TEXT` flow and `search QUERY_TEXT` intent mapping.
  - Search empty-query behavior is explicitly documented (guidance row and no executable action).
  - Existing CRUD behavior documentation remains intact and unchanged where not related to search.
- **Validation**:
  - `rg -n "mmq|search QUERY_TEXT|search intent|empty-query|CRUD|copy|update|delete" crates/memo-workflow-cli/docs/workflow-contract.md workflows/memo-add/README.md docs/WORKFLOW_GUIDE.md`

### Task 1.3: Update runtime CLI docs for version and command surface
- **Location**:
  - `crates/memo-workflow-cli/README.md`
  - `README.md`
- **Description**: Update user/developer docs to reflect `nils-memo-cli@0.3.6` and `memo-workflow-cli search` command availability.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 3
- **Acceptance criteria**:
  - Runtime README command table includes `search`.
  - Top-level workflow summary still accurately describes memo workflow and newly available search path.
- **Validation**:
  - `rg -n "0\\.3\\.6|search|memo-workflow-cli" crates/memo-workflow-cli/README.md README.md`

## Sprint 2: Runtime search implementation (`memo-workflow-cli`)
**Goal**: Add a first-class search command and script-filter search intent with stable error mapping.
**Demo/Validation**:
- Command(s): `cargo check -p nils-memo-workflow-cli`, `cargo run -p nils-memo-workflow-cli -- --help`
- Verify: runtime exposes search command and compiles with unchanged CRUD behavior.

### Task 2.1: Add `Search` subcommand + output model in CLI entrypoint
- **Location**:
  - `crates/memo-workflow-cli/src/main.rs`
  - `crates/memo-workflow-cli/src/lib.rs`
- **Description**: Extend CLI command enum to include `search --query --limit --offset --db --mode`, and add response rendering consistent with existing text/json envelope style.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 6
- **Acceptance criteria**:
  - `memo-workflow-cli --help` lists `search`.
  - `search --mode json` follows `{ok,result,error}` envelope semantics.
  - Invalid input path (empty query or invalid limit) returns user exit semantics (`2`).
- **Validation**:
  - `cargo run -p nils-memo-workflow-cli -- --help | rg "search"`
  - `tmpdir="$(mktemp -d)" && db="$tmpdir/memo.db" && cargo run -p nils-memo-workflow-cli -- add --db "$db" --text "seed" >/dev/null && cargo run -p nils-memo-workflow-cli -- search --db "$db" --query "seed" --mode json | jq -e '.ok == true and (.result | type == "array") and (.error == null)'`
  - `bash -c 'set +e; cargo run -p nils-memo-workflow-cli -- search --query "" >/dev/null 2>&1; test $? -eq 2'`
  - `bash -c 'set +e; cargo run -p nils-memo-workflow-cli -- search --query "seed" --limit 0 >/dev/null 2>&1; test $? -eq 2'`

### Task 2.2: Implement `execute_search` with upstream 0.3.6 search API
- **Location**:
  - `crates/memo-workflow-cli/src/lib.rs`
- **Description**: Add runtime search execution that delegates to `nils-memo-cli@0.3.6` search primitives, normalizes item IDs, enforces limit bounds, and returns deterministic result rows.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 8
- **Acceptance criteria**:
  - Search query returns newest-first matching rows using upstream behavior.
  - Returned rows include sufficient context for Alfred display (`item_id`, timestamp/state, preview text).
  - Runtime/storage errors remain mapped to readable non-panicking errors.
- **Validation**:
  - `tmpdir="$(mktemp -d)" && db="$tmpdir/memo.db" && cargo run -p nils-memo-workflow-cli -- add --db "$db" --text "buy milk" >/dev/null && cargo run -p nils-memo-workflow-cli -- add --db "$db" --text "buy oat milk" >/dev/null && cargo run -p nils-memo-workflow-cli -- search --db "$db" --query "oat" --mode json | jq -e '.ok == true and (.result | length) >= 1'`
  - `tmpdir="$(mktemp -d)" && db="$tmpdir/memo.db" && cargo run -p nils-memo-workflow-cli -- add --db "$db" --text "first memo" >/dev/null && sleep 1 && cargo run -p nils-memo-workflow-cli -- add --db "$db" --text "second memo" >/dev/null && cargo run -p nils-memo-workflow-cli -- search --db "$db" --query "memo" --mode json | jq -e '.ok == true and (.result | length) == 2 and .result[0].text_preview | contains("second")'`
  - `tmpdir="$(mktemp -d)" && db="$tmpdir/memo.db" && cargo run -p nils-memo-workflow-cli -- add --db "$db" --text "field check" >/dev/null && cargo run -p nils-memo-workflow-cli -- search --db "$db" --query "field" --mode json | jq -e '.result[0] | has("item_id") and has("created_at") and has("text_preview")'`
  - `bash -c 'set +e; cargo run -p nils-memo-workflow-cli -- search --query "milk" --limit 0 >/dev/null 2>&1; test $? -eq 2'`

### Task 2.3: Extend `script-filter` intent parser for `search`
- **Location**:
  - `crates/memo-workflow-cli/src/lib.rs`
- **Description**: Add `search` intent handling in `build_script_filter` so `search QUERY_TEXT` renders result rows and keeps existing fallback add/update/delete/copy behavior unchanged.
- **Dependencies**:
  - Task 2.2
- **Complexity**: 7
- **Acceptance criteria**:
  - `script-filter --query "search milk"` returns rows derived from search results.
  - Search result rows are non-destructive and route via `autocomplete` to existing `item ITEM_ID` flow.
  - Existing default add path for plain text remains unchanged.
- **Validation**:
  - `tmpdir="$(mktemp -d)" && db="$tmpdir/memo.db" && cargo run -p nils-memo-workflow-cli -- add --db "$db" --text "buy milk" >/dev/null && MEMO_DB_PATH="$db" cargo run -p nils-memo-workflow-cli -- script-filter --query "search milk" | jq -e '.items | type == "array" and length >= 1'`
  - `tmpdir="$(mktemp -d)" && db="$tmpdir/memo.db" && cargo run -p nils-memo-workflow-cli -- add --db "$db" --text "buy milk" >/dev/null && MEMO_DB_PATH="$db" cargo run -p nils-memo-workflow-cli -- script-filter --query "search milk" | jq -e '.items[0].autocomplete | startswith("item ")'`
  - `tmpdir="$(mktemp -d)" && db="$tmpdir/memo.db" && cargo run -p nils-memo-workflow-cli -- add --db "$db" --text "buy milk" >/dev/null && MEMO_DB_PATH="$db" cargo run -p nils-memo-workflow-cli -- script-filter --query "search milk" | jq -e '([.items[].arg // ""] | all(startswith("add::") | not)) and ([.items[].arg // ""] | all(startswith("delete::") | not))'`
  - `cargo run -p nils-memo-workflow-cli -- script-filter --query "buy milk" | jq -e '.items[0].arg | startswith("add::")'`

### Task 2.4: Add runtime unit coverage for search parser + bounds
- **Location**:
  - `crates/memo-workflow-cli/src/lib.rs`
- **Description**: Add unit tests for search intent parsing, empty-query guardrails, result rendering shape, and limit/offset boundary validation.
- **Dependencies**:
  - Task 2.3
- **Complexity**: 6
- **Acceptance criteria**:
  - Search-specific unit tests cover valid query, empty query, and invalid limit branches.
  - Existing token/parser tests for CRUD remain passing.
- **Validation**:
  - `cargo test -p nils-memo-workflow-cli -- --list | rg "search_|script_filter_.*search|limit_"`
  - `cargo test -p nils-memo-workflow-cli`

## Sprint 3: Workflow keyword wiring (`memo-add`)
**Goal**: Expose search in Alfred workflow through keyword wrapper and plist wiring while preserving existing command set.
**Demo/Validation**:
- Command(s): `bash workflows/memo-add/tests/smoke.sh`, `scripts/workflow-pack.sh --id memo-add`
- Verify: new keyword is packaged/wired and old keywords keep behavior.

### Task 3.1: Add `mmq` script-filter wrapper
- **Location**:
  - `workflows/memo-add/scripts/script_filter_search.sh`
  - `workflows/memo-add/scripts/script_filter.sh`
- **Description**: Create dedicated wrapper script for search keyword that routes non-empty input to `search` intent and returns guidance row when query is empty.
- **Dependencies**:
  - Task 2.3
- **Complexity**: 5
- **Acceptance criteria**:
  - `script_filter_search.sh "query text"` delegates to runtime with `search` intent.
  - Empty query from `mmq` is non-actionable guidance (not add token).
  - Script is executable and follows existing null/env/stdin query handling style.
- **Validation**:
  - `test -x workflows/memo-add/scripts/script_filter_search.sh`
  - `MEMO_WORKFLOW_CLI_BIN=workflows/memo-add/bin/memo-workflow-cli bash workflows/memo-add/scripts/script_filter_search.sh "milk" | jq -e '.items | type == "array"'`
  - `MEMO_WORKFLOW_CLI_BIN=workflows/memo-add/bin/memo-workflow-cli bash workflows/memo-add/scripts/script_filter_search.sh "" | jq -e '(.items[0].valid == false) and ([.items[].arg // ""] | all(startswith("add::") | not))'`

### Task 3.2: Update command-entry and keyword routing in plist
- **Location**:
  - `workflows/memo-add/scripts/script_filter_entry.sh`
  - `workflows/memo-add/src/info.plist.template`
- **Description**: Add search row to command menu and wire new `mmq` Script Filter object in plist template with correct script path and connection.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Entry menu includes search command hint/autocomplete.
  - Packaged plist contains `mmq` keyword pointing to `./scripts/script_filter_search.sh`.
  - Existing six keywords remain present and unchanged.
- **Validation**:
  - `bash workflows/memo-add/scripts/script_filter_entry.sh | jq -e '.items | any(.autocomplete == "mmq ")'`
  - `scripts/workflow-pack.sh --id memo-add`
  - `plutil -convert json -o - build/workflows/memo-add/pkg/info.plist | jq -e '[.objects[] | select(.type == "alfred.workflow.input.scriptfilter") | .config.keyword] | sort == ["mm","mma","mmc","mmd","mmq","mmr","mmu"]'`

### Task 3.3: Extend smoke test stubs/assertions for search path
- **Location**:
  - `workflows/memo-add/tests/smoke.sh`
- **Description**: Update smoke stub runtime and assertions to validate `mmq` behavior, search query routing, and packaged keyword count increment.
- **Dependencies**:
  - Task 3.2
- **Complexity**: 8
- **Acceptance criteria**:
  - Smoke test checks `script_filter_search.sh` and entry menu include search option.
  - Stub runtime includes deterministic `search` query branch for assertions.
  - Packaged plist assertion updates script-filter count and keyword set safely.
- **Validation**:
  - `bash workflows/memo-add/tests/smoke.sh`
  - `scripts/workflow-test.sh --id memo-add`

## Sprint 4: Regression coverage + release safety
**Goal**: Lock behavior with integration tests/docs and complete project quality gates.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `cargo test --workspace`, `scripts/workflow-pack.sh --id memo-add`
- Verify: feature is documented, tested, and packaging-safe.

### Task 4.1: Add CLI integration tests for search + non-regression
- **Location**:
  - `crates/memo-workflow-cli/tests/cli_contract.rs`
- **Description**: Add integration tests covering search command result correctness and script-filter `search` intent, while ensuring CRUD assertions stay green.
- **Dependencies**:
  - Task 2.4
- **Complexity**: 7
- **Acceptance criteria**:
  - Tests use isolated temp DB and create deterministic seed records.
  - Search query verifies matching rows and non-match behavior.
  - Existing CRUD contract tests remain unchanged in expected semantics.
- **Validation**:
  - `cargo test -p nils-memo-workflow-cli`
  - `cargo test -p nils-memo-workflow-cli -- --nocapture`

### Task 4.2: Refresh memo docs and troubleshooting for search + version bump
- **Location**:
  - `crates/memo-workflow-cli/docs/workflow-contract.md`
  - `workflows/memo-add/README.md`
  - `docs/WORKFLOW_GUIDE.md`
  - `TROUBLESHOOTING.md`
  - `crates/memo-workflow-cli/README.md`
- **Description**: Update behavior docs, examples, troubleshooting matrix, and version references from `0.3.5` to `0.3.6` with search guidance and validation commands.
- **Dependencies**:
  - Task 3.2
- **Complexity**: 5
- **Acceptance criteria**:
  - All memo-focused docs reference `0.3.6`.
  - Search keyword/intent examples and failure cases are documented.
  - Operator checklist includes search validation command(s).
- **Validation**:
  - `rg -n "0\\.3\\.6|mmq|search" crates/memo-workflow-cli/docs/workflow-contract.md workflows/memo-add/README.md docs/WORKFLOW_GUIDE.md TROUBLESHOOTING.md crates/memo-workflow-cli/README.md`
  - `! rg -n "0\\.3\\.5" crates/memo-workflow-cli/docs/workflow-contract.md workflows/memo-add/README.md docs/WORKFLOW_GUIDE.md TROUBLESHOOTING.md crates/memo-workflow-cli/README.md`

### Task 4.3: Execute full quality gates and packaging checks
- **Location**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh`
- **Description**: Run repo-required lint/test/package gates and verify memo workflow package integrity after search integration.
- **Dependencies**:
  - Task 4.1
  - Task 4.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Required lint/test gates pass for changed scope.
  - `memo-add` package builds with new keyword wiring and bundled runtime.
  - No regressions in memo workflow smoke/contract checks.
- **Validation**:
  - `scripts/workflow-lint.sh`
  - `cargo test --workspace`
  - `scripts/workflow-test.sh --id memo-add`
  - `scripts/workflow-pack.sh --id memo-add`

## Testing Strategy
- Unit:
  - Extend `crates/memo-workflow-cli/src/lib.rs` tests for search parser, query guardrails, and rendering behavior.
- Integration:
  - Extend `crates/memo-workflow-cli/tests/cli_contract.rs` with temp-DB search command + script-filter search cases.
- Workflow smoke:
  - Extend `workflows/memo-add/tests/smoke.sh` stubs/assertions for `mmq` route and packaged plist keyword set.
- End-to-end packaging:
  - Build and inspect packaged plist keyword/script wiring via `scripts/workflow-pack.sh --id memo-add` + `plutil/jq`.

## Risks & gotchas
- Upstream `nils-memo-cli@0.3.6` search API shape may differ from assumptions (naming/limit semantics), requiring adapter changes.
- Search behavior could accidentally shadow default add behavior if intent parsing precedence is incorrect.
- New keyword wiring increases plist object/connection count; missing one connection silently breaks Alfred flow.
- Large memo DBs may surface performance issues if search is unbounded; enforce strict default limit in runtime.

## Rollback plan
1. Revert dependency pin to `nils-memo-cli = "=0.3.5"` and restore `Cargo.lock`.
2. Revert runtime search command and script-filter search intent changes in `crates/memo-workflow-cli`.
3. Remove `mmq` wiring (`script_filter_search.sh`, command-entry row, plist keyword object/connection).
4. Restore memo docs/contracts to pre-search wording (`mmq` back to reserved).
5. Re-run `scripts/workflow-test.sh --id memo-add` and `scripts/workflow-pack.sh --id memo-add` to confirm stable fallback.
