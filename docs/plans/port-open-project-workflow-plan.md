# Plan: Port open-project-in-vscode workflow to monorepo

## Overview
This plan ports the existing `open-project-in-vscode` Alfred workflow behavior into this monorepo's `open-project` workflow while keeping the monorepo architecture unchanged (Rust core + thin Bash glue + generated `info.plist`).
The goal is behavior parity for project discovery, query filtering, usage-based sorting, VSCode open action, and GitHub open action (including Shift modifier path).
The implementation will move heavy logic into Rust (`workflow-common` + `workflow-cli`) and keep Alfred scripts as minimal adapters.
Packaging and validation remain on the existing `xtask` and `scripts/workflow-*` entrypoints, with added checks for parity-critical output.

## Scope
- In scope: Port `open-project` workflow behavior and metadata to match the reference workflow semantics.
- In scope: Expand Rust core and CLI command surface for script-filter output, usage recording, and GitHub URL resolution.
- In scope: Update `workflows/open-project/src/info.plist.template` to include working Alfred object graph, connections, modifiers, and user config variables.
- In scope: Add/adjust tests and smoke checks required to prevent behavior regressions.
- Out of scope: Refactor unrelated workflows (`_template`) beyond compatibility-safe changes.
- Out of scope: New workflow features not present in reference behavior (cache daemon, async indexing, cross-platform GUI actions).
- Out of scope: Release automation or publishing process changes.

## Assumptions (if any)
1. Target parity is against `out/alfred-open-project-in-vscode/src/info.plist` behavior, not necessarily byte-identical plist output.
2. `open-project` is the only workflow required for this port in this iteration.
3. macOS runtime behavior (`open`, Alfred 5, VSCode CLI) is the primary compatibility target.
4. Existing monorepo packaging flow (`scripts/workflow-pack.sh`) remains the canonical way to produce `.alfredworkflow`.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 2.1 -> Task 2.2 -> Task 3.1 -> Task 3.2 -> Task 4.1 -> Task 4.3`.
- Parallel track A: `Task 2.3` can run after `Task 2.1` and in parallel with `Task 3.1`.
- Parallel track B: `Task 3.3` can run after `Task 2.2` and in parallel with `Task 4.1`.
- Parallel track C: `Task 4.2` can run after `Task 3.1` and before `Task 4.3`.

## Sprint 1: Define parity contract and data model
**Goal**: Convert reference workflow behavior into explicit, testable requirements and extend core Alfred/Rust models to support those requirements.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/port-open-project-workflow-plan.md`, `cargo test -p alfred-core`
- Verify: Parity contract doc is complete; `alfred-core` supports fields needed by ported script-filter payload.

### Task 1.1: Write parity contract from reference workflow
- **Location**:
  - `docs/open-project-port-parity.md`
- **Description**: Document exact runtime semantics to preserve: env defaults (`PROJECT_DIRS`, `USAGE_FILE`, `VSCODE_PATH`), scanning depth, matching behavior, subtitle format, sort order, Alfred entrypoints (`c`, `code`, `github`), and Shift modifier routing.
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - `docs/open-project-port-parity.md` lists all parity-critical behaviors and maps each behavior to target files in this repo.
  - The contract explicitly separates required parity from optional improvements.
- **Validation**:
  - `test -f docs/open-project-port-parity.md`
  - `rg -n "PROJECT_DIRS|USAGE_FILE|VSCODE_PATH|Shift|github|subtitle|sort" docs/open-project-port-parity.md`

### Task 1.2: Extend Alfred feedback model for parity features
- **Location**:
  - `crates/alfred-core/src/lib.rs`
- **Description**: Add Alfred item fields required by parity (for example `valid`, `autocomplete`, optional `mods`, and optional `variables`) while preserving backward compatibility of existing serialization behavior.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 5
- **Acceptance criteria**:
  - `Item` and related structs serialize parity-required fields only when present.
  - Existing uses of `Feedback::new` and `Item::new` continue to compile without call-site breakage.
