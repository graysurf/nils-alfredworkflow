# Plan: Deliver Bangumi search workflow (API-first) with future Playwright bridge design

## Overview
This plan delivers a new Alfred workflow, `bangumi-search`, backed by a dedicated Rust binary `bangumi-cli` that directly calls Bangumi API endpoints.
Primary runtime path is API-first and production-ready: query parsing, typed search, Alfred JSON feedback, script-filter wiring, smoke tests, and packaging.
In parallel, this plan defines a future-facing Playwright scraping architecture and lightweight scaffolding that is intentionally disabled by default.
Existing workflows and shared tooling contracts remain unchanged unless explicitly touched for new workflow registration/docs.

## Scope
- In scope: Add `workflows/bangumi-search` with script filter + open action and package wiring.
- In scope: Add `crates/bangumi-cli` with config parsing, input parser, API client, feedback mapping, and CLI surface.
- In scope: Implement Bangumi API direct integration using `https://api.bgm.tv/v0/search/subjects` as primary source.
- In scope: Support optional API key configuration via workflow variable with fallback to inherited `BANGUMI_API_KEY`.
- In scope: Add icon-image cache strategy in a cache directory (not config directory), with configurable cache path, TTL, and size guardrails.
- In scope: Preserve Alfred UX behaviors for title/subtitle/autocomplete and modifier rows for summary and rank/score metadata.
- In scope: Evaluate and support subject image rendering strategy using search payload images first, with optional `/v0/subjects/{subject_id}/image?type=small` fallback.
- In scope: Add deterministic tests, smoke checks, docs, and operational guardrails required by this repo.
- In scope: Design and scaffold Playwright bridge structure for future use, while keeping it disabled in current runtime path.
- Out of scope: Enabling Playwright scraping as production data path in this implementation wave.
- Out of scope: Login-required Bangumi user endpoints and write operations (collections/progress updates).
- Out of scope: Refactoring unrelated workflows or shared crates beyond required compatibility hooks.

## Assumptions (if any)
1. Anonymous access to Bangumi search endpoints remains available for query use cases.
2. Bangumi API `v0` schema can evolve; implementation must be resilient to missing optional fields.
3. Alfred runtime environment provides network access to `api.bgm.tv`.
4. This repo keeps the established architecture: Rust business logic + thin shell adapters.
5. Playwright runtime dependencies remain optional and are not required for API-first completion.

## Success Criteria
- `bangumi-cli` can parse query/type input and emit valid Alfred feedback JSON for Bangumi search results.
- `bangumi-search` workflow script filter and action wiring work in both dev and packaged paths.
- API key behavior is explicit: workflow-configured key is used when present; otherwise inherited `BANGUMI_API_KEY` is used when available.
- Subject icon behavior is explicit and stable: use available search image URL; only use `/v0/subjects/{id}/image?type=small` as controlled fallback path.
- Icon files are cached in cache storage with deterministic keying and TTL, and cache location can be overridden by configuration.
- API-first implementation passes repository checks relevant to the new workflow and crate.
- Playwright bridge design artifacts (contracts + scaffold) are documented, testable at structure level, and explicitly disabled by default.
- `scripts/workflow-lint.sh --id bangumi-search`, `scripts/workflow-test.sh --id bangumi-search`, and `scripts/workflow-pack.sh --id bangumi-search` pass.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 2.1 -> Task 2.2 -> Task 2.3 -> Task 2.4 -> Task 2.5 -> Task 2.6 -> Task 3.1 -> Task 3.3 -> Task 3.4 -> Task 3.5`.
- Parallel track A: `Task 1.3` can run after `Task 1.1` and in parallel with `Task 1.2`.
- Parallel track B: `Task 2.3` starts immediately after `Task 2.2`, then unblocks `Task 2.4`.
- Parallel track C: `Task 3.2` can run after `Task 1.3` and in parallel with `Task 3.1`.
- Parallel track F: `Task 2.6` starts after `Task 2.4` and can run in parallel with parts of `Task 2.5` docs/error polishing.
- Parallel track D: `Task 4.1` can begin after `Task 1.1`, independent from API implementation details.
- Parallel track E: `Task 4.2` and `Task 4.3` can run in parallel after `Task 4.1`, then converge at `Task 4.4`.

## Sprint 1: Contract and scaffold baseline
**Goal**: Lock behavior contract and create minimal crate/workflow scaffolds so downstream implementation has stable surfaces.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/bangumi-search-workflow-plan.md`, `test -d workflows/bangumi-search`, `cargo check -p nils-bangumi-cli`
- Verify: Plan is valid, workflow skeleton exists, and new crate builds in workspace.

