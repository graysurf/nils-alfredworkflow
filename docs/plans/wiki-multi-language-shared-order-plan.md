# Plan: Shared Ordered List Standard + Multi-Timezone Refactor + Wiki Multi-Language Requery

## Overview
This plan introduces a shared ordered-list parsing standard extracted from the existing `multi-timezone` behavior, then migrates consumers to the shared implementation and standards documentation.
The target outcome is consistent, deterministic order semantics across workflows that consume comma/newline config lists.
`multi-timezone` will be refactored to use the shared implementation without changing user-visible behavior.
`wiki-search` will then add multi-language query support with deterministic language menu ordering and direct language-switch requery on item click.

## Scope
- In scope: Extract and document a shared ordered-list parsing standard from `multi-timezone`.
- In scope: Update `ALFRED_WORKFLOW_DEVELOPMENT.md` with normative cross-workflow ordering rules.
- In scope: Refactor `multi-timezone` to consume the shared ordered-list utility.
- In scope: Implement `wiki-search` multi-language selection with click-to-requery behavior.
- In scope: Add/adjust tests (unit + smoke + contract docs) covering order guarantees and requery behavior.
- Out of scope: Changing `multi-timezone` UX/keyword behavior beyond internal refactor.
- Out of scope: Alfred workflow graph redesign not required for language requery.
- Out of scope: Introducing new external services or non-Wikipedia providers.

## Success Criteria
- Shared ordered-list parser exists in reusable location and is documented as cross-workflow standard.
- `multi-timezone` preserves existing output behavior and order semantics after refactor.
- `wiki-search` default search uses configured default language and exposes language options in configured order.
- Selecting a language menu item triggers immediate requery in selected language (no manual query retyping).
- Required validation commands pass for changed crates/workflows.