- **Validation**:
  - `cargo test -p alfred-core`
  - `cargo clippy -p alfred-core --all-targets -- -D warnings`

### Task 1.3: Define workflow-common module boundaries
- **Location**:
  - `crates/workflow-common/src/lib.rs`
- **Description**: Refactor `workflow-common` into cohesive modules/interfaces for config parsing, project discovery, usage log IO, git metadata, and Alfred feedback assembly to support later implementation tasks.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 4
- **Acceptance criteria**:
  - Public API surface in `workflow-common` is organized around reusable functions instead of one placeholder builder.
  - Module boundaries are documented via top-level rustdoc comments.
- **Validation**:
  - `cargo check -p workflow-common`
  - `cargo test -p workflow-common`

## Sprint 2: Implement Rust core parity logic
**Goal**: Implement feature parity in Rust for scanning/filtering/sorting plus usage and GitHub URL logic.
**Demo/Validation**:
- Command(s): `cargo test -p workflow-common`, `cargo run -p workflow-cli -- --query ""`
- Verify: CLI outputs deterministic Alfred JSON with parity fields and ordering.

### Task 2.1: Implement project scan and filter pipeline
- **Location**:
  - `crates/workflow-common/src/lib.rs`
- **Description**: Implement recursive Git repo discovery over comma-separated `PROJECT_DIRS` (with `$HOME` and `~` expansion), max depth 3, basename-based query filtering, and no-result fallback item.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 8
- **Acceptance criteria**:
  - Discovery logic supports multiple roots and gracefully skips missing/unreadable roots.
  - Filtering behavior matches contract for empty and non-empty queries.
  - No-project case returns a non-valid Alfred item instead of process failure.
- **Validation**:
  - `cargo test -p workflow-common project_scan`
  - `cargo test -p workflow-common query_filter`

### Task 2.2: Implement usage log + git metadata + sort assembly
- **Location**:
  - `crates/workflow-common/src/lib.rs`
- **Description**: Implement usage file parsing with path-key first and basename fallback, parse timestamps for sort key, fetch last commit summary (`subject`, `author`, `date`), and assemble subtitle format `commit_text • last_used_text` sorted descending by usage timestamp.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 8
- **Acceptance criteria**:
  - Items are sorted by parsed usage timestamp descending; missing/invalid timestamps fall back predictably.
  - Subtitle format matches contract for both available and missing commit/usage values.
  - Duplicate usage entries are resolved according to contract precedence.
- **Validation**:
  - `cargo test -p workflow-common usage_log`
  - `cargo test -p workflow-common subtitle_format`
  - `cargo test -p workflow-common sort_order`

### Task 2.3: Implement GitHub remote normalization helper
- **Location**:
  - `crates/workflow-common/src/lib.rs`
- **Description**: Add helper that reads `origin` remote URL for a project and normalizes supported formats to HTTPS GitHub URL (for `git@github.com:owner/repo.git` and `https://github.com/owner/repo.git`), returning actionable errors otherwise.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Supported remote formats produce canonical URLs like `https://github.com/owner/repo`.
  - Unsupported remotes and missing `origin` return explicit errors for shell adapters.
- **Validation**:
  - `cargo test -p workflow-common github_remote`
  - `cargo clippy -p workflow-common --all-targets -- -D warnings`

### Task 2.4: Expand workflow-cli subcommands for Alfred actions
- **Location**:
  - `crates/workflow-cli/src/main.rs`
- **Description**: Replace single `--query` flow with subcommands for `script-filter`, `record-usage`, and `github-url`, with stable stdout/stderr contracts that shell scripts can consume.
- **Dependencies**:
  - Task 2.2
  - Task 2.3
- **Complexity**: 6
- **Acceptance criteria**:
  - CLI returns JSON only for script-filter command and plain path/URL output for action-oriented commands.
  - Exit codes cleanly separate success, user error, and runtime error.