### Task 1.1: Define Bangumi workflow contract and query grammar
- **Location**:
  - `crates/bangumi-cli/docs/workflow-contract.md`
- **Description**: Define end-to-end contract for input grammar (`[type] query`), supported types (`all/book/anime/music/game/real`), Alfred row fields, modifier semantics, fallback items, and API selection policy (v0 primary, compatibility fallback policy).
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - Contract specifies success, empty, and error feedback payload behavior.
  - Contract states how subject URL is derived when API response omits canonical `url`.
  - Contract explicitly documents User-Agent and timeout requirements.
- **Validation**:
  - `test -f crates/bangumi-cli/docs/workflow-contract.md`
  - `rg -n "^## (Input Grammar|Type Mapping|Alfred Item Mapping|API Strategy|Error Mapping|Environment Variables)$" crates/bangumi-cli/docs/workflow-contract.md`
  - `rg -n "all|book|anime|music|game|real|api.bgm.tv/v0/search/subjects|User-Agent" crates/bangumi-cli/docs/workflow-contract.md`

### Task 1.2: Create bangumi-cli crate and workspace registration
- **Location**:
  - `Cargo.toml`
  - `crates/bangumi-cli/Cargo.toml`
  - `crates/bangumi-cli/src/main.rs`
  - `crates/bangumi-cli/src/lib.rs`
- **Description**: Scaffold `nils-bangumi-cli` package with binary target `bangumi-cli`, workspace membership, and module placeholders aligned with existing CLI crate conventions.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Workspace includes `crates/bangumi-cli` member.
  - `bangumi-cli --help` renders a stable command surface placeholder.
  - Crate compiles without touching existing workflow behavior.
- **Validation**:
  - `rg -n "crates/bangumi-cli" Cargo.toml`
  - `cargo check -p nils-bangumi-cli`
  - `cargo run -p nils-bangumi-cli -- --help`

### Task 1.3: Scaffold bangumi-search workflow skeleton and manifest
- **Location**:
  - `workflows/bangumi-search/workflow.toml`
  - `workflows/bangumi-search/src/info.plist.template`
  - `workflows/bangumi-search/src/assets/icon.png`
  - `workflows/bangumi-search/scripts/script_filter.sh`
  - `workflows/bangumi-search/scripts/action_open.sh`
  - `workflows/bangumi-search/tests/smoke.sh`
  - `workflows/bangumi-search/README.md`
  - `workflows/bangumi-search/TROUBLESHOOTING.md`
- **Description**: Add workflow directory and required assets/scripts/doc shells so build/test/pack pipelines can target `bangumi-search`.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - `workflow.toml` contains required keys and points `rust_binary = "bangumi-cli"`.
  - Script files are executable and README/troubleshooting docs exist.
- **Validation**:
  - `test -d workflows/bangumi-search`
  - `test -f workflows/bangumi-search/workflow.toml`
  - `test -x workflows/bangumi-search/scripts/script_filter.sh`
  - `test -x workflows/bangumi-search/scripts/action_open.sh`
  - `scripts/workflow-lint.sh --id bangumi-search`

