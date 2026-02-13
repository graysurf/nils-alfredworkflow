# Plan: Alfred Workflow Documentation Governance Refactor (Global Standards + Per-Workflow Troubleshooting)

## Overview
This plan replaces the current root-level `TROUBLESHOOTING.md` model with a two-layer structure: one global standards document plus per-workflow troubleshooting files.
Cross-workflow concerns (for example Gatekeeper/quarantine, `alfredfiltersresults`, and Script Filter wiring) will be centralized in a new root document.
Workflow-specific symptoms, causes, operator steps, and rollback notes will move to `workflows/<id>/TROUBLESHOOTING.md`.
`DEVELOPMENT.md` will return to its core role: development workflow, test gates, and tooling usage.

## Scope
- In scope: create a root-level Alfred workflow global development standards document (replacing root troubleshooting as the primary troubleshooting home).
- In scope: split workflow-specific troubleshooting into `workflows/<id>/TROUBLESHOOTING.md`.
- In scope: update `AGENT_DOCS.toml` required docs config so strict preflight no longer depends on the legacy path.
- In scope: update troubleshooting navigation in `README.md`, `docs/WORKFLOW_GUIDE.md`, and workflow READMEs.
- In scope: keep `DEVELOPMENT.md` focused on workflow development flow, lint/test/packaging/acceptance guidance.
- Out of scope: changing workflow runtime behavior, CLI contracts, or smoke test logic.
- Out of scope: full rewrite of historical references inside `docs/plans/*.md` and legacy reports (audit and policy decision only).

## Assumptions (if any)
1. The new root file name is `ALFRED_WORKFLOW_DEVELOPMENT.md` (if maintainers prefer a different name, path references can be updated).
2. Every production workflow directory (excluding `workflows/_template`) should own a local `TROUBLESHOOTING.md`, starting from a minimum viable template.
3. Historical plan/report mentions of `TROUBLESHOOTING.md` may remain if they do not break lint, navigation, or preflight gates.

## Success Criteria
- Root troubleshooting is no longer maintained as the primary entry point; it is replaced by a global standards doc plus per-workflow troubleshooting docs.
- `AGENT_DOCS.toml` `project-dev` required docs no longer point to `TROUBLESHOOTING.md`.
- Every workflow README can link to its local troubleshooting document.
- `DEVELOPMENT.md` is focused on development workflow and test/validation strategy, not troubleshooting encyclopedia content.
- `agent-docs resolve --context startup --strict --format checklist` and `agent-docs resolve --context project-dev --strict --format checklist` continue to pass.

## Impacted Files Inventory
- Core governance docs (must change):
  - `AGENT_DOCS.toml`
  - `README.md`
  - `DEVELOPMENT.md`
  - `docs/WORKFLOW_GUIDE.md`
  - `TROUBLESHOOTING.md` (remove after migration)
  - `ALFRED_WORKFLOW_DEVELOPMENT.md` (new)
- Workflow troubleshooting targets (new/update):
  - `workflows/open-project/TROUBLESHOOTING.md`
  - `workflows/youtube-search/TROUBLESHOOTING.md`
  - `workflows/google-search/TROUBLESHOOTING.md`
  - `workflows/wiki-search/TROUBLESHOOTING.md`
  - `workflows/epoch-converter/TROUBLESHOOTING.md`
  - `workflows/multi-timezone/TROUBLESHOOTING.md`
  - `workflows/quote-feed/TROUBLESHOOTING.md`
  - `workflows/memo-add/TROUBLESHOOTING.md`
  - `workflows/cambridge-dict/TROUBLESHOOTING.md`
  - `workflows/codex-cli/TROUBLESHOOTING.md`
  - `workflows/market-expression/TROUBLESHOOTING.md`
  - `workflows/spotify-search/TROUBLESHOOTING.md`
  - `workflows/weather/TROUBLESHOOTING.md`
  - `workflows/randomer/TROUBLESHOOTING.md`
- Workflow README touch points (expected):
  - `workflows/open-project/README.md`
  - `workflows/youtube-search/README.md`
  - `workflows/google-search/README.md`
  - `workflows/wiki-search/README.md`
  - `workflows/epoch-converter/README.md`
  - `workflows/multi-timezone/README.md`
  - `workflows/quote-feed/README.md`
  - `workflows/memo-add/README.md`
  - `workflows/cambridge-dict/README.md`
  - `workflows/codex-cli/README.md`
  - `workflows/market-expression/README.md`
  - `workflows/spotify-search/README.md`
  - `workflows/weather/README.md`
  - `workflows/randomer/README.md`
