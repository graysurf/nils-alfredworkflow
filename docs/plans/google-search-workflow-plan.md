# Plan: Add Google search workflow for Alfred (Brave backend)

## Overview
This plan adds a new Alfred workflow, `google-search`, and keeps existing workflows (`open-project`, `youtube-search`) unchanged.
The workflow behavior is: user enters a query, Alfred shows Brave web results with title and short snippet, and selecting an item opens the target URL in the browser.
Implementation follows existing repo architecture: business logic in Rust, thin Alfred shell adapters, and deterministic packaging via current `scripts/workflow-*` commands.
The data source is Brave Search API using credentials provided through workflow environment variables.

## Scope
- In scope: New workflow `google-search` with script filter and open action.
- In scope: Query Brave Search API and map results to Alfred JSON.
- In scope: Show result `title` and truncated `snippet` in Alfred rows.
- In scope: Open selected result URL in browser via action script.
- In scope: Add tests, smoke checks, docs, and operational guardrails needed for maintainability.
- Out of scope: Building a crawler or scraping Brave result HTML directly.
- Out of scope: User-specific personalization, login/OAuth, or private account data.
- Out of scope: Query history sync across devices.
- Out of scope: Refactoring `open-project` or `youtube-search` internals unless required for compatibility.

## Assumptions (if any)
1. Brave Search API is acceptable as the backend for web search behavior.
2. Users will provide `BRAVE_API_KEY` in Alfred workflow variables.
3. Initial target platform is Alfred 5 on macOS 13+, aligned with current repository defaults.
4. Runtime network access to `api.search.brave.com` is available.

## Success Criteria
- Typing keyword + query shows relevant Brave result rows with title and snippet.
- Pressing Enter on a row opens the canonical result URL returned by the API.
- Missing/invalid credentials, quota failures, and API/network failures are shown as non-crashing Alfred error items.
- `scripts/workflow-lint.sh`, `scripts/workflow-test.sh --id google-search`, and packaging pass.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 2.1 -> Task 2.2 -> Task 2.3 -> Task 2.4 -> Task 3.1 -> Task 3.3 -> Task 4.4`.
- Parallel track A: `Task 1.4` can run after `Task 1.1` and in parallel with `Task 1.3`.
- Parallel track B: `Task 2.5` can run after `Task 2.4` and in parallel with `Task 3.2`.
- Parallel track C: `Task 3.5` can run after `Task 3.1` and in parallel with `Task 3.2`.
- Parallel track D: `Task 4.1` and `Task 4.2` can run in parallel after `Task 2.5`.

## Sprint 1: Contract and scaffold
**Goal**: Define runtime contract and scaffold workflow/crate surfaces to minimize downstream rework.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/google-search-workflow-plan.md`, `test -d workflows/google-search`, `cargo check -p nils-brave-cli`
- Verify: Workflow skeleton exists, env contract is explicit, and workspace remains buildable.

### Task 1.1: Define Google workflow behavior contract (Brave backend)
- **Location**:
  - `docs/google-search-contract.md`
- **Description**: Write a functional contract for keyword behavior, query handling, result schema (`title`, `subtitle`, `arg` URL), snippet truncation rules, and error-to-feedback mapping.
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - Contract includes happy path and major failure path behaviors.
  - Contract defines JSON fields required for success, empty, and error items.
- **Validation**:
  - `test -f docs/google-search-contract.md`
  - `rg -n "^## (Keyword and Query Handling|Alfred Item JSON Contract|Error Mapping|Environment Variables and Constraints)$" docs/google-search-contract.md`
  - `rg -n "title = \"Enter a search query\"|valid: false|BRAVE_API_KEY|BRAVE_COUNTRY|BRAVE_MAX_RESULTS|BRAVE_SAFESEARCH" docs/google-search-contract.md`

### Task 1.2: Scaffold new workflow folder and manifest
- **Location**:
  - `workflows/google-search/workflow.toml`
  - `workflows/google-search/scripts/script_filter.sh`
  - `workflows/google-search/scripts/action_open.sh`
  - `workflows/google-search/src/info.plist.template`
  - `workflows/google-search/src/assets/icon.png`
  - `workflows/google-search/tests/smoke.sh`
- **Description**: Generate workflow skeleton with manifest fields (`id`, `bundle_id`, `script_filter`, `action`, `rust_binary`) wired to a dedicated Brave CLI binary.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Workflow directory contains required manifest/template/scripts/tests files.
  - `workflow.toml` references `brave-cli` as `rust_binary`.
