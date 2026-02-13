# Plan: Multi-timezone clock workflow

## Overview
This plan adds a new Alfred workflow that shows current time across multiple IANA timezones.
When no timezone is provided, the workflow must auto-detect the local timezone and show exactly one row.
When one or more timezones are provided (for example `Asia/Taipei,America/New_York`), output order must strictly follow input order.
Implementation follows this repository's existing pattern: Rust CLI for logic plus shell adapter scripts for Alfred runtime wiring and fallback handling.

## Scope
- In scope: New workflow `multi-timezone` under `workflows/multi-timezone`.
- In scope: New Rust crate `timezone-cli` for parsing timezone lists, local-timezone fallback detection, and Alfred JSON output.
- In scope: Alfred configuration field for multiple timezone IDs, with query override behavior.
- In scope: Deterministic ordering rules so rendered rows follow the source input sequence.
- In scope: Fallback chain for local timezone detection with deterministic terminal fallback to `UTC`.
- In scope: Smoke tests, packaging checks, and docs updates.
- Out of scope: Date conversion between arbitrary timestamps (this workflow only shows "now").
- Out of scope: Human-language timezone parsing such as "Taipei time" or city-name geocoding.
- Out of scope: Network-based timezone lookup services.

## Assumptions (if any)
1. Workflow keyword is `tz`.
2. Alfred workflow env field `MULTI_TZ_ZONES` is the primary configurable field for multi-timezone input.
3. Query text, when non-empty, overrides `MULTI_TZ_ZONES`; when query text is empty, `MULTI_TZ_ZONES` is used.
4. If both query text and `MULTI_TZ_ZONES` are empty, the workflow renders one row using detected local timezone.
5. Invalid timezone IDs render explicit invalid feedback rows without crashing.

## Success Criteria
- `tz` (empty query, empty config field) returns exactly one valid row based on local-timezone detection fallback.
- `tz Asia/Taipei,America/New_York` returns two rows in the same order as typed.
- Configured field `MULTI_TZ_ZONES` accepts multiple IANA IDs and preserves configured order in output.
- Local-timezone detection fallback chain is implemented and test-covered, ending at `UTC` when all prior methods fail.
- `bash workflows/multi-timezone/tests/smoke.sh`, `scripts/workflow-test.sh --id multi-timezone`, and `scripts/workflow-lint.sh --id multi-timezone` pass.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 1.3 -> Task 1.4 -> Task 2.1 -> Task 2.3 -> Task 2.4 -> Task 3.1 -> Task 3.3 -> Task 3.4 -> Task 4.1`.
- Parallel track A: `Task 2.2` can run after `Task 1.3` in parallel with `Task 1.4`.
- Parallel track B: `Task 3.2` can run after `Task 1.2` in parallel with Sprint 2 tasks.
- Parallel track C: `Task 2.5` can run after `Task 2.4` in parallel with `Task 3.2`.

## Sprint 1: Contract, scaffold, and interface freeze
**Goal**: Lock behavior and scaffold workflow/crate structure with explicit input and ordering contracts.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/multi-timezone-workflow-plan.md`, `test -d workflows/multi-timezone`, `cargo check -p nils-timezone-cli`
- Verify: Repo contains scaffolded workflow and crate paths with agreed behavior contract documented.

### Task 1.1: Capture product contract and input precedence
- **Location**:
  - `crates/timezone-cli/docs/workflow-contract.md`
  - `docs/plans/multi-timezone-workflow-plan.md`
- **Description**: Document required behavior for empty input, configured timezone field, query override, invalid timezone handling, and strict row ordering semantics.
- **Dependencies**:
  - none
- **Complexity**: 4
- **Acceptance criteria**:
  - Contract defines input source precedence: query -> `MULTI_TZ_ZONES` -> local fallback.
  - Contract states output ordering rule as strict source-order preservation.
  - Contract defines valid timezone format as IANA ID (for example `Asia/Taipei`).
