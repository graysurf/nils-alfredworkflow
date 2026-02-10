# Plan: Port Epoch Converter workflow with formatted date row

## Overview
This plan ports the currently installed Alfred workflow `snooze92.epoch.converter` into this monorepo as a native Rust + shell workflow.
The target keeps the original conversion behavior (epoch to datetime, datetime to epoch, clipboard assist, current timestamp items) while aligning with repository conventions for packaging, tests, and deterministic scripts.
A new requirement is added: conversion output must include one extra row showing a date-formatted time string.
Implementation emphasizes deterministic local execution without external API dependencies.

## Scope
- In scope: New workflow `epoch-converter` under `workflows/epoch-converter`.
- In scope: New Rust crate `epoch-cli` for conversion parsing, normalization, and Alfred JSON generation.
- In scope: Keyword parity (`ts`) and support for epoch precision auto-detection (`s`, `ms`, `us`, `ns`).
- In scope: Datetime-to-epoch conversion for local/UTC and multi-precision outputs.
- In scope: Clipboard-assisted conversion attempts when query is empty or partial.
- In scope: One additional Alfred output row showing date-formatted time (`YYYY-MM-DD HH:MM:SS`) for converted timestamps.
- In scope: Smoke tests covering script behavior, plist wiring, and package artifact integrity.
- Out of scope: Natural-language parsing such as "next Friday 3pm".
- Out of scope: Arbitrary timezone database conversion beyond local timezone and UTC.
- Out of scope: Backporting changes to the original Python-based installed workflow.

## Assumptions (if any)
1. `ts` remains the primary keyword for user muscle memory; no new keyword is introduced.
2. "多加一列是日期格式的時間" means adding one explicit formatted-datetime row in conversion results.
3. Formatted datetime uses local timezone by default and format `YYYY-MM-DD HH:MM:SS`.
4. Existing monorepo packaging flow (`scripts/workflow-pack.sh`) remains the release path.

## Success Criteria
- `ts <epoch>` returns deterministic Alfred items including local/UTC conversions and one extra date-formatted row.
- `ts <date/time>` returns local/UTC epoch values in `s`, `ms`, `us`, `ns` precision.
- Query-empty flow still shows current timestamps and attempts clipboard conversion safely.
- `bash workflows/epoch-converter/tests/smoke.sh` passes without network.
- `scripts/workflow-lint.sh`, `cargo test --workspace`, and `scripts/workflow-test.sh --id epoch-converter` pass.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 1.3 -> Task 2.1 -> Task 2.2 -> Task 2.3 -> Task 2.5 -> Task 3.1 -> Task 3.4 -> Task 4.1`.
- Parallel track A: `Task 1.4` can run after `Task 1.1` in parallel with `Task 1.3`.
- Parallel track B: `Task 2.4` can run after `Task 2.1` in parallel with `Task 2.3`.
- Parallel track C: `Task 2.6` can run after `Task 2.5` in parallel with `Task 3.2`.
- Parallel track D: `Task 3.3` can run after `Task 3.1` in parallel with `Task 3.2`.
- Parallel track E: `Task 3.5` can run after `Task 3.4` in parallel with `Task 4.2`.

## Sprint 1: Contract capture and scaffold
**Goal**: Freeze behavior parity against the installed workflow and create skeleton files aligned to this repository.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/epoch-converter-workflow-plan.md`, `test -d workflows/epoch-converter`, `cargo check -p epoch-cli`
- Verify: Contract and scaffold are committed, and workspace resolves new crate/workflow paths.

### Task 1.1: Document source workflow behavior and delta requirements
- **Location**:
  - `docs/epoch-converter-contract.md`
  - `docs/plans/epoch-converter-workflow-plan.md`
- **Description**: Record baseline behavior from installed workflow `snooze92.epoch.converter` (input patterns, output item taxonomy, clipboard behavior, current timestamp items) and explicitly add the new formatted-date-row requirement.
- **Dependencies**:
  - none
