# Plan: Crate documentation migration and governance policy

## Overview
This plan migrates crate-owned documentation out of root `docs/` into crate-local paths so each publishable crate owns and releases its own docs.
It also introduces enforceable documentation placement rules in the development standard, including automation gates for new crates and new markdown files.
The migration uses a compatibility-first approach: move to crate-local docs, keep root stubs during transition, then tighten enforcement only after link integrity is verified.
The target outcome is clear ownership, fewer cross-crate doc collisions, and predictable contributor behavior for all future crate/doc additions.

## Scope
- In scope: inventory and migration of crate-owned markdown currently under root `docs/`.
- In scope: creation of missing crate-owned contract docs discovered during inventory.
- In scope: development-standard updates so new crate/new document changes must follow placement rules.
- In scope: automated lint/CI checks that block policy regressions.
- Out of scope: functional changes to Rust runtime behavior.
- Out of scope: rewriting historical design decisions in archived plans beyond link/placement hygiene.

## Assumptions (if any)
1. Crate-owned contracts should live under crate-local docs paths (for example `crates/quote-cli/docs/` and `crates/market-cli/docs/`) even when their consumer is an Alfred workflow.
2. Root `docs/` remains for workspace-level architecture, release, standards, reports, and plans.
3. Some legacy references in historical plan files can be tolerated temporarily if root stub files preserve resolvability.
4. `docs/randomer-contract.md` is currently missing and must be created as part of migration completeness.

## Success Criteria
- All identified crate-owned docs have crate-local canonical paths and explicit owning crate.
- Root `docs/` contains only workspace-level docs plus temporary migration stubs.
- `DEVELOPMENT.md` explicitly defines required doc placement for new crate creation and new markdown additions.
- `scripts/docs-placement-audit.sh` exists, is wired into `scripts/workflow-lint.sh`, and runs in CI.
- `scripts/workflow-lint.sh`, `scripts/workflow-test.sh`, and `cargo test --workspace` pass after migration.

## Document Inventory To Reorganize

### Crate-owned docs currently in root `docs/`
- `docs/cambridge-dict-contract.md` -> `crates/cambridge-cli/docs/workflow-contract.md` (reference hits: 9)
- `docs/epoch-converter-contract.md` -> `crates/epoch-cli/docs/workflow-contract.md` (reference hits: 8)
- `docs/google-search-contract.md` -> `crates/brave-cli/docs/workflow-contract.md` (reference hits: 7)
- `docs/market-cli-contract.md` -> `crates/market-cli/docs/workflow-contract.md` (reference hits: 5)
- `docs/market-expression-rules.md` -> `crates/market-cli/docs/expression-rules.md` (reference hits: 0)
- `docs/memo-workflow-contract.md` -> `crates/memo-workflow-cli/docs/workflow-contract.md` (reference hits: 19)
- `docs/multi-timezone-contract.md` -> `crates/timezone-cli/docs/workflow-contract.md` (reference hits: 8)
- `docs/open-project-port-parity.md` -> `crates/workflow-cli/docs/open-project-port-parity.md` (reference hits: 9)
- `docs/quote-workflow-contract.md` -> `crates/quote-cli/docs/workflow-contract.md` (reference hits: 9)
- `docs/spotify-search-contract.md` -> `crates/spotify-cli/docs/workflow-contract.md` (reference hits: 11)
- `docs/weather-cli-contract.md` -> `crates/weather-cli/docs/workflow-contract.md` (reference hits: 5)
- `docs/wiki-search-contract.md` -> `crates/wiki-cli/docs/workflow-contract.md` (reference hits: 8)
- `docs/youtube-search-contract.md` -> `crates/youtube-cli/docs/workflow-contract.md` (reference hits: 6)
- Missing but referenced: `docs/randomer-contract.md` -> create `crates/randomer-cli/docs/workflow-contract.md` and transitional stub at `docs/randomer-contract.md` (reference hits: 11)

### Workspace-level docs that should remain in root `docs/`
- `docs/ALFRED_WORKFLOW_MONOREPO_DESIGN.md`
- `docs/ARCHITECTURE.md`
- `docs/RELEASE.md`
- `docs/WORKFLOW_GUIDE.md`
- `docs/specs/cli-standards-mapping.md`
- `docs/specs/cli-json-envelope-v1.md`
- `docs/specs/cli-error-code-registry.md`
- `docs/reports/cli-command-inventory.md`
- `docs/plans/*.md`

