# Plan: Add Cambridge dictionary workflow for Alfred (Playwright backend)

## Overview
This plan adds a new Alfred workflow, `cambridge-dict`, to support Cambridge dictionary lookup with Playwright-based scraping.
The workflow supports two dictionary modes via parameters: English definitions (`english`) and English to Traditional Chinese translations (`english-chinese-traditional`).
The UX is a two-step flow inside Alfred: type a query to get candidate headwords, then select a candidate to render the target entry explanation in Alfred.
Implementation follows existing repository architecture: domain logic in Rust, thin shell adapters, and deterministic packaging/testing via `scripts/workflow-*` entrypoints.

## Scope
- In scope: New workflow `cambridge-dict` with Script Filter + open action.
- In scope: Playwright scraper for Cambridge candidate lookup and entry detail extraction.
- In scope: Parameterized mode switch between English and English-Chinese (Traditional).
- In scope: Alfred two-step interaction (candidate list then definition detail view).
- In scope: Cache and timeout guardrails to keep Alfred responsive.
- In scope: Tests, smoke checks, docs, CI updates, and rollback-safe release notes.
- Out of scope: Cambridge paid/offical API integration in this plan.
- Out of scope: Multi-dictionary federation (Oxford, Collins, Merriam-Webster).
- Out of scope: User account/login features and vocabulary sync.
- Out of scope: OCR/image lookup and sentence translation beyond dictionary entries.

## Assumptions (if any)
1. Runtime environment can provide `node` and Playwright browser binaries for workflow execution.
2. First release can rely on Chromium in headless mode for scraping; no Firefox/WebKit parity is required.
3. Query-to-detail transition is modeled by Alfred query tokenization (`def::<headword>`) to avoid complex multi-object workflow chains.
4. Initial mode values are exactly `english` and `english-chinese-traditional`; mode defaults to `english-chinese-traditional`.
5. Cache is stored in Alfred workflow cache/data directories and can be safely invalidated during upgrades.

## Success Criteria
- Typing keyword + query shows Cambridge candidate headwords in Alfred.
- Selecting a candidate switches to detail mode and shows part-of-speech/phonetics/definitions in Alfred without opening a browser.
- `CAMBRIDGE_DICT_MODE` reliably switches between English and English-Chinese (Traditional) output.
- Missing runtime dependencies (`node`, Playwright browser), network failures, and anti-bot pages are rendered as non-crashing Alfred feedback items.
- `scripts/workflow-lint.sh`, `scripts/workflow-test.sh --id cambridge-dict`, and `scripts/workflow-pack.sh --id cambridge-dict` pass.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 1.4 -> Task 2.1 -> Task 2.2 -> Task 2.3 -> Task 2.5 -> Task 3.2 -> Task 3.3 -> Task 3.4 -> Task 3.5 -> Task 3.6 -> Task 3.7 -> Task 4.4`.
- Parallel track A: `Task 1.3` can run in parallel with `Task 1.4` after `Task 1.1`.
- Parallel track B: `Task 2.4` can run in parallel with `Task 2.3` after `Task 2.2`.
- Parallel track C: `Task 3.1` can run after `Task 1.4` and in parallel with `Task 2.6`.
- Parallel track D: `Task 4.1` and `Task 4.2` can run in parallel after `Task 3.7`.

## Sprint 1: Contract and scaffolding
**Goal**: Freeze behavior contract, mode parameter semantics, and repository skeleton for new workflow/crate.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/cambridge-playwright-dictionary-workflow-plan.md`, `test -d workflows/cambridge-dict`, `cargo check -p nils-cambridge-cli`
- Verify: Workflow skeleton exists, mode contract is explicit, and workspace resolves new crate.

### Task 1.1: Define Cambridge workflow behavior contract
- **Location**:
  - `crates/cambridge-cli/docs/workflow-contract.md`
- **Description**: Write functional contract for keyword behavior, two-stage query flow (`search` vs `def::WORD`), Alfred JSON schema, and error mapping.
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - Contract includes candidate and detail stage behaviors.
  - Contract defines required Alfred item fields for success/empty/error states.
  - Contract includes query token grammar and examples.