- **Complexity**: 4
- **Acceptance criteria**:
  - Contract includes separate sections for epoch->datetime, datetime->epoch, clipboard assist, and empty-query behavior.
  - Contract explicitly states the additional formatted datetime row and exact format.
  - Contract defines deterministic behavior for invalid input and overflow edge cases.
- **Validation**:
  - `test -f docs/epoch-converter-contract.md`
  - `rg -n "epoch->datetime|datetime->epoch|clipboard|formatted datetime row|invalid input" docs/epoch-converter-contract.md`

### Task 1.2: Scaffold `epoch-converter` workflow structure
- **Location**:
  - `workflows/epoch-converter/workflow.toml`
  - `workflows/epoch-converter/scripts/script_filter.sh`
  - `workflows/epoch-converter/scripts/action_copy.sh`
  - `workflows/epoch-converter/src/info.plist.template`
  - `workflows/epoch-converter/src/assets/icon.png`
  - `workflows/epoch-converter/tests/smoke.sh`
- **Description**: Create workflow directory from template conventions and wire manifest fields (`id`, `bundle_id`, `script_filter`, `action`, `rust_binary`) for an epoch conversion workflow.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Workflow folder contains all required files and executable scripts.
  - Manifest keyword/action wiring matches intended command flow (`ts` -> script filter -> copy action).
  - Manifest `rust_binary` points to `epoch-cli`.
- **Validation**:
  - `test -d workflows/epoch-converter`
  - `test -f workflows/epoch-converter/workflow.toml`
  - `test -x workflows/epoch-converter/scripts/script_filter.sh`
  - `test -x workflows/epoch-converter/scripts/action_copy.sh`
  - `rg -n 'rust_binary\\s*=\\s*"epoch-cli"' workflows/epoch-converter/workflow.toml`

### Task 1.3: Add `epoch-cli` crate and workspace membership
- **Location**:
  - `Cargo.toml`
  - `crates/epoch-cli/Cargo.toml`
  - `crates/epoch-cli/src/lib.rs`
  - `crates/epoch-cli/src/main.rs`
- **Description**: Introduce a dedicated binary crate for conversion logic, keeping shell adapters thin and testable.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Workspace members include `crates/epoch-cli`.
  - CLI help command is available and exits successfully.
- **Validation**:
  - `cargo check -p epoch-cli`
  - `cargo run -p epoch-cli -- --help`

### Task 1.4: Define output schema and formatted-row contract
- **Location**:
  - `docs/epoch-converter-contract.md`
  - `crates/epoch-cli/src/feedback.rs`
  - `workflows/epoch-converter/README.md`
- **Description**: Define output item schema and labels so the extra formatted row is stable, discoverable, and copy-friendly.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Contract names all output item categories and copy payload behavior.
  - Formatted row label and format string are fixed and tested.
  - README examples include one query showing the extra row.
- **Validation**:
  - `rg -n "formatted|YYYY-MM-DD HH:MM:SS|copy payload|output schema" docs/epoch-converter-contract.md workflows/epoch-converter/README.md`

## Sprint 2: Conversion engine and CLI behavior
**Goal**: Build deterministic Rust conversion logic covering all supported input modes and output rows.
**Demo/Validation**:
- Command(s): `cargo test -p epoch-cli`, `cargo run -p epoch-cli -- convert --query "1700000000" | jq -e '.items | type == "array"'`
- Verify: CLI emits valid Alfred JSON and includes required conversion rows.

### Task 2.1: Implement input parser and precision inference
- **Location**:
  - `crates/epoch-cli/src/parser.rs`
  - `crates/epoch-cli/src/lib.rs`
- **Description**: Parse integer epoch inputs and datetime-like inputs (`YYYY-MM-DD`, `YYYY-MM-DD HH:MM[:SS[.sub]]`, `HH:MM[:SS[.sub]]`) and infer epoch precision by magnitude.
- **Dependencies**:
  - Task 1.3
  - Task 1.4