- **Validation**:
  - `test -f crates/timezone-cli/docs/workflow-contract.md`
  - `rg -n "precedence|MULTI_TZ_ZONES|IANA|order|fallback" crates/timezone-cli/docs/workflow-contract.md`

### Task 1.2: Scaffold `multi-timezone` workflow files
- **Location**:
  - `workflows/multi-timezone/workflow.toml`
  - `workflows/multi-timezone/scripts/script_filter.sh`
  - `workflows/multi-timezone/scripts/action_copy.sh`
  - `workflows/multi-timezone/src/info.plist.template`
  - `workflows/multi-timezone/src/assets/icon.png`
  - `workflows/multi-timezone/tests/smoke.sh`
- **Description**: Create workflow directory from repository template conventions and define manifest fields for a timezone-clock workflow.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Workflow contains required files and executable scripts.
  - `workflow.toml` includes `TIMEZONE_CLI_BIN`, `MULTI_TZ_ZONES`, and `MULTI_TZ_LOCAL_OVERRIDE` env keys.
  - `rust_binary` points to `timezone-cli`.
- **Validation**:
  - `test -d workflows/multi-timezone`
  - `test -f workflows/multi-timezone/workflow.toml`
  - `test -x workflows/multi-timezone/scripts/script_filter.sh`
  - `test -x workflows/multi-timezone/scripts/action_copy.sh`
  - `rg -n 'rust_binary\\s*=\\s*"timezone-cli"' workflows/multi-timezone/workflow.toml`

### Task 1.3: Add `timezone-cli` crate and workspace membership
- **Location**:
  - `Cargo.toml`
  - `crates/timezone-cli/Cargo.toml`
  - `crates/timezone-cli/src/lib.rs`
  - `crates/timezone-cli/src/main.rs`
- **Description**: Introduce a dedicated binary crate for timezone parsing, local detection, and Alfred feedback rendering.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Workspace includes `crates/timezone-cli`.
  - CLI help and command parsing run successfully.
  - Required dependencies for timezone operations are declared.
- **Validation**:
  - `cargo check -p nils-timezone-cli`
  - `cargo run -p nils-timezone-cli -- --help`

### Task 1.4: Freeze output schema and copy payload format
- **Location**:
  - `crates/timezone-cli/docs/workflow-contract.md`
  - `workflows/multi-timezone/README.md`
  - `crates/timezone-cli/src/feedback.rs`
- **Description**: Define row title/subtitle/arg schema, including timezone label, local clock display format, and copy payload format.
- **Dependencies**:
  - Task 1.1
  - Task 1.3
- **Complexity**: 4
- **Acceptance criteria**:
  - Output schema explicitly defines fields used by Alfred action.
  - Output schema includes deterministic `uid` field equal to timezone ID for order assertions.
  - Row format examples include one-row local fallback and multi-timezone list cases.
  - Invalid timezone row schema is explicitly documented.
- **Validation**:
  - `rg -n "title|subtitle|arg|uid|invalid timezone|copy payload" crates/timezone-cli/docs/workflow-contract.md workflows/multi-timezone/README.md`

## Sprint 2: Timezone engine and local detection fallback chain
**Goal**: Implement robust timezone parsing/detection logic and deterministic row rendering for current time.
**Demo/Validation**:
- Command(s): `cargo test -p nils-timezone-cli`, `cargo run -p nils-timezone-cli -- now --query "" --config-zones "" | jq -e '.items | type == "array"'`
- Verify: CLI returns valid Alfred JSON and follows ordering plus fallback rules.

### Task 2.1: Implement timezone-list parser with stable order
- **Location**:
  - `crates/timezone-cli/src/parser.rs`
  - `crates/timezone-cli/src/lib.rs`
- **Description**: Parse timezone lists from query/config strings (comma and newline separators), normalize whitespace, and preserve source order for rendering.
- **Dependencies**:
  - Task 1.3
  - Task 1.4
