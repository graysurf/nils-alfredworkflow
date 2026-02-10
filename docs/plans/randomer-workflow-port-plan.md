# Plan: Port `alfred-randomer` and extend numeric formats

## Overview
This plan ports the installed Alfred workflow `com.github.fedecalendino.alfred-randomer` into this monorepo as a first-class workflow with the repository's Rust + Bash adapter pattern.
The baseline behavior to preserve is type-driven random value generation with Alfred Script Filter output and one-click copy behavior.
In addition to parity types (`email`, `imei`, `unit`, `uuid`), this plan adds common numeric formats: `int`, `decimal`, `percent`, `currency`, `hex`, and `otp`.
The implementation emphasizes deterministic tests (format invariants + smoke stubs) so CI/local validation does not depend on Alfred runtime state.

## Scope
- In scope: New workflow `randomer` under `workflows/randomer` with script filter + copy action.
- In scope: New Rust crate `randomer-cli` for query parsing, random generators, and Alfred JSON output.
- In scope: Port parity behavior from installed Randomer for `email`, `imei`, `unit`, `uuid`.
- In scope: Add numeric formats `int`, `decimal`, `percent`, `currency`, `hex`, `otp` with explicit output contracts.
- In scope: Deterministic smoke test, docs, and packaging integration.
- Out of scope: Runtime configuration UI for per-format custom ranges/precision in v1.
- Out of scope: Locale-aware currency/i18n formatting beyond fixed USD-style v1 output.
- Out of scope: Maintaining Python runtime dependencies from original workflow.
- Out of scope: Refactoring unrelated existing workflows/crates.

## Assumptions (if any)
1. `randomer` will be introduced as a new workflow ID and bundle ID `com.graysurf.randomer`.
2. Numeric-format expansion for v1 is fixed to `int`, `decimal`, `percent`, `currency`, `hex`, `otp`.
3. `currency` uses deterministic en-US style formatting (for example `$1,234.56`) for MVP consistency.
4. Clipboard behavior will be implemented with workflow action script (`pbcopy`) rather than Alfred clipboard output object to match current repo pattern.

## Success Criteria
- Alfred keyword returns valid JSON items for all supported types: `email`, `imei`, `unit`, `uuid`, `int`, `decimal`, `percent`, `currency`, `hex`, `otp`.
- Query behavior matches Randomer parity:
  - empty/unknown query: list all available types (one sample per type).
  - exact type query: show 5 generated values for that type.
- Selecting an item copies the generated value to clipboard.
- `scripts/workflow-lint.sh`, `scripts/workflow-test.sh --id randomer`, and `scripts/workflow-pack.sh --id randomer` pass.
- `scripts/workflow-test.sh` and `scripts/workflow-pack.sh --all` still pass for the full monorepo.

## Dependency & Parallelization Map
- Critical path:
  - `Task 1.1 -> Task 1.2 -> Task 1.3 -> Task 2.1 -> Task 2.2 -> Task 2.3 -> Task 2.4 -> Task 2.5 -> Task 3.1 -> Task 3.3 -> Task 3.4 -> Task 4.2`.
- Parallel track A:
  - `Task 1.4` after `Task 1.1`, parallel with `Task 1.3`.
- Parallel track B:
  - `Task 2.6` after `Task 2.2` and `Task 2.3`, parallel with `Task 2.5`.
- Parallel track C:
  - `Task 3.2` after `Task 1.2`, parallel with `Task 3.1`.
- Parallel track D:
  - `Task 4.1` after `Task 3.3`, parallel with `Task 4.2`.