- **Validation**:
  - `test -d workflows/google-search`
  - `test -f workflows/google-search/workflow.toml`
  - `test -x workflows/google-search/scripts/script_filter.sh`
  - `scripts/workflow-lint.sh --id google-search`

### Task 1.3: Add dedicated Rust binary crate for Brave workflow
- **Location**:
  - `Cargo.toml`
  - `crates/brave-cli/Cargo.toml`
  - `crates/brave-cli/src/main.rs`
  - `crates/brave-cli/src/lib.rs`
- **Description**: Create a dedicated crate for Brave workflow command surfaces to keep API-specific logic isolated from existing binaries.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Workspace includes `crates/brave-cli` member.
  - `cargo run -p nils-brave-cli -- --help` succeeds with placeholder command surface.
- **Validation**:
  - `cargo check -p nils-brave-cli`
  - `cargo run -p nils-brave-cli -- --help`

### Task 1.4: Define workflow runtime env variables
- **Location**:
  - `workflows/google-search/workflow.toml`
  - `workflows/google-search/src/info.plist.template`
  - `docs/google-search-contract.md`
- **Description**: Define and document environment variables: `BRAVE_API_KEY` (required), `BRAVE_MAX_RESULTS` (optional, default and clamp), `BRAVE_SAFESEARCH` (optional safe-search mode), and `BRAVE_COUNTRY` (optional country bias).
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Default values and constraints are consistent across manifest/template/docs.
  - Required vs optional variables are explicit and operator-friendly.
- **Validation**:
  - `rg -n "BRAVE_API_KEY|BRAVE_COUNTRY|BRAVE_MAX_RESULTS|BRAVE_SAFESEARCH" workflows/google-search/workflow.toml workflows/google-search/src/info.plist.template docs/google-search-contract.md`

## Sprint 2: API and JSON pipeline
**Goal**: Implement API client and CLI pipeline that returns Alfred JSON from query input.
**Demo/Validation**:
- Command(s): `cargo test -p nils-brave-cli`, `cargo run -p nils-brave-cli -- search --query "rust language"`
- Verify: CLI emits valid Alfred JSON on success and deterministic fallback items on failures.

### Task 2.1: Implement config parsing and guardrails
- **Location**:
  - `crates/brave-cli/src/config.rs`
  - `crates/brave-cli/src/lib.rs`
- **Description**: Parse env vars, enforce required credentials, clamp `BRAVE_MAX_RESULTS` to API bounds, and validate `BRAVE_SAFESEARCH` values.
- **Dependencies**:
  - Task 1.3
  - Task 1.4
- **Complexity**: 4
- **Acceptance criteria**:
  - Missing credentials are detected before network call.
  - Invalid numeric/safe-search config returns actionable errors.
- **Validation**:
  - `cargo test -p nils-brave-cli`
  - `cargo test -p nils-brave-cli -- --list | rg "config_"`
  - `env -u BRAVE_API_KEY cargo run -p nils-brave-cli -- search --query "test"`

### Task 2.2: Implement Brave Web Search API client
- **Location**:
  - `crates/brave-cli/src/brave_api.rs`
  - `crates/brave-cli/Cargo.toml`
- **Description**: Call `https://api.search.brave.com/res/v1/web/search` with `q` and optional `count`, `safesearch`, `country`, using `X-Subscription-Token` for authentication, then parse response payload into typed structs.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Request builder emits expected query parameters and respects configured limits.
  - Response parser extracts `title`, `url`, and `description` safely.
  - HTTP/API errors are mapped to typed internal errors.
- **Validation**:
  - `cargo test -p nils-brave-cli`
  - `cargo test -p nils-brave-cli -- --list | rg "brave_api_"`
  - `cargo clippy -p nils-brave-cli --all-targets -- -D warnings`

### Task 2.3: Implement Alfred feedback mapping
- **Location**:
  - `crates/brave-cli/src/feedback.rs`
  - `crates/brave-cli/src/lib.rs`
- **Description**: Convert parsed API results to `alfred-core` feedback items, normalize/truncate snippets for subtitle readability, and set `arg` to API-returned result URLs.
- **Dependencies**:
  - Task 2.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Subtitle normalization and truncation are deterministic.
  - Result items always contain valid `arg` URLs for open action.
- **Validation**:
  - `cargo test -p nils-brave-cli`
  - `cargo test -p nils-brave-cli -- --list | rg "feedback_|snippet_"`
  - `cargo test -p nils-brave-cli feedback::tests::maps_search_result_to_alfred_item`
  - `cargo test -p nils-brave-cli feedback::tests::truncates_long_snippet_deterministically`