- **Validation**:
  - `test -f crates/cambridge-cli/docs/workflow-contract.md`
  - `rg -n "^## (Keyword and Query Handling|Two-Stage Query Token Grammar|Alfred Item JSON Contract|Error Mapping|Environment Variables and Constraints)$" crates/cambridge-cli/docs/workflow-contract.md`
  - `rg -n "def::|CAMBRIDGE_DICT_MODE|english-chinese-traditional|english" crates/cambridge-cli/docs/workflow-contract.md`

### Task 1.2: Define mode parameter and runtime env contract
- **Location**:
  - `crates/cambridge-cli/docs/workflow-contract.md`
  - `workflows/cambridge-dict/workflow.toml`
  - `workflows/cambridge-dict/src/info.plist.template`
- **Description**: Define environment variables and constraints: `CAMBRIDGE_DICT_MODE`, `CAMBRIDGE_MAX_RESULTS`, `CAMBRIDGE_TIMEOUT_MS`, `CAMBRIDGE_HEADLESS`.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Allowed mode values and defaults are explicit and consistent across docs/manifest/plist.
  - Numeric bounds and fallback defaults are documented.
- **Validation**:
  - `rg -n "CAMBRIDGE_DICT_MODE|CAMBRIDGE_MAX_RESULTS|CAMBRIDGE_TIMEOUT_MS|CAMBRIDGE_HEADLESS" crates/cambridge-cli/docs/workflow-contract.md workflows/cambridge-dict/workflow.toml workflows/cambridge-dict/src/info.plist.template`
  - `rg -n "english-chinese-traditional|english" crates/cambridge-cli/docs/workflow-contract.md workflows/cambridge-dict/workflow.toml`

### Task 1.3: Scaffold workflow folder and manifest
- **Location**:
  - `workflows/cambridge-dict/workflow.toml`
  - `workflows/cambridge-dict/scripts/script_filter.sh`
  - `workflows/cambridge-dict/scripts/action_open.sh`
  - `workflows/cambridge-dict/scripts/cambridge_scraper.mjs`
  - `workflows/cambridge-dict/src/info.plist.template`
  - `workflows/cambridge-dict/src/assets/icon.png`
  - `workflows/cambridge-dict/tests/smoke.sh`
  - `workflows/cambridge-dict/README.md`
- **Description**: Create workflow skeleton wired to `cambridge-cli` and Playwright scraper script with required scripts/assets/tests.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Workflow directory contains required files and executable scripts.
  - `workflow.toml` references `cambridge-cli` as `rust_binary`.
- **Validation**:
  - `test -d workflows/cambridge-dict`
  - `test -f workflows/cambridge-dict/workflow.toml`
  - `test -x workflows/cambridge-dict/scripts/script_filter.sh`
  - `scripts/workflow-lint.sh --id cambridge-dict`

### Task 1.4: Add dedicated Rust binary crate for Cambridge workflow
- **Location**:
  - `Cargo.toml`
  - `crates/cambridge-cli/Cargo.toml`
  - `crates/cambridge-cli/src/main.rs`
  - `crates/cambridge-cli/src/lib.rs`
- **Description**: Create dedicated crate for config parsing, scraper invocation bridge, feedback mapping, and CLI contract.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Workspace includes `crates/cambridge-cli`.
  - `cargo run -p nils-cambridge-cli -- --help` succeeds with placeholder command surface.
- **Validation**:
  - `cargo check -p nils-cambridge-cli`
  - `cargo run -p nils-cambridge-cli -- --help`

### Task 1.5: Add Node/Playwright dependency and bootstrap guidance
- **Location**:
  - `BINARY_DEPENDENCIES.md`
  - `DEVELOPMENT.md`
  - `scripts/setup-node-playwright.sh`
  - `TROUBLESHOOTING.md`