- **Complexity**: 7
- **Acceptance criteria**:
  - Parser accepts IANA IDs separated by commas or newlines.
  - Parser preserves original token order after trimming.
  - Parser surfaces token-level errors for invalid timezone IDs.
- **Validation**:
  - `cargo test -p nils-timezone-cli -- --list | rg "parser_|timezone_list_|order_"`
  - `cargo test -p nils-timezone-cli parser`

### Task 2.2: Implement local-timezone detection with multi-step fallback
- **Location**:
  - `crates/timezone-cli/src/local_tz.rs`
  - `crates/timezone-cli/src/error.rs`
- **Description**: Implement deterministic local-timezone detection chain: `MULTI_TZ_LOCAL_OVERRIDE` -> `TZ` env -> `iana_time_zone` crate lookup -> platform command fallback (`/usr/sbin/systemsetup -gettimezone` on macOS, `timedatectl show -p Timezone --value` on Linux) -> `/etc/localtime` symlink parse -> `UTC`.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 8
- **Acceptance criteria**:
  - Each fallback step is independently testable.
  - Test suite verifies fallback order: override -> `TZ` -> `iana_time_zone` -> platform command -> `/etc/localtime` -> `UTC`.
  - Failed probes do not crash CLI and continue to next fallback.
  - Final fallback returns `UTC` with explicit diagnostic context in logs or debug messages.
- **Validation**:
  - `cargo test -p nils-timezone-cli local_tz_fallback_chain_order`
  - `cargo test -p nils-timezone-cli local_tz_terminal_utc_when_all_probes_fail`
  - `MULTI_TZ_LOCAL_OVERRIDE="Asia/Taipei" cargo run -p nils-timezone-cli -- now --query "" --config-zones "" | jq -e '.items[0].uid == "Asia/Taipei"'`

### Task 2.3: Implement current-time rendering for requested timezone list
- **Location**:
  - `crates/timezone-cli/src/convert.rs`
  - `crates/timezone-cli/src/feedback.rs`
- **Description**: Convert current instant to each target timezone and render Alfred rows containing formatted time, timezone ID, and UTC offset, preserving input order.
- **Dependencies**:
  - Task 2.1
  - Task 2.2
- **Complexity**: 7
- **Acceptance criteria**:
  - Empty resolved timezone list yields one row from detected local timezone.
  - Multi-timezone input yields one row per timezone in exact source order.
  - Query input overrides configured timezone list when query is non-empty.
  - Subtitle includes timezone ID and UTC offset for readability.
- **Validation**:
  - `cargo test -p nils-timezone-cli -- --list | rg "render_now_|order_preserved_|local_default_"`
  - `cargo test -p nils-timezone-cli render`
  - `cargo run -p nils-timezone-cli -- now --query "" --config-zones $'Asia/Taipei\nAmerica/New_York,Europe/London' | jq -e '[.items[].uid] == ["Asia/Taipei","America/New_York","Europe/London"]'`
  - `cargo run -p nils-timezone-cli -- now --query "Europe/London,Asia/Tokyo" --config-zones "Asia/Taipei,America/New_York" | jq -e '[.items[].uid] == ["Europe/London","Asia/Tokyo"]'`

### Task 2.4: Implement CLI command surface and error contract
- **Location**:
  - `crates/timezone-cli/src/main.rs`
  - `crates/timezone-cli/src/error.rs`
- **Description**: Expose `now` command with `--query` and `--config-zones` parameters, emitting Alfred JSON on success and deterministic user/runtime errors otherwise.
- **Dependencies**:
  - Task 2.3
- **Complexity**: 6
- **Acceptance criteria**:
  - Success path emits JSON only to stdout.
  - User input errors and runtime errors map to distinct non-zero exit codes.
  - Empty query plus empty config still succeeds via local fallback.
- **Validation**:
  - `cargo test -p nils-timezone-cli -- --list | rg "main_|error_kind|exit_code"`
  - `cargo test -p nils-timezone-cli`
  - `cargo run -p nils-timezone-cli -- now --query "" --config-zones "" | jq -e '.items | length == 1'`

