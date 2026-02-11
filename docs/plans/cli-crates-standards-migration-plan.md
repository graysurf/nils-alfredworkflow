# Plan: CLI crates standards migration (nils-alfredworkflow)

## Overview
This plan migrates all CLI crates under `crates/*-cli` to align with the two external standards:
`new-cli-crate-development-standard.md` and `cli-service-json-contract-guideline-v1.md`.
The core constraint is backward compatibility for existing Alfred workflows that currently consume
legacy JSON-first outputs.
Approach: first establish compatibility policy and tooling, then migrate command contracts in
phases, and finally enforce checks/publish-readiness consistently.

## Scope
- In scope: all workspace CLI crates (`brave`, `cambridge`, `epoch`, `market`, `quote`, `randomer`, `spotify`, `timezone`, `weather`, `wiki`, `workflow`, `youtube`).
- In scope: command/output contract migration (human-readable default + explicit JSON mode + versioned envelope).
- In scope: stable error envelope (`code/message/details`) and no-secret-leak checks.
- In scope: README + crate metadata parity (`description`, contract docs, validation commands).
- In scope: workflow adapter migration so Alfred flows remain functional during CLI contract changes.
- Out of scope: feature expansion unrelated to contract/standards alignment.
- Out of scope: non-CLI crates (`alfred-core`, `alfred-plist`, `workflow-common`, `xtask`) except minimal supporting utilities.

## Assumptions (if any)
1. Existing workflow scripts may rely on current JSON shapes and cannot be broken in one-step rollout.
2. Temporary dual-mode support (legacy Alfred JSON + new service JSON envelope) is acceptable.
3. The repo keeps current exit-code semantics (`0/1/2`) during transition unless explicit decision changes them.
4. Standard documents in `/Users/terry/project/graysurf/nils-cli/docs/` are the policy baseline for migration decisions.

## Success Criteria
- Every CLI command has documented output modes and stable exit code behavior.
- Every service-consumed JSON mode returns envelope fields: `schema_version`, `command`, `ok`, plus `result/results/error`.
- Every migrated command has contract tests for success + failure envelope keys and secret-redaction checks.
- Existing Alfred workflows continue to work via explicit legacy mode/flag until migration completion.
- All CLI crate `Cargo.toml` files include required metadata (including `description`) and are publish-policy documented.
- `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace` pass.

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 1.3 -> Task 2.1 -> Task 2.2 -> Task 2.4 -> Task 3.1 -> Task 3.2`.
- Parallel track A: `Task 1.4` can run after `Task 1.2` in parallel with `Task 1.3`.
- Parallel track B: `Task 2.3` and `Task 2.5` can run in parallel after `Task 2.1`.
- Parallel track C: `Task 2.6` can run after `Task 2.2` in parallel with `Task 2.4`.
- Parallel track D: `Task 3.3` can run after `Task 3.1` in parallel with `Task 3.2`.

## Sprint 1: Baseline policy and compatibility contract
**Goal**: freeze migration policy and build a repeatable audit baseline before command-level rewrites.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/cli-crates-standards-migration-plan.md`, `rg -n "schema_version|command|ok" docs/`
- Verify: standards mapping, compatibility policy, and audit inventory are documented and reviewable.

### Task 1.1: Create local standards-mapping decision record
- **Location**:
  - `docs/specs/cli-standards-mapping.md`
  - `docs/plans/cli-crates-standards-migration-plan.md`
- **Description**: Translate external standards into repo-local policy decisions (default output, JSON envelope shape, error-code expectations, compatibility exceptions).
- **Dependencies**:
  - none
- **Complexity**: 5
- **Acceptance criteria**:
  - Mapping doc defines required fields and mode rules for this repo.
  - Migration exceptions for Alfred legacy consumers are explicit and time-bounded.
  - Documented decisions include ownership and change control.
- **Validation**:
  - `test -f docs/specs/cli-standards-mapping.md`
  - `rg -n "schema_version|legacy|human-readable|--json|error.code" docs/specs/cli-standards-mapping.md`

