# Plan: Port `quote-init.zsh` into an Alfred workflow

## Overview
This plan ports `/Users/terry/.config/zsh/bootstrap/quote-init.zsh` into a first-class Alfred workflow in this monorepo, while preserving its core behavior: show cached quotes quickly and refresh from ZenQuotes on an interval.
The workflow will expose four user-facing parameters with these defaults: display count `3`, refresh interval `1h`, fetch batch size `5`, and max retained quotes `100`.
Implementation follows the existing repository pattern: Rust domain logic in a dedicated CLI crate, thin shell adapters in `workflows/quote-feed/scripts`, and packaging via existing `scripts/workflow-*` entrypoints.
The design keeps local-first UX: results are served from local cache immediately, and network fetch is opportunistic and bounded.

## Scope
- In scope: New workflow `quote-feed` with Script Filter + copy action.
- In scope: New Rust crate `quote-cli` for config parsing, quote storage, refresh policy, ZenQuotes fetch, and Alfred JSON output.
- In scope: Parameterized defaults and guardrails:
  - `QUOTE_DISPLAY_COUNT` default `3`
  - `QUOTE_REFRESH_INTERVAL` default `1h`
  - `QUOTE_FETCH_COUNT` default `5`
  - `QUOTE_MAX_ENTRIES` default `100`
- In scope: Cache-backed behavior that shows results even when network fetch fails.
- In scope: Tests, smoke checks, docs, and package wiring.
- Out of scope: Replacing all shell-login quote output behavior in the same change.
- Out of scope: Multi-provider quote APIs, quote scoring, or user-authenticated sources.
- Out of scope: Historical analytics UI for quote usage.

## Assumptions (if any)
1. ZenQuotes endpoint remains `https://zenquotes.io/api/random` for v1, called multiple times to satisfy batch fetch.
2. Workflow keyword is `qq`.
3. Quote cache is stored under Alfred workflow data directory (`$alfred_workflow_data`) instead of Zsh bootstrap locations.
4. Copy-to-clipboard action (`pbcopy`) is the default Enter behavior for selected quote rows.

## Success Criteria
- Running keyword `qq` shows quote items from local cache immediately.
- Default behavior uses exactly these values unless overridden by workflow env:
  - display count `3`
  - refresh interval `1h`
  - fetch count `5`
  - max retained quotes `100`
- When refresh is due, workflow fetches up to `QUOTE_FETCH_COUNT` quotes, appends valid entries, and trims to `QUOTE_MAX_ENTRIES`.
- Network/API failures still produce valid Alfred JSON and do not break cached output.
- `scripts/workflow-lint.sh --id quote-feed`, `scripts/workflow-test.sh --id quote-feed`, and `scripts/workflow-pack.sh --id quote-feed` pass.

## Dependency & Parallelization Map
- Critical path:
  - `Task 1.1 -> Task 1.2 -> (Task 1.3 + Task 1.4) -> Task 2.1 -> (Task 2.2 + Task 2.3) -> Task 2.4 -> Task 2.5 -> Task 2.6 -> Task 3.1 -> Task 3.3 -> Task 3.4 -> Task 3.5 -> Task 4.2 -> Task 4.3 -> Task 4.4`.
- Parallel track A:
  - `Task 1.3` and `Task 1.4` run in parallel after `Task 1.2`; both must complete before `Task 2.1`.
- Parallel track B:
  - `Task 2.3` after `Task 2.1`, parallel with `Task 2.2`.
- Parallel track C:
  - `Task 3.2` after `Task 1.2`, parallel with `Task 2.1` to `Task 3.1`.
- Parallel track D:
  - `Task 4.1` can start after `Task 2.6` in parallel with Sprint 3 tasks; `Task 4.2` starts after `Task 3.5`, then `Task 4.3` starts after `Task 4.2`.