### Task 2.4: Implement CLI command and stdout contract
- **Location**:
  - `crates/brave-cli/src/main.rs`
- **Description**: Add `search` subcommand with `--query`, guarantee JSON-only stdout on success, and preserve actionable stderr + exit codes on failure.
- **Dependencies**:
  - Task 2.1
  - Task 2.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Success path prints JSON payload only.
  - Invalid input/runtime failures return non-zero with concise error messages.
- **Validation**:
  - `cargo test -p nils-brave-cli`
  - `cargo test -p nils-brave-cli -- --list | rg "main_"`
  - `cargo run -p nils-brave-cli -- search --query "rust" | jq -e '.items | type == "array"'`
  - `bash -c 'set +e; env -u BRAVE_API_KEY cargo run -p nils-brave-cli -- search --query "rust" >/dev/null 2>&1; test $? -ne 0'`

### Task 2.5: Add failure-mode rendering for Alfred UX
- **Location**:
  - `crates/brave-cli/src/feedback.rs`
  - `workflows/google-search/scripts/script_filter.sh`
- **Description**: Ensure missing credentials, quota errors, empty results, and API unavailable scenarios return valid non-actionable Alfred items.
- **Dependencies**:
  - Task 2.4
- **Complexity**: 6
- **Acceptance criteria**:
  - Script filter never emits malformed JSON.
  - Error subtitles provide direct recovery guidance.
- **Validation**:
  - `cargo test -p nils-brave-cli`
  - `cargo test -p nils-brave-cli -- --list | rg "error_feedback_"`
  - `bash workflows/google-search/scripts/script_filter.sh "test" | jq -e '.items | length >= 1'`

## Sprint 3: Alfred wiring and package integration
**Goal**: Wire Alfred objects/scripts to `brave-cli` and ensure packaging output is installable.
**Demo/Validation**:
- Command(s): `scripts/workflow-pack.sh --id google-search`, `bash workflows/google-search/tests/smoke.sh`
- Verify: Packaged workflow contains valid plist, scripts, assets, and executable wiring.

### Task 3.1: Build robust script filter adapter
- **Location**:
  - `workflows/google-search/scripts/script_filter.sh`
- **Description**: Implement adapter resolving packaged/release/debug `brave-cli`, pass query through, clear quarantine attributes on macOS if needed, and return fallback error JSON on command failures.
- **Dependencies**:
  - Task 2.4
  - Task 2.5
- **Complexity**: 5
- **Acceptance criteria**:
  - Adapter supports installed artifact and local dev execution paths.
  - Failure path sanitizes stderr and still outputs valid Alfred JSON.
- **Validation**:
  - `shellcheck workflows/google-search/scripts/script_filter.sh`
  - `shfmt -d workflows/google-search/scripts/script_filter.sh`
  - `bash workflows/google-search/scripts/script_filter.sh "test" | jq -e '.items'`

### Task 3.2: Add open action for selected URL
- **Location**:
  - `workflows/google-search/scripts/action_open.sh`
- **Description**: Keep open action minimal (`open "$1"`) with argument presence validation and usage error for empty arg.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 2
- **Acceptance criteria**:
  - Missing arg returns exit code 2 with usage text.
  - Valid URL arg is passed to `open` unchanged.
- **Validation**:
  - `shellcheck workflows/google-search/scripts/action_open.sh`
  - `bash -c 'tmpdir="$(mktemp -d)"; printf "#!/usr/bin/env bash\nprintf \"%s\\n\" \"\$1\" >\"$tmpdir/url\"\n" >"$tmpdir/open"; chmod +x "$tmpdir/open"; PATH="$tmpdir:$PATH" bash workflows/google-search/scripts/action_open.sh "https://example.com"; test "$(cat "$tmpdir/url")" = "https://example.com"; rm -rf "$tmpdir"'`
  - `bash -c 'set +e; bash workflows/google-search/scripts/action_open.sh >/dev/null 2>&1; test $? -eq 2'`

### Task 3.3: Wire info.plist template object graph and vars
- **Location**:
  - `workflows/google-search/src/info.plist.template`
- **Description**: Configure keyword trigger (for example `gg`), script filter object, action node wiring, and `userconfigurationconfig` entries for Brave backend env vars.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
  - Task 1.4
- **Complexity**: 7
- **Acceptance criteria**:
  - Generated plist passes lint and contains expected scriptfile/type/connection fields.
  - Alfred user configuration exposes intended env variables.