## Sprint 1: Contract capture and scaffold
**Goal**: Lock behavior parity and scaffold workflow/crate surfaces with repository conventions.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/randomer-workflow-port-plan.md`, `test -d workflows/randomer`, `cargo check -p randomer-cli`
- Verify: Contract + skeleton are committed and workspace resolves new crate/workflow layout.

### Task 1.1: Write Randomer parity + extension contract
- **Location**:
  - `docs/randomer-contract.md`
- **Description**: Document query routing rules, supported type list, output format invariants, and copy behavior contract by porting observed behavior from installed Randomer and defining new numeric-format contracts.
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - Contract includes legacy types (`email`, `imei`, `unit`, `uuid`) and new numeric types (`int`, `decimal`, `percent`, `currency`, `hex`, `otp`).
  - Contract explicitly defines empty/unknown query fallback and exact-type 5-result behavior.
  - Contract defines validation invariants for each numeric format.
- **Validation**:
  - `test -f docs/randomer-contract.md`
  - `rg -n "Keyword and Query Handling|Supported Types|Format Invariants|Clipboard Behavior" docs/randomer-contract.md`
  - `rg -n "email|imei|unit|uuid|int|decimal|percent|currency|hex|otp" docs/randomer-contract.md`
  - `rg -n "empty query|unknown query|5 generated values|arg|valid" docs/randomer-contract.md`

### Task 1.2: Scaffold `randomer` workflow directory
- **Location**:
  - `workflows/randomer/workflow.toml`
  - `workflows/randomer/scripts/script_filter.sh`
  - `workflows/randomer/scripts/action_open.sh`
  - `workflows/randomer/src/info.plist.template`
  - `workflows/randomer/src/assets/icon.png`
  - `workflows/randomer/tests/smoke.sh`
- **Description**: Create workflow skeleton from template and align manifest keys for `randomer-cli` integration while preserving repository script conventions.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Workflow directory contains required files and executable scripts.
  - `workflow.toml` references `randomer-cli` as `rust_binary`.
- **Validation**:
  - `test -d workflows/randomer`
  - `test -f workflows/randomer/workflow.toml`
  - `test -x workflows/randomer/scripts/script_filter.sh`
  - `rg -n 'rust_binary\\s*=\\s*"randomer-cli"' workflows/randomer/workflow.toml`

### Task 1.3: Add `randomer-cli` crate and workspace membership
- **Location**:
  - `Cargo.toml`
  - `crates/randomer-cli/Cargo.toml`
  - `crates/randomer-cli/src/lib.rs`
  - `crates/randomer-cli/src/main.rs`
- **Description**: Create dedicated CLI crate for random value generation and Alfred JSON output, aligned with existing crate split pattern.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Workspace includes `crates/randomer-cli`.
  - `cargo run -p randomer-cli -- --help` succeeds.
- **Validation**:
  - `cargo check -p randomer-cli`
  - `cargo run -p randomer-cli -- --help`

### Task 1.4: Freeze parity fixtures from installed Randomer behavior
- **Location**:
  - `docs/randomer-contract.md`
  - `crates/randomer-cli/tests/parity.rs`
- **Description**: Encode non-random structural parity rules from installed Randomer (`main.py` + `generators.py`) into testable invariants (for example IMEI checksum, unit checksum, UUID syntax) to reduce regressions during Rust port.
- **Dependencies**:
  - Task 1.1
  - Task 1.3
- **Complexity**: 6
- **Acceptance criteria**:
  - At least one parity test exists for each legacy generator.
  - Tests validate structure/checksum rules, not specific random values.
- **Validation**:
  - `cargo test -p randomer-cli --test parity`
  - `cargo test -p randomer-cli -- --list | rg "parity_|imei|unit|uuid|email"`

## Sprint 2: Randomer CLI implementation
**Goal**: Implement query routing + generators + Alfred feedback contract in `randomer-cli`.
**Demo/Validation**:
- Command(s): `cargo test -p randomer-cli`, `cargo run -p randomer-cli -- generate --query "imei"`
- Verify: CLI emits valid Alfred JSON and generation rules satisfy parity + new format contracts.

### Task 2.1: Implement query parser and type routing
- **Location**:
  - `crates/randomer-cli/src/lib.rs`
  - `crates/randomer-cli/src/main.rs`
- **Description**: Implement command parsing and routing logic for empty/unknown query fallback vs exact-type mode with 5 rows.
- **Dependencies**:
  - Task 1.3
  - Task 1.4
- **Complexity**: 5
- **Acceptance criteria**:
  - Query parsing is case-insensitive and trims whitespace.
  - Exact supported type yields 5 generated rows; unknown query yields full type list.
- **Validation**:
  - `cargo test -p randomer-cli`
  - `cargo test -p randomer-cli -- --list | rg "query_|routing_|case_insensitive"`

### Task 2.2: Port legacy generators (`email`, `imei`, `unit`, `uuid`)
- **Location**:
  - `crates/randomer-cli/src/generators.rs`
- **Description**: Implement Rust generator functions that preserve legacy Randomer structural behavior for existing types.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 7
- **Acceptance criteria**:
  - `imei` output is 15 digits and checksum-valid.
  - `unit` output matches expected length/prefix/checksum constraints.
  - `uuid` output parses as RFC-4122 UUID.
- **Validation**:
  - `cargo test -p randomer-cli`
  - `cargo test -p randomer-cli imei_checksum_is_valid`
  - `cargo test -p randomer-cli unit_checksum_is_valid`
  - `cargo test -p randomer-cli uuid_is_rfc4122`
  - `cargo test -p randomer-cli email_shape_is_lowercase_local_at_domain`

### Task 2.3: Add numeric format generators (`int`, `decimal`, `percent`, `currency`, `hex`, `otp`)
- **Location**:
  - `crates/randomer-cli/src/generators.rs`
  - `docs/randomer-contract.md`
- **Description**: Implement six numeric generators with explicit formatting invariants and update contract examples accordingly.
- **Dependencies**:
  - Task 2.2
- **Complexity**: 7
- **Acceptance criteria**:
  - `int` is digits-only integer.
  - `decimal` has fixed 2 decimal places.
  - `percent` is formatted with `%` suffix and bounded numeric range.
  - `currency` uses `$` prefix + grouped thousands + 2 decimals.
  - `hex` has `0x` prefix and fixed-width uppercase hex digits.
  - `otp` is zero-padded 6-digit string.
- **Validation**:
  - `cargo test -p randomer-cli`
  - `cargo test -p randomer-cli format_int_is_digits_only`
  - `cargo test -p randomer-cli format_decimal_has_fixed_scale_2`
  - `cargo test -p randomer-cli format_percent_has_suffix_and_range`
  - `cargo test -p randomer-cli format_currency_has_symbol_grouping_and_scale_2`
  - `cargo test -p randomer-cli format_hex_has_prefix_and_fixed_width`
  - `cargo test -p randomer-cli format_otp_is_six_digits_zero_padded`
  - `rg -n "int|decimal|percent|currency|hex|otp" docs/randomer-contract.md`

### Task 2.4: Implement Alfred feedback mapping
- **Location**:
  - `crates/randomer-cli/src/feedback.rs`
  - `crates/randomer-cli/src/lib.rs`
- **Description**: Map generation output to Alfred items with `title=value`, `subtitle=type`, `arg=value`, and deterministic ordering.
- **Dependencies**:
  - Task 2.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Payload contains `items` array only (Alfred JSON contract).
  - Fallback list ordering is stable across runs.
  - Every item is actionable for copy flow (`valid=true`, has `arg`).
- **Validation**:
  - `cargo test -p randomer-cli`
  - `cargo run -p randomer-cli -- generate --query "" | jq -e '.items | length == 10'`
  - `cargo run -p randomer-cli -- generate --query "unknown" | jq -e '.items | type == "array" and length >= 10'`
  - `cargo run -p randomer-cli -- generate --query "uuid" | jq -e '.items | length == 5 and all(.[]; .arg != null and (.valid == null or .valid == true))'`
  - `cargo run -p randomer-cli -- generate --query "uuid" | jq -e 'all(.items[]; .subtitle == "uuid")'`

### Task 2.5: Finalize CLI surface and error handling
- **Location**:
  - `crates/randomer-cli/src/main.rs`
- **Description**: Finalize `generate --query` command contract with JSON-only stdout and deterministic error code/message behavior.
- **Dependencies**:
  - Task 2.4
- **Complexity**: 4
- **Acceptance criteria**:
  - `--help` and invalid command paths are stable.
  - Runtime execution prints valid JSON without extra log noise.
- **Validation**:
  - `cargo run -p randomer-cli -- --help`
  - `cargo run -p randomer-cli -- generate --query "imei" | jq -e '.items | length == 5'`
  - `bash -c 'set +e; cargo run -p randomer-cli -- generate >/dev/null 2>&1; test $? -ne 0'`

### Task 2.6: Add generator contract tests for all formats
- **Location**:
  - `crates/randomer-cli/src/generators.rs`
  - `crates/randomer-cli/tests/parity.rs`
- **Description**: Add focused tests for regex/checksum/range constraints and deterministic routing behavior to lock contracts.
- **Dependencies**:
  - Task 2.2
  - Task 2.3
- **Complexity**: 6
- **Acceptance criteria**:
  - Each supported type has at least one direct contract test.
  - Tests avoid flaky expectations based on specific random values.
- **Validation**:
  - `cargo test -p randomer-cli`
  - `cargo test -p randomer-cli parity_`
  - `cargo test -p randomer-cli format_`
  - `cargo test -p randomer-cli query_routing_`

## Sprint 3: Alfred integration and smoke hardening
**Goal**: Wire workflow scripts/plist for copy-centric UX and ensure deterministic smoke validation.
**Demo/Validation**:
- Command(s): `bash workflows/randomer/tests/smoke.sh`, `scripts/workflow-pack.sh --id randomer`
- Verify: Script filter + copy action + packaged plist wiring pass without Alfred UI dependency.

### Task 3.1: Implement `script_filter.sh` adapter
- **Location**:
  - `workflows/randomer/scripts/script_filter.sh`
- **Description**: Resolve `randomer-cli` binary path (packaged/release/debug), run `generate --query`, and emit fallback Alfred error JSON when execution fails.
- **Dependencies**:
  - Task 2.5
- **Complexity**: 5
- **Acceptance criteria**:
  - Adapter always outputs valid Alfred JSON.
  - Empty query still returns list-mode output (not hard failure).
- **Validation**:
  - `shellcheck workflows/randomer/scripts/script_filter.sh`
  - `shfmt -d workflows/randomer/scripts/script_filter.sh`
  - `bash workflows/randomer/scripts/script_filter.sh "" | jq -e '.items | type == "array"'`

### Task 3.2: Implement copy action script
- **Location**:
  - `workflows/randomer/scripts/action_open.sh`
- **Description**: Replace URL-open semantics with clipboard copy semantics (`pbcopy`) while preserving argument validation and exit-code conventions.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 3
- **Acceptance criteria**:
  - Missing argument exits with usage error code.
  - Valid argument is copied exactly to clipboard without newline mutation.
- **Validation**:
  - `shellcheck workflows/randomer/scripts/action_open.sh`
  - `bash -c 'tmpdir="$(mktemp -d)"; printf "#!/usr/bin/env bash\ncat >\"$tmpdir/out\"\n" >"$tmpdir/pbcopy"; chmod +x "$tmpdir/pbcopy"; PATH="$tmpdir:$PATH" workflows/randomer/scripts/action_open.sh "123456"; test "$(cat "$tmpdir/out")" = "123456"; rm -rf "$tmpdir"'`
  - `bash -c 'set +e; workflows/randomer/scripts/action_open.sh >/dev/null 2>&1; test $? -eq 2'`

### Task 3.3: Wire `info.plist.template` + manifest for Randomer UX
- **Location**:
  - `workflows/randomer/src/info.plist.template`
  - `workflows/randomer/workflow.toml`
- **Description**: Configure keyword trigger, script/action object graph, user-facing subtitle/help text, and metadata fields for packaged workflow parity.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Packaged plist has script filter -> action connection and correct scriptfile paths.
  - Keyword/subtitle text guides users to supported type names.
  - Bundle metadata and version wiring are valid.
- **Validation**:
  - `scripts/workflow-pack.sh --id randomer`
  - `plutil -lint build/workflows/randomer/pkg/info.plist`
  - `plutil -convert json -o - build/workflows/randomer/pkg/info.plist | jq -e '.objects | length > 0 and .connections | length > 0'`

### Task 3.4: Build deterministic smoke test for randomer workflow
- **Location**:
  - `workflows/randomer/tests/smoke.sh`
- **Description**: Add smoke checks for required files/executability, action copy behavior, script filter JSON validity, error fallback, and packaged plist wiring.
- **Dependencies**:
  - Task 3.3
- **Complexity**: 8
- **Acceptance criteria**:
  - Smoke test passes without live Alfred interaction.
  - Smoke test validates package output includes `bin/randomer-cli`.
  - Smoke test catches broken script wiring and malformed JSON.
- **Validation**:
  - `bash workflows/randomer/tests/smoke.sh`
  - `scripts/workflow-test.sh --id randomer`

### Task 3.5: Ensure monorepo pack/test entrypoints include randomer
- **Location**:
  - `scripts/workflow-pack.sh`
  - `scripts/workflow-test.sh`
- **Description**: Verify existing list-based pack/test scripts include the new workflow by convention and document any compatibility adjustment if needed.
- **Dependencies**:
  - Task 3.4
- **Complexity**: 2
- **Acceptance criteria**:
  - No script code changes are required unless a real gap is proven.
  - `--all` commands include randomer artifact/test automatically.
- **Validation**:
  - `scripts/workflow-pack.sh --all`
  - `scripts/workflow-test.sh`
  - `find dist -type f -path '*randomer*' | sort`

## Sprint 4: Documentation, quality gates, and rollout safety
**Goal**: Finish operator docs and run repository-required gates before merge/release.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `scripts/workflow-test.sh`, `scripts/workflow-pack.sh --id randomer --install`
- Verify: New workflow is documented, tested, and installable without regressions.

### Task 4.1: Add docs for usage and supported formats
- **Location**:
  - `README.md`
  - `workflows/randomer/README.md`
  - `docs/randomer-contract.md`
- **Description**: Document keyword usage, type list, copy behavior, format examples, and troubleshooting tips for invalid queries.
- **Dependencies**:
  - Task 3.3
- **Complexity**: 4
- **Acceptance criteria**:
  - Docs list all supported types and show at least one example query flow.
  - Packaging/test commands for operators are copy-paste ready.
- **Validation**:
  - `rg -n "randomer|email|imei|unit|uuid|int|decimal|percent|currency|hex|otp" README.md workflows/randomer/README.md docs/randomer-contract.md`
  - `rg -n "workflow-pack.sh --id randomer|workflow-test.sh --id randomer" README.md workflows/randomer/README.md`

### Task 4.2: Execute required quality gates from `DEVELOPMENT.md`
- **Location**:
  - `DEVELOPMENT.md`
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
- **Description**: Run required format/lint/test gates and resolve any regressions before declaring completion.
- **Dependencies**:
  - Task 3.4
  - Task 4.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Required commands from `DEVELOPMENT.md` all pass.
  - Workflow-specific smoke is included in global test pass.
- **Validation**:
  - `cargo fmt --all -- --check`
  - `cargo clippy --workspace --all-targets -- -D warnings`
  - `cargo test --workspace`
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh --id randomer`