## Sprint 1: Contract and scaffolding
**Goal**: Freeze behavior contract and scaffold workflow/crate surfaces aligned to repository conventions.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/quote-init-workflow-plan.md`, `test -d workflows/quote-feed`, `cargo check -p quote-cli`
- Verify: Contract and skeleton exist, defaults are explicit, workspace resolves new members.

### Task 1.1: Write quote workflow contract and parameter spec
- **Location**:
  - `docs/quote-workflow-contract.md`
- **Description**: Document v1 behavior, quote item schema, cache/refresh lifecycle, and the four parameter defaults and constraints.
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - Contract contains query behavior, JSON contract, and fallback/error behavior.
  - Contract explicitly defines defaults `3`, `1h`, `5`, and `100`.
  - Contract defines validation/clamp rules for invalid values.
- **Validation**:
  - `test -f docs/quote-workflow-contract.md`
  - `rg -n "QUOTE_DISPLAY_COUNT|QUOTE_REFRESH_INTERVAL|QUOTE_FETCH_COUNT|QUOTE_MAX_ENTRIES" docs/quote-workflow-contract.md`
  - `rg -n "QUOTE_DISPLAY_COUNT.*3|QUOTE_REFRESH_INTERVAL.*1h|QUOTE_FETCH_COUNT.*5|QUOTE_MAX_ENTRIES.*100" docs/quote-workflow-contract.md`

### Task 1.2: Scaffold workflow directory for `quote-feed`
- **Location**:
  - `workflows/quote-feed/workflow.toml`
  - `workflows/quote-feed/scripts/script_filter.sh`
  - `workflows/quote-feed/scripts/action_copy.sh`
  - `workflows/quote-feed/src/info.plist.template`
  - `workflows/quote-feed/src/assets/icon.png`
  - `workflows/quote-feed/tests/smoke.sh`
- **Description**: Generate workflow skeleton with manifest keys and script names aligned to copy-oriented quote UX.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Workflow folder contains required files and executable scripts.
  - Manifest includes required keys and references `quote-cli` binary.
- **Validation**:
  - `test -d workflows/quote-feed`
  - `test -f workflows/quote-feed/workflow.toml`
  - `test -x workflows/quote-feed/scripts/script_filter.sh`
  - `rg -n 'rust_binary\\s*=\\s*"quote-cli"' workflows/quote-feed/workflow.toml`

### Task 1.3: Add `quote-cli` crate and workspace membership
- **Location**:
  - `Cargo.toml`
  - `crates/quote-cli/Cargo.toml`
  - `crates/quote-cli/src/lib.rs`
  - `crates/quote-cli/src/main.rs`
- **Description**: Create a dedicated CLI crate for quote cache, refresh, API client, and Alfred output responsibilities.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Workspace includes `crates/quote-cli`.
  - `cargo run -p quote-cli -- --help` succeeds.
- **Validation**:
  - `cargo check -p quote-cli`
  - `cargo run -p quote-cli -- --help`

### Task 1.4: Define workflow env variables and defaults in manifest/plist
- **Location**:
  - `workflows/quote-feed/workflow.toml`
  - `workflows/quote-feed/src/info.plist.template`
  - `docs/quote-workflow-contract.md`
- **Description**: Add Alfred user configuration variables for the four parameters and keep defaults/descriptions consistent across manifest, plist, and contract docs.
- **Dependencies**:
  - Task 1.1
  - Task 1.2
- **Complexity**: 4
- **Acceptance criteria**:
  - `userconfigurationconfig` exposes all four variables with correct defaults.
  - Defaults and descriptions are consistent in all three files.
- **Validation**:
  - `rg -n "QUOTE_DISPLAY_COUNT|QUOTE_REFRESH_INTERVAL|QUOTE_FETCH_COUNT|QUOTE_MAX_ENTRIES" workflows/quote-feed/workflow.toml workflows/quote-feed/src/info.plist.template docs/quote-workflow-contract.md`
  - `plutil -convert json -o - workflows/quote-feed/src/info.plist.template | jq -e '(.userconfigurationconfig | map({key: .variable, value: .config.default}) | from_entries) == {"QUOTE_DISPLAY_COUNT":"3","QUOTE_REFRESH_INTERVAL":"1h","QUOTE_FETCH_COUNT":"5","QUOTE_MAX_ENTRIES":"100"}'`

## Sprint 2: Quote domain logic and refresh pipeline
**Goal**: Implement robust config/store/fetch logic that preserves local-first UX and bounded updates.
**Demo/Validation**:
- Command(s): `cargo test -p quote-cli`, `cargo run -p quote-cli -- feed --query "" | jq -e '.items | type == "array"'`
- Verify: CLI returns valid Alfred JSON and refresh behavior obeys configured defaults and limits.

### Task 2.1: Implement config parsing and guardrails
- **Location**:
  - `crates/quote-cli/src/config.rs`
  - `crates/quote-cli/src/lib.rs`
- **Description**: Parse and validate all quote env variables, including duration parsing for `1h`-style interval strings and numeric clamps for counts/limits.
- **Dependencies**:
  - Task 1.3
  - Task 1.4
- **Complexity**: 6
- **Acceptance criteria**:
  - Missing env uses defaults `3`, `1h`, `5`, `100`.
  - Invalid values return actionable config errors or safe clamped values per contract.
  - Interval parser supports `s`, `m`, `h` suffixes.
- **Validation**:
  - `cargo test -p quote-cli`
  - `cargo test -p quote-cli -- --list | rg "config_|duration_|defaults_"`
  - `bash -c 'set +e; out="$(env QUOTE_REFRESH_INTERVAL=90x cargo run -p quote-cli -- feed --query "" 2>&1)"; code=$?; test $code -ne 0; printf "%s" "$out" | rg -qi "invalid|interval|refresh|error"'`

### Task 2.2: Implement quote store and retention trim
- **Location**:
  - `crates/quote-cli/src/store.rs`
  - `crates/quote-cli/src/lib.rs`
- **Description**: Implement local quote file and timestamp file access, append semantics, deduplication, and retention trimming to `QUOTE_MAX_ENTRIES`.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Store load/save is deterministic with malformed-line tolerance.
  - Appending new quotes trims persisted data to configured max entries.
  - Timestamp updates are atomic enough to avoid partial writes.
- **Validation**:
  - `cargo test -p quote-cli`
  - `cargo test -p quote-cli -- --list | rg "store_|trim_|dedupe_|timestamp_"`
  - `cargo test -p quote-cli store::tests::retains_only_max_entries`

### Task 2.3: Implement ZenQuotes fetch client with bounded latency
- **Location**:
  - `crates/quote-cli/src/zenquotes.rs`
  - `crates/quote-cli/Cargo.toml`
- **Description**: Add HTTP client logic to fetch quotes with per-request timeout and parse `q` + `a` fields into canonical `"quote" — author` lines.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Fetch function supports fetching up to `QUOTE_FETCH_COUNT` entries.
  - Invalid payloads are dropped safely and do not poison cache.
  - Timeout/network errors are typed and handled by caller.
- **Validation**:
  - `cargo test -p quote-cli`
  - `cargo test -p quote-cli -- --list | rg "zenquotes_|http_|parse_"`
  - `cargo clippy -p quote-cli --all-targets -- -D warnings`

### Task 2.4: Implement refresh policy (`stale` check + update flow)
- **Location**:
  - `crates/quote-cli/src/refresh.rs`
  - `crates/quote-cli/src/lib.rs`
- **Description**: Compare current time with last-refresh timestamp, run fetch only when interval elapsed, merge new quotes, and persist updated timestamp on success.
- **Dependencies**:
  - Task 2.2
  - Task 2.3
- **Complexity**: 8
- **Acceptance criteria**:
  - Fresh cache path does not trigger network calls.
  - Stale path fetches up to configured batch size and updates timestamp only on successful store update.
  - Failures keep previous cache intact.
- **Validation**:
  - `cargo test -p quote-cli`
  - `cargo test -p quote-cli refresh::tests::skips_fetch_when_interval_not_elapsed`
  - `cargo test -p quote-cli refresh::tests::fetches_and_updates_when_stale`

### Task 2.5: Implement Alfred feedback mapping for display count
- **Location**:
  - `crates/quote-cli/src/feedback.rs`
  - `crates/quote-cli/src/lib.rs`
- **Description**: Convert selected local quotes into Alfred JSON items with `title`, `subtitle`, `arg`, and deterministic fallback item when cache is empty.
- **Dependencies**:
  - Task 2.4
- **Complexity**: 5
- **Acceptance criteria**:
  - Empty cache emits one valid fallback item instead of malformed output.
  - Item count obeys `QUOTE_DISPLAY_COUNT`.
  - `arg` contains the full quote text for copy action.
- **Validation**:
  - `cargo test -p quote-cli`
  - `cargo run -p quote-cli -- feed --query "" | jq -e '.items | type == "array"'`
  - `cargo test -p quote-cli feedback::tests::respects_display_count`

### Task 2.6: Finalize CLI command contract
- **Location**:
  - `crates/quote-cli/src/main.rs`
- **Description**: Provide stable command surface (`feed --query`) with JSON-only stdout and concise stderr failures for script adapter handling.
- **Dependencies**:
  - Task 2.5
- **Complexity**: 4
- **Acceptance criteria**:
  - `--help` documents command/env behavior.
  - Success path prints valid Alfred JSON only.
  - Hard failures return non-zero and actionable stderr message.
- **Validation**:
  - `cargo run -p quote-cli -- --help`
  - `cargo run -p quote-cli -- feed --query "" | jq -e '.items | type == "array"'`
  - `bash -c 'set +e; out="$(cargo run -p quote-cli -- feed 2>&1)"; code=$?; test $code -ne 0; printf "%s" "$out" | rg -qi "error|usage|query"'`

## Sprint 3: Alfred integration and packaging hardening
**Goal**: Wire script adapters/plist to `quote-cli` and ensure deterministic smoke coverage.
**Demo/Validation**:
- Command(s): `bash workflows/quote-feed/tests/smoke.sh`, `scripts/workflow-pack.sh --id quote-feed`
- Verify: Workflow package is installable and Script Filter/action chain is valid.

### Task 3.1: Implement robust `script_filter.sh` adapter
- **Location**:
  - `workflows/quote-feed/scripts/script_filter.sh`
- **Description**: Resolve `quote-cli` binary (env/package/release/debug), run feed command, validate JSON shape, and emit Alfred-safe error JSON fallback on failure.
- **Dependencies**:
  - Task 2.6
- **Complexity**: 6
- **Acceptance criteria**:
  - Adapter always returns valid Alfred JSON (including error paths).
  - Runtime path resolution supports both packaged and local development contexts.
  - macOS quarantine cleanup remains best-effort only.
- **Validation**:
  - `shellcheck workflows/quote-feed/scripts/script_filter.sh`
  - `shfmt -d workflows/quote-feed/scripts/script_filter.sh`
  - `bash workflows/quote-feed/scripts/script_filter.sh "" | jq -e '.items | type == "array"'`
  - `bash -c 'QUOTE_CLI_BIN=/nonexistent bash workflows/quote-feed/scripts/script_filter.sh "" | jq -e ".items | type == \"array\" and length >= 1"'`

### Task 3.2: Implement quote copy action script
- **Location**:
  - `workflows/quote-feed/scripts/action_copy.sh`
- **Description**: Copy selected quote text to clipboard with strict arg validation and stable exit code semantics.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 2
- **Acceptance criteria**:
  - Missing arg returns exit code `2` with usage message.
  - Valid arg is copied exactly without additional newline mutation.
- **Validation**:
  - `shellcheck workflows/quote-feed/scripts/action_copy.sh`
  - `bash -c 'tmpdir="$(mktemp -d)"; printf "#!/usr/bin/env bash\ncat >\"$tmpdir/out\"\n" >"$tmpdir/pbcopy"; chmod +x "$tmpdir/pbcopy"; PATH="$tmpdir:$PATH" bash workflows/quote-feed/scripts/action_copy.sh "\"sample\" — author"; test "$(cat "$tmpdir/out")" = "\"sample\" — author"; rm -rf "$tmpdir"'`
  - `bash -c 'set +e; bash workflows/quote-feed/scripts/action_copy.sh >/dev/null 2>&1; test $? -eq 2'`

### Task 3.3: Wire `info.plist.template` object graph and variables
- **Location**:
  - `workflows/quote-feed/src/info.plist.template`
- **Description**: Configure Script Filter keyword/action flow and expose the four quote parameter variables through Alfred user config.
- **Dependencies**:
  - Task 1.4
  - Task 3.1
  - Task 3.2
- **Complexity**: 7
- **Acceptance criteria**:
  - Plist contains script nodes with external script mode (`config.type == 8`).
  - Script filter keyword and action chain are connected.
  - `userconfigurationconfig` includes all four quote variables.
- **Validation**:
  - `scripts/workflow-pack.sh --id quote-feed`
  - `plutil -lint build/workflows/quote-feed/pkg/info.plist`
  - `plutil -convert json -o - build/workflows/quote-feed/pkg/info.plist | jq -e '(.objects[] | select(.type == "alfred.workflow.input.scriptfilter") | .config.type) == 8'`
  - `plutil -convert json -o - build/workflows/quote-feed/pkg/info.plist | jq -e '(.objects[] | select(.type == "alfred.workflow.input.scriptfilter") | .uid) as $sf | (.connections[$sf] | type == "array" and length >= 1)'`
  - `plutil -convert json -o - build/workflows/quote-feed/pkg/info.plist | jq -e '[.userconfigurationconfig[].variable] | sort == ["QUOTE_DISPLAY_COUNT","QUOTE_FETCH_COUNT","QUOTE_MAX_ENTRIES","QUOTE_REFRESH_INTERVAL"]'`

### Task 3.4: Add deterministic smoke checks
- **Location**:
  - `workflows/quote-feed/tests/smoke.sh`
- **Description**: Add checks for required files, script executability, script-filter JSON validity, and packaged plist wiring assertions.
- **Dependencies**:
  - Task 3.1
  - Task 3.3
- **Complexity**: 6
- **Acceptance criteria**:
  - Smoke test fails on missing files, malformed JSON, or broken object graph.
  - Smoke test does not require external network to pass.
- **Validation**:
  - `bash workflows/quote-feed/tests/smoke.sh`
  - `scripts/workflow-test.sh --id quote-feed`
  - `rg -n "assert_file|assert_exec|jq -e|plutil|QUOTE_DISPLAY_COUNT|QUOTE_REFRESH_INTERVAL|QUOTE_FETCH_COUNT|QUOTE_MAX_ENTRIES" workflows/quote-feed/tests/smoke.sh`

### Task 3.5: Ensure package integration and artifact integrity
- **Location**:
  - `workflows/quote-feed/workflow.toml`
  - `scripts/workflow-pack.sh`
- **Description**: Verify workflow packaging path, bundled binary placement, and compatibility with `--all` packaging to avoid regressions.
- **Dependencies**:
  - Task 3.4
- **Complexity**: 4
- **Acceptance criteria**:
  - `quote-feed` packaging emits `.alfredworkflow` + checksum.
  - `scripts/workflow-pack.sh --all` remains green.
- **Validation**:
  - `scripts/workflow-pack.sh --id quote-feed`
  - `scripts/workflow-pack.sh --all`

## Sprint 4: Quality gates, docs, and migration safety
**Goal**: Finalize with robust tests/docs and a safe migration path from shell bootstrap usage.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh --id quote-feed`, `scripts/workflow-test.sh --id quote-feed`, `scripts/workflow-pack.sh --id quote-feed --install`
- Verify: All quality gates pass and operators can migrate from `quote-init.zsh` behavior safely.