### High-impact reference hubs to update
- `TROUBLESHOOTING.md`
- `README.md`
- `docs/WORKFLOW_GUIDE.md`
- `crates/*/README.md`
- `workflows/*/README.md`
- `docs/plans/*.md` (link hygiene only; no semantic rewrites)

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 1.3 -> Task 2.1 -> Task 2.2 -> Task 2.4 -> Task 3.2 -> Task 3.3 -> Task 4.1`.
- Parallel track A: `Task 1.4` can run after `Task 1.1` in parallel with `Task 1.2`.
- Parallel track B: `Task 2.3` can run after `Task 1.3` in parallel with `Task 2.1`.
- Parallel track C: `Task 3.1` can run after `Task 1.1` in parallel with Sprint 2 migration tasks.
- Parallel track D: `Task 4.2` and `Task 4.3` can run after `Task 4.1`.

## Sprint 1: Policy baseline and migration manifest
**Goal**: freeze placement policy, ownership mapping, and destination layout before file moves.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/crate-docs-migration-governance-plan.md`, `find docs -type f -name '*.md' | sort`
- Verify: policy and inventory are explicit enough to execute migration deterministically.

### Task 1.1: Author crate-doc placement policy spec
- **Location**:
  - `docs/specs/crate-docs-placement-policy.md`
  - `DEVELOPMENT.md`
- **Description**: Define normative rules for where crate-specific docs and workspace-level docs must live, including ownership and exception handling for cross-crate topics.
- **Dependencies**:
  - none
- **Complexity**: 5
- **Acceptance criteria**:
  - Policy defines allowed root `docs/` categories and disallowed crate-specific patterns.
  - Policy defines canonical crate-doc paths with concrete examples (for example `crates/quote-cli/docs/workflow-contract.md` and `crates/market-cli/docs/expression-rules.md`).
  - Policy includes required steps for new crate creation and new markdown additions.
- **Validation**:
  - `test -f docs/specs/crate-docs-placement-policy.md`
  - `rg -n "crates/quote-cli/docs/workflow-contract.md|crates/market-cli/docs/expression-rules.md|workspace-level|new crate|new markdown" docs/specs/crate-docs-placement-policy.md`
  - `rg -n "crate-docs-placement-policy|Document placement" DEVELOPMENT.md`

### Task 1.2: Create migration inventory report with ownership and target paths
- **Location**:
  - `docs/reports/crate-doc-migration-inventory.md`
- **Description**: Record every crate-owned root doc, owner crate, target path, reference hotspots, and migration status so execution can be audited.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 6
- **Acceptance criteria**:
  - Report includes all 13 existing root crate docs plus missing `randomer` contract gap.
  - Each row has current path, owner crate, target path, and link-update scope.
  - Report marks migration order and risk level per document.
- **Validation**:
  - `test -f docs/reports/crate-doc-migration-inventory.md`
  - `rg -n "cambridge|epoch|google|market|memo|timezone|open-project|quote|spotify|weather|wiki|youtube|randomer" docs/reports/crate-doc-migration-inventory.md`
  - `rg -n "Risk level|Migration order|Owner crate|Target path|Status" docs/reports/crate-doc-migration-inventory.md`

### Task 1.3: Scaffold destination crate-doc directories and crate doc indexes
- **Location**:
  - `crates/brave-cli/docs/README.md`
  - `crates/cambridge-cli/docs/README.md`
  - `crates/epoch-cli/docs/README.md`
  - `crates/market-cli/docs/README.md`
  - `crates/memo-workflow-cli/docs/README.md`
  - `crates/quote-cli/docs/README.md`
  - `crates/randomer-cli/docs/README.md`
  - `crates/spotify-cli/docs/README.md`
  - `crates/timezone-cli/docs/README.md`
  - `crates/weather-cli/docs/README.md`
  - `crates/wiki-cli/docs/README.md`
  - `crates/workflow-cli/docs/README.md`
  - `crates/youtube-cli/docs/README.md`
- **Description**: Create crate-local docs directories with a small index file that declares ownership and links to canonical contract documents.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 6
- **Acceptance criteria**:
  - Every migration-target crate has `docs/README.md`.
  - Every index defines canonical document names and intended readers.
  - Index files are linked from crate root `README.md`.