- **Complexity**: 8
- **Acceptance criteria**:
  - Epoch parser supports seconds/milliseconds/microseconds/nanoseconds input widths.
  - Datetime parser supports both space and `T` separators.
  - Invalid input returns structured user-facing parse errors without panic.
- **Validation**:
  - `cargo test -p epoch-cli -- --list | rg "parser_|precision_|datetime_"`
  - `cargo test -p epoch-cli parser`

### Task 2.2: Implement epoch-to-datetime conversion outputs
- **Location**:
  - `crates/epoch-cli/src/convert.rs`
  - `crates/epoch-cli/src/feedback.rs`
- **Description**: Convert epoch input to local and UTC datetime outputs, preserve subsecond precision, and add one extra formatted-date row (`YYYY-MM-DD HH:MM:SS`) as required.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 8
- **Acceptance criteria**:
  - Local and UTC datetime rows are both produced for valid epoch input.
  - Additional formatted row is always present for valid epoch input and follows exact format.
  - Subsecond suffix is preserved when input carries subsecond precision.
- **Validation**:
  - `cargo test -p epoch-cli -- --list | rg "epoch_to_datetime|formatted_row|subsecond"`
  - `cargo test -p epoch-cli epoch_to_datetime`
  - `cargo run -p epoch-cli -- convert --query "1700000000123" | jq -e '.items[] | select(.subtitle | contains("Formatted"))'`

### Task 2.3: Implement datetime-to-epoch conversion outputs
- **Location**:
  - `crates/epoch-cli/src/convert.rs`
  - `crates/epoch-cli/src/feedback.rs`
- **Description**: Convert parsed datetime input into local/UTC epoch outputs for `s`, `ms`, `us`, and `ns`.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 7
- **Acceptance criteria**:
  - For valid datetime input, eight rows are returned (local+UTC across 4 precisions).
  - Time-only input resolves against current local date deterministically.
  - Conversion logic handles leap-second-unsafe inputs by returning parse errors instead of silent corruption.
- **Validation**:
  - `cargo test -p epoch-cli -- --list | rg "datetime_to_epoch|timezone_|precision_rows"`
  - `cargo test -p epoch-cli datetime_to_epoch`
  - `cargo run -p epoch-cli -- convert --query "2025-01-02 03:04:05" | jq -e '.items | length >= 8'`

### Task 2.4: Implement clipboard and current timestamp item generation
- **Location**:
  - `crates/epoch-cli/src/clipboard.rs`
  - `crates/epoch-cli/src/main.rs`
  - `crates/epoch-cli/src/feedback.rs`
- **Description**: Add clipboard read support (best-effort) and emit current timestamp rows (`s`, `ms`, `us`, `ns`) when query is empty, while avoiding hard failure if clipboard access is unavailable.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 6
- **Acceptance criteria**:
  - Empty-query output includes current timestamp rows consistently.
  - Clipboard conversion rows are prefixed and distinguishable from query-based rows.
  - Clipboard read failures degrade gracefully.
- **Validation**:
  - `cargo test -p epoch-cli -- --list | rg "clipboard_|current_timestamp_|empty_query"`
  - `cargo test -p epoch-cli empty_query`

### Task 2.5: Implement CLI command surface and exit-code contract
- **Location**:
  - `crates/epoch-cli/src/main.rs`
  - `crates/epoch-cli/src/error.rs`
- **Description**: Provide a `convert --query VALUE` command that prints Alfred JSON to stdout only on success and maps parse/runtime failures to deterministic stderr + exit codes.
- **Dependencies**:
  - Task 2.2
  - Task 2.3
  - Task 2.4
- **Complexity**: 6
- **Acceptance criteria**:
  - Success path never prints noise to stderr.
  - User input errors and runtime errors are distinguishable for shell adapter mapping.
  - CLI remains deterministic for smoke test stubbing.