### Task 4.1: Add focused Rust tests for config/store/refresh edge cases
- **Location**:
  - `crates/quote-cli/src/config.rs`
  - `crates/quote-cli/src/store.rs`
  - `crates/quote-cli/src/refresh.rs`
- **Description**: Add deterministic tests for invalid env values, duration parsing, trim boundaries, stale/fresh policy, and partial API failure handling.
- **Dependencies**:
  - Task 2.6
- **Complexity**: 7
- **Acceptance criteria**:
  - Edge cases around `0`, negative-like strings, and oversized values are covered.
  - Refresh tests prove no cache corruption on fetch failure.
- **Validation**:
  - `cargo test -p quote-cli`
  - `cargo test -p quote-cli -- --list | rg "config_|store_|refresh_"`

### Task 4.2: Document workflow usage and parameter semantics
- **Location**:
  - `workflows/quote-feed/README.md`
  - `README.md`
  - `docs/WORKFLOW_GUIDE.md`
- **Description**: Document keyword usage, copy behavior, parameter defaults, and how refresh/retention settings affect runtime behavior.
- **Dependencies**:
  - Task 3.5
- **Complexity**: 4
- **Acceptance criteria**:
  - Root README includes `quote-feed` entry with setup notes.
  - Workflow guide includes env variable definitions and operational validation checklist.
