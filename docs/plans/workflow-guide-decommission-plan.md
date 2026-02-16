# Plan: Workflow Guide Decommission and Documentation Consolidation

## Overview
This plan removes `docs/WORKFLOW_GUIDE.md` and redistributes only necessary content to canonical owners:
global cross-workflow policy in `ALFRED_WORKFLOW_DEVELOPMENT.md`, and workflow-specific behavior in
`workflows/*/README.md` or `workflows/*/TROUBLESHOOTING.md`.
The migration explicitly avoids copy-forward duplication and drops stale or redundant content when a better
source already exists.
The result should be a single-source documentation model with no operational dependency on `docs/WORKFLOW_GUIDE.md`.

## Scope
- In scope: section-by-section decomposition of `docs/WORKFLOW_GUIDE.md` into `keep globally`, `move local`, or `delete`.
- In scope: migrate missing global policy content into `ALFRED_WORKFLOW_DEVELOPMENT.md` only when no equivalent canonical section exists.
- In scope: migrate workflow-specific details into `workflows/<workflow-id>/README.md` or `workflows/<workflow-id>/TROUBLESHOOTING.md` only when details are not already present.
- In scope: remove live references to `docs/WORKFLOW_GUIDE.md` from active docs and workflow runbooks.
- In scope: delete `docs/WORKFLOW_GUIDE.md` after migration validation.
- Out of scope: broad rewrite of historical planning artifacts under `docs/plans/*.md` unless those files are explicitly treated as active operator entry points.
- Out of scope: runtime code changes, packaging logic changes, or workflow behavior changes.

## Assumptions (if any)
1. `ALFRED_WORKFLOW_DEVELOPMENT.md` is the canonical global policy owner for cross-workflow troubleshooting and governance.
2. Workflow-specific environment variables, keyword flow, and runtime checks should be owned by each workflow directory (`workflows/<id>/`), not by a central encyclopedia doc.
3. If `docs/WORKFLOW_GUIDE.md` content conflicts with newer workflow-local docs (for example version drift), workflow-local docs win and conflicting guide content is removed rather than migrated.
4. Historical `docs/plans/*.md` references to `docs/WORKFLOW_GUIDE.md` can remain unless maintainers request archival cleanup in the same change.

## Success Criteria
- `docs/WORKFLOW_GUIDE.md` is removed.
- Active docs and workflow troubleshooting runbooks no longer require `docs/WORKFLOW_GUIDE.md` for navigation or rollback instructions.
- Global standards exist in one place (`ALFRED_WORKFLOW_DEVELOPMENT.md`) without duplicating workflow-local details.
- Workflow-local docs contain all workflow-specific details that were still uniquely useful in the removed guide.
- `agent-docs` strict preflight commands remain green after the migration.

## Impacted Files Inventory
- Primary targets:
  - `docs/WORKFLOW_GUIDE.md` (delete)
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
  - `workflows/*/README.md` (only workflows with identified gaps)
  - `workflows/*/TROUBLESHOOTING.md` (at least files currently referencing `docs/WORKFLOW_GUIDE.md`)
- Reference cleanup targets:
  - `docs/ALFRED_WORKFLOW_MONOREPO_DESIGN.md`
  - `docs/specs/crate-docs-placement-policy.md`
  - Any active index/entry docs that still mention `docs/WORKFLOW_GUIDE.md`
- Migration artifact target:
  - `docs/reports/workflow-guide-migration-matrix.md` (new; section-by-section decision table)

## Dependency & Parallelization Map
- Critical path:
  - Task 1.1 -> Task 1.2 -> Task 2.1 -> Task 3.1 -> Task 3.3 -> Task 4.1
- Parallel track A (after Task 2.1):
  - Task 2.2 and Task 2.3 can run in parallel.
- Parallel track B (after Task 3.1):
  - Task 3.2 and Task 3.4 can run in parallel.

## Sprint 1: Audit and migration design
**Goal**: Build an explicit, low-risk migration map so content moves only once and only to canonical owners.
**Demo/Validation**:
- Command(s): `nl -ba docs/WORKFLOW_GUIDE.md | rg '^(\\s*[0-9]+\\s+## )'`, `rg -n "docs/WORKFLOW_GUIDE\\.md" ALFRED_WORKFLOW_DEVELOPMENT.md workflows/*/TROUBLESHOOTING.md docs/ALFRED_WORKFLOW_MONOREPO_DESIGN.md docs/specs/crate-docs-placement-policy.md`
- Verify: all guide sections and live references are enumerated before edits.

