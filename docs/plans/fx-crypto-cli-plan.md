# Plan: FX + Crypto market-data CLI (no API key)

## Overview
This plan adds a new Rust CLI crate that provides reusable market data for future Alfred workflows without requiring any API key.
Fiat exchange rates use Frankfurter with a fixed 24-hour TTL cache, and crypto spot prices use Coinbase as primary with Kraken fallback plus a fixed 5-minute TTL cache.
The deliverable is a stable command/output contract and offline-testable provider/cache pipeline, not a workflow UI in this phase.
Existing workflows remain unchanged until a later integration plan consumes this CLI.

## Scope
- In scope: New crate `market-cli` with `fx` and `crypto` subcommands.
- In scope: Provider integration for Frankfurter (fiat), Coinbase spot (crypto primary), and Kraken ticker (crypto fallback).
- In scope: File-based cache with fixed TTL policy: FX 24h, crypto 5m.
- In scope: Deterministic JSON output schema designed for future workflow consumption.
- In scope: Error mapping, stale-cache fallback behavior, and unit/integration tests.
- In scope: Documentation for command contract and future workflow adapter usage.
- Out of scope: Alfred workflow UI/wiring (`workflows/*`) in this phase.
- Out of scope: API-key-based providers (CoinGecko paid/demo, ExchangeRate APIs requiring auth).
- Out of scope: Historical OHLC candles, charting, portfolio aggregation, alerts, or websocket streaming.

## Assumptions (if any)
1. Runtime environment has outbound network access for live fetches, but test suites must pass without network.
2. Future workflow scripts can call a binary and parse JSON from stdout.
3. First phase supports spot conversion only (`amount * unit_price`) and does not include fee/slippage modeling.
4. Kraken pair normalization rules (for example `BTC -> XBT`) are handled in-code with explicit mapping and tests.

## Success Criteria
- `market-cli fx --base USD --quote TWD --amount 100` returns valid JSON with provider metadata and converted amount.
- `market-cli crypto --base BTC --quote USD --amount 0.5` returns valid JSON with provider metadata and converted amount.
- No API key is required for either command path.
- FX cache TTL is fixed at 86400 seconds (24h) and crypto cache TTL is fixed at 300 seconds (5m).
- Crypto path falls back from Coinbase to Kraken on transport/HTTP/parse/unsupported-pair failure.
- When live fetch fails and stale cache exists, CLI returns stale data with explicit freshness metadata instead of hard-failing.
- Provider clients apply bounded retry/backoff for transient transport errors and 429/5xx responses.
- `cargo test -p nils-market-cli` passes with deterministic, network-independent tests.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 1.3 -> Task 2.1 -> Task 2.4 -> Task 2.5 -> Task 2.6 -> Task 2.7 -> Task 3.1 -> Task 3.3`.
- Parallel track A: `Task 1.4` can run after `Task 1.1` in parallel with `Task 1.2`.
- Parallel track B: `Task 2.2` and `Task 2.3` can run in parallel after `Task 1.3`.
- Parallel track C: `Task 2.6` can run after `Task 2.3` in parallel with `Task 2.4`.
- Parallel track D: `Task 3.2` can run after `Task 2.7` in parallel with `Task 3.1`.
- Parallel track E: `Task 3.4` can run after `Task 3.1` in parallel with `Task 3.2`.

## Sprint 1: Contract and crate scaffold
**Goal**: Freeze behavior and data contract so provider and cache implementation can proceed without interface churn.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/fx-crypto-cli-plan.md`, `cargo check -p nils-market-cli`
- Verify: Plan is valid, crate is scaffolded, and workspace compiles with placeholder command surface.

### Task 1.1: Define CLI and JSON contract for workflow-facing consumption
- **Location**:
  - `crates/market-cli/docs/workflow-contract.md`
  - `docs/plans/fx-crypto-cli-plan.md`
- **Description**: Document subcommands, flags, normalized output schema, freshness metadata fields, provider naming, and error semantics for user/runtime failures.
- **Dependencies**:
  - none
- **Complexity**: 4
- **Acceptance criteria**:
  - Contract defines `fx` and `crypto` command forms with required/optional flags.
  - JSON schema includes at minimum `kind`, `base`, `quote`, `amount`, `unit_price`, `converted`, `provider`, `fetched_at`, and `cache` metadata.
  - Freshness states are explicit (`live`, `cache_fresh`, `cache_stale_fallback`).
- **Validation**:
  - `test -f crates/market-cli/docs/workflow-contract.md`
  - `rg -n "fx|crypto|cache_stale_fallback|unit_price|converted|provider|fetched_at" crates/market-cli/docs/workflow-contract.md`