- Template / scaffolding updates:
  - `workflows/_template/README.md`
  - `workflows/_template/TROUBLESHOOTING.md` (new)
- Historical reference audit set (decision-based):
  - `docs/reports/crate-doc-migration-inventory.md`
  - `docs/plans/*.md` (all files matched by `rg -n "TROUBLESHOOTING\\.md" docs/plans`)

## Dependency & Parallelization Map
- Critical path: `Task 1.1 -> Task 1.2 -> Task 2.1 -> Task 3.1 -> Task 3.2 -> Task 4.1`.
- Parallel track A: `Task 2.2` and `Task 2.3` can run in parallel after `Task 2.1`.
- Parallel track B: `Task 3.3` can run in parallel with `Task 3.2` after `Task 3.1`.
- Parallel track C: `Task 4.2` can run in parallel with `Task 4.1`.

## Sprint 1: Governance design and migration mapping
**Goal**: Define document ownership boundaries, naming, and migration mapping before implementation to avoid rework.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/alfred-workflow-doc-governance-refactor-plan.md`, `rg -n "TROUBLESHOOTING\\.md" AGENT_DOCS.toml README.md DEVELOPMENT.md docs/WORKFLOW_GUIDE.md`
- Verify: Paths and responsibility boundaries are explicit and machine-checkable.

### Task 1.1: Define doc ownership model and file naming
- **Location**:
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
  - `DEVELOPMENT.md`
  - `workflows/_template/TROUBLESHOOTING.md`
  - `workflows/_template/README.md`
- **Description**: Define a clear three-layer ownership model: global standards (cross-workflow), workflow-specific troubleshooting, and development flow/test standards. Also define naming rules and allowed content for each layer.
- **Dependencies**:
  - none
- **Complexity**: 4
- **Acceptance criteria**:
  - The three documentation layers are complementary and non-overlapping.
  - New workflow scaffolding clearly indicates troubleshooting as a required artifact.
- **Validation**:
  - `rg -n "In scope|Out of scope|Troubleshooting|Validation" docs/plans/alfred-workflow-doc-governance-refactor-plan.md`

### Task 1.2: Build migration mapping from root troubleshooting to target destinations
- **Location**:
  - `TROUBLESHOOTING.md`
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
  - `workflows/open-project/TROUBLESHOOTING.md`
  - `workflows/youtube-search/TROUBLESHOOTING.md`
  - `workflows/google-search/TROUBLESHOOTING.md`
  - `workflows/wiki-search/TROUBLESHOOTING.md`
  - `workflows/epoch-converter/TROUBLESHOOTING.md`
  - `workflows/multi-timezone/TROUBLESHOOTING.md`
  - `workflows/quote-feed/TROUBLESHOOTING.md`
  - `workflows/memo-add/TROUBLESHOOTING.md`
  - `workflows/cambridge-dict/TROUBLESHOOTING.md`
- **Description**: Build a section-by-section migration map (global vs workflow-specific), including current sections for `open-project`, `youtube-search`, `google-search`, `wiki-search`, `epoch-converter`, `multi-timezone`, `quote-feed`, `memo-add`, and `cambridge-dict`.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 6
- **Acceptance criteria**:
  - Every section in the current root file maps to a destination (no orphan sections).
  - Shared concerns are not duplicated across all 14 workflow troubleshooting files.
- **Validation**:
  - `rg -n "^## Workflow: " TROUBLESHOOTING.md`
  - `ls -1 workflows | rg -v "^_"`

## Sprint 2: Create new docs and split troubleshooting content
**Goal**: Complete physical content migration and produce an immediately operable documentation structure.
**Demo/Validation**:
- Command(s): `find workflows -maxdepth 2 -name TROUBLESHOOTING.md | sort`, `test -f ALFRED_WORKFLOW_DEVELOPMENT.md`
- Verify: Global and per-workflow troubleshooting docs both exist and are readable.

### Task 2.1: Author root global Alfred workflow development standard
- **Location**:
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
- **Description**: Create a global standards document for shared concerns: Gatekeeper/quarantine, `alfredfiltersresults`, `config.type/scriptfile`, Script Filter queue policy, installed-workflow debug checklist, and generic rollback principles.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 5
- **Acceptance criteria**:
  - The document does not contain workflow-specific API key/query cases.
  - The document can be referenced by all workflow troubleshooting files for shared guidance.
- **Validation**:
  - `rg -n "Gatekeeper|quarantine|alfredfiltersresults|config.type|scriptfile|queue" ALFRED_WORKFLOW_DEVELOPMENT.md`

### Task 2.2: Split existing troubleshooting sections into covered workflow docs
- **Location**:
  - `workflows/open-project/TROUBLESHOOTING.md`
  - `workflows/youtube-search/TROUBLESHOOTING.md`
  - `workflows/google-search/TROUBLESHOOTING.md`
  - `workflows/wiki-search/TROUBLESHOOTING.md`
  - `workflows/epoch-converter/TROUBLESHOOTING.md`
  - `workflows/multi-timezone/TROUBLESHOOTING.md`
  - `workflows/quote-feed/TROUBLESHOOTING.md`
  - `workflows/memo-add/TROUBLESHOOTING.md`
  - `workflows/cambridge-dict/TROUBLESHOOTING.md`
- **Description**: Split current workflow sections from the root troubleshooting file into per-workflow files, preserving symptom/cause/action/rollback structure, and replacing shared material with references to global standards.
- **Dependencies**:
  - Task 1.2
  - Task 2.1
- **Complexity**: 8
- **Acceptance criteria**:
  - All 9 existing workflow sections are moved to their corresponding workflow files.
  - Each migrated file includes executable operator commands and verification steps (not only conceptual text).
  - Each migrated file includes at least `Quick operator checks`, `Common failures and actions`, and `Rollback guidance`, plus a link to `ALFRED_WORKFLOW_DEVELOPMENT.md`.
- **Validation**:
  - `for w in open-project youtube-search google-search wiki-search epoch-converter multi-timezone quote-feed memo-add cambridge-dict; do test -f "workflows/$w/TROUBLESHOOTING.md"; done`
  - `rg -n "^## Common failures and actions|^### Rollback guidance" workflows/{open-project,youtube-search,google-search,wiki-search,epoch-converter,multi-timezone,quote-feed,memo-add,cambridge-dict}/TROUBLESHOOTING.md`
  - `for w in open-project youtube-search google-search wiki-search epoch-converter multi-timezone quote-feed memo-add cambridge-dict; do rg -n "Quick operator checks|Common failures and actions|Rollback guidance|ALFRED_WORKFLOW_DEVELOPMENT\\.md" "workflows/$w/TROUBLESHOOTING.md"; done`

### Task 2.3: Create baseline troubleshooting docs for uncovered workflows
- **Location**:
  - `workflows/codex-cli/TROUBLESHOOTING.md`
  - `workflows/market-expression/TROUBLESHOOTING.md`
  - `workflows/spotify-search/TROUBLESHOOTING.md`
  - `workflows/weather/TROUBLESHOOTING.md`
  - `workflows/randomer/TROUBLESHOOTING.md`
  - `workflows/_template/TROUBLESHOOTING.md`
- **Description**: Create minimum-viable troubleshooting docs for currently uncovered workflows (quick checks + common failures + validation + rollback), and add the same structure to template scaffolding.
- **Dependencies**:
  - Task 1.2
  - Task 2.1
- **Complexity**: 7
- **Acceptance criteria**:
  - All 5 currently uncovered workflows receive troubleshooting docs.
  - `_template` includes a troubleshooting template section to prevent future gaps.
  - Each of the 5 baseline files includes at least `Quick operator checks`, `Common failures and actions`, `Validation`, and `Rollback guidance`.
- **Validation**:
  - `for w in codex-cli market-expression spotify-search weather randomer; do test -f "workflows/$w/TROUBLESHOOTING.md"; done`
  - `test -f workflows/_template/TROUBLESHOOTING.md`
  - `for w in codex-cli market-expression spotify-search weather randomer; do rg -n "Quick operator checks|Common failures and actions|Validation|Rollback guidance" "workflows/$w/TROUBLESHOOTING.md"; done`

### Task 2.4: Retire root troubleshooting file after successful split
- **Location**:
  - `TROUBLESHOOTING.md`
- **Description**: Remove root `TROUBLESHOOTING.md` only after content migration and link rewiring are complete, to avoid dual-source maintenance.
- **Dependencies**:
  - Task 2.2
  - Task 2.3
- **Complexity**: 3
- **Acceptance criteria**:
  - Root `TROUBLESHOOTING.md` no longer exists.
  - Strict preflight remains green (with Task 3.1 completed).
- **Validation**:
  - `test ! -f TROUBLESHOOTING.md`

## Sprint 3: Rewire references and enforce new governance
**Goal**: Ensure all entry points and required-doc gates point to the new structure so operators can navigate without ambiguity.
**Demo/Validation**:
- Command(s): `rg -n "TROUBLESHOOTING\\.md" AGENT_DOCS.toml README.md DEVELOPMENT.md docs/WORKFLOW_GUIDE.md workflows/*/README.md`
- Verify: Primary docs no longer point to root troubleshooting and now route to correct new locations.

### Task 3.1: Update required docs contract for project-dev preflight
- **Location**:
  - `AGENT_DOCS.toml`
- **Description**: Replace `project-dev` required doc path from `TROUBLESHOOTING.md` to the new global standards file (`ALFRED_WORKFLOW_DEVELOPMENT.md`) and update notes to match new ownership boundaries.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 5
- **Acceptance criteria**:
  - `agent-docs resolve --context project-dev --strict --format checklist` passes and shows the new path.
  - Required-doc semantics reflect the new governance model.
- **Validation**:
  - `agent-docs resolve --context project-dev --strict --format checklist`
  - `rg -n "ALFRED_WORKFLOW_DEVELOPMENT\\.md|project-dev" AGENT_DOCS.toml`

### Task 3.2: Update top-level and guide entry points
- **Location**:
  - `README.md`
  - `docs/WORKFLOW_GUIDE.md`
- **Description**: Add new top-level navigation for global standards plus per-workflow troubleshooting routes, and remove old root troubleshooting guidance.
- **Dependencies**:
  - Task 2.2
  - Task 2.3
- **Complexity**: 5
- **Acceptance criteria**:
  - A new contributor can locate the right troubleshooting file from `README.md` quickly.
  - `docs/WORKFLOW_GUIDE.md` exposes a consistent operating model for troubleshooting navigation.
- **Validation**:
  - `rg -n "Troubleshooting|ALFRED_WORKFLOW_DEVELOPMENT|workflows/.*/TROUBLESHOOTING\\.md" README.md docs/WORKFLOW_GUIDE.md`

