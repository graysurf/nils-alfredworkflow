# Plan: Weather forecast CLI (free no-token APIs)

## Overview
This plan adds a new Rust CLI crate that provides daily and weekly weather forecasts without any API token.
The primary provider is Open-Meteo, with MET Norway as fallback to improve resilience when upstream errors occur.
The deliverable is a stable command/output contract and offline-testable provider pipeline for future Alfred workflow integration.
Existing workflows remain unchanged in this phase; only CLI and supporting documentation are planned.

## Scope
- In scope: New crate `weather-cli` with `today` and `week` subcommands.
- In scope: Free no-token provider integration for Open-Meteo (primary) and MET Norway (fallback).
- In scope: Location resolution by city name (geocoding) and direct `--lat/--lon` bypass mode.
- In scope: Deterministic JSON output contract plus readable text/table mode for local usage.
- In scope: Cache, timeout, retry, stale fallback policy, and deterministic tests.
- In scope: Documentation for command contract and provider behavior.
- Out of scope: Alfred workflow UI/wiring under `workflows/*` in this phase.
- Out of scope: Severe-weather alerts, radar data, historical climate analytics, and push notifications.
- Out of scope: API-key-based providers and paid weather datasets.

## Assumptions (if any)
1. Runtime environment has outbound network access for live forecast fetches, but tests must pass without network.
2. Forecast scope is current day and next 7 days only; no hourly deep-dive output in v1 contract.
3. City search can resolve from Open-Meteo geocoding API for common localities used by this project.
4. MET Norway requests include a valid `User-Agent` string per provider usage expectations.
5. Future Alfred workflows can call binary commands and parse JSON from stdout.

## Success Criteria
- `weather-cli today --city Taipei --json` returns one-day forecast JSON with source metadata.
- `weather-cli week --city Taipei --json` returns exactly 7 forecast items for upcoming days.
- `weather-cli today --lat 25.033 --lon 121.565 --json` bypasses geocoding and succeeds.
- No API token is required for any successful command path.
- Primary/fallback policy is deterministic: Open-Meteo first, MET Norway second.
- On primary failure with fallback success, output marks fallback source and remains valid.
- Cache policy avoids repeated calls within TTL and can serve stale fallback with explicit freshness state.
- `cargo test -p nils-weather-cli` passes with network-independent fixtures/mocks.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 1.3 -> Task 1.4 -> Task 2.1 -> Task 2.3 -> Task 2.4 -> Task 3.1 -> Task 3.2`.
- Parallel track A: `Task 2.2` can run after `Task 1.4` in parallel with `Task 2.1`.
- Parallel track B: `Task 2.5` can run after `Task 1.3` in parallel with `Task 2.1`.
- Parallel track C: `Task 3.3` and `Task 3.4` can run after `Task 3.1` in parallel with `Task 3.2`.

## Sprint 1: Contract, crate scaffold, and location model
**Goal**: Lock command/output contract and crate boundaries so provider integration can proceed without interface churn.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/weather-forecast-cli-plan.md`, `cargo check -p nils-weather-cli`
- Verify: Plan is valid, crate scaffold compiles, and command surface is documented.

### Task 1.1: Define command contract and provider policy
- **Location**:
  - `crates/weather-cli/docs/workflow-contract.md`
  - `docs/plans/weather-forecast-cli-plan.md`
- **Description**: Document command grammar (`today`, `week`), required/optional flags, output schema fields, provider selection order, and cache freshness states.
- **Dependencies**:
  - none
- **Complexity**: 4
- **Acceptance criteria**:
  - Contract explicitly defines `--city` and `--lat/--lon` input modes.
  - Output schema includes `period`, `location`, `timezone`, `forecast`, `source`, and `freshness`.
  - Contract states free/no-token requirement and provider order.
- **Validation**:
  - `test -f crates/weather-cli/docs/workflow-contract.md`
  - `rg -n "today|week|--city|--lat|--lon|source|freshness|Open-Meteo|MET Norway|no-token" crates/weather-cli/docs/workflow-contract.md`