### Task 1.2: Build command surface inventory for all CLI crates
- **Location**:
  - `docs/reports/cli-command-inventory.md`
  - `crates/brave-cli/src/main.rs`
  - `crates/cambridge-cli/src/main.rs`
  - `crates/epoch-cli/src/main.rs`
  - `crates/market-cli/src/main.rs`
  - `crates/quote-cli/src/main.rs`
  - `crates/randomer-cli/src/main.rs`
  - `crates/spotify-cli/src/main.rs`
  - `crates/timezone-cli/src/main.rs`
  - `crates/weather-cli/src/main.rs`
  - `crates/wiki-cli/src/main.rs`
  - `crates/workflow-cli/src/main.rs`
  - `crates/youtube-cli/src/main.rs`
- **Description**: Enumerate commands/subcommands/options/output modes/current consumers for each CLI crate, including whether output is legacy Alfred JSON, plain text, or mixed.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 6
- **Acceptance criteria**:
  - Inventory covers all `crates/*-cli` command surfaces.
  - Each command includes current output mode and migration target mode.
  - Consumer mapping identifies impacted workflow scripts.
- **Validation**:
  - `test -f docs/reports/cli-command-inventory.md`
  - `rg -n "brave-cli|cambridge-cli|epoch-cli|market-cli|quote-cli|randomer-cli|spotify-cli|timezone-cli|weather-cli|wiki-cli|workflow-cli|youtube-cli" docs/reports/cli-command-inventory.md`
  - `rg -n "consumer|workflow|script_filter|script-filter" docs/reports/cli-command-inventory.md`

### Task 1.3: Define shared JSON envelope schema and error code registry
- **Location**:
  - `docs/specs/cli-json-envelope-v1.md`
  - `docs/specs/cli-error-code-registry.md`
- **Description**: Define a single envelope contract and stable machine error codes to be reused across all service-consumed commands.
- **Dependencies**:
  - Task 1.1
  - Task 1.2
- **Complexity**: 7
- **Acceptance criteria**:
  - Schema includes success and failure envelopes with required keys.
  - Error code registry assigns unique stable codes per crate/domain.
  - Compatibility section defines deprecation policy for old JSON shapes.
- **Validation**:
  - `test -f docs/specs/cli-json-envelope-v1.md`
  - `test -f docs/specs/cli-error-code-registry.md`
  - `rg -n "schema_version|command|ok|result|results|error|code|details" docs/specs/cli-json-envelope-v1.md docs/specs/cli-error-code-registry.md`

### Task 1.4: Add automated standards audit checks
- **Location**:
  - `scripts/cli-standards-audit.sh`
  - `DEVELOPMENT.md`
- **Description**: Add an auditable check script to detect missing README/description/json-mode/envelope-tests and document how to run it in dev workflow.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Script reports per-crate compliance status and actionable failures.
  - Development guide includes audit command and interpretation notes.
  - CI-friendly exit behavior is deterministic.
- **Validation**:
  - `bash scripts/cli-standards-audit.sh`
  - `rg -n "cli-standards-audit" DEVELOPMENT.md`

## Sprint 2: Contract migration implementation (dual-mode safe rollout)
**Goal**: migrate command outputs to standards-compliant modes while preserving Alfred behavior through explicit compatibility mode.
**Demo/Validation**:
- Command(s): `cargo test --workspace`, `scripts/workflow-test.sh`
- Verify: service JSON envelope works, human mode defaults are available where required, and existing workflows still pass.

### Task 2.1: Implement shared output-mode and envelope helper utilities
- **Location**:
  - `crates/workflow-common/src/lib.rs`
  - `crates/workflow-common/src/config.rs`
  - `crates/weather-cli/src/main.rs`
  - `crates/market-cli/src/main.rs`