### Task 1.1: Build section inventory and ownership classification
- **Location**:
  - `docs/WORKFLOW_GUIDE.md`
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
  - `README.md`
  - `workflows/_template/README.md`
  - `workflows/_template/TROUBLESHOOTING.md`
- **Description**: Enumerate all top-level sections in `docs/WORKFLOW_GUIDE.md` and classify each section as `global-policy`, `workflow-local`, or `drop` (duplicate/stale/non-canonical).
- **Dependencies**:
  - none
- **Complexity**: 4
- **Acceptance criteria**:
  - Every `##` section in `docs/WORKFLOW_GUIDE.md` has exactly one target decision.
  - Classification rationale is explicit for sections marked `drop`.
- **Validation**:
  - `nl -ba docs/WORKFLOW_GUIDE.md | rg '^(\\s*[0-9]+\\s+## )'`

### Task 1.2: Produce per-workflow delta matrix (move vs remove)
- **Location**:
  - `docs/WORKFLOW_GUIDE.md`
  - `workflows/open-project/README.md`
  - `workflows/youtube-search/README.md`
  - `workflows/google-search/README.md`
  - `workflows/netflix-search/README.md`
  - `workflows/wiki-search/README.md`
  - `workflows/bilibili-search/README.md`
  - `workflows/cambridge-dict/README.md`
  - `workflows/bangumi-search/README.md`
  - `workflows/epoch-converter/README.md`
  - `workflows/multi-timezone/README.md`
  - `workflows/quote-feed/README.md`
  - `workflows/memo-add/README.md`
  - `workflows/codex-cli/README.md`
  - `docs/reports/workflow-guide-migration-matrix.md`
  - `workflows/open-project/TROUBLESHOOTING.md`
  - `workflows/youtube-search/TROUBLESHOOTING.md`
  - `workflows/google-search/TROUBLESHOOTING.md`
  - `workflows/netflix-search/TROUBLESHOOTING.md`
  - `workflows/wiki-search/TROUBLESHOOTING.md`
  - `workflows/bilibili-search/TROUBLESHOOTING.md`
  - `workflows/cambridge-dict/TROUBLESHOOTING.md`
  - `workflows/bangumi-search/TROUBLESHOOTING.md`
  - `workflows/epoch-converter/TROUBLESHOOTING.md`
  - `workflows/multi-timezone/TROUBLESHOOTING.md`
  - `workflows/quote-feed/TROUBLESHOOTING.md`
  - `workflows/memo-add/TROUBLESHOOTING.md`
  - `workflows/codex-cli/TROUBLESHOOTING.md`
- **Description**: For each workflow section currently in `docs/WORKFLOW_GUIDE.md`, compare with workflow-local README/TROUBLESHOOTING and record only unique operational content that must migrate; mark duplicates and stale conflicts for removal. Capture decisions in `docs/reports/workflow-guide-migration-matrix.md` with columns for source section, owner, destination, decision (`move`/`drop`), and rationale.
- **Dependencies**:
  - Task 1.1
- **Complexity**: 7
- **Acceptance criteria**:
  - Each workflow has a clear decision: `no change`, `README patch`, `TROUBLESHOOTING patch`, or `drop-only`.
  - Known drift hotspots are explicitly flagged (for example version/capability mismatch between central guide and workflow-local docs).
  - `docs/reports/workflow-guide-migration-matrix.md` contains at least one decision row for every `##` section in `docs/WORKFLOW_GUIDE.md`.
- **Validation**:
  - `test -f docs/reports/workflow-guide-migration-matrix.md`
  - `rg -n "source section|owner|destination|decision|rationale" docs/reports/workflow-guide-migration-matrix.md`
  - `bash -c 'sections="$(rg -n "^## " docs/WORKFLOW_GUIDE.md | wc -l | tr -d " ")"; rows="$(rg -n "^\\| .*\\| .*\\| .*\\| (move|drop)\\| .*\\|$" docs/reports/workflow-guide-migration-matrix.md | wc -l | tr -d " ")"; test "$rows" -ge "$sections"'`
  - `for f in workflows/*/README.md; do rg -n "^## (Configuration|Keyword|Keywords|Validation|Troubleshooting)" "$f"; done`
  - `for f in workflows/*/TROUBLESHOOTING.md; do rg -n "^## (Quick operator checks|Common failures and actions|Validation|Rollback guidance)" "$f"; done`

### Task 1.3: Freeze no-duplication migration rules
- **Location**:
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
- **Description**: Define migration rules for this change in `ALFRED_WORKFLOW_DEVELOPMENT.md`: global doc stores cross-workflow standards only; workflow-local docs store behavior/config specifics; duplicated text is removed instead of mirrored; and central workflow-details encyclopedia patterns are disallowed.
- **Dependencies**:
  - Task 1.2
