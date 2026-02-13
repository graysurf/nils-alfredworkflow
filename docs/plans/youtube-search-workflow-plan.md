# Plan: Add YouTube search workflow for Alfred

## Overview
This plan adds a new Alfred workflow, `youtube-search`, in this monorepo and keeps the existing `open-project` workflow unchanged.
The workflow behavior is: user enters a query, Alfred shows matching YouTube videos with title and short description, and selecting an item opens the video page in the browser.
Implementation follows repo architecture: business logic in Rust, thin Alfred shell adapters, and deterministic packaging via existing `scripts/workflow-*` commands.
The data source is YouTube Data API v3 using an API key provided through workflow environment variables.

## Scope
- In scope: New workflow `youtube-search` with script filter and open action.
- In scope: Query YouTube Data API v3 `search.list` for videos and map results to Alfred JSON.
- In scope: Show `title` and truncated description in Alfred result rows.
- In scope: Open selected video URL in browser via action script.
- In scope: Add tests, smoke checks, and docs needed for maintainability.
- Out of scope: OAuth user login flow or personalized/private YouTube resources.
- Out of scope: Background index/cache daemon.
- Out of scope: Replacing or refactoring existing `open-project` workflow behavior.

## Assumptions (if any)
1. Public video search with API key is sufficient for this workflow.
2. Users will provide `YOUTUBE_API_KEY` in Alfred workflow variables.
3. Initial target platform is Alfred 5 on macOS 13+, consistent with repo defaults.
4. Network access to YouTube API is available at runtime.

## Success Criteria
- Typing keyword + query shows relevant video rows with title and description.
- Pressing Enter on a row opens a canonical YouTube watch URL for the selected result.
- Missing/invalid API key and quota/API failures are shown as non-crashing Alfred error items.
- `scripts/workflow-lint.sh`, `scripts/workflow-test.sh --id youtube-search`, and packaging pass.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 2.1 -> Task 2.2 -> Task 2.4 -> Task 3.1 -> Task 3.3 -> Task 4.4`.
- Parallel track A: `Task 1.4` can run after `Task 1.1` and in parallel with `Task 1.3`.
- Parallel track B: `Task 2.3` can run after `Task 2.2` and in parallel with `Task 2.4`.
- Parallel track C: `Task 3.2` can run after `Task 1.2` and in parallel with `Task 3.1`.
- Parallel track D: `Task 4.1` and `Task 4.2` can run in parallel after `Task 2.5`.

## Sprint 1: Contract and scaffold
**Goal**: Define runtime contract and scaffold workflow/crate surfaces so implementation can proceed without rework.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/youtube-search-workflow-plan.md`, `test -d workflows/youtube-search`, `cargo check -p nils-youtube-cli`
- Verify: Workflow skeleton exists, contract and env keys are documented, and workspace remains buildable.

### Task 1.1: Define workflow behavior contract
- **Location**:
  - `crates/youtube-cli/docs/workflow-contract.md`
- **Description**: Write the functional contract for keyword behavior, query handling, result schema (`title`, `subtitle`, `arg` URL), truncation rules, and API/runtime error mapping to Alfred items.
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - Contract includes happy path and failure path behaviors.
  - Contract explicitly defines expected JSON fields for each Alfred item state.
- **Validation**:
  - `test -f crates/youtube-cli/docs/workflow-contract.md`
  - `rg -n "keyword|title|subtitle|arg|error|quota|API key" crates/youtube-cli/docs/workflow-contract.md`

### Task 1.2: Scaffold new workflow folder and manifest
- **Location**:
  - `workflows/youtube-search/workflow.toml`
  - `workflows/youtube-search/scripts/script_filter.sh`
  - `workflows/youtube-search/scripts/action_open.sh`
  - `workflows/youtube-search/src/info.plist.template`
  - `workflows/youtube-search/src/assets/icon.png`
  - `workflows/youtube-search/tests/smoke.sh`
- **Description**: Generate workflow skeleton using existing repo scaffolding and align manifest fields (`id`, `bundle_id`, `script_filter`, `action`, `rust_binary`) for a dedicated YouTube CLI binary.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - New workflow directory has required manifest/template/scripts/tests files.
  - `workflow.toml` points to a YouTube-specific binary instead of reusing `workflow-cli`.
