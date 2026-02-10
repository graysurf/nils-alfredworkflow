# Plan: Add Wiki search workflow for Alfred

## Overview
This plan adds a new Alfred workflow, `wiki-search`, and keeps existing workflows (`open-project`, `youtube-search`, `google-search`, `epoch-converter`, `spotify-search`, `randomer`) unchanged.
The workflow behavior is: user enters a query, Alfred shows Wikipedia article candidates with title and short snippet, and selecting an item opens the page in the browser.
Implementation follows the current monorepo architecture: domain logic in Rust, thin Alfred shell adapters, deterministic packaging via existing `scripts/workflow-*` entrypoints.
The backend is MediaWiki Action API over public Wikipedia endpoints without API-key requirements for baseline usage.

## Scope
- In scope: New workflow `wiki-search` with script filter and open action.
- In scope: Query MediaWiki search API and map response to Alfred JSON items.
- In scope: Show result `title` and cleaned/truncated snippet in Alfred rows.
- In scope: Open selected article URL in browser via action script.
- In scope: Add tests, smoke checks, docs, and operational guardrails needed for maintainability.
- Out of scope: Full-text indexing/caching database.
- Out of scope: Authenticated Wikimedia APIs or user-personalized results.
- Out of scope: Multi-source federated search (Confluence, Notion, local wiki engines).
- Out of scope: Refactoring existing workflow internals unless required for compatibility.

## Assumptions (if any)
1. Target wiki means public Wikipedia article search as first release scope.
2. Initial target platform remains Alfred 5 on macOS 13+, aligned with current repository defaults.
3. Runtime network access to the host selected by `WIKI_LANGUAGE` (default `en.wikipedia.org`) is available.
4. Public API request volume from this workflow remains within Wikimedia acceptable use for personal tooling.

## Success Criteria
- Typing keyword + query shows relevant Wikipedia rows with title and snippet.
- Pressing Enter on a row opens a canonical article URL for the selected result.
- Missing/invalid config, empty results, and API/network failures are rendered as non-crashing Alfred items.
- `scripts/workflow-lint.sh`, `scripts/workflow-test.sh --id wiki-search`, and packaging pass.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 1.4 -> Task 2.1 -> Task 2.2 -> Task 2.4 -> Task 3.1 -> Task 3.3 -> Task 4.4`.
- Parallel track A: `Task 1.3` and `Task 1.4` can run in parallel after `Task 1.2`.
- Parallel track B: `Task 2.3` can run after `Task 2.2` and in parallel with `Task 2.4`.
- Parallel track C: `Task 3.2` can run after `Task 1.2` and in parallel with `Task 3.1`.
- Parallel track D: `Task 4.1` and `Task 4.2` can run in parallel after `Task 2.5`.

## Sprint 1: Contract and scaffold
**Goal**: Define runtime contract and scaffold workflow/crate surfaces to minimize downstream rework.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/wiki-search-workflow-plan.md`, `test -d workflows/wiki-search`, `cargo check -p wiki-cli`
- Verify: Workflow skeleton exists, env contract is explicit, and workspace remains buildable.

### Task 1.1: Define wiki workflow behavior contract
- **Location**:
  - `docs/wiki-search-contract.md`
- **Description**: Write a functional contract for keyword behavior, query normalization, result schema (`title`, `subtitle`, `arg` URL), snippet cleanup/truncation rules, and failure mapping to Alfred items.
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - Contract includes happy path and major failure path behaviors.
  - Contract defines JSON fields required for success, empty, and error items.
  - Contract clarifies canonical URL strategy (`https://{language}.wikipedia.org/?curid={pageid}`).
- **Validation**:
  - `test -f docs/wiki-search-contract.md`
  - `rg -n "^## (Keyword and Query Handling|Alfred Item JSON Contract|Snippet Normalization and Truncation|Error Mapping|Environment Variables and Constraints)$" docs/wiki-search-contract.md`
  - `rg -n "WIKI_LANGUAGE|WIKI_MAX_RESULTS|curid|valid: false|No articles found" docs/wiki-search-contract.md`