### Task 4.3: macOS acceptance and rollback drill
- **Location**:
  - `TROUBLESHOOTING.md`
  - `workflows/randomer/tests/smoke.sh`
- **Description**: Verify packaged install behavior on macOS (including quarantine edge cases) and record rollback execution checklist for rapid disable/revert if needed.
- **Dependencies**:
  - Task 4.2
- **Complexity**: 4
- **Acceptance criteria**:
  - Install + manual keyword run verifies copy workflow in Alfred.
  - Rollback checklist is concrete and references exact files/commands.
- **Validation**:
  - `scripts/workflow-pack.sh --id randomer --install`
  - `bash workflows/randomer/tests/smoke.sh`
  - `rg -n "Gatekeeper|quarantine|randomer" TROUBLESHOOTING.md`

## Testing Strategy
- Unit:
  - `randomer-cli` tests for query routing, generator invariants, and Alfred payload mapping.
- Integration:
  - Script lint/format checks (`shellcheck`, `shfmt`) + script-level success/failure behavior.
- E2E/manual:
  - Package/install workflow, run keyword queries for all types, confirm selection copies value to clipboard.

## Risks & gotchas
- Random output can create flaky assertions if tests validate exact values instead of structure/checksum/range.
- `unit` generator checksum logic is easy to regress during language port because of letter-value mapping and recursion edge cases.
- Clipboard behavior differs by environment; `pbcopy` assumptions should be isolated in action script and smoke stubs.
- Keyword compatibility (`random||rand`) may vary by Alfred field semantics; behavior needs explicit verification in packaged plist.
- Adding many formats can reduce discoverability; list ordering and subtitle guidance should remain stable and concise.