- **Validation**:
  - `test -d workflows/youtube-search`
  - `test -f workflows/youtube-search/workflow.toml`
  - `test -x workflows/youtube-search/scripts/script_filter.sh`
  - `scripts/workflow-lint.sh --id youtube-search`

### Task 1.3: Add dedicated Rust binary crate for YouTube workflow
- **Location**:
  - `Cargo.toml`
  - `crates/youtube-cli/Cargo.toml`
  - `crates/youtube-cli/src/main.rs`
  - `crates/youtube-cli/src/lib.rs`
- **Description**: Create a dedicated crate for YouTube workflow commands to avoid coupling `open-project` command surface with YouTube-specific config and API logic.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Workspace includes `crates/youtube-cli`.
  - `cargo run -p nils-youtube-cli -- --help` succeeds and exposes placeholder command surface.
- **Validation**:
  - `cargo check -p nils-youtube-cli`
  - `cargo run -p nils-youtube-cli -- --help`

### Task 1.4: Define workflow runtime env variables
- **Location**:
  - `workflows/youtube-search/workflow.toml`
  - `workflows/youtube-search/src/info.plist.template`
  - `crates/youtube-cli/docs/workflow-contract.md`
- **Description**: Define and document env variables: `YOUTUBE_API_KEY` (required), `YOUTUBE_MAX_RESULTS` (optional, default and max clamp), and `YOUTUBE_REGION_CODE` (optional).
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Env variable defaults and constraints are specified consistently across manifest/template/docs.
  - Required/optional status is explicit for operators.
- **Validation**:
  - `rg -n "YOUTUBE_API_KEY|YOUTUBE_MAX_RESULTS|YOUTUBE_REGION_CODE" workflows/youtube-search/workflow.toml workflows/youtube-search/src/info.plist.template crates/youtube-cli/docs/workflow-contract.md`

## Sprint 2: API and JSON pipeline
**Goal**: Implement API client + CLI pipeline that returns Alfred JSON items for query input.
**Demo/Validation**:
- Command(s): `cargo test -p nils-youtube-cli`, `cargo run -p nils-youtube-cli -- search --query "rust tutorial"`
- Verify: CLI emits valid Alfred JSON with multiple items in success case and deterministic fallback items in error cases.

### Task 2.1: Implement config parsing and guardrails
- **Location**:
  - `crates/youtube-cli/src/config.rs`
  - `crates/youtube-cli/src/lib.rs`
- **Description**: Parse environment variables, apply defaults, clamp `YOUTUBE_MAX_RESULTS`, and return user-facing errors when required key is missing.
- **Dependencies**:
  - Task 1.3
  - Task 1.4
- **Complexity**: 4
- **Acceptance criteria**:
  - Missing key is detected before network call.
  - Invalid numeric config falls back predictably or returns actionable user error.
- **Validation**:
  - `cargo test -p nils-youtube-cli`
  - `cargo test -p nils-youtube-cli -- --list | rg "config_"`
  - `env -u YOUTUBE_API_KEY cargo run -p nils-youtube-cli -- search --query "test"`

### Task 2.2: Implement YouTube Data API client
- **Location**:
  - `crates/youtube-cli/src/youtube_api.rs`
  - `crates/youtube-cli/Cargo.toml`
- **Description**: Call `https://www.googleapis.com/youtube/v3/search` with `part=snippet`, `type=video`, `q`, `maxResults`, optional region code, and parse response payload into internal structs.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Request builder emits expected query parameters.
  - Response parser extracts `videoId`, `title`, and `description`.
  - HTTP/API errors are mapped to typed internal errors.
- **Validation**:
  - `cargo test -p nils-youtube-cli`
  - `cargo test -p nils-youtube-cli -- --list | rg "youtube_api_"`
  - `cargo clippy -p nils-youtube-cli --all-targets -- -D warnings`

### Task 2.3: Implement Alfred feedback mapping
- **Location**:
  - `crates/youtube-cli/src/feedback.rs`
  - `crates/youtube-cli/src/lib.rs`
- **Description**: Convert parsed YouTube results to `alfred-core` feedback items, truncate/normalize descriptions for subtitle readability, and set `arg` to canonical watch URL.
- **Dependencies**:
  - Task 2.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Subtitle truncation is deterministic and avoids multiline output noise.
  - `arg` values always use canonical watch URLs built from API-returned video IDs.