### Task 1.4: Define runtime env variables and bounds
- **Location**:
  - `workflows/bangumi-search/workflow.toml`
  - `workflows/bangumi-search/src/info.plist.template`
  - `crates/bangumi-cli/docs/workflow-contract.md`
  - `crates/bangumi-cli/src/config.rs`
- **Description**: Define/env-parse variables such as `BANGUMI_API_KEY`, `BANGUMI_MAX_RESULTS`, `BANGUMI_TIMEOUT_MS`, `BANGUMI_USER_AGENT`, `BANGUMI_CACHE_DIR`, `BANGUMI_IMAGE_CACHE_TTL_SECONDS`, `BANGUMI_IMAGE_CACHE_MAX_MB`, and optional compatibility switch for legacy endpoint fallback behavior, including precedence rules (workflow config first, inherited env fallback) and cache-dir resolution order.
- **Dependencies**:
  - Task 1.1
  - Task 1.2
  - Task 1.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Required/optional env vars are consistent across manifest/template/docs/code.
  - Integer bounds and defaults are explicit and clamped deterministically.
  - API key precedence policy is documented and testable.
  - Cache directory precedence is documented and testable:
    - `BANGUMI_CACHE_DIR` when set.
    - `alfred_workflow_cache/bangumi-cli` in Alfred runtime when explicit cache dir is not set.
    - `${XDG_CACHE_HOME:-$HOME/.cache}/nils-bangumi-cli` for standalone CLI fallback.
- **Validation**:
  - `rg -n "BANGUMI_API_KEY|BANGUMI_MAX_RESULTS|BANGUMI_TIMEOUT_MS|BANGUMI_USER_AGENT|BANGUMI_CACHE_DIR|BANGUMI_IMAGE_CACHE_TTL_SECONDS|BANGUMI_IMAGE_CACHE_MAX_MB|BANGUMI_API_FALLBACK" workflows/bangumi-search/workflow.toml workflows/bangumi-search/src/info.plist.template crates/bangumi-cli/docs/workflow-contract.md crates/bangumi-cli/src/config.rs`
  - `cargo test -p nils-bangumi-cli config_`
  - `cargo test -p nils-bangumi-cli api_key_precedence_`
  - `cargo test -p nils-bangumi-cli cache_dir_resolution_`

## Sprint 2: API-first implementation in bangumi-cli
**Goal**: Implement robust API client + JSON mapping so direct API path is production-complete.
**Demo/Validation**:
- Command(s): `cargo test -p nils-bangumi-cli`, `cargo run -p nils-bangumi-cli -- query --input "anime naruto" | jq -e '.items | type == "array"'`
- Verify: Direct API path returns well-formed Alfred JSON with expected metadata and graceful fallbacks.

### Task 2.1: Implement raw input parsing and type mapping
- **Location**:
  - `crates/bangumi-cli/src/input.rs`
  - `crates/bangumi-cli/src/lib.rs`
  - `crates/bangumi-cli/src/main.rs`
- **Description**: Parse script-filter input into normalized query + Bangumi subject type mapping, with default `all` behavior and guardrails for empty/invalid type tokens.
- **Dependencies**:
  - Task 1.2
  - Task 1.4
- **Complexity**: 5
- **Acceptance criteria**:
  - Parser supports all six type aliases and default query mode.
  - Invalid tokens fail predictably with actionable user error.
- **Validation**:
  - `cargo test -p nils-bangumi-cli`
  - `cargo test -p nils-bangumi-cli input_`

### Task 2.2: Build Bangumi v0 API client and response parser
- **Location**:
  - `crates/bangumi-cli/src/bangumi_api.rs`
  - `crates/bangumi-cli/Cargo.toml`
- **Description**: Implement POST client for `https://api.bgm.tv/v0/search/subjects`, request payload construction, User-Agent header, optional Bearer authorization header from `BANGUMI_API_KEY`, timeout handling, and resilient parsing of nullable/optional response fields.
- **Dependencies**:
  - Task 2.1
  - Task 1.4
