# Plan: Sync full workflow README into Alfred readme via Rust crate

## Overview
This plan adds a dedicated Rust crate that converts a workflow `README.md` into Alfred-compatible readme content during packaging.  
The target rollout is `workflows/codex-cli`, with an opt-in packaging switch so other workflows are not changed unintentionally.  
The converter will preserve full README content, downgrade Markdown tables into bullet lists, and copy local screenshot assets into the packaged workflow directory.  
The packaging pipeline will inject the generated readme into the final `info.plist` so Alfred shows synchronized documentation without manual plist edits.

## Scope
- In scope: New Rust crate for README conversion, table downgrade, local image handling, and plist readme injection.
- In scope: Packaging integration in `scripts/workflow-pack.sh` using an opt-in `readme_source` manifest key.
- In scope: `workflows/codex-cli` onboarding with `readme_source = "README.md"` and `screenshot.png` staging support.
- In scope: Smoke-test assertions for packaged readme content and screenshot presence.
- Out of scope: Remote image downloading.
- Out of scope: General Markdown feature parity beyond what Alfred supports.
- Out of scope: Rewriting every existing workflow to opt in during this change.

## Assumptions (if any)
1. `workflows/codex-cli/README.md` remains the single source of truth for workflow documentation.
2. The only local image currently required for `codex-cli` is `workflows/codex-cli/screenshot.png`.
3. Packaging executes in an environment with Cargo available for running the new crate.
4. Alfred readme rendering keeps supporting image syntax and basic list/code/link constructs.

## Success Criteria
- `scripts/workflow-pack.sh --id codex-cli` produces `build/workflows/codex-cli/pkg/info.plist` whose `readme` value is generated from the full README.
- All table blocks in README are converted to deterministic bullet-list output in packaged `readme`.
- `build/workflows/codex-cli/pkg/screenshot.png` exists and is referenced by the injected readme content.
- `bash workflows/codex-cli/tests/smoke.sh` passes with updated package assertions.
- Existing packaging behavior for workflows without `readme_source` remains unchanged.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 2.1 -> Task 2.2 -> Task 2.4 -> Task 3.1 -> Task 3.2 -> Task 3.3 -> Task 4.3`.
- Parallel track A: `Task 1.3` can run after `Task 1.1` and in parallel with `Task 1.2`.
- Parallel track B: `Task 2.3` can run after `Task 2.1` and in parallel with `Task 2.2`.
- Parallel track C: `Task 2.5` can run after `Task 2.2` and in parallel with `Task 2.4`.
- Parallel track D: `Task 4.1` can run after `Task 3.1` and in parallel with `Task 3.2`.
- Parallel track E: `Task 4.2` can run after `Task 3.3` and in parallel with `Task 4.1`.

## Sprint 1: Contract and crate scaffold
**Goal**: Define the conversion contract and establish a dedicated Rust crate with a stable CLI interface.  
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/codex-cli-readme-sync-crate-plan.md`, `cargo check -p nils-workflow-readme-cli`
- Verify: Plan is valid and new crate is discoverable by the workspace.

### Task 1.1: Define packaging opt-in contract for README sync
- **Location**:
  - `scripts/workflow-pack.sh`
  - `workflows/codex-cli/workflow.toml`
  - `docs/WORKFLOW_GUIDE.md`
- **Description**: Define how `workflow-pack.sh` discovers README sync intent via a top-level `readme_source` key in workflow manifest and document behavior for missing/invalid paths.
- **Dependencies**:
  - none
- **Complexity**: 4
- **Acceptance criteria**:
  - Contract names one opt-in key (`readme_source`) and its relative-path semantics.
  - Contract specifies no-op behavior when the key is absent.
  - Contract specifies hard-fail behavior for configured but missing files.
- **Validation**:
  - `rg -n 'readme_source' docs/WORKFLOW_GUIDE.md`
  - `rg -n 'readme_source' workflows/codex-cli/workflow.toml`
  - `rg -n 'readme_source|README|missing' scripts/workflow-pack.sh`

### Task 1.2: Scaffold `nils-workflow-readme-cli` crate and workspace wiring
- **Location**:
  - `Cargo.toml`
  - `crates/workflow-readme-cli/Cargo.toml`
  - `crates/workflow-readme-cli/src/main.rs`
  - `crates/workflow-readme-cli/src/lib.rs`
  - `crates/workflow-readme-cli/README.md`
- **Description**: Add a new crate for README-to-Alfred conversion with explicit CLI subcommands and workspace registration following repository crate conventions.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Workspace members include `crates/workflow-readme-cli`.
  - `cargo run -p nils-workflow-readme-cli -- --help` succeeds.
  - Crate README documents command usage and output contract.
