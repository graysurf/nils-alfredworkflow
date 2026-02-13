# Plan: Add Spotify search workflow MVP (search-only)

## Overview
This plan adds a new Alfred workflow, `spotify-search`, following the existing monorepo pattern: Rust domain logic + thin shell adapters + deterministic packaging.
The MVP scope is search-only: users type a query, Alfred shows Spotify track results, and Enter opens the selected Spotify URL in browser.
Authentication uses Spotify Client Credentials flow (`client_id` + `client_secret`) without playback control or user-login scopes.
The implementation prioritizes deterministic smoke coverage so the workflow can be validated without live API access in CI/local.

## Scope
- In scope: New workflow `spotify-search` with script filter and open action.
- In scope: New Rust crate `spotify-cli` for config parsing, auth token acquisition, Spotify search API call, and Alfred JSON output.
- In scope: Environment-driven setup in Alfred (`SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET`, result limits, optional market).
- In scope: Deterministic smoke test that validates file layout, script behavior, fallback mapping, and packaged plist wiring.
- Out of scope: Playback control endpoints (play/pause/next/device transfer).
- Out of scope: OAuth Authorization Code + PKCE and user-scoped Spotify APIs.
- Out of scope: Persistent token cache daemon or background indexing.
- Out of scope: Refactoring existing workflows (`open-project`, `google-search`, `youtube-search`) beyond compatibility-safe touches.

## Assumptions (if any)
1. Spotify Web API remains reachable from the target runtime and allows Client Credentials for public search.
2. Track-level search is sufficient for MVP; artist/album/playlist multi-type search can be deferred.
3. Alfred users can configure secrets in workflow variables and accept that these values are local runtime configuration.
4. Initial target remains Alfred 5 on macOS 13+, matching repository defaults.

## Success Criteria
- Typing `sp query-text` returns Spotify track results with stable `title`, `subtitle`, and `arg` URL fields.
- Selecting a result opens a canonical Spotify URL via `action_open.sh`.
- Missing credentials, rate limits, invalid config, and transient API failures return non-crashing actionable Alfred items.
- `workflows/spotify-search/tests/smoke.sh` passes without live Spotify credentials.
- `scripts/workflow-lint.sh`, `scripts/workflow-test.sh --id spotify-search`, and `scripts/workflow-pack.sh --id spotify-search` pass.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 1.3 -> Task 2.1 -> Task 2.2 -> Task 2.3 -> Task 2.4 -> Task 2.5 -> Task 3.1 -> Task 3.3 -> Task 3.4 -> Task 4.2`.
- Parallel track A: `Task 1.4` can run after `Task 1.1` and in parallel with `Task 1.3`.
- Parallel track B: `Task 2.6` can run after `Task 2.5` and in parallel with `Task 3.2`.
- Parallel track C: `Task 3.5` can run after `Task 3.3` and in parallel with `Task 4.1`.
- Parallel track D: `Task 4.3` can run after `Task 4.2` and in parallel with release-note doc updates.

## Sprint 1: Contract and scaffold
**Goal**: Lock the MVP contract and scaffold workflow/crate surfaces with naming and env conventions aligned to existing workflows.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/spotify-search-workflow-plan.md`, `test -d workflows/spotify-search`, `cargo check -p nils-spotify-cli`
- Verify: Skeleton and contract exist, and workspace can resolve the new crate.

### Task 1.1: Define Spotify workflow behavior contract
- **Location**:
  - `crates/spotify-cli/docs/workflow-contract.md`
- **Description**: Write query handling, Alfred JSON shape, subtitle truncation rules, and error mapping for credentials/rate-limit/unavailable/invalid-config/empty-result states.
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - Contract explicitly defines success item schema (`title`, `subtitle`, `arg`).
  - Contract defines non-success items as `valid: false` and no `arg`.
  - Contract includes keyword behavior for empty query guidance.
- **Validation**:
  - `test -f crates/spotify-cli/docs/workflow-contract.md`
  - `rg -n "Keyword and Query Handling|Alfred Item JSON Contract|Error Mapping|Environment Variables" crates/spotify-cli/docs/workflow-contract.md`
  - `rg -n "SPOTIFY_CLIENT_ID|SPOTIFY_CLIENT_SECRET|SPOTIFY_MAX_RESULTS|SPOTIFY_MARKET" crates/spotify-cli/docs/workflow-contract.md`