- **Validation**:
  - `cargo test -p epoch-cli -- --list | rg "main_|error_kind|exit_code"`
  - `cargo test -p epoch-cli`
  - `cargo run -p epoch-cli -- convert --query "1700000000" | jq -e '.items | type == "array"'`
  - `bash -c 'tmp=\"$(mktemp -d)\"; cargo run -p epoch-cli -- convert --query "1700000000" >"$tmp/out.json" 2>"$tmp/err.log"; rc=$?; test $rc -eq 0; test ! -s "$tmp/err.log"; jq -e ".items | type == \"array\"" "$tmp/out.json" >/dev/null; rm -rf "$tmp"'`
  - `bash -c 'set +e; cargo run -p epoch-cli -- convert --query "not-a-date" >/tmp/epoch-cli-invalid.out 2>/tmp/epoch-cli-invalid.err; rc=$?; set -e; test $rc -ne 0; test -s /tmp/epoch-cli-invalid.err; rm -f /tmp/epoch-cli-invalid.out /tmp/epoch-cli-invalid.err'`

### Task 2.6: Add focused unit tests for edge cases and regression locks
- **Location**:
  - `crates/epoch-cli/src/parser.rs`
  - `crates/epoch-cli/src/convert.rs`
  - `crates/epoch-cli/src/main.rs`
- **Description**: Add edge-case tests for overflow bounds, whitespace normalization, invalid precision widths, timezone handling, and formatted-row presence.
- **Dependencies**:
  - Task 2.5
- **Complexity**: 6
- **Acceptance criteria**:
  - Tests lock behavior for boundary timestamps and malformed datetime input.
  - Tests explicitly assert the additional formatted row behavior.
  - Core conversion modules achieve meaningful branch coverage for error and success paths.
- **Validation**:
  - `cargo test -p epoch-cli`
  - `cargo test -p epoch-cli -- --nocapture`

## Sprint 3: Alfred adapter wiring and deterministic smoke coverage
**Goal**: Wire workflow scripts/plist for Alfred runtime and ensure packaging artifacts remain valid.
**Demo/Validation**:
- Command(s): `bash workflows/epoch-converter/tests/smoke.sh`, `scripts/workflow-pack.sh --id epoch-converter`
- Verify: Script filter emits valid JSON in all tested paths, and package artifacts pass structural checks.

### Task 3.1: Implement script-filter adapter with fallback mapping
- **Location**:
  - `workflows/epoch-converter/scripts/script_filter.sh`
- **Description**: Resolve `epoch-cli` from packaged/release/debug paths, invoke conversion command, and map CLI errors to non-crashing Alfred fallback items.
- **Dependencies**:
  - Task 2.5
  - Task 2.6
- **Complexity**: 6
- **Acceptance criteria**:
  - Script always outputs valid Alfred JSON.
  - Empty query still returns current timestamp rows and optional clipboard-derived rows.
  - Missing binary, invalid input, and runtime failures show actionable fallback items.
- **Validation**:
  - `shellcheck workflows/epoch-converter/scripts/script_filter.sh`
  - `shfmt -d workflows/epoch-converter/scripts/script_filter.sh`
  - `bash workflows/epoch-converter/scripts/script_filter.sh "1700000000" | jq -e '.items | type == "array"'`
  - `bash -c 'tmp=\"$(mktemp -d)\"; cat >"$tmp/epoch-cli-fail" <<\"EOS\"\n#!/usr/bin/env bash\nset -euo pipefail\necho \"invalid input\" >&2\nexit 2\nEOS\nchmod +x \"$tmp/epoch-cli-fail\"; EPOCH_CLI_BIN=\"$tmp/epoch-cli-fail\" bash workflows/epoch-converter/scripts/script_filter.sh \"bad\" | jq -e \".items[] | select(.valid == false)\" >/dev/null; rm -rf \"$tmp\"'`
  - `bash -c 'tmp=\"$(mktemp -d)\"; PATH=\"$tmp:$PATH\" EPOCH_CLI_BIN=\"$tmp/missing-epoch-cli\" bash workflows/epoch-converter/scripts/script_filter.sh \"1700000000\" | jq -e \".items[] | select(.valid == false)\" >/dev/null; rm -rf \"$tmp\"'`