- **Complexity**: 8
- **Acceptance criteria**:
  - Client sends keyword and optional type filter correctly.
  - API key header is attached when key exists and omitted when key is absent.
  - Parser safely handles missing `url`, `name_cn`, `rating`, `images` fields.
  - HTTP and transport failures are mapped to typed internal errors.
- **Validation**:
  - `cargo test -p nils-bangumi-cli`
  - `cargo test -p nils-bangumi-cli bangumi_api_`
  - `cargo test -p nils-bangumi-cli auth_header_`
  - `cargo clippy -p nils-bangumi-cli --all-targets -- -D warnings`

### Task 2.3: Add compatibility fallback policy for legacy search endpoint
- **Location**:
  - `crates/bangumi-cli/src/bangumi_api.rs`
  - `crates/bangumi-cli/src/config.rs`
  - `crates/bangumi-cli/docs/workflow-contract.md`
- **Description**: Implement controlled fallback to legacy endpoint (`/search/subject/{keywords}`) for narrowly-defined failure classes (endpoint incompatibility/schema regression), guarded by explicit config policy and documented tradeoffs.
- **Dependencies**:
  - Task 2.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Fallback trigger conditions are explicit and test-covered.
  - Default behavior remains v0-first; fallback does not hide unrelated failures.
- **Validation**:
  - `cargo test -p nils-bangumi-cli`
  - `cargo test -p nils-bangumi-cli fallback_`
  - `rg -n "v0-first|fallback|legacy endpoint" crates/bangumi-cli/docs/workflow-contract.md`

### Task 2.4: Implement Alfred feedback mapping (including modifiers)
- **Location**:
  - `crates/bangumi-cli/src/feedback.rs`
  - `crates/bangumi-cli/src/lib.rs`
- **Description**: Map parsed subject results into Alfred items with title/subtitle/autocomplete/arg and modifiers: `cmd` for summary preview and `ctrl` for rank/score metadata. For item icon strategy, prefer image URLs already present in search payload; use `/v0/subjects/{subject_id}/image?type=small` only as fallback when payload image is missing.
- **Dependencies**:
  - Task 2.2
  - Task 2.3
- **Complexity**: 7
- **Acceptance criteria**:
  - Subtitle format includes type tag in `all` mode and localized name when available.
  - `cmd` and `ctrl` modifiers are present only when source data exists.
  - Icon strategy is deterministic and avoids unnecessary per-item extra requests in normal path.
  - Image-endpoint fallback path uses explicit `type` query (for example `small`) and handles `400`/`404` gracefully.
  - Empty results return non-actionable guidance item.
- **Validation**:
  - `cargo test -p nils-bangumi-cli`
  - `cargo test -p nils-bangumi-cli feedback_`
  - `cargo test -p nils-bangumi-cli modifier_`
  - `cargo test -p nils-bangumi-cli subtitle_`
  - `cargo test -p nils-bangumi-cli cmd_modifier_present_`
  - `cargo test -p nils-bangumi-cli cmd_modifier_absent_`
  - `cargo test -p nils-bangumi-cli image_fallback_`

### Task 2.5: Finalize CLI command surface and error envelopes
- **Location**:
  - `crates/bangumi-cli/src/main.rs`
- **Description**: Provide stable command entrypoints (`query` for workflow input, optional `search` for explicit typed query), enforce stdout JSON contract, and map user/runtime errors to exit codes and optional service envelope mode.
- **Dependencies**:
  - Task 2.1
  - Task 2.4
- **Complexity**: 5
- **Acceptance criteria**:
  - Success path emits JSON only on stdout.
  - User input errors and runtime errors produce deterministic stderr + exit codes.
  - CLI tests cover core command routing branches.
- **Validation**:
  - `cargo test -p nils-bangumi-cli`
  - `cargo test -p nils-bangumi-cli main_`
  - `cargo run -p nils-bangumi-cli -- query --input "anime naruto" | jq -e '.items | type == "array"'`
  - `bash -c 'set +e; cargo run -p nils-bangumi-cli -- query --input "anime" >/dev/null 2>&1; test $? -ne 0'`