- **Complexity**: 3
- **Acceptance criteria**:
  - Migration rules can be applied mechanically during edits.
  - Rules prevent future reintroduction of a central workflow-details encyclopedia.
- **Validation**:
  - `rg -n "Layer 1|Layer 2|Out of scope|Reference policy|no-duplication|workflow-details encyclopedia" ALFRED_WORKFLOW_DEVELOPMENT.md`

## Sprint 2: Global doc consolidation and reference rewiring
**Goal**: Consolidate global-only content and remove active dependency on the guide path.
**Demo/Validation**:
- Command(s): `rg -n "docs/WORKFLOW_GUIDE\\.md" ALFRED_WORKFLOW_DEVELOPMENT.md docs/ALFRED_WORKFLOW_MONOREPO_DESIGN.md docs/specs/crate-docs-placement-policy.md workflows/*/TROUBLESHOOTING.md`
- Verify: active governance docs no longer require the removed file.

### Task 2.1: Migrate global-only sections into canonical global doc
- **Location**:
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
  - `docs/WORKFLOW_GUIDE.md`
- **Description**: Move only missing global contracts from the guide (for example workflow onboarding contract, manifest/readme-sync governance notes if still unique) into `ALFRED_WORKFLOW_DEVELOPMENT.md`; if equivalent canonical content already exists elsewhere, add references or drop redundant copy.
- **Dependencies**:
  - Task 1.2
  - Task 1.3
- **Complexity**: 6
- **Acceptance criteria**:
  - `ALFRED_WORKFLOW_DEVELOPMENT.md` gains only cross-workflow policy content.
  - No workflow-specific API/keyword/env-variable encyclopedia content is added to global policy.
- **Validation**:
  - `rg -n "Manifest|readme_source|workflow new|Troubleshooting operating model" ALFRED_WORKFLOW_DEVELOPMENT.md`
  - `! rg -n "YouTube Search workflow details|Google Search workflow details|Memo Add workflow details" ALFRED_WORKFLOW_DEVELOPMENT.md`

### Task 2.2: Remove live references from workflow troubleshooting rollback steps
- **Location**:
  - `workflows/bangumi-search/TROUBLESHOOTING.md`
  - `workflows/bilibili-search/TROUBLESHOOTING.md`
  - `workflows/cambridge-dict/TROUBLESHOOTING.md`
  - `workflows/multi-timezone/TROUBLESHOOTING.md`
- **Description**: Update rollback guidance bullets that currently require `docs/WORKFLOW_GUIDE.md`, replacing them with workflow-local/global-doc references only.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 4
- **Acceptance criteria**:
  - No rollback guidance in active workflow runbooks references `docs/WORKFLOW_GUIDE.md`.
  - Rollback checklists remain actionable after replacement.
- **Validation**:
  - `! rg -n "docs/WORKFLOW_GUIDE\\.md" workflows/*/TROUBLESHOOTING.md`

### Task 2.3: Update workspace-level policy docs that still name the guide
- **Location**:
  - `docs/ALFRED_WORKFLOW_MONOREPO_DESIGN.md`
  - `docs/specs/crate-docs-placement-policy.md`
- **Description**: Remove or replace mentions of `docs/WORKFLOW_GUIDE.md` in workspace-level architecture/policy docs so those docs remain accurate after deletion.
- **Dependencies**:
  - Task 2.1
- **Complexity**: 5
- **Acceptance criteria**:
  - Policy docs do not list a removed path as a canonical or allowed doc target.
  - Replacement references point to current canonical owners (`ALFRED_WORKFLOW_DEVELOPMENT.md`, workflow-local docs, or other active docs).
- **Validation**:
  - `! rg -n "docs/WORKFLOW_GUIDE\\.md" docs/ALFRED_WORKFLOW_MONOREPO_DESIGN.md docs/specs/crate-docs-placement-policy.md`

## Sprint 3: Workflow-local migration and guide removal
**Goal**: Complete workflow-local content landing and safely delete the central guide.
**Demo/Validation**:
- Command(s): `test ! -f docs/WORKFLOW_GUIDE.md`, `rg -n "workflow details|Operator validation checklist" workflows/*/README.md workflows/*/TROUBLESHOOTING.md`
- Verify: workflow-local docs now own required details and guide file is gone.

