# Crate Doc Migration Inventory

This report records legacy root crate-specific docs that were migrated to crate-local canonical paths and then removed from root `docs/`.

- Data source: repository file inventory and reference search via `rg -n "docs/<doc-name>.md" .`.
- Scope: 14 legacy root docs.
- Migration order: historical rollout order from lower coupling to higher coupling.

| Migration order | Legacy root path | Owner crate | Canonical path | Status |
| --- | --- | --- | --- | --- |
| 1 | `docs/market-expression-rules.md` | `market-cli` | `crates/market-cli/docs/expression-rules.md` | Migrated and root file removed |
| 2 | `docs/market-cli-contract.md` | `market-cli` | `crates/market-cli/docs/workflow-contract.md` | Migrated and root file removed |
| 3 | `docs/weather-cli-contract.md` | `weather-cli` | `crates/weather-cli/docs/workflow-contract.md` | Migrated and root file removed |
| 4 | `docs/youtube-search-contract.md` | `youtube-cli` | `crates/youtube-cli/docs/workflow-contract.md` | Migrated and root file removed |
| 5 | `docs/google-search-contract.md` | `brave-cli` | `crates/brave-cli/docs/workflow-contract.md` | Migrated and root file removed |
| 6 | `docs/epoch-converter-contract.md` | `epoch-cli` | `crates/epoch-cli/docs/workflow-contract.md` | Migrated and root file removed |
| 7 | `docs/multi-timezone-contract.md` | `timezone-cli` | `crates/timezone-cli/docs/workflow-contract.md` | Migrated and root file removed |
| 8 | `docs/wiki-search-contract.md` | `wiki-cli` | `crates/wiki-cli/docs/workflow-contract.md` | Migrated and root file removed |
| 9 | `docs/cambridge-dict-contract.md` | `cambridge-cli` | `crates/cambridge-cli/docs/workflow-contract.md` | Migrated and root file removed |
| 10 | `docs/quote-workflow-contract.md` | `quote-cli` | `crates/quote-cli/docs/workflow-contract.md` | Migrated and root file removed |
| 11 | `docs/randomer-contract.md` | `randomer-cli` | `crates/randomer-cli/docs/workflow-contract.md` | Migrated and root file removed |
| 12 | `docs/spotify-search-contract.md` | `spotify-cli` | `crates/spotify-cli/docs/workflow-contract.md` | Migrated and root file removed |
| 13 | `docs/open-project-port-parity.md` | `workflow-cli` | `crates/workflow-cli/docs/open-project-port-parity.md` | Migrated and root file removed |
| 14 | `docs/memo-workflow-contract.md` | `memo-workflow-cli` | `crates/memo-workflow-cli/docs/workflow-contract.md` | Migrated and root file removed |

## Legacy root docs removal status

- Decision reference: `docs/specs/crate-docs-placement-policy.md` (`Legacy root doc lifecycle decision`).
- Lifecycle policy: remove legacy root docs after references are migrated.
- Snapshot date: 2026-02-13.

| Legacy root path | Canonical target | Current status | Lifecycle status |
| --- | --- | --- | --- |
| `docs/cambridge-dict-contract.md` | `crates/cambridge-cli/docs/workflow-contract.md` | Removed from root `docs/` | Retired legacy path |
| `docs/epoch-converter-contract.md` | `crates/epoch-cli/docs/workflow-contract.md` | Removed from root `docs/` | Retired legacy path |
| `docs/google-search-contract.md` | `crates/brave-cli/docs/workflow-contract.md` | Removed from root `docs/` | Retired legacy path |
| `docs/market-cli-contract.md` | `crates/market-cli/docs/workflow-contract.md` | Removed from root `docs/` | Retired legacy path |
| `docs/market-expression-rules.md` | `crates/market-cli/docs/expression-rules.md` | Removed from root `docs/` | Retired legacy path |
| `docs/memo-workflow-contract.md` | `crates/memo-workflow-cli/docs/workflow-contract.md` | Removed from root `docs/` | Retired legacy path |
| `docs/multi-timezone-contract.md` | `crates/timezone-cli/docs/workflow-contract.md` | Removed from root `docs/` | Retired legacy path |
| `docs/open-project-port-parity.md` | `crates/workflow-cli/docs/open-project-port-parity.md` | Removed from root `docs/` | Retired legacy path |
| `docs/quote-workflow-contract.md` | `crates/quote-cli/docs/workflow-contract.md` | Removed from root `docs/` | Retired legacy path |
| `docs/spotify-search-contract.md` | `crates/spotify-cli/docs/workflow-contract.md` | Removed from root `docs/` | Retired legacy path |
| `docs/weather-cli-contract.md` | `crates/weather-cli/docs/workflow-contract.md` | Removed from root `docs/` | Retired legacy path |
| `docs/wiki-search-contract.md` | `crates/wiki-cli/docs/workflow-contract.md` | Removed from root `docs/` | Retired legacy path |
| `docs/youtube-search-contract.md` | `crates/youtube-cli/docs/workflow-contract.md` | Removed from root `docs/` | Retired legacy path |
| `docs/randomer-contract.md` | `crates/randomer-cli/docs/workflow-contract.md` | Removed from root `docs/` | Retired legacy path |

## Notes

- All canonical crate docs remain under `crates/<crate>/docs/`.
- Root `docs/` is reserved for workspace-level documentation categories only.