### Task 1.2: Scaffold new workflow folder and manifest
- **Location**:
  - `workflows/wiki-search/workflow.toml`
  - `workflows/wiki-search/scripts/script_filter.sh`
  - `workflows/wiki-search/scripts/action_open.sh`
  - `workflows/wiki-search/src/info.plist.template`
  - `workflows/wiki-search/src/assets/icon.png`
  - `workflows/wiki-search/tests/smoke.sh`
- **Description**: Generate workflow skeleton with manifest fields (`id`, `bundle_id`, `script_filter`, `action`, `rust_binary`) wired to a dedicated `wiki-cli` binary.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Workflow directory contains required manifest/template/scripts/tests files.
  - `workflow.toml` references `wiki-cli` as `rust_binary`.
- **Validation**:
  - `test -d workflows/wiki-search`
  - `test -f workflows/wiki-search/workflow.toml`
  - `test -x workflows/wiki-search/scripts/script_filter.sh`
  - `scripts/workflow-lint.sh --id wiki-search`

### Task 1.3: Add dedicated Rust binary crate for wiki workflow
- **Location**:
  - `Cargo.toml`
  - `crates/wiki-cli/Cargo.toml`
  - `crates/wiki-cli/src/main.rs`
  - `crates/wiki-cli/src/lib.rs`
- **Description**: Create a dedicated crate for wiki workflow command surfaces to isolate MediaWiki-specific configuration, API, and feedback behavior from other binaries.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Workspace includes `crates/wiki-cli` member.
  - `cargo run -p wiki-cli -- --help` succeeds with placeholder command surface.
- **Validation**:
  - `cargo check -p wiki-cli`
  - `cargo run -p wiki-cli -- --help`

### Task 1.4: Define workflow runtime env variables
- **Location**:
  - `workflows/wiki-search/workflow.toml`
  - `workflows/wiki-search/src/info.plist.template`
  - `docs/wiki-search-contract.md`
- **Description**: Define and document `WIKI_LANGUAGE` (optional, default `en`) and `WIKI_MAX_RESULTS` (optional, default and clamp rules), with constraints shared across manifest/template/docs.
- **Dependencies**:
  - Task 1.1
  - Task 1.2
- **Complexity**: 4
- **Acceptance criteria**:
  - Default values and constraints are consistent across manifest/template/docs.
  - Variable semantics are explicit for operators and testable in code.
- **Validation**:
  - `rg -n "WIKI_LANGUAGE|WIKI_MAX_RESULTS" workflows/wiki-search/workflow.toml workflows/wiki-search/src/info.plist.template docs/wiki-search-contract.md`

## Sprint 2: API and JSON pipeline
**Goal**: Implement API client and CLI pipeline that returns Alfred JSON from query input.
**Demo/Validation**:
- Command(s): `cargo test -p wiki-cli`, `cargo run -p wiki-cli -- search --query "rust"`
- Verify: CLI emits valid Alfred JSON on success and deterministic fallback items on failures.

### Task 2.1: Implement config parsing and guardrails
- **Location**:
  - `crates/wiki-cli/src/config.rs`
  - `crates/wiki-cli/src/lib.rs`
- **Description**: Parse env vars, enforce `WIKI_LANGUAGE` pattern/normalization, clamp `WIKI_MAX_RESULTS`, and detect invalid config before any network request.
- **Dependencies**:
  - Task 1.3
  - Task 1.4
- **Complexity**: 4
- **Acceptance criteria**:
  - Invalid language or numeric config returns actionable config errors.
  - Default config is deterministic when env vars are absent.
- **Validation**:
  - `cargo test -p wiki-cli`
  - `cargo test -p wiki-cli -- --list | rg "config_"`
  - `env WIKI_LANGUAGE='EN-US!' cargo run -p wiki-cli -- search --query "rust" >/dev/null`

