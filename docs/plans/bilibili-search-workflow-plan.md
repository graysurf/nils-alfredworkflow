# Plan: Add Bilibili search workflow for Alfred

## Overview
This plan adds a new Alfred workflow, `bilibili-search`, in this monorepo and keeps existing workflows unchanged.
The workflow behavior is: user enters a query, Alfred shows Bilibili suggestion terms, and selecting an item opens Bilibili search in the browser.
Implementation follows existing repository architecture: Rust business logic in a dedicated crate, thin shell adapters in workflow scripts, and deterministic packaging via `scripts/workflow-*`.
The reference behavior follows `alfred-web-search-suggest` Bilibili integration (`s.search.bilibili.com/main/suggest` with optional UID personalization), adapted to this monorepo standards.

## Scope
- In scope: Add new workflow `bilibili-search` with script filter and open action.
- In scope: Add new crate `bilibili-cli` for config parsing, suggest API client, feedback mapping, and CLI surface.
- In scope: Support optional personalized suggestions via workflow variable `BILIBILI_UID`.
- In scope: Keep Script Filter output resilient (always valid Alfred JSON on failure).
- In scope: Add smoke checks, Rust tests, docs, troubleshooting, and rollback guidance for maintainability.
- Out of scope: Login-required/private Bilibili APIs and cookie/session based personalization.
- Out of scope: Fetching video metadata/details pages in CLI (this workflow is suggestion-first).
- Out of scope: Refactoring unrelated workflows or shared crates beyond compatibility-safe hooks.

## Assumptions (if any)
1. Bilibili suggest endpoint `https://s.search.bilibili.com/main/suggest` remains publicly reachable for query suggestions.
2. Endpoint response keeps compatible core shape (`code`, `result.tag[].value`) or changes can be handled defensively.
3. Alfred runtime environment has network access to Bilibili endpoints.
4. Optional UID personalization should be best-effort and must not block anonymous search suggestions.

## Success Criteria
- Typing `bl <query>` shows suggestion rows with Bilibili-oriented subtitle guidance.
- Pressing Enter on any row opens `https://search.bilibili.com/all?keyword=<encoded-query>`.
- Empty query, short query, network failure, and malformed payload scenarios render non-crashing Alfred feedback items.
- Optional `BILIBILI_UID` is passed to suggest request when configured and omitted when empty.
- `scripts/workflow-lint.sh --id bilibili-search`, `scripts/workflow-test.sh --id bilibili-search`, and `scripts/workflow-pack.sh --id bilibili-search` pass.

## Dependency & Parallelization Map
- Critical path: `Task 1.0 -> Task 1.1 -> Task 1.2 -> Task 1.3 -> Task 2.1 -> Task 2.2 -> Task 2.3 -> Task 2.4 -> Task 3.1 -> Task 3.3 -> Task 3.5 -> Task 4.4`.
- Parallel track A: `Task 1.4` can run after `Task 1.1` and in parallel with `Task 1.3`.
- Parallel track B: `Task 2.5` can run after `Task 2.4` and in parallel with script-level wiring in Sprint 3.
- Parallel track C: `Task 3.2` can run after `Task 1.2` and in parallel with `Task 3.1`.
- Parallel track D: `Task 4.2` and `Task 4.3` can run in parallel after `Task 3.4`.
- Parallel track E: `Task 4.1` (test hardening) can start incrementally after each Sprint 2 task and converge at `Task 4.4`.