### Task 2.5: Add regression tests for ordering, invalid IDs, and fallback transitions
- **Location**:
  - `crates/timezone-cli/src/parser.rs`
  - `crates/timezone-cli/src/local_tz.rs`
  - `crates/timezone-cli/src/main.rs`
- **Description**: Add targeted tests for input-order preservation, invalid timezone reporting, and staged fallback behavior under stubbed environments.
- **Dependencies**:
  - Task 2.4
- **Complexity**: 7
- **Acceptance criteria**:
  - Tests assert order stability for at least three-timezone input.
  - Tests cover at least one failure path per fallback stage.
  - Tests verify `UTC` terminal fallback when all probes fail.
- **Validation**:
  - `cargo test -p nils-timezone-cli order_preserved_for_config_list`
  - `cargo test -p nils-timezone-cli query_overrides_config_list`
  - `cargo test -p nils-timezone-cli local_tz_terminal_utc_when_all_probes_fail`

## Sprint 3: Alfred runtime adapter and smoke coverage
**Goal**: Wire the new CLI into Alfred scripts/plist and provide deterministic smoke tests.
**Demo/Validation**:
- Command(s): `bash workflows/multi-timezone/tests/smoke.sh`, `scripts/workflow-pack.sh --id multi-timezone`
- Verify: Script filter always emits valid Alfred JSON and packaged artifact is structurally correct.

### Task 3.1: Implement `script_filter.sh` with config/query precedence
- **Location**:
  - `workflows/multi-timezone/scripts/script_filter.sh`
- **Description**: Resolve `timezone-cli` binary path, pass query plus `MULTI_TZ_ZONES` and `MULTI_TZ_LOCAL_OVERRIDE`, and map CLI failures to non-crashing Alfred fallback rows.
- **Dependencies**:
  - Task 2.4
  - Task 2.5
- **Complexity**: 6
- **Acceptance criteria**:
  - Binary resolution follows env override -> packaged -> release -> debug order.
  - Script forwards query/config values to CLI without altering order.
  - Any error path still returns valid Alfred JSON with `valid=false`.
- **Validation**:
  - `scripts/workflow-lint.sh --id multi-timezone`
  - `bash workflows/multi-timezone/scripts/script_filter.sh "Asia/Taipei,America/New_York" | jq -e '.items | type == "array"'`

### Task 3.2: Implement copy action script
- **Location**:
  - `workflows/multi-timezone/scripts/action_copy.sh`
- **Description**: Copy selected row argument via `pbcopy`, with deterministic usage error when argument is missing.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 3
- **Acceptance criteria**:
  - Missing arg exits with code `2`.
  - Valid arg is copied unchanged.
  - Behavior is script-testable with stubbed `pbcopy`.
- **Validation**:
  - `scripts/workflow-lint.sh --id multi-timezone`
  - `bash -c 'set +e; bash workflows/multi-timezone/scripts/action_copy.sh >/dev/null 2>&1; test $? -eq 2'`
  - `bash -c 'tmpdir="$(mktemp -d)"; printf "#!/usr/bin/env bash\ncat >\"$tmpdir/out\"\n" >"$tmpdir/pbcopy"; chmod +x "$tmpdir/pbcopy"; PATH="$tmpdir:$PATH" bash workflows/multi-timezone/scripts/action_copy.sh "Asia/Taipei 2026-02-10 12:34:56"; test "$(cat "$tmpdir/out")" = "Asia/Taipei 2026-02-10 12:34:56"; rm -rf "$tmpdir"'`

### Task 3.3: Wire plist template, keyword, and env fields
- **Location**:
  - `workflows/multi-timezone/src/info.plist.template`
  - `workflows/multi-timezone/workflow.toml`
- **Description**: Configure Alfred nodes with keyword `tz`, set env fields for timezone configuration, and ensure manifest/plist metadata consistency.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Packaged plist has valid object graph and script links.
  - Keyword trigger is exactly `tz`.
  - Env fields are available in workflow configuration UI.