### Task 2.2: Implement MediaWiki search API client
- **Location**:
  - `crates/wiki-cli/src/wiki_api.rs`
  - `crates/wiki-cli/Cargo.toml`
- **Description**: Call `https://{language}.wikipedia.org/w/api.php` with `action=query`, `list=search`, `format=json`, `utf8=1`, `srsearch`, `srlimit`, and `srprop=snippet`, then parse typed response structs including `title`, `snippet`, and `pageid`.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Request builder emits expected query parameters and configured limits.
  - Response parser extracts required fields robustly.
  - HTTP/API errors are mapped to typed internal errors.
- **Validation**:
  - `cargo test -p wiki-cli`
  - `cargo test -p wiki-cli -- --list | rg "wiki_api_"`
  - `cargo clippy -p wiki-cli --all-targets -- -D warnings`

### Task 2.3: Implement Alfred feedback mapping
- **Location**:
  - `crates/wiki-cli/src/feedback.rs`
  - `crates/wiki-cli/src/lib.rs`
- **Description**: Convert parsed API results to `alfred-core` feedback items, normalize snippets by stripping HTML/search markup and collapsing whitespace, truncate subtitle deterministically, and map URL args using `curid` format.
- **Dependencies**:
  - Task 2.2
  - Task 1.3
- **Complexity**: 6
- **Acceptance criteria**:
  - Snippet cleanup removes markup artifacts and multiline noise.
  - `arg` always points to canonical article URL using selected language host.
- **Validation**:
  - `cargo test -p wiki-cli`
  - `cargo test -p wiki-cli -- --list | rg "feedback_|snippet_|url_"`
  - `cargo test -p wiki-cli feedback::tests::maps_result_to_alfred_item`
  - `cargo test -p wiki-cli feedback::tests::strips_html_tags_and_truncates`

### Task 2.4: Implement CLI command and stdout contract
- **Location**:
  - `crates/wiki-cli/src/main.rs`
- **Description**: Add `search` subcommand with `--query`, keep JSON-only stdout in success path, and preserve concise stderr + non-zero exit code on failures.
- **Dependencies**:
  - Task 2.1
  - Task 2.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Success path prints JSON payload only.
  - Invalid input/runtime failures return non-zero with actionable text.
- **Validation**:
  - `cargo test -p wiki-cli`
  - `cargo test -p wiki-cli -- --list | rg "main_"`
  - `cargo run -p wiki-cli -- search --query "rust" | jq -e '.items | type == "array"'`
  - `bash -c 'set +e; cargo run -p wiki-cli -- search --query "" >/dev/null 2>&1; test $? -ne 0'`

### Task 2.5: Add failure-mode rendering for Alfred UX
- **Location**:
  - `crates/wiki-cli/src/feedback.rs`
  - `workflows/wiki-search/scripts/script_filter.sh`
- **Description**: Ensure empty query, invalid config, no results, and API/network failures return valid non-actionable Alfred items with clear recovery guidance.
- **Dependencies**:
  - Task 2.4
- **Complexity**: 6
- **Acceptance criteria**:
  - Script filter never emits malformed JSON.
  - Error subtitles explain what user can do next.
- **Validation**:
  - `cargo test -p wiki-cli`
  - `cargo test -p wiki-cli -- --list | rg "error_feedback_"`
  - `bash workflows/wiki-search/scripts/script_filter.sh "test" | jq -e '.items | length >= 1'`

## Sprint 3: Alfred wiring and package integration
**Goal**: Wire Alfred objects/scripts to `wiki-cli` and ensure packaging output is installable.
**Demo/Validation**:
- Command(s): `scripts/workflow-pack.sh --id wiki-search`, `bash workflows/wiki-search/tests/smoke.sh`
- Verify: Packaged workflow contains valid plist, scripts, assets, and executable wiring.