### Task 3.3: Restore DEVELOPMENT.md responsibility boundaries
- **Location**:
  - `DEVELOPMENT.md`
- **Description**: Remove deep troubleshooting content and workflow-specific troubleshooting pointers from `DEVELOPMENT.md`; keep development flow, lint/test/pack gates, and macOS acceptance instructions, with links to the new docs.
- **Dependencies**:
  - Task 2.1
  - Task 3.2
- **Complexity**: 6
- **Acceptance criteria**:
  - `DEVELOPMENT.md` is no longer used as a troubleshooting knowledge base.
  - Pre-commit and validation workflow guidance remains complete and executable.
- **Validation**:
  - `rg -n "Required before committing|workflow-lint|workflow-test|workflow-pack|Gatekeeper" DEVELOPMENT.md`
  - `rg -n "TROUBLESHOOTING\\.md section" DEVELOPMENT.md`

### Task 3.4: Add workflow-local troubleshooting links in each workflow README
- **Location**:
  - `workflows/open-project/README.md`
  - `workflows/youtube-search/README.md`
  - `workflows/google-search/README.md`
  - `workflows/wiki-search/README.md`
  - `workflows/epoch-converter/README.md`
  - `workflows/multi-timezone/README.md`
  - `workflows/quote-feed/README.md`
  - `workflows/memo-add/README.md`
  - `workflows/cambridge-dict/README.md`
  - `workflows/codex-cli/README.md`
  - `workflows/market-expression/README.md`
  - `workflows/spotify-search/README.md`
  - `workflows/weather/README.md`
  - `workflows/randomer/README.md`
  - `workflows/_template/README.md`