## Sprint 1: Contract and scaffold baseline
**Goal**: Freeze contract and scaffold crate/workflow surfaces aligned with monorepo conventions.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/bilibili-search-workflow-plan.md`, `test -d workflows/bilibili-search`, `cargo check -p nils-bilibili-cli`
- Verify: Plan is executable, workflow skeleton exists, and the new crate is registered/buildable.

### Task 1.0: Capture reference behavior inventory from alfred-web-search-suggest
- **Location**:
  - `/Users/terry/Project/graysurf/alfred-web-search-suggest/src/bilibili.php` (read-only reference)
  - `/Users/terry/Project/graysurf/alfred-web-search-suggest/src/info.plist` (read-only reference)
  - `docs/reports/bilibili-reference-alignment.md`
- **Description**: Capture the exact reference behavior contract (endpoint, query params, UID handling, suggestion row semantics, keyword mapping, and direct-search URL pattern) and record explicit parity decisions for this monorepo implementation.
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - Inventory doc lists concrete reference inputs/outputs for Bilibili suggestion behavior.
  - Inventory doc records at least one intentional adaptation decision for `nils-alfredworkflow` standards.
- **Validation**:
  - `test -f docs/reports/bilibili-reference-alignment.md`
  - `rg -n "main/suggest|userid|bilibili_uid|search.bilibili.com/all|keyword bl" docs/reports/bilibili-reference-alignment.md`

### Task 1.1: Define Bilibili workflow behavior contract
- **Location**:
  - `crates/bilibili-cli/docs/workflow-contract.md`
- **Description**: Define end-to-end contract for keyword behavior, query handling, suggestion mapping, direct-search fallback row semantics, URL construction, and error mapping into Alfred items.
- **Dependencies**:
  - Task 1.0
- **Complexity**: 3
- **Acceptance criteria**:
  - Contract documents success, empty-query, short-query, and runtime-error output expectations.
  - Contract specifies how `BILIBILI_UID` affects request construction.
  - Contract defines URL canonicalization to `https://search.bilibili.com/all?keyword=` plus percent-encoded query text.
- **Validation**:
  - `test -f crates/bilibili-cli/docs/workflow-contract.md`
  - `rg -n "^## (Keyword and Query Handling|Request Contract|Alfred Item Mapping|Error Mapping|Environment Variables)$" crates/bilibili-cli/docs/workflow-contract.md`
  - `rg -n "BILIBILI_UID|search.bilibili.com/all|main/suggest" crates/bilibili-cli/docs/workflow-contract.md`

### Task 1.2: Scaffold bilibili-search workflow directory and manifest
- **Location**:
  - `workflows/bilibili-search/workflow.toml`
  - `workflows/bilibili-search/scripts/script_filter.sh`
  - `workflows/bilibili-search/scripts/action_open.sh`
  - `workflows/bilibili-search/src/info.plist.template`
  - `workflows/bilibili-search/src/assets/icon.png`
  - `workflows/bilibili-search/tests/smoke.sh`
  - `workflows/bilibili-search/README.md`
  - `workflows/bilibili-search/TROUBLESHOOTING.md`
- **Description**: Scaffold workflow files and metadata so lint/test/pack pipelines can target `bilibili-search` from day one.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Workflow directory contains required manifest/template/scripts/tests/docs surfaces.
  - `workflow.toml` points to dedicated `rust_binary = "bilibili-cli"`.
  - Script files are executable.
- **Validation**:
  - `test -d workflows/bilibili-search`
  - `test -f workflows/bilibili-search/workflow.toml`
  - `test -x workflows/bilibili-search/scripts/script_filter.sh`
  - `test -x workflows/bilibili-search/scripts/action_open.sh`

### Task 1.3: Create bilibili-cli crate and workspace registration
- **Location**:
  - `Cargo.toml`
  - `crates/bilibili-cli/Cargo.toml`
  - `crates/bilibili-cli/src/main.rs`
  - `crates/bilibili-cli/src/lib.rs`
- **Description**: Add dedicated crate `nils-bilibili-cli` with command surface placeholders and workspace membership to isolate Bilibili behavior from existing search crates.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Workspace members include `crates/bilibili-cli`.
  - `cargo run -p nils-bilibili-cli -- --help` succeeds.
  - New crate compiles without changing existing workflow behavior.
- **Validation**:
  - `rg -n "crates/bilibili-cli" Cargo.toml`
  - `cargo check -p nils-bilibili-cli`
  - `cargo run -p nils-bilibili-cli -- --help`

### Task 1.4: Define runtime env variables and bounds
- **Location**:
  - `workflows/bilibili-search/workflow.toml`
  - `workflows/bilibili-search/src/info.plist.template`
  - `crates/bilibili-cli/docs/workflow-contract.md`
  - `crates/bilibili-cli/src/config.rs`
- **Description**: Define and document workflow/CLI env variables such as `BILIBILI_UID`, `BILIBILI_MAX_RESULTS`, `BILIBILI_TIMEOUT_MS`, and optional `BILIBILI_USER_AGENT`, including defaults and clamping rules.
- **Dependencies**:
  - Task 1.1
  - Task 1.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Required/optional status is consistent across manifest, plist template, contract doc, and config parser.
  - Numeric bounds are explicit and deterministic.
  - `BILIBILI_UID` empty value behavior is explicitly documented.