### Task 1.2: Add `market-cli` crate and workspace membership
- **Location**:
  - `Cargo.toml`
  - `crates/market-cli/Cargo.toml`
  - `crates/market-cli/src/lib.rs`
  - `crates/market-cli/src/main.rs`
- **Description**: Create a dedicated crate for market-data capabilities and register it in workspace members.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Workspace includes `crates/market-cli`.
  - `cargo run -p nils-market-cli -- --help` succeeds with declared subcommands.
- **Validation**:
  - `cargo check -p nils-market-cli`
  - `cargo run -p nils-market-cli -- --help`

### Task 1.3: Define domain model and command surface
- **Location**:
  - `crates/market-cli/src/model.rs`
  - `crates/market-cli/src/main.rs`
  - `crates/market-cli/src/error.rs`
- **Description**: Implement typed request/response model and command parsing for `fx`/`crypto`, including strict symbol normalization and non-zero amount validation.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Invalid symbol format and zero/negative amounts map to user errors.
  - Output model serializes deterministically and matches contract field names.
  - Runtime errors keep user errors separate via stable exit codes.
- **Validation**:
  - `cargo test -p nils-market-cli -- --list | rg "main_|model_|error_"`
  - `cargo test -p nils-market-cli`

### Task 1.4: Implement cache directory and TTL policy configuration
- **Location**:
  - `crates/market-cli/src/config.rs`
  - `crates/market-cli/src/cache.rs`
- **Description**: Resolve cache root via `MARKET_CACHE_DIR` -> `alfred_workflow_cache` -> `alfred_workflow_data` -> temp fallback and define fixed TTL constants (`FX=86400`, `CRYPTO=300`).
- **Dependencies**:
  - Task 1.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Cache-root precedence is deterministic and test-covered.
  - TTL values are constants and not silently overridden at runtime.
  - Cache key strategy is explicit per market kind and pair.
- **Validation**:
  - `cargo test -p nils-market-cli config`
  - `cargo test -p nils-market-cli cache`
  - `rg -n "FX_TTL_SECS|CRYPTO_TTL_SECS|MARKET_CACHE_DIR|alfred_workflow_cache|alfred_workflow_data" crates/market-cli/src/config.rs crates/market-cli/src/cache.rs`

## Sprint 2: Provider clients, fallback chain, and cache orchestration
**Goal**: Build production-grade fetch pipeline with deterministic parsing, fallback behavior, and cache freshness controls.
**Demo/Validation**:
- Command(s): `cargo test -p nils-market-cli`, `cargo clippy -p nils-market-cli --all-targets -- -D warnings`
- Verify: Provider parsing, fallback, and cache behavior all pass offline tests.

### Task 2.1: Implement cache read/write and freshness evaluation
- **Location**:
  - `crates/market-cli/src/cache.rs`
  - `crates/market-cli/src/model.rs`
- **Description**: Implement atomic cache persistence with timestamps, TTL-age checks, and freshness-state derivation for both fx and crypto records.
- **Dependencies**:
  - Task 1.4
  - Task 1.3
- **Complexity**: 7
- **Acceptance criteria**:
  - Cache read/write uses atomic file replacement and parent-dir creation.
  - Freshness evaluation distinguishes fresh vs stale based on market-specific TTL.
  - Corrupted cache payload does not panic and is treated as cache miss.
- **Validation**:
  - `cargo test -p nils-market-cli cache_freshness_`
  - `cargo test -p nils-market-cli cache_handles_corrupt_payload_as_miss`

### Task 2.2: Implement Frankfurter FX provider client and parser
- **Location**:
  - `crates/market-cli/src/providers/frankfurter.rs`
  - `crates/market-cli/src/providers/mod.rs`
- **Description**: Fetch latest fiat rates from Frankfurter endpoint and parse pair-specific unit rate with resilient HTTP/error decoding.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 7
- **Acceptance criteria**:
  - Request builder uses base/symbol query params and no API key.
  - Parser handles expected success payload and missing-rate response safely.
  - Transport/HTTP/parse failures map to typed provider errors.
- **Validation**:
  - `cargo test -p nils-market-cli frankfurter_`
  - `cargo test -p nils-market-cli provider_error_mapping_`

### Task 2.3: Implement Coinbase primary + Kraken fallback crypto providers
- **Location**:
  - `crates/market-cli/src/providers/coinbase.rs`
  - `crates/market-cli/src/providers/kraken.rs`
  - `crates/market-cli/src/providers/mod.rs`
- **Description**: Add unauthenticated crypto spot clients for Coinbase and Kraken, including pair normalization/mapping and parser fixtures for both payload shapes.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 8
- **Acceptance criteria**:
  - Coinbase parser extracts numeric spot price from API response body.
  - Kraken parser extracts ticker close price with symbol mapping support.
  - Pair mapping tests cover at least `BTC/USD`, `ETH/USD`, and one unsupported-pair failure case.
