# Crate Doc Migration Inventory

This report records crate-owned root docs that must migrate to crate-local canonical paths.

- Data source: current repository files under `docs/` and direct reference search via `rg -n "docs/<doc-name>.md" .`.
- Scope: 14 crate-owned root docs tracked through migration closure.
- Migration order: recommended rollout from lower coupling to higher coupling and known gap handling.

| Migration order | Current path | Owner crate | Final canonical path | Reference hotspots | Link-update scope | Risk level | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `docs/market-expression-rules.md` | `market-cli` | `crates/market-cli/docs/expression-rules.md` | `docs/plans/crate-docs-migration-governance-plan.md` (3) | 3 direct hits across 1 file; update all root-path links to canonical path. | Low | Completed |
| 2 | `docs/market-cli-contract.md` | `market-cli` | `crates/market-cli/docs/workflow-contract.md` | `docs/plans/fx-crypto-cli-plan.md` (5), `docs/plans/crate-docs-migration-governance-plan.md` (3) | 8 direct hits across 2 files; rewrite plan links and keep transition stub. | Low | Completed |
| 3 | `docs/weather-cli-contract.md` | `weather-cli` | `crates/weather-cli/docs/workflow-contract.md` | `docs/plans/weather-forecast-cli-plan.md` (5), `docs/plans/crate-docs-migration-governance-plan.md` (3) | 8 direct hits across 2 files; update plan references to canonical crate doc. | Low | Completed |
| 4 | `docs/youtube-search-contract.md` | `youtube-cli` | `crates/youtube-cli/docs/workflow-contract.md` | `docs/plans/youtube-search-workflow-plan.md` (5), `docs/plans/crate-docs-migration-governance-plan.md` (3) | 9 direct hits across 3 files; includes `TROUBLESHOOTING.md` link updates. | Low | Completed |
| 5 | `docs/google-search-contract.md` | `brave-cli` | `crates/brave-cli/docs/workflow-contract.md` | `docs/plans/google-search-workflow-plan.md` (6), `docs/plans/crate-docs-migration-governance-plan.md` (3) | 10 direct hits across 3 files; includes `TROUBLESHOOTING.md` link updates. | Medium | Completed |
| 6 | `docs/epoch-converter-contract.md` | `epoch-cli` | `crates/epoch-cli/docs/workflow-contract.md` | `docs/plans/epoch-converter-workflow-plan.md` (7), `docs/plans/crate-docs-migration-governance-plan.md` (3) | 11 direct hits across 3 files; includes `TROUBLESHOOTING.md` link updates. | Medium | Completed |
| 7 | `docs/multi-timezone-contract.md` | `timezone-cli` | `crates/timezone-cli/docs/workflow-contract.md` | `docs/plans/multi-timezone-workflow-plan.md` (7), `docs/plans/crate-docs-migration-governance-plan.md` (3) | 11 direct hits across 3 files; includes `TROUBLESHOOTING.md` link updates. | Medium | Completed |
| 8 | `docs/wiki-search-contract.md` | `wiki-cli` | `crates/wiki-cli/docs/workflow-contract.md` | `docs/plans/wiki-search-workflow-plan.md` (7), `docs/plans/crate-docs-migration-governance-plan.md` (3) | 11 direct hits across 3 files; includes `TROUBLESHOOTING.md` link updates. | Medium | Completed |
| 9 | `docs/cambridge-dict-contract.md` | `cambridge-cli` | `crates/cambridge-cli/docs/workflow-contract.md` | `docs/plans/cambridge-playwright-dictionary-workflow-plan.md` (8), `docs/plans/crate-docs-migration-governance-plan.md` (3) | 12 direct hits across 3 files; includes `TROUBLESHOOTING.md` link updates. | Medium | Completed |
| 10 | `docs/quote-workflow-contract.md` | `quote-cli` | `crates/quote-cli/docs/workflow-contract.md` | `docs/plans/quote-init-workflow-plan.md` (8), `docs/plans/crate-docs-migration-governance-plan.md` (3) | 12 direct hits across 3 files; includes `TROUBLESHOOTING.md` link updates. | Medium | Completed |
| 11 | `docs/randomer-contract.md` | `randomer-cli` | `crates/randomer-cli/docs/workflow-contract.md` | `docs/plans/randomer-workflow-port-plan.md` (11), `docs/plans/crate-docs-migration-governance-plan.md` (5) | 16 direct hits across 2 files; create canonical doc and root stub, then update links. | High | Completed |
| 12 | `docs/spotify-search-contract.md` | `spotify-cli` | `crates/spotify-cli/docs/workflow-contract.md` | `docs/plans/spotify-search-workflow-plan.md` (11), `docs/plans/crate-docs-migration-governance-plan.md` (3) | 14 direct hits across 2 files; high plan-link concentration to rewrite. | High | Completed |
| 13 | `docs/open-project-port-parity.md` | `workflow-cli` | `crates/workflow-cli/docs/open-project-port-parity.md` | `docs/plans/port-open-project-workflow-plan.md` (8), `docs/plans/crate-docs-migration-governance-plan.md` (6) | 15 direct hits across 3 files; includes self-reference that must be normalized after move. | High | Completed |
| 14 | `docs/memo-workflow-contract.md` | `memo-workflow-cli` | `crates/memo-workflow-cli/docs/workflow-contract.md` | `docs/plans/memo-add-workflow-plan.md` (8), `docs/plans/memo-workflow-update-delete-plan.md` (6) | 22 direct hits across 4 files; widest link-update blast radius in current repo. | High | Completed |