- **Validation**:
  - `for p in crates/{brave-cli,cambridge-cli,epoch-cli,market-cli,memo-workflow-cli,quote-cli,randomer-cli,spotify-cli,timezone-cli,weather-cli,wiki-cli,workflow-cli,youtube-cli}/docs/README.md; do test -f "$p"; done`
  - `rg -n "## Documentation|docs/README.md" crates/*/README.md`

### Task 1.4: Baseline publishable non-CLI crate docs
- **Location**:
  - `crates/alfred-core/README.md`
  - `crates/alfred-core/docs/README.md`
  - `crates/alfred-plist/README.md`
  - `crates/alfred-plist/docs/README.md`
  - `crates/workflow-common/README.md`
  - `crates/workflow-common/docs/README.md`
- **Description**: Add minimum crate-level docs for publishable non-CLI crates so policy is uniformly applicable across independent crate publishing.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 4
- **Acceptance criteria**:
  - All publishable non-CLI crates have top-level README and docs index.
  - README files include crate purpose, public API surface summary, and validation commands.
  - Policy exceptions are not required for these crates.
- **Validation**:
  - `for p in crates/{alfred-core,alfred-plist,workflow-common}/README.md crates/{alfred-core,alfred-plist,workflow-common}/docs/README.md; do test -f "$p"; done`

## Sprint 2: Document migration and link compatibility
**Goal**: move crate-owned docs to crate-local canonical paths and preserve link continuity during transition.
**Demo/Validation**:
- Command(s): `bash scripts/docs-placement-audit.sh`, `rg -n "Moved to crates/" docs/*.md`
- Verify: canonical docs exist in crates and legacy root paths remain resolvable via stubs.

### Task 2.1: Move root crate-contract docs to canonical crate paths
- **Location**:
  - `docs/cambridge-dict-contract.md`
  - `docs/epoch-converter-contract.md`
  - `docs/google-search-contract.md`
  - `docs/market-cli-contract.md`
  - `docs/market-expression-rules.md`
  - `docs/memo-workflow-contract.md`
  - `docs/multi-timezone-contract.md`
  - `docs/open-project-port-parity.md`
  - `docs/quote-workflow-contract.md`
  - `docs/spotify-search-contract.md`
  - `docs/weather-cli-contract.md`
  - `docs/wiki-search-contract.md`
  - `docs/youtube-search-contract.md`
  - `crates/brave-cli/docs/workflow-contract.md`
  - `crates/cambridge-cli/docs/workflow-contract.md`
  - `crates/epoch-cli/docs/workflow-contract.md`
  - `crates/market-cli/docs/workflow-contract.md`
  - `crates/market-cli/docs/expression-rules.md`
  - `crates/memo-workflow-cli/docs/workflow-contract.md`
  - `crates/timezone-cli/docs/workflow-contract.md`
  - `crates/workflow-cli/docs/open-project-port-parity.md`
  - `crates/quote-cli/docs/workflow-contract.md`
  - `crates/spotify-cli/docs/workflow-contract.md`
  - `crates/weather-cli/docs/workflow-contract.md`
  - `crates/wiki-cli/docs/workflow-contract.md`
  - `crates/youtube-cli/docs/workflow-contract.md`
- **Description**: Relocate crate-owned contract/rules documents into crate-local docs with canonical naming and owner metadata.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 8
- **Acceptance criteria**:
  - All mapped canonical files exist under owning crates.
  - Canonical files preserve prior contract content and section headings.
  - Crate README links point to new canonical paths.
- **Validation**:
  - `for p in crates/{brave-cli,cambridge-cli,epoch-cli,memo-workflow-cli,quote-cli,randomer-cli,spotify-cli,timezone-cli,weather-cli,wiki-cli,youtube-cli}/docs/workflow-contract.md crates/market-cli/docs/workflow-contract.md crates/market-cli/docs/expression-rules.md crates/workflow-cli/docs/open-project-port-parity.md; do test -f "$p"; done`
  - `rg -n "^# (Cambridge Dict Contract|Epoch Converter Workflow Contract|Google Search Workflow Contract|Market CLI Contract|Market Expression Rules \\(Alfred v1\\)|Memo Add Workflow Contract|Multi Timezone Workflow Contract|Open Project Port Parity Contract|Quote Feed Workflow Contract|Spotify Search Workflow Contract|weather-cli contract|Wiki Search Workflow Contract|YouTube Search Workflow Contract)" crates/{brave-cli,cambridge-cli,epoch-cli,market-cli,memo-workflow-cli,timezone-cli,workflow-cli,quote-cli,spotify-cli,weather-cli,wiki-cli,youtube-cli}/docs/*.md`
  - `rg -n "docs/workflow-contract.md|docs/expression-rules.md|docs/open-project-port-parity.md" crates/*/README.md`