## Rollback plan
- Operational steps:
  1. Revert the Randomer implementation commit(s) with `git revert <commit>` (or drop the feature branch before merge).
  2. Remove Randomer-specific additions and workspace membership listed below if the revert is partial.
  3. Run `cargo clean` to clear stale `randomer-cli` binaries from local build cache.
  4. Re-run baseline gates and ensure `dist` no longer contains randomer artifacts.
- Randomer-specific additions to remove if needed:
  - `crates/randomer-cli/Cargo.toml`
  - `crates/randomer-cli/src/lib.rs`
  - `crates/randomer-cli/src/main.rs`
  - `crates/randomer-cli/src/generators.rs`
  - `crates/randomer-cli/src/feedback.rs`
  - `crates/randomer-cli/tests/parity.rs`
  - `workflows/randomer/workflow.toml`
  - `workflows/randomer/scripts/script_filter.sh`
  - `workflows/randomer/scripts/action_open.sh`
  - `workflows/randomer/src/info.plist.template`
  - `workflows/randomer/tests/smoke.sh`
  - `workflows/randomer/README.md`
  - `docs/randomer-contract.md`
- Remove workspace member for `crates/randomer-cli` from `Cargo.toml`.
- Re-run baseline gates to confirm rollback health:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh --all`
  - `bash -c 'test "$(find dist -type f -path "*randomer*" | wc -l | tr -d " ")" = "0"'`