### Task 2.6: Implement image cache manager for icon paths
- **Location**:
  - `crates/bangumi-cli/src/image_cache.rs`
  - `crates/bangumi-cli/src/config.rs`
  - `crates/bangumi-cli/src/feedback.rs`
  - `crates/bangumi-cli/src/lib.rs`
- **Description**: Implement cache-backed icon resolver for subject images using deterministic cache keys (`subject_id` + image type), TTL expiration, optional max-size cleanup, and cache directory precedence (`BANGUMI_CACHE_DIR` -> Alfred cache -> XDG cache fallback).
- **Dependencies**:
  - Task 1.4
  - Task 2.4
- **Complexity**: 7
- **Acceptance criteria**:
  - First fetch stores icon file under resolved cache dir and returns local file path.
  - Cache hit within TTL does not perform network download.
  - Expired cache refreshes cleanly without breaking item rendering.
  - Cache-dir fallback order behaves as documented in both Alfred and standalone CLI contexts.
- **Validation**:
  - `cargo test -p nils-bangumi-cli image_cache_`
  - `cargo test -p nils-bangumi-cli cache_dir_resolution_`
  - `cargo test -p nils-bangumi-cli cache_ttl_`

## Sprint 3: Workflow wiring, packaging, and operator docs
**Goal**: Connect `bangumi-cli` into Alfred workflow runtime and validate package quality gates.
**Demo/Validation**:
- Command(s): `bash workflows/bangumi-search/tests/smoke.sh`, `scripts/workflow-test.sh --id bangumi-search`, `scripts/workflow-pack.sh --id bangumi-search`
- Verify: Workflow executes in dev and package modes with stable feedback/error behavior.

### Task 3.1: Build script_filter adapter with shared coalesce helpers
- **Location**:
  - `workflows/bangumi-search/scripts/script_filter.sh`
- **Description**: Implement script filter adapter using shared helpers (`script_filter_query_policy.sh`, `script_filter_async_coalesce.sh`, `script_filter_search_driver.sh`) and `bangumi-cli` resolution logic for package/release/debug paths.
- **Dependencies**:
  - Task 2.5
  - Task 1.3
- **Complexity**: 6
- **Acceptance criteria**:
  - Empty/short-query behavior is non-actionable and user-guided.
  - Backend errors always map to valid Alfred JSON fallback items.
  - Query coalescing and TTL cache knobs are configurable via env vars.
- **Validation**:
  - `shellcheck workflows/bangumi-search/scripts/script_filter.sh`
  - `shfmt -d workflows/bangumi-search/scripts/script_filter.sh`
  - `bash workflows/bangumi-search/scripts/script_filter.sh "anime naruto" | jq -e '.items | type == "array"'`

### Task 3.2: Implement URL open action script
- **Location**:
  - `workflows/bangumi-search/scripts/action_open.sh`
- **Description**: Add minimal action script that validates arg presence and opens selected URL via `open`.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 2
- **Acceptance criteria**:
  - Missing arg exits with code 2 and usage text.
  - Valid URL arg is passed through unchanged.
- **Validation**:
  - `shellcheck workflows/bangumi-search/scripts/action_open.sh`
  - `bash -c 'tmpdir="$(mktemp -d)"; printf "#!/usr/bin/env bash\nprintf \"%s\\n\" \"\$1\" >\"$tmpdir/url\"\n" >"$tmpdir/open"; chmod +x "$tmpdir/open"; PATH="$tmpdir:$PATH" bash workflows/bangumi-search/scripts/action_open.sh "https://bgm.tv/subject/2782"; test "$(cat "$tmpdir/url")" = "https://bgm.tv/subject/2782"; rm -rf "$tmpdir"'`
  - `bash -c 'set +e; bash workflows/bangumi-search/scripts/action_open.sh >/dev/null 2>&1; test $? -eq 2'`