- **Validation**:
  - `rg -n "BILIBILI_UID|BILIBILI_MAX_RESULTS|BILIBILI_TIMEOUT_MS|BILIBILI_USER_AGENT" workflows/bilibili-search/workflow.toml workflows/bilibili-search/src/info.plist.template crates/bilibili-cli/docs/workflow-contract.md crates/bilibili-cli/src/config.rs`
  - `cargo test -p nils-bilibili-cli config_`

## Sprint 2: Suggest API and feedback pipeline
**Goal**: Implement Bilibili suggest ingestion and deterministic Alfred JSON rendering in `bilibili-cli`.
**Demo/Validation**:
- Command(s): `cargo test -p nils-bilibili-cli`, `cargo run -p nils-bilibili-cli -- query --input "naruto" --mode alfred | jq -e '.items | type == "array"'`
- Verify: CLI emits valid Alfred JSON for success/empty/error paths without shell-side data shaping.

### Task 2.1: Implement config parsing and guardrails
- **Location**:
  - `crates/bilibili-cli/src/config.rs`
  - `crates/bilibili-cli/src/lib.rs`
- **Description**: Parse env vars, normalize optional UID, clamp max results/timeout values, and surface actionable config errors.
- **Dependencies**:
  - Task 1.3
  - Task 1.4
- **Complexity**: 4
- **Acceptance criteria**:
  - Missing optional vars resolve to documented defaults.
  - Invalid numeric env values produce deterministic errors.
  - Config parser output is stable for both Alfred runtime and local CLI runs.
- **Validation**:
  - `cargo test -p nils-bilibili-cli`
  - `cargo test -p nils-bilibili-cli -- --list | rg "config_"`

### Task 2.2: Implement Bilibili suggest API client and parser
- **Location**:
  - `crates/bilibili-cli/src/bilibili_api.rs`
  - `crates/bilibili-cli/Cargo.toml`
- **Description**: Implement GET request to `https://s.search.bilibili.com/main/suggest` with `term` and optional `userid`, parse response payload (`result.tag[].value`), and map transport/schema failures into typed errors.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Request includes expected query parameters and timeout.
  - Parser safely handles empty/missing `result` and malformed tag rows.
  - Dedupe/normalization rules are deterministic before feedback mapping.
- **Validation**:
  - `cargo test -p nils-bilibili-cli`
  - `cargo test -p nils-bilibili-cli bilibili_api_builds_expected_query_params`
  - `cargo test -p nils-bilibili-cli bilibili_api_parser_dedupes_and_normalizes_terms`
  - `cargo test -p nils-bilibili-cli -- --list | rg "bilibili_api_"`
  - `cargo clippy -p nils-bilibili-cli --all-targets -- -D warnings`

### Task 2.3: Implement Alfred feedback mapping for suggestions
- **Location**:
  - `crates/bilibili-cli/src/feedback.rs`
  - `crates/bilibili-cli/src/lib.rs`
- **Description**: Convert normalized suggestion terms into Alfred items with title/subtitle/autocomplete and URL `arg`, include direct-search fallback row when suggestions are empty.
- **Dependencies**:
  - Task 2.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Every actionable row carries a valid Bilibili search URL in `arg`.
  - Empty results produce a non-crashing guidance row plus direct-search fallback.
  - Subtitle text remains concise and stable for Chinese/English mixed queries.
- **Validation**:
  - `cargo test -p nils-bilibili-cli`
  - `cargo test -p nils-bilibili-cli -- --list | rg "feedback_|url_|fallback_"`

### Task 2.4: Implement CLI command surface and stdout contract
- **Location**:
  - `crates/bilibili-cli/src/main.rs`
- **Description**: Add `query` command (workflow-facing) and optional `search` alias (explicit query), enforce Alfred JSON on stdout and deterministic stderr/exit codes for errors.
- **Dependencies**:
  - Task 2.1
  - Task 2.3
- **Complexity**: 5
- **Acceptance criteria**:
  - `query --input` success path prints JSON only on stdout.
  - User/runtime errors map to predictable exit codes and clear messages.
  - Service-envelope mode remains available for diagnostics parity with existing crates.
- **Validation**:
  - `cargo test -p nils-bilibili-cli`
  - `cargo test -p nils-bilibili-cli -- --list | rg "main_|query_"`
  - `cargo run -p nils-bilibili-cli -- query --input "naruto" --mode alfred | jq -e '.items | type == "array"'`
  - `bash -c 'set +e; cargo run -p nils-bilibili-cli -- query --input "" >/dev/null 2>&1; test $? -ne 0'`