### Task 3.2: Implement copy action script for selected conversion value
- **Location**:
  - `workflows/epoch-converter/scripts/action_copy.sh`
- **Description**: Add action script that copies selected item argument to clipboard (`pbcopy`) with proper usage handling for missing args.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 3
- **Acceptance criteria**:
  - Missing arg exits with usage error code.
  - Valid arg is copied without transformation.
  - Script behavior is deterministic under test stubs.
- **Validation**:
  - `shellcheck workflows/epoch-converter/scripts/action_copy.sh`
  - `bash -c 'set +e; bash workflows/epoch-converter/scripts/action_copy.sh >/dev/null 2>&1; test $? -eq 2'`
  - `bash -c 'tmpdir=\"$(mktemp -d)\"; printf \"#!/usr/bin/env bash\\ncat >\\\"$tmpdir/out\\\"\\n\" >\"$tmpdir/pbcopy\"; chmod +x \"$tmpdir/pbcopy\"; PATH=\"$tmpdir:$PATH\" bash workflows/epoch-converter/scripts/action_copy.sh \"1700000000\"; test \"$(cat \"$tmpdir/out\")\" = \"1700000000\"; rm -rf \"$tmpdir\"'`

### Task 3.3: Wire plist template and workflow metadata
- **Location**:
  - `workflows/epoch-converter/src/info.plist.template`
  - `workflows/epoch-converter/workflow.toml`
- **Description**: Configure Script Filter and Action nodes, keyword `ts`, and user-facing metadata consistent with repository plist conventions.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Packaged plist has valid object graph and script connections.
  - Keyword trigger is exactly `ts`.
  - Manifest and plist names/IDs are internally consistent.
- **Validation**:
  - `scripts/workflow-pack.sh --id epoch-converter`
  - `plutil -lint build/workflows/epoch-converter/pkg/info.plist`
  - `plutil -convert json -o - build/workflows/epoch-converter/pkg/info.plist | jq -e '.objects[] | select(.type=="alfred.workflow.input.scriptfilter") | .config.keyword == "ts"'`

### Task 3.4: Build smoke test for runtime parity and formatted-row assertion
- **Location**:
  - `workflows/epoch-converter/tests/smoke.sh`
- **Description**: Create deterministic smoke test with stubbed `epoch-cli` outputs and assertions for query conversion, clipboard behavior, fallback mapping, and the additional formatted-date row.
- **Dependencies**:
  - Task 3.1
  - Task 3.3
- **Complexity**: 8
- **Acceptance criteria**:
  - Smoke test validates required files, executable bits, manifest wiring, and packaged artifact integrity.
  - Smoke test includes explicit assertion that formatted-date row exists for epoch input.
  - Smoke test passes in local and CI-like environments without network.
- **Validation**:
  - `bash workflows/epoch-converter/tests/smoke.sh`
  - `scripts/workflow-test.sh --id epoch-converter`

### Task 3.5: Update workflow docs and operator guide
- **Location**:
  - `workflows/epoch-converter/README.md`
  - `README.md`
  - `docs/WORKFLOW_GUIDE.md`
- **Description**: Add setup/usage docs for epoch workflow, including examples that show the new formatted-date row and required validation commands.
- **Dependencies**:
  - Task 3.4
- **Complexity**: 4
- **Acceptance criteria**:
  - Root README lists `epoch-converter` in workflow catalog.
  - Workflow README documents supported input formats and copy behavior.
  - Guide references smoke/lint/pack entrypoints for this workflow.
- **Validation**:
  - `rg -n "epoch-converter|ts <|formatted" workflows/epoch-converter/README.md README.md docs/WORKFLOW_GUIDE.md`