- **Validation**:
  - `cargo check -p nils-workflow-readme-cli`
  - `cargo run -p nils-workflow-readme-cli -- --help`
  - `rg -n 'nils-workflow-readme-cli' Cargo.toml crates/workflow-readme-cli/Cargo.toml`

### Task 1.3: Define converter command interface and exit-code contract
- **Location**:
  - `crates/workflow-readme-cli/src/main.rs`
  - `crates/workflow-readme-cli/README.md`
- **Description**: Define CLI parameters for workflow root, README source, stage directory, and target plist; document deterministic exit codes for user/input/runtime failures.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 4
- **Acceptance criteria**:
  - CLI supports one end-to-end command usable from shell packaging scripts.
  - README contains command examples and failure mode descriptions.
  - Exit codes distinguish invalid input from runtime IO errors.
- **Validation**:
  - `cargo run -p nils-workflow-readme-cli -- --help`
  - `rg -n 'Usage|Exit codes|workflow-root|stage-dir|plist' crates/workflow-readme-cli/README.md`
  - `bash -c 'set +e; tmpdir="$(mktemp -d)"; cargo run -p nils-workflow-readme-cli -- convert --workflow-root workflows/codex-cli --readme-source DOES_NOT_EXIST.md --stage-dir "$tmpdir" --plist "$tmpdir/info.plist" >/dev/null 2>&1; rc=$?; rm -rf "$tmpdir"; test "$rc" -ne 0'`

## Sprint 2: Markdown transformation and asset staging engine
**Goal**: Implement deterministic transformation from full README to Alfred-compatible readme text with table downgrade and local image staging metadata.  
**Demo/Validation**:
- Command(s): `cargo test -p nils-workflow-readme-cli`, `cargo run -p nils-workflow-readme-cli -- convert --workflow-root workflows/codex-cli --readme-source README.md --stage-dir build/workflows/codex-cli/pkg --plist build/workflows/codex-cli/pkg/info.plist --dry-run`
- Verify: Converter reports transformed readme output plan, table downgrades, and local asset copy plan.

### Task 2.1: Implement Markdown parsing pipeline for full-document ingestion
- **Location**:
  - `crates/workflow-readme-cli/src/lib.rs`
  - `crates/workflow-readme-cli/Cargo.toml`
- **Description**: Parse the entire README AST and preserve non-table structures (headings, paragraphs, lists, fenced code, links, images) with deterministic serialization.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 7
- **Acceptance criteria**:
  - Converter processes full README from start to end without truncation.
  - Non-table sections remain semantically intact in output markdown.
  - Output ordering matches source section ordering.
- **Validation**:
  - `cargo test -p nils-workflow-readme-cli`
  - `cargo test -p nils-workflow-readme-cli -- --list | rg 'parse_|serialize_|section_'`

### Task 2.2: Implement table-to-bullet downgrade rules
- **Location**:
  - `crates/workflow-readme-cli/src/lib.rs`
  - `crates/workflow-readme-cli/tests/table_downgrade.rs`
- **Description**: Convert each Markdown table into bullet-list entries using header-aware labeling so information remains readable in Alfred readme.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 8
- **Acceptance criteria**:
  - Every table row appears in downgraded output with all cell values retained.
  - Output contains no raw Markdown table separators (`|---|`).
  - Downgrade format is deterministic across runs.
- **Validation**:
  - `cargo test -p nils-workflow-readme-cli`
  - `cargo test -p nils-workflow-readme-cli -- --list | rg 'table_|downgrade_'`

### Task 2.3: Implement local image discovery and stage copy planner
- **Location**:
  - `crates/workflow-readme-cli/src/lib.rs`
  - `crates/workflow-readme-cli/tests/image_assets.rs`
- **Description**: Extract local image paths from README markdown, validate path safety, and prepare copy operations into package stage dir while preserving resolvable relative links.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Local relative image paths are detected and normalized against workflow root.
  - Missing configured local images fail with actionable error text.
  - `screenshot.png` is marked for stage copy for `codex-cli`.
- **Validation**:
  - `cargo test -p nils-workflow-readme-cli`
  - `cargo test -p nils-workflow-readme-cli -- --list | rg 'image_|asset_|path_'`

### Task 2.4: Implement plist readme injection with XML-safe output
- **Location**:
  - `crates/workflow-readme-cli/src/lib.rs`
  - `crates/workflow-readme-cli/src/main.rs`
- **Description**: Update rendered `info.plist` readme key with converted markdown and ensure XML-safe serialization and plist integrity.
- **Dependencies**:
  - Task 2.2
  - Task 2.3
- **Complexity**: 7
- **Acceptance criteria**:
  - Injected readme is written into plist key `readme`.
  - Special XML characters are persisted without plist corruption.
  - `plutil -lint` succeeds on injected plist.