### Task 3.1: Build robust script filter adapter
- **Location**:
  - `workflows/wiki-search/scripts/script_filter.sh`
- **Description**: Implement adapter resolving packaged/release/debug `wiki-cli`, pass query through, clear quarantine attributes on macOS if needed, and emit fallback Alfred JSON on command failures.
- **Dependencies**:
  - Task 2.4
  - Task 2.5
- **Complexity**: 5
- **Acceptance criteria**:
  - Adapter supports installed artifact and local dev execution paths.
  - Failure path sanitizes stderr and still outputs valid Alfred JSON.
- **Validation**:
  - `shellcheck workflows/wiki-search/scripts/script_filter.sh`
  - `shfmt -d workflows/wiki-search/scripts/script_filter.sh`
  - `bash workflows/wiki-search/scripts/script_filter.sh "test" | jq -e '.items'`

### Task 3.2: Add open action for selected wiki URL
- **Location**:
  - `workflows/wiki-search/scripts/action_open.sh`
- **Description**: Keep open action minimal (`open "$1"`) with argument presence validation and usage error for empty arg.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 2
- **Acceptance criteria**:
  - Missing arg returns exit code 2 with usage text.
  - Valid URL arg is passed to `open` unchanged.
- **Validation**:
  - `shellcheck workflows/wiki-search/scripts/action_open.sh`
  - `bash -c 'tmpdir="$(mktemp -d)"; printf "#!/usr/bin/env bash\nprintf \"%s\\n\" \"\$1\" >\"$tmpdir/url\"\n" >"$tmpdir/open"; chmod +x "$tmpdir/open"; PATH="$tmpdir:$PATH" bash workflows/wiki-search/scripts/action_open.sh "https://en.wikipedia.org/?curid=18839"; test "$(cat "$tmpdir/url")" = "https://en.wikipedia.org/?curid=18839"; rm -rf "$tmpdir"'`
  - `bash -c 'set +e; bash workflows/wiki-search/scripts/action_open.sh >/dev/null 2>&1; test $? -eq 2'`

### Task 3.3: Wire info.plist template object graph and vars
- **Location**:
  - `workflows/wiki-search/src/info.plist.template`
- **Description**: Configure keyword trigger (for example `wk`), script filter object, action node wiring, and `userconfigurationconfig` entries for wiki env vars.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
  - Task 1.4
- **Complexity**: 7
- **Acceptance criteria**:
  - Generated plist passes lint and contains expected scriptfile/type/connection fields.
  - Alfred user configuration exposes intended env variables.
- **Validation**:
  - `scripts/workflow-pack.sh --id wiki-search`
  - `plutil -lint build/workflows/wiki-search/pkg/info.plist`
  - `plutil -convert json -o - build/workflows/wiki-search/pkg/info.plist | jq -e '[.userconfigurationconfig[].variable] | sort == ["WIKI_LANGUAGE","WIKI_MAX_RESULTS"]'`

### Task 3.4: Align manifest and packaging references
- **Location**:
  - `workflows/wiki-search/workflow.toml`
  - `scripts/workflow-pack.sh`
- **Description**: Ensure manifest references (`rust_binary`, scripts, assets) package correctly and do not regress existing workflow packaging behavior.
- **Dependencies**:
  - Task 3.3
- **Complexity**: 4
- **Acceptance criteria**:
  - `workflow-pack.sh --id wiki-search` outputs installable `.alfredworkflow`.
  - `workflow-pack.sh --all` still succeeds.
- **Validation**:
  - `scripts/workflow-pack.sh --id wiki-search`
  - `scripts/workflow-pack.sh --all`

### Task 3.5: Add filesystem and script-contract smoke checks
- **Location**:
  - `workflows/wiki-search/tests/smoke.sh`