- **Description**: Document and wire setup for Node runtime and Playwright browser installation for Cambridge workflow development and debugging.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 4
- **Acceptance criteria**:
  - Dependency docs include Node and Playwright requirements and verification commands.
  - Setup/troubleshooting docs include a deterministic Playwright install path.
- **Validation**:
  - `rg -n "node|playwright|npx playwright install" BINARY_DEPENDENCIES.md DEVELOPMENT.md TROUBLESHOOTING.md`
  - `bash -n scripts/setup-node-playwright.sh`

## Sprint 2: Playwright scraper and extraction contracts
**Goal**: Build deterministic scraper outputs for both candidate and detail stages across both dictionary modes.
**Demo/Validation**:
- Command(s): `node --test workflows/cambridge-dict/scripts/tests/cambridge_scraper.test.mjs`, `node workflows/cambridge-dict/scripts/cambridge_scraper.mjs suggest --query open --mode english`
- Verify: Scraper emits typed JSON for success/error without malformed output.

### Task 2.1: Implement scraper CLI skeleton
- **Location**:
  - `workflows/cambridge-dict/scripts/cambridge_scraper.mjs`
  - `workflows/cambridge-dict/scripts/lib/scraper_contract.mjs`
- **Description**: Implement Node CLI entrypoint with subcommands `suggest` and `define`, JSON output contract, argument parsing, and exit-code semantics.
- **Dependencies**:
  - Task 1.5
- **Complexity**: 5
- **Acceptance criteria**:
  - CLI validates required arguments and mode values.
  - Success and failure paths always emit parseable JSON payloads.
- **Validation**:
  - `node workflows/cambridge-dict/scripts/cambridge_scraper.mjs --help`
  - `node workflows/cambridge-dict/scripts/cambridge_scraper.mjs suggest --query open --mode english | jq -e '.ok | type == "boolean"'`
  - `bash -c 'set +e; node workflows/cambridge-dict/scripts/cambridge_scraper.mjs suggest --query "" --mode english >/dev/null 2>&1; test $? -ne 0'`

### Task 2.2: Implement mode-aware URL/router and selector registry
- **Location**:
  - `workflows/cambridge-dict/scripts/lib/cambridge_routes.mjs`
  - `workflows/cambridge-dict/scripts/lib/cambridge_selectors.mjs`
- **Description**: Centralize dictionary-mode URL builders and fallback selectors for candidate list and entry details in both modes.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Route builder supports both modes without duplicated hard-coded paths.
  - Selector registry supports stable fallback chains for DOM drift tolerance.
- **Validation**:
  - `node --test workflows/cambridge-dict/scripts/tests/cambridge_routes.test.mjs`
  - `node --test workflows/cambridge-dict/scripts/tests/cambridge_selectors.test.mjs`

### Task 2.3: Implement candidate extraction (`suggest`)
- **Location**:
  - `workflows/cambridge-dict/scripts/cambridge_scraper.mjs`
  - `workflows/cambridge-dict/scripts/lib/extract_suggest.mjs`
- **Description**: Extract candidate headwords from Cambridge pages/autocomplete results, normalize dedupe order, and cap to `CAMBRIDGE_MAX_RESULTS`.
- **Dependencies**:
  - Task 2.2
- **Complexity**: 8
- **Acceptance criteria**:
  - Extractor returns deterministic ordered candidates with stable IDs.
  - Empty/noise pages return non-crashing empty result payloads.
- **Validation**:
  - `node --test workflows/cambridge-dict/scripts/tests/extract_suggest.test.mjs`
  - `node --test workflows/cambridge-dict/scripts/tests/extract_suggest_limit.test.mjs`
  - `CAMBRIDGE_MAX_RESULTS=3 node workflows/cambridge-dict/scripts/cambridge_scraper.mjs suggest --query open --mode english | jq -e '.ok == true and (.items | length) <= 3'`
  - `node workflows/cambridge-dict/scripts/cambridge_scraper.mjs suggest --query open --mode english-chinese-traditional | jq -e '.ok == true and (.items | type == "array")'`