- **Validation**:
  - `cargo test -p nils-youtube-cli`
  - `cargo test -p nils-youtube-cli -- --list | rg "feedback_|watch_url_"`

### Task 2.4: Implement CLI command and stdout contract
- **Location**:
  - `crates/youtube-cli/src/main.rs`
- **Description**: Add `search` subcommand with `--query`, return Alfred JSON on stdout only, and keep user/runtime errors distinguishable via exit codes and stderr.
- **Dependencies**:
  - Task 2.1
  - Task 2.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Success path prints only JSON payload.
  - Invalid input and runtime failures return non-zero with concise error text.
- **Validation**:
  - `cargo test -p nils-youtube-cli`
  - `cargo test -p nils-youtube-cli -- --list | rg "main_"`
  - `cargo run -p nils-youtube-cli -- search --query "lofi hip hop" | jq -e '.items | type == "array"'`
  - `bash -c 'set +e; env -u YOUTUBE_API_KEY cargo run -p nils-youtube-cli -- search --query "lofi hip hop" >/dev/null 2>&1; test $? -ne 0'`

### Task 2.5: Add failure-mode rendering for Alfred UX
- **Location**:
  - `crates/youtube-cli/src/feedback.rs`
  - `workflows/youtube-search/scripts/script_filter.sh`
- **Description**: Ensure missing key, quota errors, empty results, and API unavailable scenarios produce readable non-crashing Alfred items.
- **Dependencies**:
  - Task 2.4
- **Complexity**: 6
- **Acceptance criteria**:
  - Script filter never returns malformed JSON.
  - Error subtitles help user recover (set key, reduce frequency, retry later).
- **Validation**:
  - `cargo test -p nils-youtube-cli`
  - `cargo test -p nils-youtube-cli -- --list | rg "error_feedback_"`
  - `bash workflows/youtube-search/scripts/script_filter.sh "test" | jq -e '.items | length >= 1'`

## Sprint 3: Alfred wiring and package integration
**Goal**: Wire Alfred objects/scripts to the new CLI and ensure artifact packaging is installable.
**Demo/Validation**:
- Command(s): `scripts/workflow-pack.sh --id youtube-search`, `bash workflows/youtube-search/tests/smoke.sh`
- Verify: Packaged workflow contains valid plist, scripts, assets, and executable binary wiring.

### Task 3.1: Build robust script filter adapter
- **Location**:
  - `workflows/youtube-search/scripts/script_filter.sh`
- **Description**: Implement thin adapter that resolves packaged/release/debug `youtube-cli`, passes query through, and emits fallback error item JSON if command fails.
- **Dependencies**:
  - Task 2.4
  - Task 2.5
- **Complexity**: 5
- **Acceptance criteria**:
  - Adapter supports installed artifact and local dev execution paths.
  - Failure path sanitizes stderr and still returns valid Alfred JSON.
- **Validation**:
  - `shellcheck workflows/youtube-search/scripts/script_filter.sh`
  - `shfmt -d workflows/youtube-search/scripts/script_filter.sh`
  - `bash workflows/youtube-search/scripts/script_filter.sh "test" | jq -e '.items'`

### Task 3.2: Add open action for selected video URL
- **Location**:
  - `workflows/youtube-search/scripts/action_open.sh`
- **Description**: Keep open action minimal (`open "$1"`), with argument presence validation and clear usage error for empty arg.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 2
- **Acceptance criteria**:
  - Missing arg returns exit code 2 with usage text.
  - Valid URL arg opens browser without additional transformation.
- **Validation**:
  - `shellcheck workflows/youtube-search/scripts/action_open.sh`
  - `bash -c 'tmpdir="$(mktemp -d)"; printf "#!/usr/bin/env bash\nprintf \"%s\\n\" \"\$1\" >\"$tmpdir/url\"\n" >"$tmpdir/open"; chmod +x "$tmpdir/open"; PATH="$tmpdir:$PATH" bash workflows/youtube-search/scripts/action_open.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ"; test "$(cat "$tmpdir/url")" = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"; rm -rf "$tmpdir"'`
  - `bash -c 'set +e; bash workflows/youtube-search/scripts/action_open.sh >/dev/null 2>&1; test $? -eq 2'`

### Task 3.3: Wire info.plist template object graph and vars
- **Location**:
  - `workflows/youtube-search/src/info.plist.template`