- **Description**: Provide shared helpers for output mode selection (`human`, `json`, `alfred-json`) and envelope rendering to reduce per-crate drift.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 8
- **Acceptance criteria**:
  - Shared helper supports success/failure envelopes with stable keys.
  - Helper is adopted by at least two pilot crates before broad rollout.
  - No secret-sensitive fields are emitted by helper APIs.
- **Validation**:
  - `cargo test -p nils-workflow-common`
  - `cargo test -p nils-weather-cli`
  - `cargo test -p nils-market-cli`

### Task 2.2: Migrate weather-cli and market-cli to full contract v1
- **Location**:
  - `crates/weather-cli/src/main.rs`
  - `crates/weather-cli/tests/cli_contract.rs`
  - `crates/market-cli/src/main.rs`
  - `crates/market-cli/tests/cli_contract.rs`
- **Description**: Add versioned JSON envelope and explicit mode behavior, keeping existing JSON payload fields under `result` while preserving existing workflow consumers.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 8
- **Acceptance criteria**:
  - `--json` output uses required envelope keys.
  - Human-readable default is explicit and documented per policy decision.
  - Legacy integration paths remain available via explicit compatibility mode.
- **Validation**:
  - `cargo test -p nils-weather-cli`
  - `cargo test -p nils-market-cli`

### Task 2.3: Migrate search/workflow JSON-first crates to explicit compatibility mode
- **Location**:
  - `crates/brave-cli/src/main.rs`
  - `crates/cambridge-cli/src/main.rs`
  - `crates/epoch-cli/src/main.rs`
  - `crates/quote-cli/src/main.rs`
  - `crates/randomer-cli/src/main.rs`
  - `crates/spotify-cli/src/main.rs`
  - `crates/timezone-cli/src/main.rs`
  - `crates/wiki-cli/src/main.rs`
  - `crates/youtube-cli/src/main.rs`
- **Description**: Add explicit output mode flags and versioned service JSON envelope while retaining Alfred JSON compatibility mode for workflow callers.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 9
- **Acceptance criteria**:
  - Each crate exposes explicit mode selection.
  - Service JSON mode conforms to envelope spec with stable errors.
  - Alfred compatibility mode is retained and documented.
- **Validation**:
  - `cargo test -p nils-brave-cli`
  - `cargo test -p nils-cambridge-cli`
  - `cargo test -p nils-epoch-cli`
  - `cargo test -p nils-quote-cli`
  - `cargo test -p nils-randomer-cli`
  - `cargo test -p nils-spotify-cli`
  - `cargo test -p nils-timezone-cli`
  - `cargo test -p nils-wiki-cli`
  - `cargo test -p nils-youtube-cli`
  - `rg -n "json|format|alfred" crates/brave-cli/src/main.rs crates/cambridge-cli/src/main.rs crates/epoch-cli/src/main.rs crates/quote-cli/src/main.rs crates/randomer-cli/src/main.rs crates/spotify-cli/src/main.rs crates/timezone-cli/src/main.rs crates/wiki-cli/src/main.rs crates/youtube-cli/src/main.rs`

### Task 2.4: Update workflow scripts to call explicit compatibility mode
- **Location**:
  - `workflows/cambridge-dict/scripts/script_filter.sh`
  - `workflows/epoch-converter/scripts/script_filter.sh`
  - `workflows/google-search/scripts/script_filter.sh`
  - `workflows/market-expression/scripts/script_filter.sh`
  - `workflows/multi-timezone/scripts/script_filter.sh`
  - `workflows/open-project/scripts/script_filter.sh`
  - `workflows/open-project/scripts/script_filter_github.sh`
  - `workflows/quote-feed/scripts/script_filter.sh`
  - `workflows/randomer/scripts/script_filter.sh`
  - `workflows/randomer/scripts/script_filter_expand.sh`
  - `workflows/randomer/scripts/script_filter_types.sh`
  - `workflows/spotify-search/scripts/script_filter.sh`
  - `workflows/wiki-search/scripts/script_filter.sh`
  - `workflows/youtube-search/scripts/script_filter.sh`
  - `workflows/cambridge-dict/tests/smoke.sh`
  - `workflows/epoch-converter/tests/smoke.sh`
  - `workflows/google-search/tests/smoke.sh`
  - `workflows/market-expression/tests/smoke.sh`
  - `workflows/multi-timezone/tests/smoke.sh`
  - `workflows/open-project/tests/smoke.sh`
  - `workflows/quote-feed/tests/smoke.sh`
  - `workflows/randomer/tests/smoke.sh`
  - `workflows/spotify-search/tests/smoke.sh`
  - `workflows/wiki-search/tests/smoke.sh`
  - `workflows/youtube-search/tests/smoke.sh`