### Task 3.3: Wire info.plist template and workflow env config
- **Location**:
  - `workflows/bangumi-search/src/info.plist.template`
  - `workflows/bangumi-search/workflow.toml`
- **Description**: Configure Alfred object graph (keyword -> script filter -> open action) and expose user configuration for Bangumi env vars.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
  - Task 1.4
- **Complexity**: 7
- **Acceptance criteria**:
  - Packaged `info.plist` passes validation and has correct script/action wiring.
  - `userconfigurationconfig` includes Bangumi env keys only once with accurate defaults.
- **Validation**:
  - `scripts/workflow-pack.sh --id bangumi-search`
  - `plutil -lint build/workflows/bangumi-search/pkg/info.plist`
  - `plutil -convert json -o - build/workflows/bangumi-search/pkg/info.plist | jq -e '[.userconfigurationconfig[].variable] | sort == ["BANGUMI_API_FALLBACK","BANGUMI_API_KEY","BANGUMI_CACHE_DIR","BANGUMI_IMAGE_CACHE_MAX_MB","BANGUMI_IMAGE_CACHE_TTL_SECONDS","BANGUMI_MAX_RESULTS","BANGUMI_TIMEOUT_MS","BANGUMI_USER_AGENT"]'`
  - `plutil -convert json -o - build/workflows/bangumi-search/pkg/info.plist | jq -e 'reduce .userconfigurationconfig[] as $it ({}; .[$it.variable] = $it.default) | .BANGUMI_MAX_RESULTS == "10" and .BANGUMI_TIMEOUT_MS == "8000" and .BANGUMI_API_FALLBACK == "auto" and .BANGUMI_API_KEY == "" and .BANGUMI_CACHE_DIR == "" and .BANGUMI_IMAGE_CACHE_TTL_SECONDS == "86400" and .BANGUMI_IMAGE_CACHE_MAX_MB == "128"'`

### Task 3.4: Complete README and troubleshooting docs for operators
- **Location**:
  - `workflows/bangumi-search/README.md`
  - `workflows/bangumi-search/TROUBLESHOOTING.md`
  - `docs/WORKFLOW_GUIDE.md`
- **Description**: Document keyword usage, type prefixes, env vars, common failures (network/rate-limit/config), and required validation flow aligned with repo conventions.
- **Dependencies**:
  - Task 3.1
  - Task 3.3
- **Complexity**: 4
- **Acceptance criteria**:
  - README contains usage examples for all six types and direct-search URL fallback.
  - Troubleshooting includes quick checks, common failures/actions, validation, rollback guidance.
  - Global workflow guide includes a Bangumi section.
- **Validation**:
  - `rg -n "all|book|anime|music|game|real|BANGUMI_MAX_RESULTS|BANGUMI_TIMEOUT_MS|BANGUMI_USER_AGENT|BANGUMI_CACHE_DIR|BANGUMI_IMAGE_CACHE_TTL_SECONDS|BANGUMI_IMAGE_CACHE_MAX_MB" workflows/bangumi-search/README.md workflows/bangumi-search/TROUBLESHOOTING.md docs/WORKFLOW_GUIDE.md`
  - `rg -n "Quick operator checks|Common failures and actions|Validation|Rollback guidance" workflows/bangumi-search/TROUBLESHOOTING.md`

### Task 3.5: Add smoke and contract tests for workflow + CLI
- **Location**:
  - `workflows/bangumi-search/tests/smoke.sh`
  - `crates/bangumi-cli/tests/cli_contract.rs`
  - `crates/bangumi-cli/src/main.rs`
  - `crates/bangumi-cli/src/feedback.rs`
  - `crates/bangumi-cli/src/bangumi_api.rs`
- **Description**: Add deterministic smoke/contract tests covering CLI JSON shape, script-filter behavior, and non-crashing fallback paths.
- **Dependencies**:
  - Task 3.1
  - Task 3.4