### Task 1.2: Scaffold `spotify-search` workflow folder and manifest
- **Location**:
  - `workflows/spotify-search/workflow.toml`
  - `workflows/spotify-search/scripts/script_filter.sh`
  - `workflows/spotify-search/scripts/action_open.sh`
  - `workflows/spotify-search/src/info.plist.template`
  - `workflows/spotify-search/src/assets/icon.png`
  - `workflows/spotify-search/tests/smoke.sh`
- **Description**: Create workflow skeleton from repository template and align manifest fields (`id`, `bundle_id`, `script_filter`, `action`, `rust_binary`) for Spotify runtime wiring.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Workflow directory contains all required baseline files.
  - `workflow.toml` uses `spotify-cli` as `rust_binary`.
- **Validation**:
  - `test -d workflows/spotify-search`
  - `test -f workflows/spotify-search/workflow.toml`
  - `test -x workflows/spotify-search/scripts/script_filter.sh`
  - `rg -n 'rust_binary\\s*=\\s*\"spotify-cli\"' workflows/spotify-search/workflow.toml`
  - `scripts/workflow-lint.sh --id spotify-search`

### Task 1.3: Add dedicated `spotify-cli` crate and workspace membership
- **Location**:
  - `Cargo.toml`
  - `crates/spotify-cli/Cargo.toml`
  - `crates/spotify-cli/src/lib.rs`
  - `crates/spotify-cli/src/main.rs`
- **Description**: Create a dedicated binary crate to isolate Spotify API logic from existing workflow binaries and keep command surface explicit.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Workspace includes `crates/spotify-cli` member.
  - `cargo run -p nils-spotify-cli -- --help` succeeds.
- **Validation**:
  - `cargo check -p nils-spotify-cli`
  - `cargo run -p nils-spotify-cli -- --help`

### Task 1.4: Define env variable contract in manifest + plist UI
- **Location**:
  - `workflows/spotify-search/workflow.toml`
  - `workflows/spotify-search/src/info.plist.template`
  - `crates/spotify-cli/docs/workflow-contract.md`
- **Description**: Define and document `SPOTIFY_CLIENT_ID` (required), `SPOTIFY_CLIENT_SECRET` (required), `SPOTIFY_MAX_RESULTS` (optional clamp), and `SPOTIFY_MARKET` (optional uppercase country code).
- **Dependencies**:
  - Task 1.1
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Required/optional flags are consistent across docs, manifest, and Alfred user config UI.
  - Defaults and guardrails are explicitly documented.
- **Validation**:
  - `rg -n "SPOTIFY_CLIENT_ID|SPOTIFY_CLIENT_SECRET|SPOTIFY_MAX_RESULTS|SPOTIFY_MARKET" workflows/spotify-search/workflow.toml workflows/spotify-search/src/info.plist.template crates/spotify-cli/docs/workflow-contract.md`
  - `rg -n 'SPOTIFY_CLIENT_ID\\s*=\\s*\"\"|SPOTIFY_CLIENT_SECRET\\s*=\\s*\"\"|SPOTIFY_MAX_RESULTS\\s*=\\s*\"10\"' workflows/spotify-search/workflow.toml`
  - `rg -n 'SPOTIFY_CLIENT_ID|SPOTIFY_CLIENT_SECRET|SPOTIFY_MAX_RESULTS|SPOTIFY_MARKET|required|placeholder|default' workflows/spotify-search/src/info.plist.template`
  - `rg -n 'required|optional|default' crates/spotify-cli/docs/workflow-contract.md`

## Sprint 2: Spotify API and CLI pipeline
**Goal**: Implement a deterministic Rust pipeline for config + auth + search + Alfred feedback JSON.
**Demo/Validation**:
- Command(s): `cargo test -p nils-spotify-cli`, `cargo run -p nils-spotify-cli -- search --query "daft punk"`
- Verify: CLI prints valid Alfred JSON on success and deterministic errors on failure.

### Task 2.1: Implement runtime config parsing and guardrails
- **Location**:
  - `crates/spotify-cli/src/config.rs`
  - `crates/spotify-cli/src/lib.rs`
- **Description**: Parse env vars, enforce required credentials, clamp max results to API-safe range, and validate market format.
- **Dependencies**:
  - Task 1.3
  - Task 1.4
- **Complexity**: 5
- **Acceptance criteria**:
  - Missing credentials fail before network call.
  - Invalid `SPOTIFY_MAX_RESULTS` and `SPOTIFY_MARKET` produce actionable config errors.
- **Validation**:
  - `cargo test -p nils-spotify-cli`
  - `cargo test -p nils-spotify-cli -- --list | rg "config_"`
  - `env -u SPOTIFY_CLIENT_ID -u SPOTIFY_CLIENT_SECRET cargo run -p nils-spotify-cli -- search --query "test"`

