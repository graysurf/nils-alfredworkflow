# Crate Documentation Placement Policy

## Scope

- This policy applies to all markdown documentation in this repository.
- The goal is to keep crate-owned docs with the owning crate and keep root `docs/` workspace-level.

## Normative Rules

### Allowed root docs categories (workspace-level only)

- `docs/ARCHITECTURE.md`, `ALFRED_WORKFLOW_DEVELOPMENT.md`, and similar repository-wide architecture or workflow guides.
- `docs/specs/*.md` for shared standards that are not owned by a single crate.
- `docs/plans/*.md` for implementation planning.
- `docs/reports/*.md` for audit/inventory/report outputs.
- `docs/RELEASE.md` and other repository-wide release/operations documents.

### Disallowed root docs patterns (crate-specific)

- Crate-specific contracts, rules, or behavior docs must not be added under root `docs/`.
- Disallowed examples:
  - `docs/*-contract.md` when the content is owned by one crate.
  - `docs/*-workflow-contract.md` when the content is owned by one crate.
  - `docs/*-expression-rules.md` when the content is owned by one crate.
- Root compatibility stubs are not allowed. Migrate references directly to canonical crate docs and remove the legacy root file.

### Legacy root doc lifecycle decision

- Decision: legacy root crate-specific docs are removed after references are migrated.
- Migration completion requires deleting the root legacy file and updating all references to canonical crate paths.
- Re-introducing root compatibility stubs is out of scope unless this policy is explicitly changed.

## Canonical Crate-Doc Paths

- Crate-specific markdown must live under `crates/<crate-name>/docs/`.
- Canonical examples:
  - `crates/quote-cli/docs/workflow-contract.md`
  - `crates/market-cli/docs/expression-rules.md`
- Each crate must also include `crates/<crate-name>/docs/README.md` as the local documentation index.

## Ownership And Cross-Crate Exceptions

- Default owner of a crate-specific document is the owning crate maintainers.
- Cross-crate topics follow these rules:
  - If one crate is the primary owner, keep the canonical document in that crate and link from other crates.
  - If the topic is truly workspace-level, place it under root `docs/` in an allowed category and explicitly mark it as workspace-level.
- Any exception must include PR rationale describing owner, scope, and why canonical crate placement is not sufficient.

## Required Steps

### Required for new crate creation

1. Create `crates/<crate-name>/README.md`.
2. Create `crates/<crate-name>/docs/README.md`.
3. Add required crate-specific docs under `crates/<crate-name>/docs/` (for example `workflow-contract.md`).
4. Link crate docs from `crates/<crate-name>/README.md`.
5. Do not add new crate-specific markdown under root `docs/`.

### Required for new markdown additions

1. Classify the document before adding it: workspace-level or crate-specific.
2. If crate-specific, place it in `crates/<crate-name>/docs/`.
3. If workspace-level, place it only in an allowed root `docs/` category.
4. For cross-crate topics, choose canonical owner or declare workspace-level scope with rationale.
5. Do not keep root compatibility stubs; remove legacy root files after migrating references.