### Task 3.1: Apply minimal workflow-local patches from delta matrix
- **Location**:
  - `workflows/open-project/README.md`
  - `workflows/youtube-search/README.md`
  - `workflows/google-search/README.md`
  - `workflows/netflix-search/README.md`
  - `workflows/wiki-search/README.md`
  - `workflows/bilibili-search/README.md`
  - `workflows/cambridge-dict/README.md`
  - `workflows/bangumi-search/README.md`
  - `workflows/epoch-converter/README.md`
  - `workflows/multi-timezone/README.md`
  - `workflows/quote-feed/README.md`
  - `workflows/memo-add/README.md`
  - `workflows/codex-cli/README.md`
  - `workflows/open-project/TROUBLESHOOTING.md`
  - `workflows/youtube-search/TROUBLESHOOTING.md`
  - `workflows/google-search/TROUBLESHOOTING.md`
  - `workflows/netflix-search/TROUBLESHOOTING.md`
  - `workflows/wiki-search/TROUBLESHOOTING.md`
  - `workflows/bilibili-search/TROUBLESHOOTING.md`
  - `workflows/cambridge-dict/TROUBLESHOOTING.md`
  - `workflows/bangumi-search/TROUBLESHOOTING.md`
  - `workflows/epoch-converter/TROUBLESHOOTING.md`
  - `workflows/multi-timezone/TROUBLESHOOTING.md`
  - `workflows/quote-feed/TROUBLESHOOTING.md`
  - `workflows/memo-add/TROUBLESHOOTING.md`
  - `workflows/codex-cli/TROUBLESHOOTING.md`
  - `docs/WORKFLOW_GUIDE.md`
- **Description**: For workflows with true gaps identified in Task 1.2, migrate only non-duplicated, still-accurate operational details to local docs; skip workflows where local docs already cover the content.
- **Dependencies**:
  - Task 1.2
  - Task 2.1
- **Complexity**: 8
- **Acceptance criteria**:
  - Every retained workflow-specific fact from the old guide has a single local owner.
  - No local doc receives duplicate sections that restate existing content without adding operational value.
  - Conflicting stale statements from the old guide are dropped.
- **Validation**:
  - `for f in workflows/*/README.md; do rg -n "^## (Configuration|Keyword|Keywords|Troubleshooting)" "$f"; done`
  - `for f in workflows/*/TROUBLESHOOTING.md; do rg -n "^## (Quick operator checks|Common failures and actions|Validation|Rollback guidance)" "$f"; done`

### Task 3.2: Decide and apply policy for historical references
- **Location**:
  - `docs/plans/alfred-workflow-doc-governance-refactor-plan.md`
  - `docs/reports/crate-doc-migration-inventory.md`
- **Description**: Decide whether to leave historical references untouched or bulk-rewrite them; if untouched, document rationale in the change summary to avoid accidental scope expansion.
- **Dependencies**:
  - Task 2.3
- **Complexity**: 3
- **Acceptance criteria**:
  - Decision is explicit (`leave historical as-is` or `rewrite selected historical docs`).
  - Active docs remain clean regardless of historical choice.
- **Validation**:
  - `rg -n "docs/WORKFLOW_GUIDE\\.md" docs/plans docs/reports || true`

### Task 3.3: Delete `docs/WORKFLOW_GUIDE.md`
- **Location**:
  - `docs/WORKFLOW_GUIDE.md`
- **Description**: Remove the file after all required content migration and reference rewiring is complete.
- **Dependencies**:
  - Task 3.1
  - Task 2.2
  - Task 2.3
- **Complexity**: 2
- **Acceptance criteria**:
  - File is removed from repository.
  - No active path in documentation requires this file for operator workflow.
- **Validation**:
  - `test ! -f docs/WORKFLOW_GUIDE.md`

### Task 3.4: Re-run active-doc reference sweep
- **Location**:
  - `README.md`
  - `DEVELOPMENT.md`
  - `AGENT_DOCS.toml`
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
  - `workflows/_template/README.md`
  - `workflows/_template/TROUBLESHOOTING.md`
  - `workflows/codex-cli/README.md`
  - `workflows/codex-cli/TROUBLESHOOTING.md`
  - `workflows/multi-timezone/TROUBLESHOOTING.md`
  - `workflows/bangumi-search/TROUBLESHOOTING.md`
  - `docs/ALFRED_WORKFLOW_MONOREPO_DESIGN.md`
  - `docs/specs/crate-docs-placement-policy.md`
- **Description**: Ensure active docs do not retain stale references to the deleted guide path.
- **Dependencies**:
  - Task 3.3
- **Complexity**: 4
- **Acceptance criteria**:
  - Active-doc sweep for `docs/WORKFLOW_GUIDE.md` returns no matches.
  - Navigation remains coherent through `README.md` -> global standards -> workflow-local troubleshooting.