- **Validation**:
  - `cargo test -p workflow-cli`
  - `cargo run -p workflow-cli -- script-filter --query ""`
  - `cargo run -p workflow-cli -- record-usage --path "$PWD"`

## Sprint 3: Wire Alfred workflow assets and packaging
**Goal**: Replace skeleton glue/template with working Alfred workflow wiring that uses new Rust core behaviors.
**Demo/Validation**:
- Command(s): `scripts/workflow-pack.sh --id open-project`, `plutil -lint build/workflows/open-project/pkg/info.plist`
- Verify: Packaged workflow contains valid plist graph and runnable scripts with expected command plumbing.

### Task 3.1: Replace open-project shell scripts with thin adapters
- **Location**:
  - `workflows/open-project/scripts/script_filter.sh`
  - `workflows/open-project/scripts/action_open.sh`
  - `workflows/open-project/scripts/action_record_usage.sh`
  - `workflows/open-project/scripts/action_open_github.sh`
- **Description**: Keep shell scripts minimal: resolve binary path, pass Alfred args/env to `workflow-cli`, call editor launcher (`VSCODE_PATH`) for project open, and call `open` for GitHub URL.
- **Dependencies**:
  - Task 2.4
- **Complexity**: 7
- **Acceptance criteria**:
  - Shell scripts contain no business logic that duplicates Rust behavior.
  - Scripts return non-zero on invalid input and pass through useful stderr context.
  - New action scripts are executable and included in packaging.
- **Validation**:
  - `shellcheck workflows/open-project/scripts/script_filter.sh workflows/open-project/scripts/action_open.sh workflows/open-project/scripts/action_record_usage.sh workflows/open-project/scripts/action_open_github.sh`
  - `shfmt -d workflows/open-project/scripts/script_filter.sh workflows/open-project/scripts/action_open.sh workflows/open-project/scripts/action_record_usage.sh workflows/open-project/scripts/action_open_github.sh`

### Task 3.2: Port full info.plist template object graph
- **Location**:
  - `workflows/open-project/src/info.plist.template`
- **Description**: Replace minimal plist template with complete Alfred object graph and connections for `c`, `code`, and `github` entrypoints, usage recording chain, VSCode action, GitHub action, and Shift modifier routing.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 8
- **Acceptance criteria**:
  - Template includes required `objects`, `connections`, `uidata`, `userconfigurationconfig`, and metadata fields needed for runtime parity.
  - Template keeps manifest substitutions (`bundle_id`, `name`, `version`) compatible with existing pack script.
- **Validation**:
  - `scripts/workflow-pack.sh --id open-project`
  - `plutil -lint build/workflows/open-project/pkg/info.plist`
  - `plutil -convert json -o - build/workflows/open-project/pkg/info.plist | jq '.objects | length > 0'`

### Task 3.3: Align workflow manifest and pack behavior for new assets
- **Location**:
  - `workflows/open-project/workflow.toml`
  - `scripts/workflow-pack.sh`
- **Description**: Ensure manifest defaults and packaging script copy/render logic match the newly introduced scripts and plist requirements without breaking other workflows.
- **Dependencies**:
  - Task 3.2
- **Complexity**: 5
- **Acceptance criteria**:
  - `workflow.toml` exposes parity-relevant env defaults and metadata.
  - `workflow-pack.sh` can still package all workflows with no regressions.
- **Validation**:
  - `scripts/workflow-pack.sh --id open-project`
  - `scripts/workflow-pack.sh --all`

## Sprint 4: Test parity and stabilize
**Goal**: Lock in parity with automated checks and concise documentation for maintenance.
**Demo/Validation**:
- Command(s): `scripts/workflow-lint.sh`, `scripts/workflow-test.sh`, `scripts/workflow-pack.sh --id open-project --install`
- Verify: All standard quality gates pass and packaged workflow behaves according to parity contract in manual Alfred run.

### Task 4.1: Add focused unit tests for parity-sensitive logic
- **Location**:
  - `crates/workflow-common/src/lib.rs`
  - `crates/workflow-cli/src/main.rs`