- **Validation**:
  - `rg -n "quote-feed|qq|QUOTE_DISPLAY_COUNT|QUOTE_REFRESH_INTERVAL|QUOTE_FETCH_COUNT|QUOTE_MAX_ENTRIES" workflows/quote-feed/README.md README.md docs/WORKFLOW_GUIDE.md`

### Task 4.3: Add troubleshooting and migration notes from `quote-init.zsh`
- **Location**:
  - `TROUBLESHOOTING.md`
  - `docs/quote-workflow-contract.md`
- **Description**: Add troubleshooting notes for API timeout, malformed payloads, empty cache, and a migration note comparing legacy zsh behavior vs workflow behavior.
- **Dependencies**:
  - Task 4.2
- **Complexity**: 4
- **Acceptance criteria**:
  - Troubleshooting includes symptom -> cause -> action mapping.
  - Migration section clarifies where quote data is stored before/after migration.
- **Validation**:
  - `rg -n "quote-feed|zenquotes|cache|migration|quote-init.zsh" TROUBLESHOOTING.md docs/quote-workflow-contract.md`

### Task 4.4: Run end-to-end quality gates and release readiness checks
- **Location**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh`
  - `BINARY_DEPENDENCIES.md`
- **Description**: Execute repo quality gates for new workflow plus workspace, verify required tooling availability, and capture release-ready checklist output.
- **Description**: Execute repo quality gates for new workflow plus workspace and verify required tooling availability.
- **Dependencies**:
  - Task 4.1
  - Task 4.2
  - Task 4.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Lint/test/pack commands complete successfully for `quote-feed`.
  - No regressions on existing workflows in aggregate checks.
- **Validation**:
  - `command -v cargo jq rg shellcheck shfmt zip unzip >/dev/null`
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh --id quote-feed`
  - `scripts/workflow-pack.sh --all`

## Testing Strategy
- Unit:
  - `quote-cli` modules (`config`, `store`, `zenquotes`, `refresh`, `feedback`) with deterministic fixtures.
- Integration:
  - CLI output contract tests (`feed --query`) + adapter script JSON checks.
- E2E/manual:
  - Package/install workflow, run `qq` in Alfred, verify immediate cached output + later refresh behavior with defaults `3/1h/5/100`.

## Risks & gotchas
- ZenQuotes lacks true multi-quote batch endpoint in current script, so batch fetch may require multiple requests and can hit latency/rate limits.
- Parsing human-friendly duration strings (`1h`) can introduce ambiguous/invalid cases without strict grammar.
- Alfred data-path assumptions (`$alfred_workflow_data`) differ from shell bootstrap paths, requiring explicit migration guidance.
- Copy action with quote strings containing special characters must preserve exact text payload.

## Rollback plan
1. Disable distribution of `quote-feed` artifact and keep existing workflows unchanged.
2. Revert `quote-feed` + `quote-cli` changesets (workflow dir, crate membership, docs) in one rollback commit.
3. Re-run baseline gates to confirm repository health:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
4. Continue using legacy `/Users/terry/.config/zsh/bootstrap/quote-init.zsh` path until a revised workflow plan is approved.