## Stub lifecycle decision and current status

- Decision reference: `docs/specs/crate-docs-placement-policy.md` (`Root compatibility stub lifecycle decision`).
- Lifecycle policy: permanent redirect stubs, no deprecation sunset date.
- Snapshot date: 2026-02-13.

| Root stub file | Canonical target | Current stub status | Lifecycle status |
| --- | --- | --- | --- |
| `docs/cambridge-dict-contract.md` | `crates/cambridge-cli/docs/workflow-contract.md` | Present; contains `Moved to` pointer. | Active permanent redirect |
| `docs/epoch-converter-contract.md` | `crates/epoch-cli/docs/workflow-contract.md` | Present; contains `Moved to` pointer. | Active permanent redirect |
| `docs/google-search-contract.md` | `crates/brave-cli/docs/workflow-contract.md` | Present; contains `Moved to` pointer. | Active permanent redirect |
| `docs/market-cli-contract.md` | `crates/market-cli/docs/workflow-contract.md` | Present; contains `Moved to` pointer. | Active permanent redirect |
| `docs/market-expression-rules.md` | `crates/market-cli/docs/expression-rules.md` | Present; contains `Moved to` pointer. | Active permanent redirect |
| `docs/memo-workflow-contract.md` | `crates/memo-workflow-cli/docs/workflow-contract.md` | Present; contains `Moved to` pointer. | Active permanent redirect |
| `docs/multi-timezone-contract.md` | `crates/timezone-cli/docs/workflow-contract.md` | Present; contains `Moved to` pointer. | Active permanent redirect |
| `docs/open-project-port-parity.md` | `crates/workflow-cli/docs/open-project-port-parity.md` | Present; contains `Moved to` pointer. | Active permanent redirect |
| `docs/quote-workflow-contract.md` | `crates/quote-cli/docs/workflow-contract.md` | Present; contains `Moved to` pointer. | Active permanent redirect |
| `docs/spotify-search-contract.md` | `crates/spotify-cli/docs/workflow-contract.md` | Present; contains `Moved to` pointer. | Active permanent redirect |
| `docs/weather-cli-contract.md` | `crates/weather-cli/docs/workflow-contract.md` | Present; contains `Moved to` pointer. | Active permanent redirect |
| `docs/wiki-search-contract.md` | `crates/wiki-cli/docs/workflow-contract.md` | Present; contains `Moved to` pointer. | Active permanent redirect |
| `docs/youtube-search-contract.md` | `crates/youtube-cli/docs/workflow-contract.md` | Present; contains `Moved to` pointer. | Active permanent redirect |
| `docs/randomer-contract.md` | `crates/randomer-cli/docs/workflow-contract.md` | Present; contains canonical pointer stub text. | Active permanent redirect |

## Notes

- All migration items are completed; the canonical destination for each item is listed in `Final canonical path`.
- High-impact docs link hygiene pass is clean for `README.md`, `TROUBLESHOOTING.md`, and `docs/WORKFLOW_GUIDE.md`.