### Task 2.2: Add root compatibility stubs for moved files
- **Location**:
  - `docs/cambridge-dict-contract.md`
  - `docs/epoch-converter-contract.md`
  - `docs/google-search-contract.md`
  - `docs/market-cli-contract.md`
  - `docs/market-expression-rules.md`
  - `docs/memo-workflow-contract.md`
  - `docs/multi-timezone-contract.md`
  - `docs/open-project-port-parity.md`
  - `docs/quote-workflow-contract.md`
  - `docs/spotify-search-contract.md`
  - `docs/weather-cli-contract.md`
  - `docs/wiki-search-contract.md`
  - `docs/youtube-search-contract.md`
- **Description**: Replace moved root files with short stubs that point to canonical crate-local paths to prevent abrupt link breakage.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Each legacy root path exists with a clear "Moved to" pointer.
  - Stubs include migration date and target path.
  - No stub contains duplicate full contract body.
- **Validation**:
  - `for p in docs/{cambridge-dict-contract,epoch-converter-contract,google-search-contract,market-cli-contract,market-expression-rules,memo-workflow-contract,multi-timezone-contract,open-project-port-parity,quote-workflow-contract,spotify-search-contract,weather-cli-contract,wiki-search-contract,youtube-search-contract}.md; do test -f "$p"; done`
  - `rg -n "Moved to" docs/{cambridge-dict-contract,epoch-converter-contract,google-search-contract,market-cli-contract,market-expression-rules,memo-workflow-contract,multi-timezone-contract,open-project-port-parity,quote-workflow-contract,spotify-search-contract,weather-cli-contract,wiki-search-contract,youtube-search-contract}.md`

### Task 2.3: Create and migrate missing randomer contract
- **Location**:
  - `crates/randomer-cli/docs/workflow-contract.md`
  - `docs/randomer-contract.md`
  - `docs/plans/randomer-workflow-port-plan.md`
- **Description**: Materialize the missing randomer contract in crate-local docs and keep a root stub for legacy references.
- **Dependencies**:
  - Task 1.3
- **Complexity**: 6
- **Acceptance criteria**:
  - Canonical randomer contract exists under `crates/randomer-cli/docs/`.
  - Root stub exists and points to canonical file.
  - Randomer plan references are updated to canonical path where practical.
- **Validation**:
  - `test -f crates/randomer-cli/docs/workflow-contract.md`
  - `test -f docs/randomer-contract.md`
  - `rg -n "Moved to|workflow-contract.md" docs/randomer-contract.md docs/plans/randomer-workflow-port-plan.md`

### Task 2.4: Update high-impact references to canonical crate docs
- **Location**:
  - `README.md`
  - `DEVELOPMENT.md`
  - `TROUBLESHOOTING.md`
  - `docs/WORKFLOW_GUIDE.md`
  - `crates/alfred-core/README.md`
  - `crates/alfred-plist/README.md`
  - `crates/brave-cli/README.md`
  - `crates/cambridge-cli/README.md`
  - `crates/epoch-cli/README.md`
  - `crates/market-cli/README.md`
  - `crates/memo-workflow-cli/README.md`
  - `crates/quote-cli/README.md`
  - `crates/randomer-cli/README.md`
  - `crates/spotify-cli/README.md`
  - `crates/timezone-cli/README.md`
  - `crates/weather-cli/README.md`
  - `crates/wiki-cli/README.md`
  - `crates/workflow-cli/README.md`
  - `crates/workflow-common/README.md`
  - `crates/workflow-readme-cli/README.md`
  - `crates/youtube-cli/README.md`
  - `workflows/cambridge-dict/README.md`
  - `workflows/codex-cli/README.md`
  - `workflows/epoch-converter/README.md`
  - `workflows/google-search/README.md`
  - `workflows/market-expression/README.md`
  - `workflows/memo-add/README.md`
  - `workflows/multi-timezone/README.md`
  - `workflows/open-project/README.md`
  - `workflows/quote-feed/README.md`
  - `workflows/randomer/README.md`
  - `workflows/spotify-search/README.md`
  - `workflows/weather/README.md`
  - `workflows/wiki-search/README.md`
  - `workflows/youtube-search/README.md`