- **Complexity**: 6
- **Acceptance criteria**:
  - Smoke test validates both normal query and failure fallback outputs.
  - CLI contract tests pin command behavior and exit-code conventions.
- **Validation**:
  - `cargo test -p nils-bangumi-cli`
  - `bash workflows/bangumi-search/tests/smoke.sh`
  - `scripts/workflow-test.sh --id bangumi-search`
  - `scripts/workflow-pack.sh --id bangumi-search`

## Sprint 4: Playwright bridge architecture for future follow-up
**Goal**: Design future scraping path and scaffold bridge structure without changing current production path.
**Demo/Validation**:
- Command(s): `cargo check -p nils-bangumi-cli`, `node --check workflows/bangumi-search/scripts/bangumi_scraper.mjs`, `rg -n "disabled by default|feature flag|handoff" crates/bangumi-cli/docs/playwright-bridge-design.md`
- Verify: Future architecture is actionable, scaffold compiles structurally, and runtime remains API-first.

### Task 4.1: Write Playwright bridge design doc and contracts
- **Location**:
  - `crates/bangumi-cli/docs/playwright-bridge-design.md`
- **Description**: Define future scraper architecture: stage model, Rust-to-Node bridge boundaries, JSON schema, error taxonomy (`anti_bot`, `cookie_wall`, `timeout`, `parse_error`), runtime bootstrap strategy, and migration trigger conditions.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 6
- **Acceptance criteria**:
  - Design doc includes clear goals/non-goals and explicit rollout gates.
  - JSON schema and CLI args are specific enough for direct implementation handoff.
- **Validation**:
  - `test -f crates/bangumi-cli/docs/playwright-bridge-design.md`
  - `rg -n "^## (Goals|Non-goals|Bridge Boundaries|CLI Contract|JSON Schema|Error Taxonomy|Runtime Bootstrap|Rollout Gates|Handoff Checklist)$" crates/bangumi-cli/docs/playwright-bridge-design.md`

### Task 4.2: Scaffold disabled Node scraper entrypoint and parser modules
- **Location**:
  - `workflows/bangumi-search/scripts/bangumi_scraper.mjs`
  - `workflows/bangumi-search/scripts/lib/bangumi_routes.mjs`
  - `workflows/bangumi-search/scripts/lib/extract_search.mjs`
  - `workflows/bangumi-search/scripts/lib/error_classify.mjs`
  - `workflows/bangumi-search/scripts/tests/bangumi_scraper_contract.test.mjs`
- **Description**: Add non-production scaffold for scraper entrypoint and parser modules that currently return structured not-implemented payloads and contract-level tests, without being invoked by script filter.
- **Dependencies**:
  - Task 4.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Entry script supports `--help` and emits structured JSON envelope.
  - Current workflow runtime path does not call scraper script.
  - Contract tests validate schema shape and error envelope consistency.
- **Validation**:
  - `node --check workflows/bangumi-search/scripts/bangumi_scraper.mjs`
  - `node workflows/bangumi-search/scripts/bangumi_scraper.mjs --help >/dev/null`
  - `node --test workflows/bangumi-search/scripts/tests/bangumi_scraper_contract.test.mjs`
  - `bash -c '! rg -n "bangumi_scraper" workflows/bangumi-search/scripts/script_filter.sh'`

### Task 4.3: Scaffold Rust scraper bridge module behind feature gate
- **Location**:
  - `crates/bangumi-cli/src/scraper_bridge.rs`
  - `crates/bangumi-cli/src/config.rs`
  - `crates/bangumi-cli/src/lib.rs`
  - `crates/bangumi-cli/Cargo.toml`
- **Description**: Add typed bridge module and config placeholders behind opt-in Cargo feature (for example `scraper-bridge`) so future implementation can be added incrementally without impacting default API-first build.
- **Dependencies**:
  - Task 4.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Default build path remains unchanged and feature is disabled by default.
  - Feature-gated module compiles and includes typed request/response contracts.