- **Validation**:
  - `! rg -n "docs/WORKFLOW_GUIDE\\.md" README.md DEVELOPMENT.md AGENT_DOCS.toml ALFRED_WORKFLOW_DEVELOPMENT.md workflows/*/README.md workflows/*/TROUBLESHOOTING.md docs/ALFRED_WORKFLOW_MONOREPO_DESIGN.md docs/specs/crate-docs-placement-policy.md`

## Sprint 4: Validation and rollout safety
**Goal**: Prove documentation preflight and navigation paths still work after decommission.
**Demo/Validation**:
- Command(s): `agent-docs resolve --context startup --strict --format checklist`, `agent-docs resolve --context project-dev --strict --format checklist`
- Verify: required-doc gate remains green with the new documentation topology.

### Task 4.1: Execute documentation validation gates
- **Location**:
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
  - `AGENT_DOCS.toml`
  - `workflows/_template/README.md`
  - `workflows/_template/TROUBLESHOOTING.md`
  - `workflows/codex-cli/README.md`
  - `workflows/codex-cli/TROUBLESHOOTING.md`
  - `workflows/multi-timezone/TROUBLESHOOTING.md`
  - `workflows/bangumi-search/TROUBLESHOOTING.md`
- **Description**: Run strict preflight and text-search checks to ensure required docs and navigation conventions remain valid.
- **Dependencies**:
  - Task 3.4
- **Complexity**: 4
- **Acceptance criteria**:
  - Both strict `agent-docs resolve` commands pass.
  - Active-doc reference sweep for deleted path is empty.
- **Validation**:
  - `agent-docs resolve --context startup --strict --format checklist`
  - `agent-docs resolve --context project-dev --strict --format checklist`
  - `! rg -n "docs/WORKFLOW_GUIDE\\.md" README.md DEVELOPMENT.md AGENT_DOCS.toml ALFRED_WORKFLOW_DEVELOPMENT.md workflows/*/README.md workflows/*/TROUBLESHOOTING.md docs/ALFRED_WORKFLOW_MONOREPO_DESIGN.md docs/specs/crate-docs-placement-policy.md`

### Task 4.2: Perform operator navigation rehearsal
- **Location**:
  - `README.md`
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`
  - `workflows/bangumi-search/README.md`
  - `workflows/bangumi-search/TROUBLESHOOTING.md`
- **Description**: Validate operator path manually: start from repository README, reach global standards, then jump to a workflow-local troubleshooting guide and execute at least one documented check command.
- **Dependencies**:
  - Task 4.1
- **Complexity**: 3
- **Acceptance criteria**:
  - Operator can locate global and local docs within three navigation steps.
  - At least one workflow-local check command runs as documented and exits with status `0`.
- **Validation**:
  - `rg -n "ALFRED_WORKFLOW_DEVELOPMENT\\.md|TROUBLESHOOTING\\.md" README.md`
  - `bash workflows/bangumi-search/tests/smoke.sh`

## Testing Strategy
- Unit: N/A (documentation-only migration).
- Integration:
  - Path/reference integrity checks with `rg`.
  - Required-doc gates with `agent-docs resolve --context startup/project-dev --strict --format checklist`.
- E2E/manual:
  - Documentation navigation rehearsal from README to global standards to workflow-local troubleshooting.
  - One representative workflow-local operator command execution.

## Risks & gotchas
- Risk: Stale central-guide statements may conflict with newer workflow-local docs.
  - Mitigation: Treat workflow-local docs as source of truth and drop conflicting guide text.
- Risk: Over-migration introduces duplicated content across global and local docs.
  - Mitigation: Enforce Task 1.3 no-duplication rules before applying patches.
- Risk: Hidden references to `docs/WORKFLOW_GUIDE.md` remain in active docs.
  - Mitigation: Run explicit active-doc sweep (`Task 3.4` and `Task 4.1`) with strict path list.
- Risk: Historical docs still reference deleted path and may confuse maintainers.
  - Mitigation: Make an explicit historical-doc policy decision in Task 3.2 and record it in implementation notes.

## Rollback plan
1. If migration breaks documentation navigation, immediately restore `docs/WORKFLOW_GUIDE.md` from the previous commit as a temporary compatibility file.
2. Revert the specific doc patches that introduced broken references (`ALFRED_WORKFLOW_DEVELOPMENT.md`, workflow-local docs, policy docs).
3. Re-run `agent-docs` strict checks and active-doc reference sweep before attempting a second migration pass.
4. Re-apply migration in smaller batches (global first, then workflow-local) to isolate failures quickly.
