# Crate Doc Migration Summary (Maintainers)

## What moved vs what stayed

- Moved: crate-owned docs are now canonical under `crates/<crate>/docs/`.
- Stayed at root: workspace-level docs remain under allowed categories (`docs/specs/`, `docs/plans/`, `docs/reports/`, and repo-wide guides).
- Transitional state: some legacy root doc paths still exist as short compatibility stubs that only point to canonical crate-local docs.

### before/after path examples

| Type | before | after |
| --- | --- | --- |
| Crate workflow contract | `docs/weather-cli-contract.md` | `crates/weather-cli/docs/workflow-contract.md` |
| Crate workflow contract | `docs/market-cli-contract.md` | `crates/market-cli/docs/workflow-contract.md` |
| Crate rules doc | `docs/market-expression-rules.md` | `crates/market-cli/docs/expression-rules.md` |
| Workspace policy (stays root) | `docs/specs/crate-docs-placement-policy.md` | `docs/specs/crate-docs-placement-policy.md` |
| Migration inventory (stays root) | `docs/reports/crate-doc-migration-inventory.md` | `docs/reports/crate-doc-migration-inventory.md` |

## Enforcement changes

- New crate-specific markdown under root `docs/` is disallowed by policy.
- Root stubs are migration-only pointers; they must not duplicate full crate content.
- Contributors must classify each new markdown file (`workspace-level` vs `crate-specific`) before placement.

## Contributor workflows (common)

1. Add or update crate-specific docs:
   - Edit/create in `crates/<crate>/docs/`.
   - Ensure `crates/<crate>/docs/README.md` exists and links to the doc.
2. Add workspace-level standards/plans/reports:
   - Place only in allowed root categories (`docs/specs/`, `docs/plans/`, `docs/reports/`).
3. Migrate a legacy root crate doc:
   - Move canonical content to `crates/<crate>/docs/...`.
   - Keep only a minimal pointer stub at the old root path during transition.

## Mandatory pre-commit checks

- `bash scripts/docs-placement-audit.sh --strict` (required docs placement gate)
- `scripts/workflow-lint.sh`
- `cargo test --workspace`
- `scripts/workflow-test.sh`

## References

- Policy spec: `docs/specs/crate-docs-placement-policy.md`
- Migration inventory: `docs/reports/crate-doc-migration-inventory.md`