### Task 2.5: Finalize error-class mapping for Script Filter UX
- **Location**:
  - `crates/bilibili-cli/src/main.rs`
  - `crates/bilibili-cli/src/feedback.rs`
  - `workflows/bilibili-search/scripts/script_filter.sh`
- **Description**: Align CLI error phrases and script error-to-item mapping so common failures (empty query, invalid config, timeout/network, malformed payload) render actionable Alfred rows.
- **Dependencies**:
  - Task 2.4
- **Complexity**: 5
- **Acceptance criteria**:
  - Script filter never returns malformed JSON on CLI failure.
  - Error titles/subtitles are distinct for user-fixable vs transient runtime failures.
- **Validation**:
  - `cargo test -p nils-bilibili-cli`
  - `bash workflows/bilibili-search/scripts/script_filter.sh "na" | jq -e '.items | type == "array"'`
  - `bash -c 'set +e; BILIBILI_TIMEOUT_MS=bad bash workflows/bilibili-search/scripts/script_filter.sh "naruto" | jq -e ".items | type == \"array\""'`

## Sprint 3: Alfred wiring and package integration
**Goal**: Wire scripts/plist/packaging so `bilibili-search` works in dev and packaged runtime paths.
**Demo/Validation**:
- Command(s): `bash workflows/bilibili-search/tests/smoke.sh`, `scripts/workflow-pack.sh --id bilibili-search`
- Verify: Workflow package contains valid plist graph, scripts, assets, and executable binary wiring.

### Task 3.1: Build robust script-filter adapter
- **Location**:
  - `workflows/bilibili-search/scripts/script_filter.sh`
- **Description**: Implement helper resolution, CLI binary resolution (`BILIBILI_CLI_BIN` override + package/release/debug paths), query policy checks, and async coalesce driver integration.
- **Dependencies**:
  - Task 2.4
  - Task 2.5
- **Complexity**: 6
- **Acceptance criteria**:
  - Adapter resolves runtime helpers consistently in both repo/dev and packaged contexts.
  - Short query policy (minimum chars) is enforced before remote API calls.
  - Pending state and final fetch orchestration reuse shared `script_filter_search_driver.sh`.
- **Validation**:
  - `shellcheck workflows/bilibili-search/scripts/script_filter.sh`
  - `shfmt -d workflows/bilibili-search/scripts/script_filter.sh`
  - `bash workflows/bilibili-search/scripts/script_filter.sh "naruto" | jq -e '.items | type == "array"'`

### Task 3.2: Implement URL open action script
- **Location**:
  - `workflows/bilibili-search/scripts/action_open.sh`
- **Description**: Wire action script through shared `workflow_action_open_url.sh` helper and enforce argument validation semantics.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 2
- **Acceptance criteria**:
  - Valid URL argument opens browser via helper.
  - Missing argument returns usage failure (exit code 2 path from helper contract).
- **Validation**:
  - `shellcheck workflows/bilibili-search/scripts/action_open.sh`
  - `bash -c 'tmpdir="$(mktemp -d)"; printf "#!/usr/bin/env bash\nprintf \"%s\\n\" \"$1\" >\"$tmpdir/url\"\n" >"$tmpdir/open"; chmod +x "$tmpdir/open"; PATH="$tmpdir:$PATH" bash workflows/bilibili-search/scripts/action_open.sh "https://search.bilibili.com/all?keyword=naruto"; test "$(cat "$tmpdir/url")" = "https://search.bilibili.com/all?keyword=naruto"; rm -rf "$tmpdir"'`

### Task 3.3: Wire info.plist template object graph and user variables
- **Location**:
  - `workflows/bilibili-search/src/info.plist.template`
- **Description**: Configure keyword trigger (`bl`), script filter object, action node connection, and `userconfigurationconfig` entries for `BILIBILI_UID` and other runtime vars.
- **Dependencies**:
  - Task 1.4
  - Task 3.1
  - Task 3.2
- **Complexity**: 7
- **Acceptance criteria**:
  - Packaged plist passes lint and contains expected scriptfile/type/connection wiring.
  - Workflow variable fields in Alfred UI match runtime contract names.