- **Description**: Update all workflow script calls to pass explicit output mode/flags so workflow behavior remains stable despite default mode migration.
- **Dependencies**:
  - Task 2.2
  - Task 2.3
- **Complexity**: 8
- **Acceptance criteria**:
  - All workflow script invocations pass explicit mode flags.
  - Existing smoke tests pass without behavior regressions.
  - No workflow depends on implicit output defaults.
- **Validation**:
  - `scripts/workflow-test.sh`
  - `rg -n "--format|--json|alfred" workflows/*/scripts`

### Task 2.5: Migrate workflow-cli mixed-output contract to v1
- **Location**:
  - `crates/workflow-cli/src/main.rs`
  - `crates/workflow-cli/tests/cli_contract.rs`
- **Description**: Standardize `workflow-cli` command outputs under documented mode rules, preserving plain-text action commands and adding service envelope where structured JSON is consumed.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 7
- **Acceptance criteria**:
  - `script-filter` supports explicit standards-compliant JSON mode.
  - Action commands keep deterministic plain-text contract.
  - Contract tests cover both success and failure paths.
- **Validation**:
  - `cargo test -p nils-workflow-cli`
  - `scripts/workflow-test.sh`

### Task 2.6: Add envelope + secret-leak contract tests across all CLI crates
- **Location**:
  - `crates/brave-cli/tests/cli_contract.rs`
  - `crates/cambridge-cli/tests/cli_contract.rs`
  - `crates/epoch-cli/tests/cli_contract.rs`
  - `crates/market-cli/tests/cli_contract.rs`
  - `crates/quote-cli/tests/cli_contract.rs`
  - `crates/randomer-cli/tests/cli_contract.rs`
  - `crates/spotify-cli/tests/cli_contract.rs`
  - `crates/timezone-cli/tests/cli_contract.rs`
  - `crates/weather-cli/tests/cli_contract.rs`
  - `crates/wiki-cli/tests/cli_contract.rs`
  - `crates/workflow-cli/tests/cli_contract.rs`
  - `crates/youtube-cli/tests/cli_contract.rs`
- **Description**: Add tests to assert envelope keys, machine error fields, and no secret/token leakage in all JSON success/failure responses.
- **Dependencies**:
  - Task 2.2
  - Task 2.3
  - Task 2.5
- **Complexity**: 9
- **Acceptance criteria**:
  - Every service JSON command has required envelope tests.
  - Secret leakage tests cover representative error and success cases.
  - Contract tests are deterministic and network-independent.
- **Validation**:
  - `cargo test --workspace`

## Sprint 3: Metadata, release readiness, and enforcement
**Goal**: finalize standards enforcement and ensure future CLI changes cannot regress compliance.
**Demo/Validation**:
- Command(s): `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`, `bash scripts/cli-standards-audit.sh`
- Verify: compliance checks are green and documented in contributor workflow.