### Task 1.2: Add `weather-cli` crate and workspace membership
- **Location**:
  - `Cargo.toml`
  - `crates/weather-cli/Cargo.toml`
  - `crates/weather-cli/src/lib.rs`
  - `crates/weather-cli/src/main.rs`
- **Description**: Create dedicated crate for weather data retrieval, register it in workspace members, and expose top-level subcommands.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Workspace includes `crates/weather-cli`.
  - `cargo run -p nils-weather-cli -- --help` lists `today` and `week`.
- **Validation**:
  - `cargo check -p nils-weather-cli`
  - `cargo run -p nils-weather-cli -- --help`

### Task 1.3: Define weather domain model and error taxonomy
- **Location**:
  - `crates/weather-cli/src/model.rs`
  - `crates/weather-cli/src/error.rs`
  - `crates/weather-cli/src/main.rs`
- **Description**: Implement typed request/response models, serialization rules, and stable user/runtime/provider error classes with deterministic exit behavior.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Model can represent one-day and seven-day forecast outputs with identical field names.
  - Invalid input (empty city, partial coordinates, unsupported output mode) maps to user errors.
  - Runtime/provider failures map to typed internal errors without panics.
- **Validation**:
  - `cargo test -p nils-weather-cli model_`
  - `cargo test -p nils-weather-cli error_`

### Task 1.4: Implement location resolution and timezone handling
- **Location**:
  - `crates/weather-cli/src/geocoding.rs`
  - `crates/weather-cli/src/config.rs`
  - `crates/weather-cli/src/service.rs`
- **Description**: Build city-to-coordinate resolution via Open-Meteo geocoding, coordinate bypass mode, and timezone normalization used by output contract.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 7
- **Acceptance criteria**:
  - City lookup resolves canonical name, latitude, longitude, and timezone.
  - `--lat/--lon` bypasses geocoding and keeps deterministic location label behavior.
  - Ambiguous/no-result city cases return actionable user-facing errors.
- **Validation**:
  - `cargo test -p nils-weather-cli geocoding_`
  - `cargo test -p nils-weather-cli location_resolution_`

## Sprint 2: Provider integration, fallback orchestration, and resiliency
**Goal**: Build deterministic fetch pipeline with primary/fallback provider chain and operational safeguards.
**Demo/Validation**:
- Command(s): `cargo test -p nils-weather-cli`, `cargo clippy -p nils-weather-cli --all-targets -- -D warnings`
- Verify: Provider parsing, fallback behavior, and cache/retry policy all pass deterministic tests.

### Task 2.1: Implement Open-Meteo forecast provider (primary)
- **Location**:
  - `crates/weather-cli/src/providers/open_meteo.rs`
  - `crates/weather-cli/src/providers/mod.rs`
  - `crates/weather-cli/src/model.rs`
- **Description**: Add Open-Meteo client for one-day and seven-day forecasts, parse required fields, and normalize provider payload into internal forecast models.
- **Dependencies**:
  - Task 1.4
- **Complexity**: 7
- **Acceptance criteria**:
  - Provider supports both `forecast_days=1` and `forecast_days=7`.
  - Parser extracts forecast date, max/min temperature, precipitation probability, and weather code.
  - Parse/transport/HTTP failures map to provider-level typed errors.
- **Validation**:
  - `cargo test -p nils-weather-cli open_meteo_`
  - `cargo test -p nils-weather-cli provider_error_mapping_`

### Task 2.2: Implement MET Norway provider (fallback)
- **Location**:
  - `crates/weather-cli/src/providers/met_no.rs`
  - `crates/weather-cli/src/providers/mod.rs`
  - `crates/weather-cli/src/model.rs`
- **Description**: Add MET Norway fallback client with required `User-Agent`, transform timeseries payload into day-level summaries, and normalize to the common model.
- **Dependencies**:
  - Task 1.4