- **Description**: Configure keyword trigger (for example `yt`), script filter node to external script mode, action node wiring, and `userconfigurationconfig` entries for YouTube env vars.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
  - Task 1.4
- **Complexity**: 7
- **Acceptance criteria**:
  - Generated plist passes lint and contains expected scriptfile/type/connection fields.
  - Alfred user configuration exposes the intended env variables.
- **Validation**:
  - `scripts/workflow-pack.sh --id youtube-search`
  - `plutil -lint build/workflows/youtube-search/pkg/info.plist`
  - `plutil -convert json -o - build/workflows/youtube-search/pkg/info.plist | jq -e '[.userconfigurationconfig[].variable] | sort == ["YOUTUBE_API_KEY","YOUTUBE_MAX_RESULTS","YOUTUBE_REGION_CODE"]'`

### Task 3.4: Align manifest and packaging references
- **Location**:
  - `workflows/youtube-search/workflow.toml`
  - `scripts/workflow-pack.sh`
- **Description**: Ensure manifest `rust_binary`, scripts, and assets are correctly packaged with no regressions for other workflows.
- **Dependencies**:
  - Task 3.3
- **Complexity**: 4
- **Acceptance criteria**:
  - `workflow-pack.sh --id youtube-search` outputs installable `.alfredworkflow`.
  - `workflow-pack.sh --all` still succeeds.
- **Validation**:
  - `scripts/workflow-pack.sh --id youtube-search`
  - `scripts/workflow-pack.sh --all`

### Task 3.5: Add filesystem and script-contract smoke checks
- **Location**:
  - `workflows/youtube-search/tests/smoke.sh`
- **Description**: Add smoke checks for required files, executability, and minimal script filter JSON contract without relying on live API calls.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Smoke test fails on missing required files, non-executable scripts, or malformed script-filter JSON output.
  - Smoke test is deterministic without requiring live API calls.
- **Validation**:
  - `bash workflows/youtube-search/tests/smoke.sh`
  - `scripts/workflow-test.sh --id youtube-search`

### Task 3.6: Add packaged plist wiring smoke checks
- **Location**:
  - `workflows/youtube-search/tests/smoke.sh`
- **Description**: Extend smoke test with packaged plist assertions for script node types, scriptfile paths, keyword presence, and action-chain connections.
- **Dependencies**:
  - Task 3.3
  - Task 3.5
- **Complexity**: 7
- **Acceptance criteria**:
  - Packaged plist checks fail when expected object graph wiring is missing.
  - Validation remains deterministic and does not require Alfred GUI interaction.
- **Validation**:
  - `bash workflows/youtube-search/tests/smoke.sh`
  - `scripts/workflow-pack.sh --id youtube-search`

## Sprint 4: Quality gates, docs, and rollout safety
**Goal**: Finalize with test coverage, operator docs, and rollback-safe delivery steps.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `scripts/workflow-test.sh --id youtube-search`, `scripts/workflow-pack.sh --id youtube-search --install`
- Verify: Repo quality gates pass and the workflow is installable with clear operator docs.

### Task 4.1: Add config and API-layer Rust tests
- **Location**:
  - `crates/youtube-cli/src/config.rs`
  - `crates/youtube-cli/src/youtube_api.rs`
- **Description**: Add tests for env parsing defaults/guardrails and request parameter construction plus API error classification.
- **Dependencies**:
  - Task 2.5
- **Complexity**: 5
- **Acceptance criteria**:
  - Config and API request behavior is covered without live-network dependence.
  - Tests assert key guardrails (required key, max results clamp, parameter completeness).
- **Validation**:
  - `cargo test -p nils-youtube-cli`
  - `cargo test -p nils-youtube-cli -- --list | rg "config_|youtube_api_"`

### Task 4.2: Add feedback and CLI contract Rust tests
- **Location**:
  - `crates/youtube-cli/src/feedback.rs`
  - `crates/youtube-cli/src/main.rs`
- **Description**: Add tests for response-to-feedback mapping, subtitle truncation, URL assembly, and CLI stdout/stderr/exit-code contract.
- **Dependencies**:
  - Task 2.5
- **Complexity**: 6
- **Acceptance criteria**:
  - Feedback rendering and CLI contract are covered without live API calls.
  - Tests explicitly verify JSON-on-stdout and non-zero error exit-code paths.