- **Validation**:
  - `cargo test -p nils-market-cli coinbase_`
  - `cargo test -p nils-market-cli kraken_`
  - `cargo test -p nils-market-cli crypto_pair_mapping_`

### Task 2.4: Implement market service orchestration and fresh-cache short-circuit
- **Location**:
  - `crates/market-cli/src/service.rs`
  - `crates/market-cli/src/providers/mod.rs`
  - `crates/market-cli/src/cache.rs`
- **Description**: Orchestrate fetch order by kind: FX direct from Frankfurter and crypto Coinbase-first then Kraken fallback, with cache-hit short-circuit and successful live-write refresh.
- **Dependencies**:
  - Task 2.1
  - Task 2.2
  - Task 2.3
- **Complexity**: 9
- **Acceptance criteria**:
  - Crypto fetch tries Coinbase first and only calls Kraken when Coinbase path fails.
  - Live success writes/refreshes cache; fresh cache short-circuits network.
  - Cache write path persists provider and fetch timestamp metadata for future stale fallback decisions.
- **Validation**:
  - `cargo test -p nils-market-cli service_crypto_falls_back_to_kraken`
  - `cargo test -p nils-market-cli service_short_circuits_on_fresh_cache`
  - `cargo test -p nils-market-cli service_writes_cache_after_live_success`

### Task 2.5: Implement stale-cache recovery and provider trace diagnostics
- **Location**:
  - `crates/market-cli/src/service.rs`
  - `crates/market-cli/src/error.rs`
  - `crates/market-cli/src/model.rs`
- **Description**: Add stale-cache fallback behavior for live-provider failure paths and include provider-attempt trace in runtime errors when no usable result exists.
- **Dependencies**:
  - Task 2.4
- **Complexity**: 8
- **Acceptance criteria**:
  - When live fetch fails and stale cache exists, command succeeds with `cache_stale_fallback` freshness state.
  - When all providers fail and no cache exists, command fails with provider trace context.
  - Stale fallback preserves last-known unit price and provider identity in output.
- **Validation**:
  - `cargo test -p nils-market-cli service_uses_stale_cache_on_provider_failure`
  - `cargo test -p nils-market-cli service_fails_without_cache_when_all_providers_fail`
  - `cargo test -p nils-market-cli service_stale_payload_preserves_provider_metadata`

### Task 2.6: Add transient failure retry/backoff policy for unauthenticated providers
- **Location**:
  - `crates/market-cli/src/providers/mod.rs`
  - `crates/market-cli/src/providers/frankfurter.rs`
  - `crates/market-cli/src/providers/coinbase.rs`
  - `crates/market-cli/src/providers/kraken.rs`
- **Description**: Implement bounded retry/backoff policy for transport and `429`/`5xx` responses to reduce rate-limit churn and improve resiliency without unbounded request loops.
- **Dependencies**:
  - Task 2.3
  - Task 2.4
- **Complexity**: 7
- **Acceptance criteria**:
  - Retry attempts are bounded and deterministic.
  - Backoff strategy is documented in code comments and contract docs.
  - Non-retryable errors (for example malformed symbols and parse failures) fail fast without retry loops.
- **Validation**:
  - `cargo test -p nils-market-cli provider_retries_transient_failures_with_backoff`
  - `cargo test -p nils-market-cli provider_does_not_retry_non_retryable_failures`

### Task 2.7: Add numeric precision and conversion behavior tests
- **Location**:
  - `crates/market-cli/src/model.rs`
  - `crates/market-cli/src/service.rs`
- **Description**: Standardize numeric parsing and conversion output format to avoid floating drift in user-visible values.
- **Dependencies**:
  - Task 2.5
  - Task 2.6
- **Complexity**: 6
- **Acceptance criteria**:
  - Conversion math is deterministic for fixture inputs.
  - Serialization format is stable across runs and locale settings.
  - Amount and unit price validation rejects malformed numeric input.
- **Validation**:
  - `cargo test -p nils-market-cli conversion_`
  - `cargo test -p nils-market-cli numeric_`

## Sprint 3: CLI UX, documentation, and future-workflow readiness
**Goal**: Finalize command UX and provide reliable integration guidance for upcoming workflow implementation.
**Demo/Validation**:
- Command(s): `cargo test -p nils-market-cli`, `cargo run -p nils-market-cli -- fx --base USD --quote TWD --amount 100`, `cargo run -p nils-market-cli -- crypto --base BTC --quote USD --amount 0.5`
- Verify: Commands produce stable JSON contract and documented integration path for workflow scripts.