- **Complexity**: 8
- **Acceptance criteria**:
  - Requests include explicit `User-Agent` header.
  - Day aggregation derives values needed by contract for today/week outputs.
  - Missing/partial intervals are handled without panics and with clear errors.
- **Validation**:
  - `cargo test -p nils-weather-cli met_no_`
  - `cargo test -p nils-weather-cli met_no_daily_aggregation_`

### Task 2.3: Implement provider orchestration and source metadata
- **Location**:
  - `crates/weather-cli/src/service.rs`
  - `crates/weather-cli/src/providers/mod.rs`
  - `crates/weather-cli/src/error.rs`
- **Description**: Orchestrate Open-Meteo primary then MET fallback for both command modes, preserve source/fallback metadata, and surface deterministic failures when all providers fail.
- **Dependencies**:
  - Task 2.1
  - Task 2.2
- **Complexity**: 9
- **Acceptance criteria**:
  - Orchestrator attempts fallback only when primary path fails.
  - Successful fallback response includes source marker and attempt trace metadata.
  - Full provider failure returns structured runtime error with provider trace.
- **Validation**:
  - `cargo test -p nils-weather-cli service_uses_fallback_when_primary_fails`
  - `cargo test -p nils-weather-cli service_reports_provider_trace_on_total_failure`

### Task 2.4: Add cache, timeout, retry, and stale fallback behavior
- **Location**:
  - `crates/weather-cli/src/cache.rs`
  - `crates/weather-cli/src/config.rs`
  - `crates/weather-cli/src/service.rs`
  - `crates/weather-cli/src/providers/mod.rs`
- **Description**: Implement file-based cache (30-minute TTL), bounded timeout/retry policy, and stale-cache fallback semantics with explicit freshness tags.
- **Dependencies**:
  - Task 2.3
- **Complexity**: 8
- **Acceptance criteria**:
  - Fresh cache short-circuits network calls.
  - Live fetch failure with stale cache returns `cache_stale_fallback` state.
  - Timeout/retry behavior is bounded and deterministic.
- **Validation**:
  - `cargo test -p nils-weather-cli cache_`
  - `cargo test -p nils-weather-cli service_short_circuits_on_fresh_cache`
  - `cargo test -p nils-weather-cli service_returns_stale_cache_on_provider_failure`
  - `cargo test -p nils-weather-cli timeout_retry_bounds_`

### Task 2.5: Implement weather code mapping and localized summaries
- **Location**:
  - `crates/weather-cli/src/weather_code.rs`
  - `crates/weather-cli/src/model.rs`
  - `crates/weather-cli/src/main.rs`
- **Description**: Map provider weather codes to consistent localized summary strings and ensure both output modes use the same normalized semantic labels.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Known weather codes map to stable text summaries.
  - Unknown codes degrade gracefully with fallback label.
  - JSON and text/table outputs show consistent summary semantics.
- **Validation**:
  - `cargo test -p nils-weather-cli weather_code_`
  - `cargo test -p nils-weather-cli summary_mapping_`

## Sprint 3: CLI UX hardening, docs, and integration readiness
**Goal**: Finalize user-facing command behavior and provide integration-ready docs for workflow adoption.
**Demo/Validation**:
- Command(s): `cargo test -p nils-weather-cli`, `cargo run -p nils-weather-cli -- today --city Taipei --json`, `cargo run -p nils-weather-cli -- week --city Taipei --json`
- Verify: Commands output stable contract, docs are complete, and smoke checks are available.

### Task 3.1: Finalize command handlers and output modes
- **Location**:
  - `crates/weather-cli/src/main.rs`
  - `crates/weather-cli/src/service.rs`
  - `crates/weather-cli/src/error.rs`
- **Description**: Wire end-to-end command handling for `today`/`week`, support `--json` and text/table output, and enforce stable exit-code policy for user vs runtime failures.
- **Dependencies**:
  - Task 2.4
  - Task 2.5