## Sprint 4: Integration hardening and release readiness
**Goal**: Validate workspace-level quality gates, finalize migration notes, and ensure safe fallback path.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `cargo test --workspace`, `scripts/workflow-test.sh`
- Verify: Full repository checks pass with new workflow integrated.

### Task 4.1: Run required repository quality gates
- **Location**:
  - `DEVELOPMENT.md`
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
- **Description**: Execute required lint/test commands from project development policy and confirm no regressions across existing workflows.
- **Dependencies**:
  - Task 3.4
  - Task 3.5
- **Complexity**: 5
- **Acceptance criteria**:
  - Workspace fmt/clippy/test checks pass.
  - Workflow test suite passes for existing workflows and `epoch-converter`.
  - Any intermittent failure has documented root cause and mitigation path.
- **Validation**:
  - `cargo fmt --all -- --check`
  - `cargo clippy --workspace --all-targets -- -D warnings`
  - `cargo test --workspace`
  - `scripts/workflow-test.sh`

### Task 4.2: Package and local install acceptance for epoch workflow
- **Location**:
  - `dist/epoch-converter/0.1.5/Epoch Converter.alfredworkflow`
  - `dist/epoch-converter/0.1.5/Epoch Converter.alfredworkflow.sha256`
  - `build/workflows/epoch-converter/pkg/info.plist`
- **Description**: Produce packaged `.alfredworkflow`, verify checksum output, and run local install smoke to ensure end-user workflow behavior.
- **Dependencies**:
  - Task 4.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Packaging generates expected artifact and checksum.
  - Installed workflow executes `ts` keyword with query and empty-query flows.
  - Action script copies selected value reliably.
- **Validation**:
  - `scripts/workflow-pack.sh --id epoch-converter --install`
  - `test -f dist/epoch-converter/0.1.5/Epoch\ Converter.alfredworkflow`
  - `test -f dist/epoch-converter/0.1.5/Epoch\ Converter.alfredworkflow.sha256`

### Task 4.3: Migration and rollback operational notes
- **Location**:
  - `docs/epoch-converter-contract.md`
  - `TROUBLESHOOTING.md`
- **Description**: Document migration path from old installed workflow, keyword conflict handling, and explicit rollback steps to previous workflow package.
- **Dependencies**:
  - Task 4.2
- **Complexity**: 3
- **Acceptance criteria**:
  - Docs include clear "new workflow id vs old bundle id" guidance.
  - Rollback can be executed in under 5 minutes with deterministic commands.
  - Troubleshooting includes known clipboard and timezone pitfalls.
- **Validation**:
  - `rg -n "rollback|bundle id|keyword conflict|timezone|clipboard" docs/epoch-converter-contract.md TROUBLESHOOTING.md`

## Testing Strategy
- Unit: `epoch-cli` parser/converter/feedback tests lock input grammar, precision inference, timezone behavior, and formatted-row output.
- Integration: script adapter tests verify CLI resolution, fallback mapping, and JSON validity.
- E2E/manual: workflow smoke + packaged plist checks + local Alfred install check.

## Risks & gotchas
- Epoch precision inference can misclassify boundary values; tests must lock threshold behavior.
- Local timezone conversion can differ across DST boundaries; tests should use deterministic fixtures where possible.
- Clipboard access behavior differs by environment; code must degrade gracefully when `pbpaste` is unavailable.
- Keyword `ts` can conflict if old workflow stays enabled simultaneously; migration docs must define operator steps.

## Rollback plan
1. Disable/remove `epoch-converter` workflow package from Alfred and re-enable original `snooze92.epoch.converter`.
2. Reinstall previous stable artifact for this repo from `dist/epoch-converter/<previous-version>/`.
3. Revert workflow-specific files and crate membership commit if regression is code-level.
4. Run `scripts/workflow-test.sh --id epoch-converter` and `cargo test -p epoch-cli` on the rolled-back revision before re-publishing.