### Task 2.4: Implement entry detail extraction (`define`)
- **Location**:
  - `workflows/cambridge-dict/scripts/cambridge_scraper.mjs`
  - `workflows/cambridge-dict/scripts/lib/extract_define.mjs`
- **Description**: Extract entry detail fields (headword, POS, phonetics, and definition lines) and normalize text for Alfred subtitles.
- **Dependencies**:
  - Task 2.2
- **Complexity**: 8
- **Acceptance criteria**:
  - Extractor returns detail payloads for both modes with predictable field names.
  - Definition rows are clean, bounded, and resilient to missing optional fields.
- **Validation**:
  - `node --test workflows/cambridge-dict/scripts/tests/extract_define.test.mjs`
  - `node workflows/cambridge-dict/scripts/cambridge_scraper.mjs define --entry open --mode english | jq -e '.ok == true and .entry.headword == "open"'`

### Task 2.5: Add anti-bot, cookie-wall, and timeout classification
- **Location**:
  - `workflows/cambridge-dict/scripts/cambridge_scraper.mjs`
  - `workflows/cambridge-dict/scripts/lib/error_classify.mjs`
- **Description**: Detect Cloudflare/cookie wall/timeouts and map them into stable machine-readable error codes for Rust/Alfred fallback mapping.
- **Dependencies**:
  - Task 2.3
  - Task 2.4
- **Complexity**: 7
- **Acceptance criteria**:
  - Error payload includes code, user-facing hint, and retriable flag.
  - Timeouts and anti-bot pages are distinguishable from no-result conditions.
- **Validation**:
  - `node --test workflows/cambridge-dict/scripts/tests/error_classify.test.mjs`
  - `rg -n "cloudflare|cookie|timeout|retriable" workflows/cambridge-dict/scripts/lib/error_classify.mjs`

### Task 2.6: Add scraper fixtures and deterministic Node tests
- **Location**:
  - `workflows/cambridge-dict/scripts/tests/fixtures/suggest-english-open.html`
  - `workflows/cambridge-dict/scripts/tests/fixtures/suggest-english-chinese-traditional-open.html`
  - `workflows/cambridge-dict/scripts/tests/fixtures/define-english-open.html`
  - `workflows/cambridge-dict/scripts/tests/fixtures/define-english-chinese-traditional-open.html`
  - `workflows/cambridge-dict/scripts/tests/cambridge_scraper.test.mjs`
- **Description**: Add fixture-driven tests to validate parser/normalizer behavior without live network dependency.
- **Dependencies**:
  - Task 2.5
- **Complexity**: 6
- **Acceptance criteria**:
  - Fixture tests cover mode switch, empty state, and common error classification paths.
  - Test suite is runnable in CI without launching real browsers.
- **Validation**:
  - `node --test workflows/cambridge-dict/scripts/tests/*.test.mjs`

## Sprint 3: Rust bridge and Alfred UX wiring
**Goal**: Bridge scraper outputs to Alfred-friendly JSON and finalize two-stage interactive behavior.
**Demo/Validation**:
- Command(s): `cargo test -p nils-cambridge-cli`, `bash workflows/cambridge-dict/scripts/script_filter.sh "open"`
- Verify: Script Filter returns valid Alfred JSON for search and detail stages.

### Task 3.1: Implement `cambridge-cli` config parsing and guardrails
- **Location**:
  - `crates/cambridge-cli/src/config.rs`
  - `crates/cambridge-cli/src/lib.rs`
- **Description**: Parse env vars, enforce mode constraints, clamp result limits/timeouts, and validate tokenized detail queries.
- **Dependencies**:
  - Task 1.4
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Invalid mode and invalid numeric values return actionable config errors.
  - Defaults match contract for all optional env variables.
- **Validation**:
  - `cargo test -p nils-cambridge-cli`
  - `cargo test -p nils-cambridge-cli -- --list | rg "config_|mode_|token_"`