- **Validation**:
  - `cargo test -p nils-workflow-readme-cli`
  - `bash -c 'tmpdir="$(mktemp -d)"; cp workflows/codex-cli/src/info.plist.template "$tmpdir/info.plist"; cargo run -p nils-workflow-readme-cli -- convert --workflow-root workflows/codex-cli --readme-source README.md --stage-dir "$tmpdir" --plist "$tmpdir/info.plist"; plutil -lint "$tmpdir/info.plist" >/dev/null; plutil -convert json -o - "$tmpdir/info.plist" | jq -e ".readme | contains(\"# Codex CLI - Alfred Workflow\")" >/dev/null; if plutil -convert json -o - "$tmpdir/info.plist" | jq -e ".readme | contains(\"|---|\")" >/dev/null; then rm -rf "$tmpdir"; exit 1; fi; rm -rf "$tmpdir"'`

### Task 2.5: Add deterministic fixture tests for codex-cli README features
- **Location**:
  - `crates/workflow-readme-cli/tests/codex_readme_fixtures.rs`
  - `crates/workflow-readme-cli/tests/fixtures/codex-cli-readme.md`
  - `crates/workflow-readme-cli/tests/fixtures/expected/codex-cli-readme-alfred.md`
- **Description**: Add fixtures that cover codex README sections (image, three tables, code blocks) and assert conversion output structure and key snippets.
- **Dependencies**:
  - Task 2.2
  - Task 2.3
- **Complexity**: 6
- **Acceptance criteria**:
  - Fixture suite includes at least one image case and one multi-table case.
  - Assertions verify no table separators remain in transformed output.
  - Assertions verify image reference for `screenshot.png` remains valid after staging.
- **Validation**:
  - `cargo test -p nils-workflow-readme-cli`

## Sprint 3: Packaging integration for codex-cli workflow
**Goal**: Wire the new crate into workflow packaging and ensure codex-cli package output includes synchronized readme and screenshot.  
**Demo/Validation**:
- Command(s): `scripts/workflow-pack.sh --id codex-cli`, `plutil -convert json -o - build/workflows/codex-cli/pkg/info.plist | jq -r '.readme' | head -n 20`
- Verify: Packaged plist readme is generated from README and screenshot is available in stage dir.

### Task 3.1: Integrate converter invocation into `workflow-pack.sh`
- **Location**:
  - `scripts/workflow-pack.sh`
- **Description**: After `info.plist` render, call the new crate when `readme_source` is set, passing workflow root, stage dir, readme path, and plist output path.
- **Dependencies**:
  - Task 2.4
- **Complexity**: 6
- **Acceptance criteria**:
  - Packaging command conditionally runs converter only for opted-in workflows.
  - Converter failure aborts packaging with clear stderr.
  - Workflows without opt-in key keep current behavior unchanged.
- **Validation**:
  - `bash -n scripts/workflow-pack.sh`
  - `scripts/workflow-pack.sh --id codex-cli`
  - `scripts/workflow-pack.sh --id wiki-search`

### Task 3.2: Opt in codex-cli manifest and align readme/image path policy
- **Location**:
  - `workflows/codex-cli/workflow.toml`
  - `workflows/codex-cli/README.md`
- **Description**: Add `readme_source = "README.md"` and confirm README image references are compatible with staged package paths (`screenshot.png`).
- **Dependencies**:
  - Task 1.1
  - Task 3.1
- **Complexity**: 3
- **Acceptance criteria**:
  - `workflow.toml` contains `readme_source` pointing to local README.
  - README image references resolve to copied assets in packaged output.
- **Validation**:
  - `rg -n '^readme_source\\s*=\\s*"README.md"' workflows/codex-cli/workflow.toml`
  - `rg -n '\\!\\[.*\\]\\(\\./screenshot\\.png\\)' workflows/codex-cli/README.md`

### Task 3.3: Update codex-cli smoke test for readme sync assertions
- **Location**:
  - `workflows/codex-cli/tests/smoke.sh`
- **Description**: Extend packaging assertions to verify screenshot staging and readme content markers from README conversion, including table downgrade evidence.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
  - Task 2.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Smoke test checks `build/workflows/codex-cli/pkg/screenshot.png` exists.
  - Smoke test checks packaged readme contains `# Codex CLI - Alfred Workflow`.
  - Smoke test checks packaged readme does not contain table separator patterns.
- **Validation**:
  - `bash workflows/codex-cli/tests/smoke.sh`

### Task 3.4: Keep static template readme as fallback-safe baseline
- **Location**:
  - `workflows/codex-cli/src/info.plist.template`