- **Description**: Update active operational docs and crate/workflow README links to canonical crate-doc paths while leaving archived history intact via stubs.
- **Dependencies**:
  - Task 2.2
  - Task 2.3
- **Complexity**: 7
- **Acceptance criteria**:
  - Operational docs no longer depend on legacy `docs/*-contract.md` paths.
  - Crate and workflow READMEs point to canonical crate docs when referencing contracts.
  - Remaining legacy references are limited to historical/archival contexts.
- **Validation**:
  - `rg -n "docs/(cambridge-dict-contract|epoch-converter-contract|google-search-contract|market-cli-contract|market-expression-rules|memo-workflow-contract|multi-timezone-contract|open-project-port-parity|quote-workflow-contract|spotify-search-contract|weather-cli-contract|wiki-search-contract|youtube-search-contract|randomer-contract)\.md" README.md DEVELOPMENT.md TROUBLESHOOTING.md docs/WORKFLOW_GUIDE.md crates/*/README.md workflows/*/README.md`
  - `rg -n "crates/(brave-cli|cambridge-cli|epoch-cli|market-cli|memo-workflow-cli|quote-cli|randomer-cli|spotify-cli|timezone-cli|weather-cli|wiki-cli|workflow-cli|youtube-cli)/docs/(workflow-contract\.md|expression-rules\.md|open-project-port-parity\.md)" README.md DEVELOPMENT.md TROUBLESHOOTING.md docs/WORKFLOW_GUIDE.md crates/*/README.md workflows/*/README.md`

## Sprint 3: Development-standard enforcement and CI gates
**Goal**: ensure all future crate/document additions follow placement rules by default.
**Demo/Validation**:
- Command(s): `bash scripts/docs-placement-audit.sh`, `scripts/workflow-lint.sh`
- Verify: policy violations fail fast locally and in CI.

### Task 3.1: Add mandatory documentation placement section to development standard
- **Location**:
  - `DEVELOPMENT.md`
- **Description**: Add a normative section that mandates doc ownership/path rules for new crates and new markdown files, including contributor checklist items.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Section explicitly defines required docs for new publishable crates.
  - Section explicitly forbids crate-owned docs under root `docs/`.
  - Section includes a required audit command before commit.
- **Validation**:
  - `rg -n "Documentation placement|new crate|new markdown|docs-placement-audit" DEVELOPMENT.md`

### Task 3.2: Implement docs-placement audit script
- **Location**:
  - `scripts/docs-placement-audit.sh`
  - `release/crates-io-publish-order.txt`
- **Description**: Implement a deterministic audit that checks crate-doc placement, required crate docs presence, and disallowed root-doc patterns for crate-specific files.
- **Dependencies**:
  - Task 1.2
  - Task 2.1
- **Complexity**: 8
- **Acceptance criteria**:
  - Script fails on newly introduced crate-specific root docs.
  - Script checks required README/docs-index presence for publishable crates.
  - Script output is CI-friendly with clear PASS/WARN/FAIL semantics.
- **Validation**:
  - `bash scripts/docs-placement-audit.sh`
  - `bash scripts/docs-placement-audit.sh --strict`
  - `bash -c 'set +e; tmp_file=\"docs/_audit_tmp_crate_owned_contract.md\"; printf \"# temp\\n\" > \"$tmp_file\"; bash scripts/docs-placement-audit.sh --strict >/dev/null 2>&1; rc=$?; rm -f \"$tmp_file\"; test \"$rc\" -ne 0'`
  - `rg -n "README.md|docs/README.md|publish|root docs|FAIL|WARN|PASS" scripts/docs-placement-audit.sh`

### Task 3.3: Wire docs-placement audit into lint and CI
- **Location**:
  - `scripts/workflow-lint.sh`
  - `.github/workflows/ci.yml`
- **Description**: Ensure docs-placement audit runs as part of standard lint entrypoints and CI validation pipeline.
- **Dependencies**:
  - Task 3.2
- **Complexity**: 4
- **Acceptance criteria**:
  - `scripts/workflow-lint.sh` runs `scripts/docs-placement-audit.sh`.
  - CI job contains an explicit docs-placement audit step (or relies on lint inclusion).
  - Failures block merge.
- **Validation**:
  - `rg -n "docs-placement-audit" scripts/workflow-lint.sh .github/workflows/ci.yml`
  - `scripts/workflow-lint.sh`