### Task 3.2: Implement Node scraper subprocess bridge
- **Location**:
  - `crates/cambridge-cli/src/scraper_bridge.rs`
  - `crates/cambridge-cli/src/lib.rs`
- **Description**: Invoke `node cambridge_scraper.mjs` with bounded timeout and decode JSON contract into typed Rust structs.
- **Dependencies**:
  - Task 3.1
  - Task 2.6
- **Complexity**: 8
- **Acceptance criteria**:
  - Bridge handles missing `node`, non-zero exit, malformed JSON, and timeout paths.
  - Suggest/define subcommands are routed correctly based on query token grammar.
- **Validation**:
  - `cargo test -p nils-cambridge-cli`
  - `cargo test -p nils-cambridge-cli -- --list | rg "bridge_|scraper_|timeout_"`
  - `bash -c 'set +e; CAMBRIDGE_NODE_BIN=/nonexistent cargo run -p nils-cambridge-cli -- query --input "open" >/dev/null 2>&1; test $? -ne 0'`

### Task 3.3: Implement Alfred feedback mapping for two-stage UX
- **Location**:
  - `crates/cambridge-cli/src/feedback.rs`
  - `crates/cambridge-cli/src/lib.rs`
- **Description**: Map suggest results to selectable items and detail results to structured explanation rows; emit `autocomplete` tokens to transition from candidate to detail stage.
- **Dependencies**:
  - Task 3.2
- **Complexity**: 7
- **Acceptance criteria**:
  - Suggest items include stable title/subtitle and detail transition token (`def::WORD`).
  - Detail rows remain readable and non-actionable when appropriate.
- **Validation**:
  - `cargo test -p nils-cambridge-cli`
  - `cargo test -p nils-cambridge-cli -- --list | rg "feedback_|autocomplete_|detail_"`

### Task 3.4: Implement CLI command surface and stdout contract
- **Location**:
  - `crates/cambridge-cli/src/main.rs`
- **Description**: Add `query --input TEXT` command with JSON-only stdout on success and concise stderr on failure.
- **Dependencies**:
  - Task 3.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Success path emits Alfred JSON only.
  - Failure path uses non-zero exit and actionable single-line errors.
- **Validation**:
  - `cargo test -p nils-cambridge-cli`
  - `cargo run -p nils-cambridge-cli -- query --input "open" | jq -e '.items | type == "array"'`

### Task 3.5: Implement script filter and open-action adapters
- **Location**:
  - `workflows/cambridge-dict/scripts/script_filter.sh`
  - `workflows/cambridge-dict/scripts/action_open.sh`
- **Description**: Resolve binaries/scripts in packaged and dev layouts, call `cambridge-cli`, and emit fallback Alfred JSON when runtime errors occur.
- **Dependencies**:
  - Task 3.4
- **Complexity**: 6
- **Acceptance criteria**:
  - Script filter always returns valid Alfred JSON for empty query, success, and failure.
  - Action script opens canonical Cambridge URL when `arg` URL is provided.
- **Validation**:
  - `shellcheck workflows/cambridge-dict/scripts/script_filter.sh workflows/cambridge-dict/scripts/action_open.sh`
  - `shfmt -d workflows/cambridge-dict/scripts/script_filter.sh workflows/cambridge-dict/scripts/action_open.sh`
  - `bash workflows/cambridge-dict/scripts/script_filter.sh "open" | jq -e '.items | type == "array"'`

### Task 3.6: Wire `info.plist.template` object graph and env vars
- **Location**:
  - `workflows/cambridge-dict/src/info.plist.template`
  - `workflows/cambridge-dict/workflow.toml`
- **Description**: Configure keyword trigger, script nodes, action chain, and Alfred user configuration for mode/results/timeout/headless parameters.
- **Dependencies**:
  - Task 3.5
  - Task 1.3
- **Complexity**: 7
- **Acceptance criteria**:
  - Generated plist passes lint and includes expected scriptfile/type wiring.
  - User config exposes intended env vars with defaults and descriptions.