- **Validation**:
  - `cargo test -p nils-youtube-cli`
  - `cargo test -p nils-youtube-cli -- --list | rg "feedback_|main_|watch_url_|error_feedback_"`

### Task 4.3: Document workflow usage and operator setup
- **Location**:
  - `README.md`
  - `docs/WORKFLOW_GUIDE.md`
  - `TROUBLESHOOTING.md`
- **Description**: Document setup (`YOUTUBE_API_KEY`), expected quota behavior, command surfaces, and local troubleshooting steps for common API failures.
- **Dependencies**:
  - Task 3.4
- **Complexity**: 3
- **Acceptance criteria**:
  - Docs include a clear quick-start for installing and configuring `youtube-search`.
  - Troubleshooting includes missing key, quota exceeded, and network failure guidance.
- **Validation**:
  - `rg -n "youtube-search|YOUTUBE_API_KEY|quota|workflow pack" README.md docs/WORKFLOW_GUIDE.md TROUBLESHOOTING.md`

### Task 4.4: Run final repo-level validation and packaging gates
- **Location**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh`
- **Description**: Execute required project gates and ensure `youtube-search` integrates cleanly with workspace lint/test/package pipelines before merge.
- **Dependencies**:
  - Task 3.6
  - Task 4.1
  - Task 4.2
  - Task 4.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Required commands from `DEVELOPMENT.md` pass for the changed scope.
  - Packaged artifact exists under a versioned `dist/youtube-search/` subdirectory.
- **Validation**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh --id youtube-search`
  - `scripts/workflow-pack.sh --id youtube-search`
  - `test -f dist/youtube-search/*/*.alfredworkflow`

### Task 4.5: Add post-release rollback and support notes
- **Location**:
  - `TROUBLESHOOTING.md`
  - `docs/plans/youtube-search-workflow-plan.md`
- **Description**: Document actionable rollback sequence (revert workflow + crate + workspace member, rebuild package), first-release support checklist, and explicit disable triggers for sustained API failures.
- **Dependencies**:
  - Task 4.4
- **Complexity**: 3
- **Acceptance criteria**:
  - Rollback steps are explicit, ordered, and executable.
  - Support notes include objective signals for disabling workflow quickly if API failures spike.
- **Validation**:
  - `rg -n "rollback|revert|youtube-search|Cargo.toml|disable|support" TROUBLESHOOTING.md docs/plans/youtube-search-workflow-plan.md`

## Testing Strategy
- Unit: `youtube-cli` tests for env parsing, request building, response parsing, subtitle truncation, URL assembly, and error mapping.
- Integration: Script adapter tests plus smoke tests validating plist/script wiring and packaging output shape.
- E2E/manual: Install packaged workflow, set `YOUTUBE_API_KEY`, run keyword query, verify item rendering and browser open behavior.
- Non-functional: Confirm interactive latency is acceptable and error feedback remains readable under API failures.

## Risks & gotchas
- `search.list` quota cost is high (100 units/request), so aggressive querying can exhaust daily quota quickly.
- API key mishandling can leak credentials in logs or shell history if error paths are not sanitized.
- Alfred plist wiring is brittle; node connection mistakes can silently break action flow.
- Live API schemas and error payloads can evolve; parser/error mapping must be defensive.
- Network instability can degrade UX; fallback messaging should remain concise and actionable.

## First-release support window (D0-D2)
- Monitor failure classes separately: missing key, quota exceeded, API unavailable, and empty results.
- Trigger emergency disable plan if either condition is met:
  - API unavailable + quota failures together exceed 30% of sampled queries for 30 minutes.
  - Script-filter failures produce malformed/non-JSON output at any time.
- Keep operator response template ready:
  - Current status (degraded/disabled)
  - Scope (`youtube-search` only)
  - Workaround (temporarily use browser/manual search)
  - Next update time

## Rollback plan
- Step 1: Pause distribution of new `youtube-search` workflow artifacts.
- Step 2: Revert or remove the YouTube workflow and crate changeset:
  - `workflows/youtube-search/`
  - `crates/youtube-cli/`
  - related workspace entry in `Cargo.toml`
  - related docs updates
- Step 3: Rebuild and run validation after rollback:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh --all`
- Step 4: Reinstall known-good artifacts (for unaffected workflows) using existing pack/install flow.
- Step 5: If already released, publish patch release notes indicating temporary removal of `youtube-search` and operator workaround.