## Sprint 4: Link hygiene, hardening, and rollout closure
**Goal**: complete migration safely, verify no broken references, and define deprecation path for stubs.
**Demo/Validation**:
- Command(s): `cargo test --workspace`, `scripts/workflow-test.sh`, `scripts/workflow-lint.sh`
- Verify: full repository checks are green after migration and governance rollout.

### Task 4.1: Full regression and documentation link hygiene pass
- **Location**:
  - `README.md`
  - `TROUBLESHOOTING.md`
  - `docs/WORKFLOW_GUIDE.md`
  - `docs/reports/crate-doc-migration-inventory.md`
- **Description**: Run full validation, scan for stale high-impact links, and finalize inventory status as completed.
- **Dependencies**:
  - Task 2.4
  - Task 3.3
- **Complexity**: 5
- **Acceptance criteria**:
  - Lint, tests, and workflow test gates pass.
  - Inventory report marks each migration item as completed with final canonical path.
  - No stale high-impact links remain in operational docs.
- **Validation**:
  - `scripts/workflow-lint.sh`
  - `cargo test --workspace`
  - `scripts/workflow-test.sh`
  - `rg -n "docs/(cambridge-dict-contract|epoch-converter-contract|google-search-contract|market-cli-contract|market-expression-rules|memo-workflow-contract|multi-timezone-contract|open-project-port-parity|quote-workflow-contract|spotify-search-contract|weather-cli-contract|wiki-search-contract|youtube-search-contract|randomer-contract)\.md" README.md TROUBLESHOOTING.md docs/WORKFLOW_GUIDE.md`

### Task 4.2: Stub deprecation and removal decision
- **Location**:
  - `docs/specs/crate-docs-placement-policy.md`
  - `docs/reports/crate-doc-migration-inventory.md`
- **Description**: Decide and document whether root compatibility stubs are kept permanently or removed after a defined deprecation window.
- **Dependencies**:
  - Task 4.1
- **Complexity**: 3
- **Acceptance criteria**:
  - Policy defines stub lifecycle (`permanent redirects` or `sunset date`).
  - Inventory captures current status for each stub file.
  - Decision is referenced in development standards.
- **Validation**:
  - `rg -n "stub|deprecation|sunset|redirect" docs/specs/crate-docs-placement-policy.md docs/reports/crate-doc-migration-inventory.md DEVELOPMENT.md`

### Task 4.3: Publish migration summary for maintainers
- **Location**:
  - `docs/reports/crate-doc-migration-summary.md`
- **Description**: Publish a concise summary of what moved, what stayed, enforcement changes, and what contributors must do going forward.
- **Dependencies**:
  - Task 4.1
- **Complexity**: 3
- **Acceptance criteria**:
  - Summary includes before/after path examples and common contributor workflows.
  - Summary includes mandatory pre-commit checks.
  - Summary links to policy spec and inventory.
- **Validation**:
  - `test -f docs/reports/crate-doc-migration-summary.md`
  - `rg -n "before|after|pre-commit|docs-placement-audit|crate-docs-placement-policy" docs/reports/crate-doc-migration-summary.md`

## Testing Strategy
- Unit: shell-level checks for `scripts/docs-placement-audit.sh` conditions via deterministic repo state assertions.
- Integration: `scripts/workflow-lint.sh` (includes docs placement, formatting, clippy, existing standards audits).
- End-to-end: `scripts/workflow-test.sh` and `cargo test --workspace` to ensure doc path changes do not break workflow scripts/tests.
- Manual: spot-check canonical links from `README.md`, `TROUBLESHOOTING.md`, and representative workflow README files.

## Risks & gotchas
- High historical-link volume in `docs/plans/*.md` can cause churn if rewritten indiscriminately.
- Cross-crate docs (for example open-project parity) need explicit single-owner decisions to avoid split ownership.
- Introducing strict placement gates too early can block unrelated feature work; rollout should be phased.
- Non-CLI publishable crates currently have weak doc baselines and need initial scaffolding to pass policy.

## Rollback plan
- Keep migration in two commits: (1) file moves + stubs, (2) enforcement gates. Revert commit (2) first if rollout blocks contributors.
- If canonical-path migration causes breakage, temporarily restore previous root-doc bodies from history while preserving crate-local copies.
- If CI noise is too high, run `scripts/docs-placement-audit.sh` in warning mode first, then re-enable strict mode after cleanup.
- Preserve `docs/reports/crate-doc-migration-inventory.md` as source of truth during rollback to avoid losing ownership mapping.