- **Validation**:
  - `scripts/workflow-pack.sh --id cambridge-dict`
  - `plutil -lint build/workflows/cambridge-dict/pkg/info.plist`
  - `plutil -convert json -o - build/workflows/cambridge-dict/pkg/info.plist | jq -e '[.userconfigurationconfig[].variable] | index("CAMBRIDGE_DICT_MODE") != null and index("CAMBRIDGE_MAX_RESULTS") != null and index("CAMBRIDGE_TIMEOUT_MS") != null and index("CAMBRIDGE_HEADLESS") != null'`

### Task 3.7: Add workflow smoke tests with scraper stubs
- **Location**:
  - `workflows/cambridge-dict/tests/smoke.sh`
- **Description**: Add deterministic smoke checks for required files, executability, fallback mapping, layout resolution, and plist wiring without live Playwright execution.
- **Dependencies**:
  - Task 3.5
  - Task 3.6
- **Complexity**: 7
- **Acceptance criteria**:
  - Smoke test validates candidate-stage and detail-stage JSON behavior via stubbed `cambridge-cli`/scraper outputs.
  - Smoke test verifies packaged plist object types and scriptfile references.
- **Validation**:
  - `bash workflows/cambridge-dict/tests/smoke.sh`
  - `scripts/workflow-test.sh --id cambridge-dict`
  - `scripts/workflow-pack.sh --id cambridge-dict`

## Sprint 4: Quality gates, documentation, and rollout safety
**Goal**: Finalize operational readiness, CI reliability, and rollback-safe release process.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `scripts/workflow-test.sh --id cambridge-dict`, `scripts/workflow-pack.sh --id cambridge-dict`
- Verify: Repo quality gates pass and workflow package is installable.

### Task 4.1: Document workflow usage and parameter switch behavior
- **Location**:
  - `workflows/cambridge-dict/README.md`
  - `README.md`
  - `docs/WORKFLOW_GUIDE.md`
  - `TROUBLESHOOTING.md`
- **Description**: Document keyword usage, two-stage query flow, `CAMBRIDGE_DICT_MODE` semantics, and known anti-bot/runtime limitations with mitigations.
- **Dependencies**:
  - Task 3.7
- **Complexity**: 3
- **Acceptance criteria**:
  - Docs clearly explain English vs English-Chinese mode switching.
  - Troubleshooting covers `node` missing, browser missing, timeout, and anti-bot pages.
- **Validation**:
  - `rg -n "cambridge-dict|CAMBRIDGE_DICT_MODE|def::|Playwright|Cloudflare|cookie" workflows/cambridge-dict/README.md README.md docs/WORKFLOW_GUIDE.md TROUBLESHOOTING.md`

### Task 4.2: Update CI for Node/Playwright-aware validation
- **Location**:
  - `.github/workflows/ci.yml`
- **Description**: Add Node setup and Playwright dependency handling for deterministic non-live tests, while keeping live scraping checks opt-in.
- **Dependencies**:
  - Task 1.5
  - Task 3.7
- **Complexity**: 5
- **Acceptance criteria**:
  - CI continues to run lint/test/package successfully on Ubuntu.
  - Playwright install overhead is scoped to tasks that require it.
- **Validation**:
  - `rg -n "node|playwright|workflow-test.sh|workflow-pack.sh" .github/workflows/ci.yml`

### Task 4.3: Add optional live scraper smoke gate (manual/cron)
- **Location**:
  - `workflows/cambridge-dict/tests/live-smoke.sh`
  - `.github/workflows/ci.yml`
- **Description**: Add opt-in live smoke test that runs real Playwright query against Cambridge under explicit env flag to detect upstream DOM drift early.
- **Dependencies**:
  - Task 2.5
  - Task 3.7
- **Complexity**: 6
- **Acceptance criteria**:
  - Live smoke test is skipped by default and clearly reports skip reason.
  - When enabled, test verifies both modes (`english`, `english-chinese-traditional`) on at least one stable word.