- **Description**: Add a local troubleshooting link to every workflow README so operators do not need to jump back to root docs; update template README to enforce the same convention.
- **Dependencies**:
  - Task 2.2
  - Task 2.3
- **Complexity**: 7
- **Acceptance criteria**:
  - Every workflow README includes a stable section/link to local troubleshooting.
  - `_template` README documents troubleshooting as a required section for new workflows.
- **Validation**:
  - `rg -n "Troubleshooting|\\(\\./TROUBLESHOOTING\\.md\\)" workflows/*/README.md`

## Sprint 4: Validation, migration safeguards, and rollout
**Goal**: Validate that the new governance model is operable long-term and includes a practical rollback path.
**Demo/Validation**:
- Command(s): `plan-tooling validate --file docs/plans/alfred-workflow-doc-governance-refactor-plan.md`, `agent-docs resolve --context startup --strict --format checklist`, `agent-docs resolve --context project-dev --strict --format checklist`
- Verify: Plan and required-doc gates are aligned with the new topology.

### Task 4.1: Run governance-level checks after doc migration
- **Location**:
  - `AGENT_DOCS.toml`
  - `README.md`
  - `DEVELOPMENT.md`
  - `docs/WORKFLOW_GUIDE.md`
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
  - `workflows/open-project/TROUBLESHOOTING.md`
  - `workflows/youtube-search/TROUBLESHOOTING.md`
  - `workflows/google-search/TROUBLESHOOTING.md`
  - `workflows/wiki-search/TROUBLESHOOTING.md`
  - `workflows/epoch-converter/TROUBLESHOOTING.md`
  - `workflows/multi-timezone/TROUBLESHOOTING.md`
  - `workflows/quote-feed/TROUBLESHOOTING.md`
  - `workflows/memo-add/TROUBLESHOOTING.md`
  - `workflows/cambridge-dict/TROUBLESHOOTING.md`
  - `workflows/codex-cli/TROUBLESHOOTING.md`
  - `workflows/market-expression/TROUBLESHOOTING.md`
  - `workflows/spotify-search/TROUBLESHOOTING.md`
  - `workflows/weather/TROUBLESHOOTING.md`
  - `workflows/randomer/TROUBLESHOOTING.md`