### Task 3.1: Normalize CLI crate metadata and README completeness
- **Location**:
  - `crates/brave-cli/Cargo.toml`
  - `crates/brave-cli/README.md`
  - `crates/cambridge-cli/Cargo.toml`
  - `crates/cambridge-cli/README.md`
  - `crates/epoch-cli/Cargo.toml`
  - `crates/epoch-cli/README.md`
  - `crates/market-cli/Cargo.toml`
  - `crates/market-cli/README.md`
  - `crates/quote-cli/Cargo.toml`
  - `crates/quote-cli/README.md`
  - `crates/randomer-cli/Cargo.toml`
  - `crates/randomer-cli/README.md`
  - `crates/spotify-cli/Cargo.toml`
  - `crates/spotify-cli/README.md`
  - `crates/timezone-cli/Cargo.toml`
  - `crates/timezone-cli/README.md`
  - `crates/weather-cli/Cargo.toml`
  - `crates/weather-cli/README.md`
  - `crates/wiki-cli/Cargo.toml`
  - `crates/wiki-cli/README.md`
  - `crates/workflow-cli/Cargo.toml`
  - `crates/workflow-cli/README.md`
  - `crates/youtube-cli/Cargo.toml`
  - `crates/youtube-cli/README.md`
- **Description**: Ensure every CLI crate has required metadata (`description`, publish policy notes) and complete command/output docs aligned with standards.
- **Dependencies**:
  - Task 2.6
- **Complexity**: 6
- **Acceptance criteria**:
  - All CLI `Cargo.toml` include required description metadata.
  - All CLI README files document output modes and contract version.
  - Internal-only crates (if any) explicitly set and document `publish = false`.
- **Validation**:
  - `rg -n "^description\s*=\s*\"" crates/*-cli/Cargo.toml`
  - `rg -n "Output Contract|Standards Status" crates/*-cli/README.md`

### Task 3.2: Update publish order and publish dry-run policy
- **Location**:
  - `release/crates-io-publish-order.txt`
  - `scripts/publish-crates.sh`
  - `DEVELOPMENT.md`
- **Description**: Align publish order with final CLI set (including `nils-weather-cli` if publishable) and document dry-run policy per standards.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Publish order reflects all publishable CLI crates in dependency-safe order.
  - Dry-run instructions cover single crate and all-crates scenarios.
  - Non-publishable crates are excluded with documented reason.
- **Validation**:
  - `cat release/crates-io-publish-order.txt`
  - `scripts/publish-crates.sh --dry-run`

### Task 3.3: Enforce standards gate in routine workflow
- **Location**:
  - `scripts/workflow-lint.sh`
  - `DEVELOPMENT.md`
  - `.github/workflows/ci.yml`
- **Description**: Wire standards audit into lint/CI flow to prevent regressions after migration completion.
- **Dependencies**:
  - Task 3.1
- **Complexity**: 6
- **Acceptance criteria**:
  - CI/lint path runs standards audit automatically.
  - Local developer path has a single recommended command sequence.
  - Failures are actionable and mapped to docs.
- **Validation**:
  - `scripts/workflow-lint.sh`
  - `rg -n "cli-standards-audit|standards" DEVELOPMENT.md .github/workflows/ci.yml`

## Testing Strategy
- Unit: output-mode parsing, envelope serialization, error code mapping, redaction behavior.
- Integration: per-crate CLI contract tests for success/failure envelopes and compatibility mode behavior.
- E2E/manual: workflow smoke tests (`scripts/workflow-test.sh`) and representative live checks for API-backed CLIs.

## Risks & gotchas
- Existing workflows currently depend on JSON-first outputs; changing defaults without compatibility mode will break Alfred behavior.
- Rolling migration across many crates can introduce inconsistent envelope naming if shared helpers are not enforced early.
- Secret leakage can regress when upstream errors are passed through verbatim; redaction tests must be mandatory.
- External standards were authored in another repo context; local policy mapping must resolve conflicts explicitly.
- Publish-order updates can accidentally include unstable crates; publish policy needs explicit gating.

## Rollback plan
1. Keep compatibility mode as rollback switch for each crate and workflow script during transition.
2. Revert default-mode changes first while preserving new envelope tests/helpers to avoid full rework loss.
3. Roll back workflow script flag updates in lockstep if CLI output defaults are reverted.
4. Revert publish-order additions for crates not yet meeting contract and test gates.
5. Preserve standards-mapping docs and audit scripts so reattempts start from consistent policy baseline.