- **Validation**:
  - `bash workflows/cambridge-dict/tests/live-smoke.sh --help`
  - `bash -c 'set +e; CAMBRIDGE_LIVE_SMOKE=0 bash workflows/cambridge-dict/tests/live-smoke.sh; test $? -eq 0'`
  - `CAMBRIDGE_LIVE_SMOKE=1 bash workflows/cambridge-dict/tests/live-smoke.sh --mode english --word open`
  - `CAMBRIDGE_LIVE_SMOKE=1 bash workflows/cambridge-dict/tests/live-smoke.sh --mode english-chinese-traditional --word open`

### Task 4.4: Run final repository quality gates and packaging checks
- **Location**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh`
- **Description**: Execute required project gates and verify `cambridge-dict` artifact output and installability.
- **Dependencies**:
  - Task 4.1
  - Task 4.2
  - Task 4.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Required commands from `DEVELOPMENT.md` pass for changed scope.
  - Packaged artifact exists under versioned `dist/cambridge-dict/` path.
- **Validation**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh --id cambridge-dict`
  - `scripts/workflow-pack.sh --id cambridge-dict`
  - `test -f dist/cambridge-dict/*/*.alfredworkflow`

### Task 4.5: Add release support checklist and rollback notes
- **Location**:
  - `TROUBLESHOOTING.md`
  - `docs/plans/cambridge-playwright-dictionary-workflow-plan.md`
- **Description**: Document first-release monitoring checklist, disable triggers, and executable rollback procedure for workflow/crate/docs changes.
- **Dependencies**:
  - Task 4.4
- **Complexity**: 3
- **Acceptance criteria**:
  - Rollback sequence is explicit and runnable.
  - Support checklist includes measurable failure thresholds.
- **Validation**:
  - `rg -n "rollback|disable|cambridge-dict|cambridge-cli|threshold" TROUBLESHOOTING.md docs/plans/cambridge-playwright-dictionary-workflow-plan.md`

## Testing Strategy
- Unit: `cambridge-cli` config/token parsing, scraper bridge decoding, and Alfred feedback mapping.
- Unit: Node fixture tests for route mapping, selector fallback, candidate/detail extraction, and error classification.
- Integration: Workflow script smoke tests for executable layout resolution and fallback JSON guarantees.
- E2E/manual: Install packaged workflow, run keyword queries in both modes, verify two-stage behavior and URL open action.
- Non-functional: Verify warm-cache response latency, timeout behavior, and stability under transient network failures.

## Risks & gotchas
- Cambridge anti-bot/cookie challenge pages can cause intermittent scraper failures.
- DOM structure drift can silently break selectors and reduce extraction quality.
- Playwright cold start latency may hurt Alfred typing experience without caching.
- Runtime dependency drift (`node` version, browser binaries) can cause environment-specific failures.
- Terms and rate constraints can change; behavior must fail gracefully with clear operator guidance.

## First-release support window (D0-D2)
- Track failure classes separately: missing runtime dependency, anti-bot challenge, timeout/network, parser mismatch, and empty results.
- Trigger emergency degraded mode if either condition is met:
  - Anti-bot/challenge related failures exceed 25% of sampled queries for 30 minutes.
  - Script filter outputs malformed/non-JSON payload at any time.
- Operator response template:
  - Current status (healthy/degraded)
  - Scope (`cambridge-dict` only)
  - Workaround (open Cambridge website directly)
  - Next update time and mitigation in progress

## Rollback plan
- Step 1: Stop distributing new `cambridge-dict` artifacts.
- Step 2: Revert workflow and crate changes:
  - `workflows/cambridge-dict/`
  - `crates/cambridge-cli/`
  - workspace member update in `Cargo.toml`
  - docs updates in `README.md`, `docs/WORKFLOW_GUIDE.md`, `TROUBLESHOOTING.md`, and `crates/cambridge-cli/docs/workflow-contract.md`
- Step 3: Re-run quality gates after rollback:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh --all`
- Step 4: Reinstall known-good workflow artifacts and verify unaffected workflows.
- Step 5: Publish rollback notice with impact scope and temporary workaround.