## Assumptions (if any)
1. `WIKI_LANGUAGE` will continue to define default language; a dedicated ordered options variable (for example `WIKI_LANGUAGE_OPTIONS`) can be introduced for menu list without breaking existing users.
2. Click-to-requery can be implemented with existing action path (`action_open.sh`) by dispatching language-switch payloads to Alfred query re-entry mechanics.
3. The shared ordered-list utility should support comma/newline separators, trim whitespace, ignore empty tokens, and preserve input order.
4. Linux CI does not need to execute real Alfred app requery; smoke tests can assert generated switch payload/deep-link contract.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 2.1 -> Task 2.2 -> Task 3.1 -> Task 3.2 -> Task 3.3 -> Task 3.5`.
- Parallel track A: `Task 1.3` can run after `Task 1.2` in parallel with `Task 2.1` prep.
- Parallel track B: `Task 2.3` can run after `Task 2.2` in parallel with `Task 2.4`.
- Parallel track C: `Task 3.4` can run after `Task 3.2` in parallel with `Task 3.5`.
- Parallel track D: `Task 3.6` can run after `Task 3.3` and `Task 3.4`.

## Sprint 1: Shared Standard Extraction
**Goal**: Define and codify a reusable ordered-list parsing standard and helper reusable by multiple workflows.
**Demo/Validation**:
- Command(s): `cargo test -p nils-workflow-common`, `rg -n "ordered list|config order|comma/newline" ALFRED_WORKFLOW_DEVELOPMENT.md`
- Verify: Shared parser utility exists with unit tests and global standards doc defines deterministic ordering rules.

### Task 1.1: Add cross-workflow ordered-list standard to Alfred development guide
- **Location**:
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
- **Description**: Add a normative section defining ordered-list config parsing rules (separators, whitespace handling, empty token handling, stable order retention, and query-over-config precedence expectations when applicable).
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - Standard explicitly states comma/newline list support and strict order preservation.
  - Standard clarifies when to keep logic shared vs workflow-local.
  - Validation guidance references concrete commands for order assertions.
- **Validation**:
  - `rg -n "ordered-list|order preservation|comma|newline" ALFRED_WORKFLOW_DEVELOPMENT.md`

### Task 1.2: Implement shared ordered-list parser utility in workflow-common
- **Location**:
  - `crates/workflow-common/src/list_parser.rs`
  - `crates/workflow-common/src/lib.rs`
  - `crates/workflow-common/README.md`
- **Description**: Introduce reusable parsing helper(s) for ordered comma/newline token lists, including trimming, empty-token skipping, deterministic order retention, and optional normalization hooks.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 6
- **Acceptance criteria**:
  - Public API is generic enough for both timezone IDs and wiki language codes.
  - Unit tests cover order preservation, mixed separators, and delimiters-only input.
  - Crate docs mention the new shared parser surface.
- **Validation**:
  - `cargo test -p nils-workflow-common`
  - `cargo clippy -p nils-workflow-common --all-targets -- -D warnings`

### Task 1.3: Add standards-oriented regression fixtures for shared parser behavior
- **Location**:
  - `crates/workflow-common/src/list_parser.rs`
- **Description**: Add targeted table-driven tests encoding edge conditions (leading/trailing separators, duplicate tokens, whitespace-only values, multiline mixed with commas).
- **Dependencies**:
  - Task 1.2
- **Complexity**: 4
- **Acceptance criteria**:
  - Tests prove deterministic stable order for all valid tokens.
  - Failures produce actionable mismatch output.
- **Validation**:
  - `cargo test -p nils-workflow-common list_parser`

## Sprint 2: Multi-Timezone Refactor to Shared Utility
**Goal**: Replace local ordered-list parsing in `multi-timezone` with shared parser while keeping runtime behavior stable.
**Demo/Validation**:
- Command(s): `cargo test -p nils-timezone-cli`, `bash workflows/multi-timezone/tests/smoke.sh`
- Verify: Existing order guarantees and fallback behavior remain unchanged.

### Task 2.1: Migrate timezone list parsing to shared utility
- **Location**:
  - `crates/timezone-cli/src/parser.rs`
  - `crates/timezone-cli/src/main.rs`
  - `crates/timezone-cli/Cargo.toml`
- **Description**: Replace direct `split([',', '\n'])` tokenization with shared parser utility, then keep timezone-specific validation/mapping local (`chrono_tz` parse + error mapping).
- **Dependencies**:
  - Task 1.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Timezone parser uses shared token stream as sole tokenizer source.
  - User-facing errors and precedence behavior remain backward compatible.
- **Validation**:
  - `cargo test -p nils-timezone-cli`
  - `cargo clippy -p nils-timezone-cli --all-targets -- -D warnings`

### Task 2.2: Preserve and extend deterministic-order tests after migration
- **Location**:
  - `crates/timezone-cli/src/parser.rs`
  - `crates/timezone-cli/src/main.rs`
  - `workflows/multi-timezone/tests/smoke.sh`
- **Description**: Keep existing order assertions and add at least one mixed-separator regression test to prove no order drift after shared parser adoption.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Unit and smoke tests confirm query/config order is unchanged.
  - No flaky ordering assertions introduced.
- **Validation**:
  - `cargo test -p nils-timezone-cli order_preserved_for_config_list`
  - `bash workflows/multi-timezone/tests/smoke.sh`

### Task 2.3: Update multi-timezone docs to reference shared standard
- **Location**:
  - `workflows/multi-timezone/README.md`
  - `crates/timezone-cli/docs/workflow-contract.md`
- **Description**: Document that ordering behavior is backed by shared ordered-list standard and remains deterministic for query/config paths.
- **Dependencies**:
  - Task 2.2
- **Complexity**: 3
- **Acceptance criteria**:
  - Workflow README + contract mention shared ordering standard.
  - Docs remain workflow-specific (no duplication of global spec text).
- **Validation**:
  - `rg -n "deterministic|order|shared" workflows/multi-timezone/README.md crates/timezone-cli/docs/workflow-contract.md`

## Sprint 3: Wiki Multi-Language + Direct Click Requery
**Goal**: Add ordered language menu and direct click-to-requery flow for `wiki-search`.
**Demo/Validation**:
- Command(s): `cargo test -p nils-wiki-cli`, `bash workflows/wiki-search/tests/smoke.sh`, `scripts/workflow-test.sh --id wiki-search`
- Verify: default language search works, language menu follows config order, clicking language entry triggers immediate requery in selected language.

### Task 3.1: Extend wiki runtime config for default + ordered language options
- **Location**:
  - `crates/wiki-cli/src/config.rs`
  - `crates/wiki-cli/src/lib.rs`
  - `crates/wiki-cli/Cargo.toml`
- **Description**: Add language options parsing backed by shared ordered-list parser, keep strict language-code validation, and define effective default language + options precedence.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 7
- **Acceptance criteria**:
  - Config supports deterministic language options order.
  - Default language resolution is explicit and backward compatible.
  - Invalid language tokens produce actionable config errors.
- **Validation**:
  - `cargo test -p nils-wiki-cli config::tests`

### Task 3.2: Add wiki language-switch rows with deterministic ordering
- **Location**:
  - `crates/wiki-cli/src/main.rs`
  - `crates/wiki-cli/src/feedback.rs`
  - `crates/wiki-cli/docs/workflow-contract.md`
- **Description**: Enrich Alfred payload with language-switch menu rows sourced from ordered config options, excluding/marking current language clearly, and preserving configured order.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 8
- **Acceptance criteria**:
  - Language menu row order exactly matches configured options order.
  - Search result rows still render correctly after menu injection.
  - Contract doc specifies menu row schema and ordering rule.
- **Validation**:
  - `cargo test -p nils-wiki-cli feedback::tests`
  - `cargo test -p nils-wiki-cli main_search_command_outputs_feedback_json_contract`

### Task 3.3: Implement click-to-requery dispatch path in workflow scripts
- **Location**:
  - `workflows/wiki-search/scripts/script_filter.sh`
  - `workflows/wiki-search/scripts/action_open.sh`
  - `workflows/wiki-search/src/info.plist.template`
- **Description**: Implement payload protocol distinguishing article-open vs language-switch actions; for language-switch action, trigger immediate Alfred-side requery with selected language and original query.
- **Dependencies**:
  - Task 3.2
- **Complexity**: 9
- **Acceptance criteria**:
  - Clicking language row triggers direct requery (no manual retyping).
  - Clicking article row still opens canonical URL in browser.
  - Script errors remain mapped to non-crashing Alfred items.
- **Validation**:
  - `bash workflows/wiki-search/tests/smoke.sh`
  - `shellcheck workflows/wiki-search/scripts/script_filter.sh workflows/wiki-search/scripts/action_open.sh`

### Task 3.4: Update wiki workflow configuration surfaces for multi-language options
- **Location**:
  - `workflows/wiki-search/workflow.toml`
  - `workflows/wiki-search/src/info.plist.template`
  - `workflows/wiki-search/README.md`
- **Description**: Add/describe new language-options config variable(s), default values, and operator guidance while preserving existing settings compatibility.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 4
- **Acceptance criteria**:
  - Manifest/plist expose required variables for default language + options list.
  - README clearly documents ordering semantics and switch behavior.
- **Validation**:
  - `rg -n "WIKI_LANGUAGE|WIKI_LANGUAGE_OPTIONS|order" workflows/wiki-search/workflow.toml workflows/wiki-search/src/info.plist.template workflows/wiki-search/README.md`

### Task 3.5: Add exhaustive wiki smoke tests for ordering and requery behavior
- **Location**:
  - `workflows/wiki-search/tests/smoke.sh`
  - `crates/wiki-cli/tests/cli_contract.rs`
- **Description**: Add deterministic assertions for language menu order, default-language first search, and click-to-requery payload generation/dispatch behavior.
- **Dependencies**:
  - Task 3.3
  - Task 3.4
- **Complexity**: 7
- **Acceptance criteria**:
  - Smoke test covers ordered options (for example `zh,en`) and verifies emitted action payload for both switch/open paths.
  - Contract tests assert service envelope/error behavior remains intact.
- **Validation**:
  - `bash workflows/wiki-search/tests/smoke.sh`
  - `cargo test -p nils-wiki-cli --test cli_contract`

### Task 3.6: End-to-end packaging and workflow-level regression checks
- **Location**:
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh`
- **Description**: Run workflow-level regression and packaging checks to ensure no breakage in installable artifacts after script/config changes.
- **Dependencies**:
  - Task 3.5