### Task 3.1: Finalize main command flow and output contract enforcement
- **Location**:
  - `crates/market-cli/src/main.rs`
  - `crates/market-cli/src/error.rs`
  - `crates/market-cli/src/service.rs`
- **Description**: Wire command handlers end-to-end, enforce JSON-only stdout success path, and map user/runtime error categories to stable exit codes.
- **Dependencies**:
  - Task 2.7
- **Complexity**: 6
- **Acceptance criteria**:
  - Successful commands print one JSON object per invocation to stdout.
  - User input issues return exit code `2`; runtime/provider issues return exit code `1`.
  - Error messages are concise and actionable for future script adapters.
- **Validation**:
  - `cargo test -p nils-market-cli main_`
  - `cargo test -p nils-market-cli main_outputs_fx_json_contract`
  - `cargo test -p nils-market-cli main_outputs_crypto_json_contract`
  - `bash -c 'set -euo pipefail; cargo run -p nils-market-cli -- fx --base USD --quote TWD --amount 100 >/dev/null'`
  - `bash -c 'set -euo pipefail; cargo run -p nils-market-cli -- crypto --base BTC --quote USD --amount 0.5 >/dev/null'`

### Task 3.2: Document workflow adapter integration guide (without implementing workflow)
- **Location**:
  - `crates/market-cli/docs/workflow-contract.md`
  - `README.md`
- **Description**: Add an operator-focused section showing how future workflow `script_filter.sh` can call `market-cli`, parse JSON, and render fallback/error rows.
- **Dependencies**:
  - Task 2.7
- **Complexity**: 3
- **Acceptance criteria**:
  - Docs include minimal shell adapter example for both `fx` and `crypto`.
  - Docs specify cache behavior expectations (`24h`, `5m`, stale fallback).
  - Docs clarify that no API key is required for current provider set.
- **Validation**:
  - `rg -n "market-cli|Frankfurter|Coinbase|Kraken|24h|5m|no API key" README.md crates/market-cli/docs/workflow-contract.md`

### Task 3.3: Add deterministic smoke tests for command contract
- **Location**:
  - `crates/market-cli/src/main.rs`
  - `crates/market-cli/tests/cli_contract.rs`
- **Description**: Build contract tests around injected service fakes to validate output fields and error exit semantics without network dependency.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Contract tests verify required JSON fields for both command kinds.
  - Contract tests verify freshness metadata states and provider name emission.
  - Contract tests verify invalid input and runtime failure exit behavior.
- **Validation**:
  - `cargo test -p nils-market-cli cli_contract`
  - `cargo test -p nils-market-cli`

### Task 3.4: Add optional live-smoke script for maintainers
- **Location**:
  - `scripts/market-cli-live-smoke.sh`
  - `DEVELOPMENT.md`
- **Description**: Add an opt-in live check script (not required for CI) that exercises Frankfurter and Coinbase/Kraken endpoints and reports provider/freshness summary.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Script exits non-zero only for contract breakage; skips cleanly when network unavailable.
  - Development guide clearly marks this as optional/manual validation.
- **Validation**:
  - `bash scripts/market-cli-live-smoke.sh`
  - `rg -n "market-cli-live-smoke|optional" DEVELOPMENT.md`

## Testing Strategy
- Unit: Provider parsing fixtures, pair normalization, config parsing, TTL freshness logic, conversion math, and error mapping.
- Integration: Service-level tests with mocked provider/cache behaviors covering fresh-cache hit, live success write-through, Coinbase->Kraken fallback, and stale-cache recovery.
- E2E/manual: Optional live-smoke script for real endpoint sanity checks, plus direct `cargo run -p nils-market-cli` command invocations.

## Risks & gotchas
- Upstream unauthenticated API response schema can change without notice; parser tests must isolate shape assumptions and fail clearly.
- Unauthenticated endpoints can throttle unpredictably; retry/backoff policy plus cache-first reads must be enforced to avoid request storms.
- Kraken symbol/pair conventions can cause subtle unsupported-pair bugs; maintain explicit mapping table with focused tests.
- Stale-cache fallback can hide prolonged provider outages; output metadata must expose freshness and provider path for visibility.
- Numeric precision can drift if floating-only math is used; enforce deterministic formatting and fixture-based assertions.

## Rollback plan
1. Revert `market-cli` workspace membership and remove `crates/market-cli` if rollout creates unacceptable maintenance or reliability costs.
2. Keep existing workflows untouched (this phase has no workflow wiring), so rollback impact is isolated to new crate/docs/scripts.
3. Remove optional live-smoke script/docs references if operational noise outweighs value.
4. Purge generated cache files under `MARKET_CACHE_DIR` (or fallback cache root) to eliminate stale state after rollback.