- **Description**: Run preflight gates plus doc scans to ensure no primary flow still depends on root troubleshooting and that navigation is complete.
- **Dependencies**:
  - Task 3.1
  - Task 3.2
  - Task 3.3
  - Task 3.4
- **Complexity**: 4
- **Acceptance criteria**:
  - Strict preflight checks pass.
  - Primary docs no longer reference root `TROUBLESHOOTING.md`.
- **Validation**:
  - `agent-docs resolve --context startup --strict --format checklist`
  - `agent-docs resolve --context project-dev --strict --format checklist`
  - `! rg -n "TROUBLESHOOTING\\.md" AGENT_DOCS.toml README.md DEVELOPMENT.md docs/WORKFLOW_GUIDE.md`

### Task 4.2: Audit historical references and decide policy
- **Location**:
  - `docs/reports/crate-doc-migration-inventory.md`
  - `docs/plans/crate-docs-migration-governance-plan.md`
  - `docs/plans/script-filter-input-throttle-shared-plan.md`
  - `docs/plans/google-search-workflow-plan.md`
- **Description**: Audit historical references to root troubleshooting and record one explicit policy: either preserve history as-is or perform batch updates.
- **Dependencies**:
  - Task 4.1
- **Complexity**: 5
- **Acceptance criteria**:
  - One explicit and documented policy exists for historical references.
  - If preserving history, the rationale is documented in global standards or README.
- **Validation**:
  - `rg -n "TROUBLESHOOTING\\.md" docs/reports/crate-doc-migration-inventory.md docs/plans`

### Task 4.3: Dry-run rollout and rollback rehearsal
- **Location**:
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
  - `README.md`
  - `AGENT_DOCS.toml`
- **Description**: Perform a documentation-level rollout rehearsal (README -> workflow troubleshooting -> preflight) and verify rollback is practical.
- **Dependencies**:
  - Task 4.1
- **Complexity**: 4
- **Acceptance criteria**:
  - A maintainer can complete navigation and issue-localization flow in under 3 minutes.
  - Rollback can restore previous entry points in a single revert.
- **Validation**:
  - `git diff --name-only`
  - `agent-docs resolve --context project-dev --strict --format checklist`

## Testing Strategy
- Unit:
  - No code-level unit tests are required for governance-only doc refactoring; rely on `plan-tooling validate` and structural scans.
- Integration:
  - Use `agent-docs resolve` to validate required-doc contracts and preflight continuity.
  - Use `rg` scans over primary entry docs (README, DEVELOPMENT, WORKFLOW_GUIDE, workflow READMEs) to enforce routing consistency.
- E2E/manual:
  - Manually navigate from `README.md` to a workflow README and then to local troubleshooting, verifying fast operator discoverability.

## Risks & gotchas
- If `AGENT_DOCS.toml` is not updated in sync, removing root `TROUBLESHOOTING.md` will fail strict preflight.
- If shared guidance is duplicated into every workflow troubleshooting file, drift will reappear quickly.
- Bulk edits across 14 workflow READMEs and troubleshooting files increase risk of link/section naming inconsistency.
- Without an explicit policy for historical references, old root paths will continue to create noise in search results.

## Rollback plan
- Immediate rollback to previous entry model (single commit revert):
  - Restore root `TROUBLESHOOTING.md` and previous `AGENT_DOCS.toml` required-doc path.
  - Revert new navigation updates in `README.md`, `DEVELOPMENT.md`, and `docs/WORKFLOW_GUIDE.md`.
- Keep newly created workflow troubleshooting files but hide them from entry points to prevent data loss while re-planning.
- Post-rollback verification commands:
  - `agent-docs resolve --context startup --strict --format checklist`
  - `agent-docs resolve --context project-dev --strict --format checklist`