- **Complexity**: 5
- **Acceptance criteria**:
  - `wiki-search` and `multi-timezone` workflow tests pass.
  - Packaging output remains valid and installable.
- **Validation**:
  - `scripts/workflow-test.sh --id multi-timezone`
  - `scripts/workflow-test.sh --id wiki-search`
  - `scripts/workflow-pack.sh --id multi-timezone`
  - `scripts/workflow-pack.sh --id wiki-search`

## Testing Strategy
- Unit:
  - Shared parser behavior tests in `nils-workflow-common`.
  - `timezone-cli` parser and `wiki-cli` config/feedback unit tests for ordered semantics.
- Integration:
  - CLI contract tests in `crates/wiki-cli/tests/cli_contract.rs` and existing `timezone-cli` integration tests.
- E2E/manual:
  - Workflow smoke tests for `multi-timezone` and `wiki-search`.
  - Optional macOS manual check for Alfred click-to-requery UX after install (`scripts/workflow-pack-install.sh --id wiki-search`).

## Risks & gotchas
- Action-path coupling risk: `wiki-search` currently assumes action means URL open; adding switch actions requires explicit payload protocol and backward-compatible parsing.
- Alfred requery mechanism risk: Deep-link/query reinjection behavior can vary by environment; tests should validate generated command/payload deterministically even when Alfred app is absent.
- Config ambiguity risk: Default-language variable vs options-list variable must be explicitly documented to prevent operator confusion.
- Cross-crate coupling risk: Moving parsing utility into `workflow-common` increases dependency surface; API should stay minimal and stable.

## Rollback plan
1. Revert wiki language-switch action path to URL-open-only behavior (`action_open.sh` + payload schema rollback).
2. Keep `wiki-search` on single-language default mode (`WIKI_LANGUAGE`) by disabling options-list parsing.
3. Revert `timezone-cli` parser to pre-shared local tokenization if shared utility causes regressions.
4. Retain standards doc section but mark shared helper rollout as paused with explicit compatibility note.
5. Re-run gates before rollback release: `scripts/workflow-lint.sh`, `cargo test --workspace`, `scripts/workflow-test.sh`.