- **Validation**:
  - `cargo check -p nils-bangumi-cli`
  - `cargo check -p nils-bangumi-cli --features scraper-bridge`
  - `rg -n "scraper-bridge" crates/bangumi-cli/Cargo.toml crates/bangumi-cli/src/lib.rs`

### Task 4.4: Define operational rollout/rollback gates for scraper activation
- **Location**:
  - `crates/bangumi-cli/docs/playwright-bridge-design.md`
  - `workflows/bangumi-search/TROUBLESHOOTING.md`
- **Description**: Document explicit enablement checklist, observability signals, failure thresholds, and rollback switches for future scraper activation so follow-up implementation has an operationally safe playbook.
- **Dependencies**:
  - Task 4.1
  - Task 4.2
  - Task 4.3
- **Complexity**: 4
- **Acceptance criteria**:
  - Rollout gates include success metrics, abort conditions, and owner-visible switch points.
  - Troubleshooting doc reflects API-first default and scraper-disabled status.
- **Validation**:
  - `rg -n "disabled by default|enablement checklist|abort conditions|rollback switch" crates/bangumi-cli/docs/playwright-bridge-design.md workflows/bangumi-search/TROUBLESHOOTING.md`

## Testing Strategy
- Unit:
  - `crates/bangumi-cli/src/input.rs` parser coverage for type tokens, spacing, and empty queries.
  - `crates/bangumi-cli/src/config.rs` env parsing/clamp/error coverage.
  - `crates/bangumi-cli/src/bangumi_api.rs` response parsing and fallback trigger tests using fixture JSON.
  - `crates/bangumi-cli/src/image_cache.rs` cache keying, TTL behavior, and directory resolution coverage.
  - `crates/bangumi-cli/src/feedback.rs` subtitle formatting, modifier generation, and no-result/error item tests.
- Integration:
  - `crates/bangumi-cli/tests/cli_contract.rs` for stdout JSON shape and exit code behavior.
  - `crates/bangumi-cli/tests/cli_contract.rs` includes API-key present/absent parity assertions.
  - `workflows/bangumi-search/tests/smoke.sh` for script filter + action integration contract.
- E2E/manual:
  - `scripts/workflow-pack.sh --id bangumi-search --install` then Alfred keyword/manual verification.
  - Manual checks for typed prefixes (`anime`, `book`, `music`, `game`, `real`, `all`) and modifier behavior.
  - Confirm no Playwright runtime requirement for API-first normal path.

## Risks & gotchas
- Bangumi `v0` search is marked experimental; schema or behavior can change without notice.
- `/v0/subjects/{subject_id}/image` requires mandatory `type` query; missing type returns `400`.
- `v0` payload may omit canonical `url`, so URL synthesis (`https://bgm.tv/subject/{id}`) must be stable and test-covered.
- Using image endpoint for every row can introduce N+1 request overhead; keep it as fallback, not primary icon source.
- Cache directory may be unwritable in some environments; fallback handling must keep workflow response non-fatal.
- Large icon churn can grow disk usage; max-size guardrails and cleanup policy are required.
- Rate limits/Cloudflare behavior can produce transient failures; script filter must always return valid fallback JSON.
- Alfred `quicklookurl` parity is not currently modeled in `alfred-core`; equivalent UX may require alternative modifier design.
- Introducing scraper scaffolding may accidentally leak into default runtime path if gating is not strict.

## Rollback plan
- Keep rollback granular and operational:
  - Revert `workflows/bangumi-search` registration and crate wiring while leaving existing workflows untouched.
  - Keep `bangumi-cli` API path behind minimal command surface so temporary disablement can be done by script filter fallback item.
  - If `v0` API instability occurs, switch to compatibility fallback policy and release patch workflow package.
  - If scraper scaffolding causes build/runtime regressions, disable feature gate and remove script references from package stage.
- Validation after rollback:
  - `cargo check --workspace`
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh --id bangumi-search`