- **Description**: Add smoke checks for required files, script executability, and minimal script-filter JSON behavior without requiring live Wikipedia API availability.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
- **Complexity**: 5
- **Acceptance criteria**:
  - Smoke test fails on missing files, non-executable scripts, or malformed JSON output.
  - Smoke test remains deterministic without live API calls.
- **Validation**:
  - `bash workflows/wiki-search/tests/smoke.sh`
  - `scripts/workflow-test.sh --id wiki-search`
  - `rg -n "assert_file|assert_exec|jq -e|WIKI_CLI_BIN" workflows/wiki-search/tests/smoke.sh`

### Task 3.6: Add packaged plist wiring smoke checks
- **Location**:
  - `workflows/wiki-search/tests/smoke.sh`
- **Description**: Extend smoke test with packaged plist assertions for keyword, script node types, scriptfile paths, and action-chain connections.
- **Dependencies**:
  - Task 3.3
  - Task 3.5
- **Complexity**: 7
- **Acceptance criteria**:
  - Plist checks fail if object graph wiring is broken.
  - Validation remains deterministic and does not require Alfred GUI interaction.
- **Validation**:
  - `bash workflows/wiki-search/tests/smoke.sh`
  - `scripts/workflow-pack.sh --id wiki-search`
  - `plutil -convert json -o - build/workflows/wiki-search/pkg/info.plist | jq -e '[.objects[].type] | index("alfred.workflow.input.scriptfilter") != null and index("alfred.workflow.action.script") != null'`
  - `plutil -convert json -o - build/workflows/wiki-search/pkg/info.plist | jq -e '[.objects[].config.scriptfile] | index("./scripts/script_filter.sh") != null and index("./scripts/action_open.sh") != null'`
  - `plutil -convert json -o - build/workflows/wiki-search/pkg/info.plist | jq -e '.objects[] | select(.type == "alfred.workflow.input.scriptfilter") | .config.keyword == "wk"'`

## Sprint 4: Quality gates, docs, and rollout safety
**Goal**: Finalize with coverage, operator docs, and rollback-safe release steps.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `scripts/workflow-test.sh --id wiki-search`, `scripts/workflow-pack.sh --id wiki-search --install`
- Verify: Quality gates pass and workflow is installable with clear operator guidance.

### Task 4.1: Add config and API-layer Rust tests
- **Location**:
  - `crates/wiki-cli/src/config.rs`
  - `crates/wiki-cli/src/wiki_api.rs`
- **Description**: Add tests for env parsing defaults/guardrails, API request parameter construction, snippet payload decoding, and error classification.
- **Dependencies**:
  - Task 2.5
- **Complexity**: 5
- **Acceptance criteria**:
  - Config and API behavior are covered without live network calls.
  - Tests assert language normalization and result-limit bounds.
- **Validation**:
  - `cargo test -p wiki-cli`
  - `cargo test -p wiki-cli -- --list | rg "config_|wiki_api_"`

### Task 4.2: Add feedback and CLI contract Rust tests
- **Location**:
  - `crates/wiki-cli/src/feedback.rs`
  - `crates/wiki-cli/src/main.rs`
- **Description**: Add tests for snippet cleanup/truncation, URL forwarding, empty-result/error mapping, and CLI stdout/stderr/exit-code contract.
- **Dependencies**:
  - Task 2.5
- **Complexity**: 6
- **Acceptance criteria**:
  - Feedback and CLI contract are covered without live API calls.
  - Tests explicitly verify JSON-on-stdout and non-zero failure paths.
- **Validation**:
  - `cargo test -p wiki-cli`
  - `cargo test -p wiki-cli -- --list | rg "feedback_|main_|snippet_|error_feedback_"`

### Task 4.3: Document workflow usage and operator setup
- **Location**:
  - `README.md`
  - `docs/WORKFLOW_GUIDE.md`
  - `TROUBLESHOOTING.md`
- **Description**: Document setup (`WIKI_LANGUAGE`, `WIKI_MAX_RESULTS`), expected API/network failure behavior, command surface, and troubleshooting for common runtime issues.
- **Dependencies**:
  - Task 3.4