- **Validation**:
  - `scripts/workflow-pack.sh --id multi-timezone`
  - `bash -c 'if command -v plutil >/dev/null 2>&1; then plutil -lint build/workflows/multi-timezone/pkg/info.plist; plutil -convert json -o - build/workflows/multi-timezone/pkg/info.plist | jq -e ".objects[] | select(.type==\"alfred.workflow.input.scriptfilter\") | .config.keyword == \"tz\""; else echo "skip: plutil unavailable"; fi'`

### Task 3.4: Build smoke test for ordering and local fallback behavior
- **Location**:
  - `workflows/multi-timezone/tests/smoke.sh`
- **Description**: Add deterministic smoke tests using stubbed CLI outputs to assert success passthrough, error mapping, source-order preservation, and empty-input local fallback row count.
- **Dependencies**:
  - Task 3.1
  - Task 3.3
- **Complexity**: 8
- **Acceptance criteria**:
  - Smoke test verifies required files, executable bits, and manifest wiring.
  - Smoke test asserts output ordering for at least three timezones.
  - Smoke test asserts empty query with empty config yields one local row.
- **Validation**:
  - `bash workflows/multi-timezone/tests/smoke.sh`
  - `scripts/workflow-test.sh --id multi-timezone`

### Task 3.5: Update workflow and repository documentation
- **Location**:
  - `workflows/multi-timezone/README.md`
  - `README.md`
  - `docs/WORKFLOW_GUIDE.md`
- **Description**: Document usage, timezone field format, local fallback chain, and ordering guarantees with concrete examples.
- **Dependencies**:
  - Task 3.4
- **Complexity**: 4
- **Acceptance criteria**:
  - Workflow README includes examples for empty query, configured zones, and query override.
  - Root README includes the new workflow in the workflow table.
  - Guide links to smoke/lint/pack commands for this workflow.
- **Validation**:
  - `rg -n "multi-timezone|MULTI_TZ_ZONES|tz |order|fallback" workflows/multi-timezone/README.md README.md docs/WORKFLOW_GUIDE.md`

## Sprint 4: Integration gates and operational readiness
**Goal**: Run full repository checks, package artifacts, and prepare rollback instructions.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `cargo test --workspace`, `scripts/workflow-test.sh`
- Verify: Repository quality gates remain green with the new workflow integrated.

### Task 4.1: Run required repository quality gates
- **Location**:
  - `DEVELOPMENT.md`
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
- **Description**: Execute required lint/test checks and confirm no regressions in existing workflows after adding `multi-timezone`.
- **Dependencies**:
  - Task 3.4
  - Task 3.5
- **Complexity**: 5
- **Acceptance criteria**:
  - Workspace fmt, clippy, and test gates pass.
  - Workflow smoke suite passes including the new workflow.
  - Failures (if any) are triaged with actionable remediation notes.
- **Validation**:
  - `cargo fmt --all -- --check`
  - `cargo clippy --workspace --all-targets -- -D warnings`
  - `cargo test --workspace`
  - `scripts/workflow-test.sh`

### Task 4.2: Package and local install validation
- **Location**:
  - `scripts/workflow-pack.sh`
  - `workflows/multi-timezone/workflow.toml`
  - `workflows/multi-timezone/scripts/script_filter.sh`
  - `build/workflows/multi-timezone/pkg/info.plist`
- **Description**: Build distributable artifact, verify checksum generation, and validate local install behavior for keyword and copy action.
- **Dependencies**:
  - Task 4.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Packaging emits workflow artifact and checksum in expected dist path.
  - Installed workflow responds to `tz` with local fallback and multi-timezone query cases.
  - Copy action still works on selected row.