- **Validation**:
  - `scripts/workflow-pack.sh --id google-search`
  - `plutil -lint build/workflows/google-search/pkg/info.plist`
  - `plutil -convert json -o - build/workflows/google-search/pkg/info.plist | jq -e '[.userconfigurationconfig[].variable] | sort == ["BRAVE_API_KEY","BRAVE_COUNTRY","BRAVE_MAX_RESULTS","BRAVE_SAFESEARCH"]'`

### Task 3.4: Align manifest and packaging references
- **Location**:
  - `workflows/google-search/workflow.toml`
  - `scripts/workflow-pack.sh`
- **Description**: Ensure manifest references (`rust_binary`, scripts, assets) package correctly with no regression for existing workflows.
- **Dependencies**:
  - Task 3.3
- **Complexity**: 4
- **Acceptance criteria**:
  - `workflow-pack.sh --id google-search` outputs installable `.alfredworkflow`.
  - `workflow-pack.sh --all` still succeeds.
- **Validation**:
  - `scripts/workflow-pack.sh --id google-search`
  - `scripts/workflow-pack.sh --all`

### Task 3.5: Add filesystem and script-contract smoke checks
- **Location**:
  - `workflows/google-search/tests/smoke.sh`
- **Description**: Add smoke checks for required files, script executability, and minimal script-filter JSON behavior without live API dependency.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Smoke test fails on missing files, non-executable scripts, or malformed JSON output.
  - Smoke test remains deterministic without live API calls.
- **Validation**:
  - `bash workflows/google-search/tests/smoke.sh`
  - `scripts/workflow-test.sh --id google-search`
  - `rg -n "assert_file|assert_exec|jq -e|BRAVE_CLI_BIN" workflows/google-search/tests/smoke.sh`

### Task 3.6: Add packaged plist wiring smoke checks
- **Location**:
  - `workflows/google-search/tests/smoke.sh`
- **Description**: Extend smoke test with packaged plist assertions for keyword, script node types, scriptfile paths, and action-chain connections.
- **Dependencies**:
  - Task 3.3
  - Task 3.5
- **Complexity**: 7
- **Acceptance criteria**:
  - Plist checks fail if object graph wiring is broken.
  - Validation remains deterministic and does not require Alfred GUI interaction.
- **Validation**:
  - `bash workflows/google-search/tests/smoke.sh`
  - `scripts/workflow-pack.sh --id google-search`
  - `plutil -convert json -o - build/workflows/google-search/pkg/info.plist | jq -e '[.objects[].type] | index(\"alfred.workflow.input.scriptfilter\") != null and index(\"alfred.workflow.action.script\") != null'`
  - `plutil -convert json -o - build/workflows/google-search/pkg/info.plist | jq -e '[.objects[].config.scriptfile] | index(\"./scripts/script_filter.sh\") != null and index(\"./scripts/action_open.sh\") != null'`
  - `plutil -convert json -o - build/workflows/google-search/pkg/info.plist | jq -e '.objects[] | select(.type == \"alfred.workflow.input.scriptfilter\") | .config.keyword == \"gg\"'`

## Sprint 4: Quality gates, docs, and rollout safety
**Goal**: Finalize with coverage, operator docs, and rollback-safe release steps.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `scripts/workflow-test.sh --id google-search`, `scripts/workflow-pack.sh --id google-search --install`
- Verify: Quality gates pass and workflow is installable with clear operator guidance.

### Task 4.1: Add config and API-layer Rust tests
- **Location**:
  - `crates/brave-cli/src/config.rs`
  - `crates/brave-cli/src/brave_api.rs`
- **Description**: Add tests for env parsing defaults/guardrails, request parameter construction, and API error classification.
- **Dependencies**:
  - Task 2.5
- **Complexity**: 5
- **Acceptance criteria**:
  - Config and request behavior are covered without live network calls.
  - Tests assert required credentials and API parameter bounds.
- **Validation**:
  - `cargo test -p nils-brave-cli`
  - `cargo test -p nils-brave-cli -- --list | rg "config_|brave_api_"`

### Task 4.2: Add feedback and CLI contract Rust tests
- **Location**:
  - `crates/brave-cli/src/feedback.rs`
  - `crates/brave-cli/src/main.rs`
- **Description**: Add tests for response-to-feedback mapping, snippet truncation, URL forwarding, and CLI stdout/stderr/exit-code contract.
- **Dependencies**:
  - Task 2.5