- **Description**: Preserve a concise static `readme` string in template so non-packaged template inspection remains readable even before converter injection.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 2
- **Acceptance criteria**:
  - Template retains valid `readme` string.
  - Packaged output always overwrites template readme when conversion runs.
- **Validation**:
  - `plutil -lint workflows/codex-cli/src/info.plist.template`
  - `scripts/workflow-pack.sh --id codex-cli`

## Sprint 4: Hardening, docs, and release-quality validation
**Goal**: Ensure failure modes are explicit, docs are updated, and repo quality gates pass with the new packaging behavior.  
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `cargo test --workspace`, `scripts/workflow-test.sh --id codex-cli`, `scripts/workflow-pack.sh --id codex-cli`
- Verify: Lint/test/pack suite passes with README-sync feature enabled.

### Task 4.1: Add converter error taxonomy and operator hints
- **Location**:
  - `crates/workflow-readme-cli/src/main.rs`
  - `crates/workflow-readme-cli/src/lib.rs`
  - `crates/workflow-readme-cli/README.md`
- **Description**: Classify and report invalid manifest path, missing readme, missing image, malformed markdown, and plist write errors with actionable remediations.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Error messages identify failing path and expected behavior.
  - User/input errors are distinguishable from runtime IO failures.
  - README includes troubleshooting commands.
- **Validation**:
  - `cargo test -p nils-workflow-readme-cli`
  - `cargo run -p nils-workflow-readme-cli -- --help`

### Task 4.2: Document packaging behavior and maintainer workflow updates
- **Location**:
  - `docs/WORKFLOW_GUIDE.md`
  - `workflows/codex-cli/README.md`
- **Description**: Document how README sync works during packaging, including opt-in key semantics, table downgrade expectations, and local screenshot requirements.
- **Dependencies**:
  - Task 3.3
- **Complexity**: 3
- **Acceptance criteria**:
  - Workflow guide contains a dedicated section for README-to-plist sync.
  - Codex workflow README notes that tables are downgraded in Alfred readme rendering.
  - Docs include the exact packaging command for validation.
- **Validation**:
  - `rg -n 'readme_source|README sync|table downgrade|screenshot' docs/WORKFLOW_GUIDE.md workflows/codex-cli/README.md`

### Task 4.3: Execute full verification suite and freeze rollout baseline
- **Location**:
  - `scripts/workflow-lint.sh`
  - `scripts/workflow-test.sh`
  - `scripts/workflow-pack.sh`
  - `workflows/codex-cli/tests/smoke.sh`
- **Description**: Run repository quality gates and codex-specific smoke/pack checks to confirm the feature is production-ready for release packaging.
- **Dependencies**:
  - Task 3.3
  - Task 4.1
  - Task 4.2
- **Complexity**: 4
- **Acceptance criteria**:
  - Required lint/test/pack commands pass without new warnings or regressions.
  - Packaged `info.plist` readme contains converted full README content.
  - Packaged artifact includes screenshot and codex bundled runtime as before.
- **Validation**:
  - `scripts/workflow-lint.sh`
  - `cargo test --workspace`
  - `scripts/workflow-test.sh --id codex-cli`
  - `scripts/workflow-pack.sh --id codex-cli`
  - `bash workflows/codex-cli/tests/smoke.sh`

## Testing Strategy
- Unit:
  - Crate-level unit tests for AST traversal, table downgrade formatting, image path normalization, and plist readme write behavior.
- Integration:
  - End-to-end converter invocation against `workflows/codex-cli/README.md` + staged plist fixture.
  - Packaging integration path through `scripts/workflow-pack.sh --id codex-cli`.
- E2E/manual:
  - Import generated `.alfredworkflow` and visually verify Alfred readme contains full content, downgraded tables, and screenshot rendering.

## Risks & gotchas
- Markdown parser differences can subtly alter spacing/list formatting; snapshot-based tests are needed to lock output.
- Injecting large README text into plist can introduce escaping edge cases (`&`, `<`, `>`), requiring explicit XML-safe handling.
- If packaging is run from a clean environment without prior Cargo build cache, converter invocation adds build latency.
- README edits may unintentionally degrade Alfred readability even when technically valid; docs should define preferred authoring constraints.

## Rollback plan
- Revert `scripts/workflow-pack.sh` converter invocation and remove `readme_source` opt-in key from `workflows/codex-cli/workflow.toml`.
- Keep static template `readme` text in `workflows/codex-cli/src/info.plist.template` as immediate fallback behavior.
- Remove `crates/workflow-readme-cli` from workspace members and delete crate files if rollback is full.
- Re-run `scripts/workflow-pack.sh --id codex-cli` and `bash workflows/codex-cli/tests/smoke.sh` to confirm packaging returns to pre-feature behavior.