- **Validation**:
  - `scripts/workflow-pack.sh --id bilibili-search`
  - `plutil -lint build/workflows/bilibili-search/pkg/info.plist`
  - `plutil -convert json -o - build/workflows/bilibili-search/pkg/info.plist | jq -e '[.userconfigurationconfig[].variable] | index("BILIBILI_UID") != null'`
  - `plutil -convert json -o - build/workflows/bilibili-search/pkg/info.plist | jq -e '.objects[] | select(.type == "alfred.workflow.input.scriptfilter") | .config.keyword == "bl"'`

### Task 3.4: Align manifest and packaging references
- **Location**:
  - `workflows/bilibili-search/workflow.toml`
  - `scripts/workflow-pack.sh`
- **Description**: Verify workflow manifest references (`rust_binary`, scripts, assets, optional readme_source) package correctly and do not regress existing workflows in `--all` packaging mode.
- **Dependencies**:
  - Task 3.3
- **Complexity**: 4
- **Acceptance criteria**:
  - `workflow-pack.sh --id bilibili-search` produces installable artifact.
  - `workflow-pack.sh --all` remains green with the new workflow included.
- **Validation**:
  - `scripts/workflow-pack.sh --id bilibili-search`
  - `scripts/workflow-pack.sh --all`

### Task 3.5: Add deterministic smoke checks for script/file contracts
- **Location**:
  - `workflows/bilibili-search/tests/smoke.sh`
- **Description**: Add smoke checks for required files, script executability, script-filter JSON contract, and no-crash behavior under missing optional env values.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Smoke checks fail loudly on missing files, non-executable scripts, or malformed JSON output.
  - Smoke checks remain deterministic and do not rely on live Bilibili network.
- **Validation**:
  - `bash workflows/bilibili-search/tests/smoke.sh`
  - `scripts/workflow-test.sh --id bilibili-search`

### Task 3.6: Extend smoke checks with packaged plist assertions
- **Location**:
  - `workflows/bilibili-search/tests/smoke.sh`
- **Description**: Add packaged plist assertions for object type presence, scriptfile paths, keyword wiring, and action-chain connections.
- **Dependencies**:
  - Task 3.3
  - Task 3.5
- **Complexity**: 7
- **Acceptance criteria**:
  - Packaged plist assertions catch missing or broken object graph wiring.
  - Checks remain headless and reproducible in CI/local shells.
- **Validation**:
  - `bash workflows/bilibili-search/tests/smoke.sh`
  - `scripts/workflow-pack.sh --id bilibili-search`

## Sprint 4: Docs, quality gates, and rollout safety
**Goal**: Finalize tests/docs and run end-to-end quality gates for merge readiness.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `scripts/workflow-test.sh --id bilibili-search`, `scripts/workflow-pack.sh --id bilibili-search --install`
- Verify: Workflow is quality-gated, documented, packageable, and operationally reversible.

### Task 4.1: Add comprehensive Rust tests for config/api/feedback/main
- **Location**:
  - `crates/bilibili-cli/src/config.rs`
  - `crates/bilibili-cli/src/bilibili_api.rs`
  - `crates/bilibili-cli/src/feedback.rs`
  - `crates/bilibili-cli/src/main.rs`
- **Description**: Add deterministic tests for env parsing, response parsing normalization, URL composition, fallback rows, and CLI stdout/stderr/exit-code contracts.
- **Dependencies**:
  - Task 2.5
- **Complexity**: 6
- **Acceptance criteria**:
  - Unit tests cover both success and failure mapping without live network dependency.
  - CLI tests verify Alfred JSON contract and error code behavior.
- **Validation**:
  - `cargo test -p nils-bilibili-cli`
  - `cargo test -p nils-bilibili-cli -- --list | rg "config_|bilibili_api_|feedback_|main_"`

### Task 4.2: Document workflow usage and operator guidance
- **Location**:
  - `README.md`
  - `docs/WORKFLOW_GUIDE.md`
  - `workflows/bilibili-search/README.md`
- **Description**: Add user-facing docs for keyword usage, optional UID personalization, environment variables, runtime behavior, and deterministic validation commands.
- **Dependencies**:
  - Task 3.4
- **Complexity**: 4
- **Acceptance criteria**:
  - Root workflow table includes `bilibili-search`.
  - Workflow guide includes dedicated `bilibili-search` section and operator checklist.
  - Workflow local README includes config table and keyword behavior.