### Task 2.2: Implement Spotify token client (Client Credentials)
- **Location**:
  - `crates/spotify-cli/src/spotify_auth.rs`
  - `crates/spotify-cli/Cargo.toml`
- **Description**: Implement token request to Spotify Accounts service and parse access token payload with robust HTTP/transport error typing.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Auth client returns token payload on 2xx and structured errors otherwise.
  - Credential values are never logged to stdout/stderr.
- **Validation**:
  - `cargo test -p nils-spotify-cli`
  - `cargo test -p nils-spotify-cli -- --list | rg "spotify_auth_"`
  - `cargo clippy -p nils-spotify-cli --all-targets -- -D warnings`

### Task 2.3: Implement Spotify search API client (track search only)
- **Location**:
  - `crates/spotify-cli/src/spotify_api.rs`
- **Description**: Call Spotify Search endpoint with `type=track`, map response fields to internal result structs (`name`, `artists`, `external_url`), and classify HTTP vs transport vs parse errors.
- **Dependencies**:
  - Task 2.2
- **Complexity**: 8
- **Acceptance criteria**:
  - Request params include `q`, `type=track`, `limit`, and optional `market`.
  - Parser extracts canonical external URL and human-readable subtitle components.
  - Empty API response maps to empty result vector without process failure.
- **Validation**:
  - `cargo test -p nils-spotify-cli`
  - `cargo test -p nils-spotify-cli -- --list | rg "spotify_api_"`
  - `cargo clippy -p nils-spotify-cli --all-targets -- -D warnings`

### Task 2.4: Implement Alfred feedback mapping for tracks
- **Location**:
  - `crates/spotify-cli/src/feedback.rs`
  - `crates/spotify-cli/src/lib.rs`
- **Description**: Map track results to Alfred items with deterministic subtitle normalization/truncation and `arg` as Spotify external URL.
- **Dependencies**:
  - Task 2.3
- **Complexity**: 6
- **Acceptance criteria**:
  - Subtitle combines artist names + album/name metadata in stable format.
  - Overlong subtitles are truncated consistently and remain single-line.
  - Empty result set returns one non-actionable fallback item.
- **Validation**:
  - `cargo test -p nils-spotify-cli`
  - `cargo test -p nils-spotify-cli -- --list | rg "feedback_|track_url_|subtitle_"`

### Task 2.5: Implement CLI command and output contract
- **Location**:
  - `crates/spotify-cli/src/main.rs`
- **Description**: Add `search --query` command and ensure success path prints JSON-only stdout while failures use concise stderr + non-zero exit codes.
- **Dependencies**:
  - Task 2.1
  - Task 2.4
- **Complexity**: 6
- **Acceptance criteria**:
  - Empty query is user error and does not call API.
  - Success emits valid Alfred JSON payload only.
  - Runtime errors are mapped to predictable message classes for shell adapter mapping.
- **Validation**:
  - `cargo test -p nils-spotify-cli`
  - `cargo test -p nils-spotify-cli -- --list | rg "main_"`
  - `cargo run -p nils-spotify-cli -- search --query "chill" | jq -e '.items | type == "array"'`
  - `bash -c 'set +e; env -u SPOTIFY_CLIENT_ID -u SPOTIFY_CLIENT_SECRET cargo run -p nils-spotify-cli -- search --query "chill" >/dev/null 2>&1; test $? -ne 0'`

### Task 2.6: Add focused unit tests for error classification
- **Location**:
  - `crates/spotify-cli/src/spotify_auth.rs`
  - `crates/spotify-cli/src/spotify_api.rs`
  - `crates/spotify-cli/src/main.rs`
- **Description**: Add tests that lock user-error/runtime-error classification and verify mapping behavior required by script filter error handling.
- **Dependencies**:
  - Task 2.5
- **Complexity**: 5
- **Acceptance criteria**:
  - Missing credentials map to user error class.
  - HTTP 429 and 5xx scenarios map to runtime class with deterministic wording.
- **Validation**:
  - `cargo test -p nils-spotify-cli`
  - `cargo test -p nils-spotify-cli -- --list | rg "error|runtime|config"`

## Sprint 3: Alfred wiring and smoke test hardening
**Goal**: Wire Alfred runtime scripts/plist and ship deterministic smoke coverage for MVP behavior.
**Demo/Validation**:
- Command(s): `bash workflows/spotify-search/tests/smoke.sh`, `scripts/workflow-pack.sh --id spotify-search`
- Verify: Smoke passes end-to-end with stubs and packaged plist assertions.