- **Complexity**: 6
- **Acceptance criteria**:
  - Success path prints exactly one structured payload per invocation.
  - User input errors use stable non-zero user exit code.
  - Runtime/provider errors use stable runtime exit code with concise message.
- **Validation**:
  - `cargo test -p nils-weather-cli main_`
  - `bash -c 'set -euo pipefail; cargo run -p nils-weather-cli -- today --city Taipei --json | jq -se "length == 1 and (.[0] | type == \"object\")"'`
  - `bash -c 'set -euo pipefail; cargo run -p nils-weather-cli -- week --city Taipei --json | jq -se "length == 1 and (.[0] | type == \"object\")"'`
  - `cargo test -p nils-weather-cli exit_code_mapping_`

### Task 3.2: Add deterministic CLI contract tests
- **Location**:
  - `crates/weather-cli/tests/cli_contract.rs`
  - `crates/weather-cli/src/main.rs`
  - `crates/weather-cli/src/service.rs`
- **Description**: Add contract tests using mocked provider/cache layers to verify output fields, source metadata, and exit-code behavior without network dependency.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Tests assert required fields for both `today` and `week`.
  - Tests assert fallback source metadata and freshness states.
  - Tests assert invalid input and full-provider-failure exit behavior.
- **Validation**:
  - `cargo test -p nils-weather-cli cli_contract`
  - `cargo test -p nils-weather-cli`

### Task 3.3: Add optional live smoke script for maintainers
- **Location**:
  - `scripts/weather-cli-live-smoke.sh`
  - `DEVELOPMENT.md`
- **Description**: Add opt-in live endpoint smoke script to verify primary/fallback behavior and contract shape, clearly documented as optional manual validation.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Script verifies both `today` and `week` command paths with live providers.
  - Script exits non-zero only on contract breakage and skips cleanly on network absence.
  - Development guide documents usage and optional nature.
- **Validation**:
  - `bash scripts/weather-cli-live-smoke.sh`
  - `rg -n "weather-cli-live-smoke|optional" DEVELOPMENT.md`

### Task 3.4: Document workflow adapter integration guide
- **Location**:
  - `crates/weather-cli/docs/workflow-contract.md`
  - `README.md`
- **Description**: Document how workflow script filters can call `weather-cli`, parse JSON, and render fallback/error rows without embedding provider logic in workflow shell scripts.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 3
- **Acceptance criteria**:
  - Docs include minimal adapter examples for `today` and `week`.
  - Docs explain freshness/source semantics for UI rendering decisions.
  - Docs reiterate no-token provider policy and fallback behavior.
- **Validation**:
  - `rg -n "weather-cli|today|week|freshness|source|Open-Meteo|MET Norway|no token" README.md crates/weather-cli/docs/workflow-contract.md`

## Testing Strategy
- Unit: Input validation, weather-code mapping, geocoding parsing, provider response parsing, and cache freshness logic.
- Integration: Service orchestration tests for primary success, fallback success, and total provider failure with/without stale cache.
- E2E/manual: Optional live smoke script plus direct `cargo run -p nils-weather-cli` command checks.

## Risks & gotchas
- Free unauthenticated weather APIs can change payload shape without notice; fixture-based parser tests must isolate schema assumptions.
- MET Norway timeseries aggregation to day-level values may differ from Open-Meteo semantics; normalization rules must be documented and deterministic.
- Geocoding ambiguity (same city name across regions) can produce surprising location choices; CLI contract should define tie-break policy and error messaging.
- Aggressive retries can trigger rate limits; bounded timeout/retry and short-lived cache must prevent request storms.
- Fallback success can mask primary outages; source and freshness metadata must remain visible in output.

## Rollback plan
1. Revert workspace membership for `crates/weather-cli` and remove crate files if rollout causes reliability or maintenance issues.
2. Keep existing workflow directories unchanged in this phase, so rollback remains isolated to new CLI/docs/scripts artifacts.
3. Remove optional live-smoke script and docs references if operational overhead outweighs value.
4. Purge weather cache files under configured cache directory to eliminate stale state after rollback.