- **Validation**:
  - `rg -n "bilibili-search|BILIBILI_UID|bl " README.md docs/WORKFLOW_GUIDE.md workflows/bilibili-search/README.md`

### Task 4.3: Add workflow-local troubleshooting and rollback runbook
- **Location**:
  - `workflows/bilibili-search/TROUBLESHOOTING.md`
  - `TROUBLESHOOTING.md`
- **Description**: Document symptom-to-action table for common runtime issues and publish rollback guidance aligned with monorepo operator model.
- **Dependencies**:
  - Task 3.6
- **Complexity**: 3
- **Acceptance criteria**:
  - Local troubleshooting doc includes quick checks, common failures, and validation command set.
  - Global troubleshooting index references `bilibili-search` routes where applicable.
- **Validation**:
  - `rg -n "bilibili|BILIBILI_UID|rollback|API unavailable" workflows/bilibili-search/TROUBLESHOOTING.md TROUBLESHOOTING.md`

### Task 4.4: Execute final repo gates and package validation
- **Location**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh`
- **Description**: Run full lint/test/pack checks for changed scope and verify versioned artifact creation for release readiness.
- **Dependencies**:
  - Task 4.1
  - Task 4.2
  - Task 4.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Required project checks pass for changed scope.
  - Packaged artifact exists under `dist/bilibili-search/` with a versioned subdirectory.
- **Validation**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh --id bilibili-search`
  - `scripts/workflow-pack.sh --id bilibili-search`
  - `test -f dist/bilibili-search/*/*.alfredworkflow`

### Task 4.5: Define first-release support window and disable triggers
- **Location**:
  - `workflows/bilibili-search/TROUBLESHOOTING.md`
  - `docs/plans/bilibili-search-workflow-plan.md`
- **Description**: Define D0-D2 monitoring checklist, error-class sampling categories, and objective disable thresholds for rapid operational response.
- **Dependencies**:
  - Task 4.4
- **Complexity**: 3
- **Acceptance criteria**:
  - Support window checklist explicitly names alert classes and mitigation actions.
  - Disable triggers are measurable and tied to fallback/rollback procedures.
- **Validation**:
  - `rg -n "D0-D2|disable|trigger|rollback|support window" workflows/bilibili-search/TROUBLESHOOTING.md docs/plans/bilibili-search-workflow-plan.md`
  - `rg -n "30%.*30 minutes|malformed JSON" workflows/bilibili-search/TROUBLESHOOTING.md docs/plans/bilibili-search-workflow-plan.md`

## Testing Strategy
- Unit: `bilibili-cli` tests for config parsing, API response parsing, URL generation, feedback rendering, and error mapping.
- Integration: script adapter checks (`shellcheck`, `shfmt`) plus smoke tests validating script-filter JSON contract and packaged plist wiring.
- E2E/manual: package and install workflow, run `bl` queries with/without `BILIBILI_UID`, verify suggestions and browser-open behavior.
- Non-functional: validate acceptable interactive latency under coalescing and stable UX when endpoint is slow/unavailable.

## Risks & gotchas
- Upstream Bilibili suggest response schema can change without notice; parser must remain defensive.
- Endpoint throttling or anti-bot controls can cause transient failures and noisy user experience.
- Mixed Chinese/English query normalization and URL encoding can introduce subtle regressions.
- Alfred plist object graph wiring is brittle; incorrect UID connections can silently break Enter action.
- Optional personalization via UID can create hard-to-reproduce behavior differences across operators.

## First-release support window (D0-D2)
- Monitor failure classes separately: invalid config, API unavailable, malformed payload, empty suggestions.
- Trigger emergency disable procedure if either condition is met:
  - Script-filter malformed JSON observed at any time.
  - API unavailable class exceeds 30% of sampled queries for 30 minutes.
- Keep operator response template ready:
  - Current status (degraded/disabled)
  - Scope (`bilibili-search` only)
  - Workaround (manual browser search)
  - Next update time

## Rollback plan
- Step 1: Stop distributing new `bilibili-search` artifacts.
- Step 2: Revert or remove Bilibili workflow and crate changesets:
  - `workflows/bilibili-search/`
  - `crates/bilibili-cli/`
  - workspace entry in `Cargo.toml`
  - related docs updates
- Step 3: Rebuild and validate rollback state:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh --all`
- Step 4: Reinstall known-good artifacts and publish rollback note with temporary workaround.