### Task 3.1: Implement script filter adapter with fallback error mapping
- **Location**:
  - `workflows/spotify-search/scripts/script_filter.sh`
- **Description**: Resolve packaged/release/debug `spotify-cli`, execute search command, and map stderr signatures to actionable Alfred items.
- **Dependencies**:
  - Task 2.5
  - Task 2.6
- **Complexity**: 6
- **Acceptance criteria**:
  - Adapter always emits valid Alfred JSON even when CLI fails.
  - Error mapping includes missing credentials, rate limit, API unavailable, and invalid config.
- **Validation**:
  - `shellcheck workflows/spotify-search/scripts/script_filter.sh`
  - `shfmt -d workflows/spotify-search/scripts/script_filter.sh`
  - `bash workflows/spotify-search/scripts/script_filter.sh "test" | jq -e '.items | type == "array"'`

### Task 3.2: Implement URL open action script
- **Location**:
  - `workflows/spotify-search/scripts/action_open.sh`
- **Description**: Keep open action minimal (`open "$1"`) with argument validation and usage error code parity with existing workflows.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 2
- **Acceptance criteria**:
  - Missing arg exits 2 with usage text.
  - Valid URL is forwarded unchanged to `open`.
- **Validation**:
  - `shellcheck workflows/spotify-search/scripts/action_open.sh`
  - `bash -c 'tmpdir="$(mktemp -d)"; printf "#!/usr/bin/env bash\nprintf \"%s\\n\" \"\$1\" >\"$tmpdir/url\"\n" >"$tmpdir/open"; chmod +x "$tmpdir/open"; PATH="$tmpdir:$PATH" bash workflows/spotify-search/scripts/action_open.sh "https://open.spotify.com/track/abc"; test "$(cat "$tmpdir/url")" = "https://open.spotify.com/track/abc"; rm -rf "$tmpdir"'`
  - `bash -c 'set +e; bash workflows/spotify-search/scripts/action_open.sh >/dev/null 2>&1; test $? -eq 2'`

### Task 3.3: Wire `info.plist.template` keyword, object graph, and user config
- **Location**:
  - `workflows/spotify-search/src/info.plist.template`
- **Description**: Configure keyword trigger (`sp`), script-filter/action object connection, and Alfred variable UI entries for Spotify env vars.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
  - Task 1.4
- **Complexity**: 7
- **Acceptance criteria**:
  - Packaged plist includes correct script paths and connection mapping.
  - User configuration variables and required flags match contract.
- **Validation**:
  - `scripts/workflow-pack.sh --id spotify-search`
  - `plutil -lint build/workflows/spotify-search/pkg/info.plist`
  - `plutil -convert json -o - build/workflows/spotify-search/pkg/info.plist | jq -e '[.userconfigurationconfig[].variable] | sort == ["SPOTIFY_CLIENT_ID","SPOTIFY_CLIENT_SECRET","SPOTIFY_MARKET","SPOTIFY_MAX_RESULTS"]'`

### Task 3.4: Implement deterministic smoke test with stubs and packaging checks
- **Location**:
  - `workflows/spotify-search/tests/smoke.sh`
- **Description**: Build smoke test similar to existing search workflows: assert required files/executables, stub `spotify-cli` success/failure modes, verify fallback titles, and validate packaged plist wiring.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
  - Task 3.3
- **Complexity**: 8
- **Acceptance criteria**:
  - Smoke test passes without network access and without real Spotify credentials.
  - Smoke test fails on missing file/script permissions, malformed JSON, or broken plist wiring.
  - Smoke test validates packaged binary placement under `build/workflows/spotify-search/pkg/bin/spotify-cli`.
- **Validation**:
  - `bash workflows/spotify-search/tests/smoke.sh`
  - `scripts/workflow-test.sh --id spotify-search`

### Task 3.5: Align manifest and packaging metadata
- **Location**:
  - `workflows/spotify-search/workflow.toml`
  - `scripts/workflow-pack.sh`
- **Description**: Ensure manifest values and pack script interaction correctly build/package `spotify-cli` and preserve existing workflow packaging behavior.
- **Dependencies**:
  - Task 3.3
- **Complexity**: 4
- **Acceptance criteria**:
  - `workflow-pack.sh --id spotify-search` produces installable artifact with checksum.
  - `workflow-pack.sh --all` still succeeds.
- **Validation**:
  - `scripts/workflow-pack.sh --id spotify-search`
  - `scripts/workflow-pack.sh --all`