- **Validation**:
  - `scripts/workflow-pack.sh --id multi-timezone`
  - `bash -c 'if [[ "$(uname -s)" == "Darwin" ]]; then scripts/workflow-pack.sh --id multi-timezone --install; else echo "skip: workflow install requires macOS"; fi'`
  - `bash -c 'id="$(awk -F= '\''$1 ~ /^[[:space:]]*id[[:space:]]*$/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/^\"|\"$/, "", $2); print $2; exit}'\'' workflows/multi-timezone/workflow.toml)"; version="$(awk -F= '\''$1 ~ /^[[:space:]]*version[[:space:]]*$/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/^\"|\"$/, "", $2); print $2; exit}'\'' workflows/multi-timezone/workflow.toml)"; name="$(awk -F= '\''$1 ~ /^[[:space:]]*name[[:space:]]*$/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/^\"|\"$/, "", $2); print $2; exit}'\'' workflows/multi-timezone/workflow.toml)"; test -f "dist/$id/$version/${name}.alfredworkflow"; test -f "dist/$id/$version/${name}.alfredworkflow.sha256"'`
  - `bash workflows/multi-timezone/tests/smoke.sh`
  - `bash -c 'tmpdir="$(mktemp -d)"; printf "#!/usr/bin/env bash\ncat >\"$tmpdir/out\"\n" >"$tmpdir/pbcopy"; chmod +x "$tmpdir/pbcopy"; PATH="$tmpdir:$PATH" bash workflows/multi-timezone/scripts/action_copy.sh "copy-check"; test "$(cat "$tmpdir/out")" = "copy-check"; rm -rf "$tmpdir"'`
  - `bash -c 'if [[ "$(uname -s)" == "Darwin" ]]; then wf="$(for p in "$HOME"/Library/Application\ Support/Alfred/Alfred.alfredpreferences/workflows/*/info.plist; do [ -f "$p" ] || continue; bid="$(plutil -extract bundleid raw -o - "$p" 2>/dev/null || true)"; [ "$bid" = "com.graysurf.multi-timezone" ] && dirname "$p"; done | head -n1)"; test -n "$wf"; "$wf/scripts/script_filter.sh" "Asia/Taipei,America/New_York" | jq -e ".items | length == 2"; else echo "skip: install verification requires macOS"; fi'`

### Task 4.3: Add troubleshooting and rollback procedures
- **Location**:
  - `crates/timezone-cli/docs/workflow-contract.md`
  - `TROUBLESHOOTING.md`
- **Description**: Document operational recovery for timezone misconfiguration, missing timezone database, and rollback to previous release artifact.
- **Dependencies**:
  - Task 4.2
- **Complexity**: 3
- **Acceptance criteria**:
  - Troubleshooting includes invalid IANA IDs and local-timezone detection fallback notes.
  - Rollback steps are executable in under five minutes.
  - Docs call out how to clear conflicting env field values.
- **Validation**:
  - `rg -n "rollback|IANA|MULTI_TZ_ZONES|fallback|timezone database" crates/timezone-cli/docs/workflow-contract.md TROUBLESHOOTING.md`

## Testing Strategy
- Unit: `timezone-cli` parser, local-timezone detector, and renderer tests lock ordering and fallback behavior.
- Integration: script adapter tests verify CLI resolution, env/query precedence, and error-to-feedback mapping.
- E2E/manual: workflow smoke tests plus packaged plist checks and local install verification.

## Risks & gotchas
- OS timezone metadata can differ across local dev and CI; fallback tests must rely on stubs and deterministic fixtures.
- Some environments may not provide `systemsetup` or `timedatectl`; fallback chain must treat missing commands as non-fatal.
- Daylight-saving transitions can create confusing offsets; output should always include UTC offset to reduce ambiguity.
- Input-order preservation can be accidentally broken if intermediate data uses unordered collections.

## Rollback plan
1. Disable `multi-timezone` workflow in Alfred and remove custom env field values.
2. Reinstall previous stable artifact from the previous version directory under `dist/multi-timezone/`.
3. Revert `multi-timezone` workflow and `timezone-cli` crate changes in git if regression is code-level.
4. Re-run `scripts/workflow-test.sh --id multi-timezone` and `cargo test -p nils-timezone-cli` on the rollback revision before republishing.