- **Complexity**: 6
- **Acceptance criteria**:
  - Feedback and CLI contract are covered without live API calls.
  - Tests explicitly verify JSON-on-stdout and non-zero failure paths.
- **Validation**:
  - `cargo test -p nils-brave-cli`
  - `cargo test -p nils-brave-cli -- --list | rg "feedback_|main_|snippet_|error_feedback_"`

### Task 4.3: Document workflow usage and operator setup
- **Location**:
  - `README.md`
  - `docs/WORKFLOW_GUIDE.md`
  - `TROUBLESHOOTING.md`
- **Description**: Document setup (`BRAVE_API_KEY`, optional `BRAVE_MAX_RESULTS`/`BRAVE_SAFESEARCH`/`BRAVE_COUNTRY`), expected quota behavior, command surface, and troubleshooting for common API failures.
- **Dependencies**:
  - Task 3.4
- **Complexity**: 3
- **Acceptance criteria**:
  - Docs include a clear quick-start for installing/configuring `google-search`.
  - Troubleshooting includes missing credentials, quota exceeded, and API unavailable guidance.
- **Validation**:
  - `rg -n "google-search|BRAVE_API_KEY|BRAVE_COUNTRY|quota|workflow pack" README.md docs/WORKFLOW_GUIDE.md TROUBLESHOOTING.md`

### Task 4.4: Run final repo-level validation and packaging gates
- **Location**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh`
- **Description**: Execute required project quality gates and verify `google-search` integrates cleanly with workspace lint/test/package pipelines.
- **Dependencies**:
  - Task 3.6
  - Task 4.1
  - Task 4.2
  - Task 4.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Required commands from `DEVELOPMENT.md` pass for changed scope.
  - Packaged artifact exists under versioned `dist/google-search/` output.
- **Validation**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh --id google-search`
  - `scripts/workflow-pack.sh --id google-search`
  - `test -f dist/google-search/*/*.alfredworkflow`

### Task 4.5: Add post-release rollback and support notes
- **Location**:
  - `TROUBLESHOOTING.md`
  - `docs/plans/google-search-workflow-plan.md`
- **Description**: Document executable rollback sequence (workflow + crate + workspace member revert), support checklist, and objective disable triggers for sustained API failures.
- **Dependencies**:
  - Task 4.4
- **Complexity**: 3
- **Acceptance criteria**:
  - Rollback steps are explicit, ordered, and executable.
  - Support notes include measurable criteria for temporary disablement.
- **Validation**:
  - `rg -n "rollback|revert|google-search|Cargo.toml|disable|support" TROUBLESHOOTING.md docs/plans/google-search-workflow-plan.md`

## Testing Strategy
- Unit: `brave-cli` tests for env parsing, request building, response parsing, snippet truncation, URL forwarding, and error mapping.
- Integration: Script adapter tests plus smoke tests for plist/script wiring and package output shape.
- E2E/manual: Install packaged workflow, set API variables, run keyword query, verify item rendering and browser open behavior.
- Non-functional: Confirm query latency and ensure error feedback remains concise under API failures.

## Risks & gotchas
- Brave Search API has quota and billing constraints; frequent queries can hit rate/usage caps.
- Credential handling mistakes can leak sensitive values in logs if stderr sanitization is incomplete.
- Alfred plist wiring is brittle; broken object connections can silently degrade action flow.
- API payload shape can evolve; parser and error mapping should be defensive.
- Search ranking and regional relevance can differ from user expectations and may require tuning `BRAVE_COUNTRY`/`BRAVE_SAFESEARCH`.

## First-release support window (D0-D2)
- Monitor failure classes separately: missing credentials, quota exceeded, API unavailable, and empty results.
- Trigger emergency disable plan if either condition is met:
  - API unavailable + quota failures exceed 30% of sampled queries for 30 minutes.
  - Script filter emits malformed or non-JSON output at any time.
- Keep operator response template ready:
  - Current status (degraded/disabled)
  - Scope (`google-search` only)
  - Workaround (temporarily use browser search)
  - Next update time

## Rollback plan
- Step 1: Pause distribution of new `google-search` workflow artifacts.
- Step 2: Revert or remove Brave workflow and crate changes:
  - `workflows/google-search/`
  - `crates/brave-cli/`
  - workspace member update in `Cargo.toml`
  - related docs updates
- Step 3: Rebuild and run validation after rollback:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh --all`
- Step 4: Reinstall known-good artifacts for unaffected workflows.
- Step 5: If already released, publish patch notes explaining temporary removal and workaround.