## Sprint 4: Docs, quality gates, and rollout safety
**Goal**: Finalize operator docs and run full quality gates before release tagging.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `scripts/workflow-test.sh --id spotify-search`, `scripts/workflow-pack.sh --id spotify-search --install`
- Verify: Workflow is documented, validated, and installable without regressions.

### Task 4.1: Document setup and runtime behavior
- **Location**:
  - `README.md`
  - `workflows/spotify-search/README.md`
  - `crates/spotify-cli/docs/workflow-contract.md`
- **Description**: Add quick start, env setup, keyword usage, known limits, and troubleshooting pointers for search-only Spotify workflow.
- **Dependencies**:
  - Task 3.3
- **Complexity**: 4
- **Acceptance criteria**:
  - Docs clearly separate required credentials from optional tuning variables.
  - Operator steps include at least one copy-paste packaging + validation flow.
- **Validation**:
  - `rg -n "spotify-search|SPOTIFY_CLIENT_ID|SPOTIFY_CLIENT_SECRET|sp query-text" README.md workflows/spotify-search/README.md crates/spotify-cli/docs/workflow-contract.md`
  - `rg -n "Required credentials|Optional tuning" README.md workflows/spotify-search/README.md crates/spotify-cli/docs/workflow-contract.md`
  - `rg -n "workflow-pack.sh --id spotify-search|scripts/workflow-test.sh --id spotify-search" README.md workflows/spotify-search/README.md`

### Task 4.2: Run and lock quality gates for new workflow
- **Location**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `workflows/spotify-search/tests/smoke.sh`
- **Description**: Execute lint/test/pack gates and address any contract or regression failures before merge.
- **Dependencies**:
  - Task 3.4
  - Task 3.5
  - Task 4.1
- **Complexity**: 5
- **Acceptance criteria**:
  - All required pre-merge checks in `DEVELOPMENT.md` pass.
  - `spotify-search` smoke runs as part of workflow test entrypoint.
- **Validation**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh --id spotify-search`
  - `scripts/workflow-pack.sh --id spotify-search`

### Task 4.3: Release readiness check for monorepo packaging
- **Location**:
  - `.github/workflows/release.yml`
  - `scripts/workflow-pack.sh`
- **Description**: Confirm tag-based release packaging automatically includes the new artifact and checksum in release bundle output.
- **Dependencies**:
  - Task 4.2
- **Complexity**: 3
- **Acceptance criteria**:
  - `workflow-pack.sh --all` contains Spotify artifact in `dist` tree.
  - No release workflow script change is required beyond artifact inclusion by convention.
- **Validation**:
  - `scripts/workflow-pack.sh --all`
  - `find dist -type f -path '*spotify-search*' | sort`

## Testing Strategy
- Unit: `spotify-cli` tests for config guardrails, auth response parsing, search response parsing, feedback mapping, and CLI contract.
- Integration: script-level checks (`shellcheck`, `shfmt`) and smoke stubs for deterministic success/failure mapping.
- E2E/manual: package + install workflow, set Spotify credentials in Alfred, run `sp` queries, and verify Enter opens Spotify URLs.

## Risks & gotchas
- Client Credentials is process-local and may request tokens frequently under rapid typing; this can amplify rate limits without cache.
- Market filtering affects track availability and may produce unexpected empty results across regions.
- Spotify API error payload formats can vary; parser must preserve fallback behavior when message extraction fails.
- Storing `SPOTIFY_CLIENT_SECRET` in Alfred variables requires local machine trust; docs should call this out.
- Alfred script filter latency can degrade perceived UX if network retries are too aggressive.

## Rollback plan
- Revert new Spotify-specific files first to disable feature cleanly:
  - `crates/spotify-cli/Cargo.toml`
  - `crates/spotify-cli/src/lib.rs`
  - `crates/spotify-cli/src/main.rs`
  - `crates/spotify-cli/src/config.rs`
  - `crates/spotify-cli/src/spotify_auth.rs`
  - `crates/spotify-cli/src/spotify_api.rs`
  - `crates/spotify-cli/src/feedback.rs`
  - `workflows/spotify-search/workflow.toml`
  - `workflows/spotify-search/scripts/script_filter.sh`
  - `workflows/spotify-search/scripts/action_open.sh`
  - `workflows/spotify-search/src/info.plist.template`
  - `workflows/spotify-search/tests/smoke.sh`
  - `crates/spotify-cli/docs/workflow-contract.md`
- Remove workspace membership entry in `Cargo.toml` for `crates/spotify-cli`.
- Re-run baseline checks to confirm rollback health:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh --all`