- **Complexity**: 3
- **Acceptance criteria**:
  - Docs include clear quick-start for installing/configuring `wiki-search`.
  - Troubleshooting includes invalid language config, network/API failure, and empty result guidance.
- **Validation**:
  - `rg -n "wiki-search|WIKI_LANGUAGE|WIKI_MAX_RESULTS|workflow pack|Wikipedia" README.md docs/WORKFLOW_GUIDE.md TROUBLESHOOTING.md`

### Task 4.4: Run final repo-level validation and packaging gates
- **Location**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh`
- **Description**: Execute required project quality gates and verify `wiki-search` integrates cleanly with workspace lint/test/package pipelines.
- **Dependencies**:
  - Task 3.6
  - Task 4.1
  - Task 4.2
  - Task 4.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Required commands from `DEVELOPMENT.md` pass for changed scope.
  - Packaged artifact exists under versioned `dist/wiki-search/` output.
- **Validation**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh --id wiki-search`
  - `scripts/workflow-pack.sh --id wiki-search`
  - `test -f dist/wiki-search/*/*.alfredworkflow`

### Task 4.5: Add post-release rollback and support notes
- **Location**:
  - `TROUBLESHOOTING.md`
  - `docs/plans/wiki-search-workflow-plan.md`
- **Description**: Document executable rollback sequence (workflow + crate + workspace member revert), support checklist, and objective disable triggers for sustained API failures.
- **Dependencies**:
  - Task 4.4
- **Complexity**: 3
- **Acceptance criteria**:
  - Rollback steps are explicit, ordered, and executable.
  - Support notes include measurable criteria for temporary disablement.
- **Validation**:
  - `rg -n "rollback|revert|wiki-search|Cargo.toml|disable|support" TROUBLESHOOTING.md docs/plans/wiki-search-workflow-plan.md`

## Testing Strategy
- Unit: `wiki-cli` tests for config parsing, request construction, response parsing, snippet normalization/truncation, URL generation, and error mapping.
- Integration: Script adapter checks plus smoke tests for plist/script wiring and package output shape.
- E2E/manual: Install packaged workflow, run keyword queries, verify item rendering and browser open behavior.
- Non-functional: Validate response latency and confirm graceful behavior when Wikipedia API is unavailable.

## Risks & gotchas
- Wikipedia snippets include HTML/search markup; improper cleanup can degrade Alfred readability.
- Wikimedia endpoints can return transient `5xx` or throttling behavior; UX must avoid crashy/error spam behavior.
- Alfred plist wiring is brittle; broken object graph connections can silently break enter-action flow.
- Cross-language host selection (`WIKI_LANGUAGE`) can produce unexpected relevance differences.
- Public API schema drift can break parsers unless decoding remains defensive.

## First-release support window (D0-D2)
- Monitor failure classes separately: invalid config, API unavailable, no results, and malformed JSON output.
- Trigger emergency disable plan if either condition is met:
  - API unavailable responses exceed 30% of sampled queries for 30 minutes.
  - Script filter emits malformed/non-JSON output at any time.
- Keep operator response template ready:
  - Current status (degraded/disabled)
  - Scope (`wiki-search` only)
  - Workaround (open Wikipedia in browser directly)
  - Next update time

## Rollback plan
- Step 1: Pause distribution of new `wiki-search` artifacts.
- Step 2: Revert or remove wiki workflow and crate changes:
  - `workflows/wiki-search/`
  - `crates/wiki-cli/`
  - workspace member update in `Cargo.toml`
  - related docs updates (`docs/wiki-search-contract.md`, workflow guide references)
- Step 3: Rebuild and run validation after rollback:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh --all`
- Step 4: Reinstall known-good artifacts for unaffected workflows.
- Step 5: If already released, publish patch notes describing temporary removal and workaround.