- **Description**: Add tests for path expansion, usage parsing fallback behavior, timestamp sorting, subtitle composition, GitHub URL normalization, and CLI stdout/stderr contract.
- **Dependencies**:
  - Task 3.3
- **Complexity**: 7
- **Acceptance criteria**:
  - Each parity-sensitive rule from `docs/open-project-port-parity.md` has at least one direct unit test.
  - Failing cases include helpful assertion messages for fast diagnosis.
- **Validation**:
  - `cargo test -p workflow-common`
  - `cargo test -p workflow-cli`

### Task 4.2: Upgrade workflow smoke test to assert runtime contract
- **Location**:
  - `workflows/open-project/tests/smoke.sh`
- **Description**: Extend smoke tests to validate presence/executability of new scripts, sanity-check script-filter JSON output shape, and verify packaged plist includes expected keywords/modifier routes.
- **Dependencies**:
  - Task 3.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Smoke test fails when parity-critical workflow nodes are missing from plist.
  - Smoke test is deterministic and runnable in CI/local without Alfred GUI interaction.
- **Validation**:
  - `bash workflows/open-project/tests/smoke.sh`
  - `scripts/workflow-test.sh --id open-project`

### Task 4.3: Update docs for operators and contributors
- **Location**:
  - `README.md`
  - `docs/WORKFLOW_GUIDE.md`
  - `docs/open-project-port-parity.md`
- **Description**: Document new command usage, env variable behavior, and expected parity boundaries so future changes can preserve intended behavior.
- **Dependencies**:
  - Task 4.1
  - Task 4.2
- **Complexity**: 4
- **Acceptance criteria**:
  - Readme and workflow guide document how to validate and package ported workflow.
  - Parity document includes a final status checklist marked complete.
- **Validation**:
  - `rg -n "open-project|PROJECT_DIRS|USAGE_FILE|VSCODE_PATH|workflow-cli" README.md docs/WORKFLOW_GUIDE.md docs/open-project-port-parity.md`
  - `plan-tooling validate --file docs/plans/port-open-project-workflow-plan.md`

## Testing Strategy
- Unit: Rust unit tests in `workflow-common` and `workflow-cli` for filtering, usage parsing, sort order, URL normalization, and CLI command contracts.
- Integration: Script-level checks with `shellcheck`, `shfmt`, and smoke validation of packaged plist JSON structure.
- E2E/manual: Install packaged `open-project` workflow, trigger `c`, `code`, and `github` keywords in Alfred, verify Enter/Shift behavior and output ordering with controlled usage log data.

## Risks & gotchas
- `info.plist` object graph is brittle; wrong UID wiring can silently break modifier routes even when plist lint passes.
- Timestamp parsing differences can change ordering behavior; tests must lock exact format and fallback handling.
- Heavy filesystem scanning may affect interactive latency on large trees; keep depth and filters aligned with contract.
- Editor launch command (`VSCODE_PATH`) may include spaces or custom executables; shell adapter quoting must be strict.
- Git remotes may include formats beyond GitHub; failure mode must be explicit and non-destructive.

## Rollback plan
- Keep changes isolated to `open-project` workflow and shared crates touched by this port.
- If parity regression is found after merge, revert the port commit set for these files first:
  - `workflows/open-project/src/info.plist.template`
  - `workflows/open-project/scripts/script_filter.sh`
  - `workflows/open-project/scripts/action_open.sh`
  - `workflows/open-project/scripts/action_record_usage.sh`
  - `workflows/open-project/scripts/action_open_github.sh`
  - `crates/workflow-common/src/lib.rs`
  - `crates/workflow-cli/src/main.rs`
  - `crates/alfred-core/src/lib.rs`
- Rebuild and reinstall previous artifact using `scripts/workflow-pack.sh --id open-project --install`.
- Keep `docs/open-project-port-parity.md` as postmortem input to address gaps before reattempting port.
