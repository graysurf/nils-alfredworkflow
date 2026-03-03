# Crate Legacy Removal Matrix (Sprint 2 / S2T1)

This legacy removal matrix freezes the crate-level compatibility flags and branches that must be deleted during Sprint
2 runtime migration work.

## Matrix

| Legacy option/path to remove | Current crates and path(s) | Canonical replacement | Planned removal task | Status |
| --- | --- | --- | --- | --- |
| `--json` compatibility boolean flag for output mode | `crates/workflow-cli/src/main.rs`, `crates/workflow-readme-cli/src/main.rs`, `crates/weather-cli/src/main.rs`, `crates/market-cli/src/main.rs` | Keep only `--output json` for machine mode selection | `S2T2`, `S2T4` | planned |
| Legacy output parser aliases `text`, `alfred`, `alfred_json` | `crates/workflow-common/src/output_contract.rs` (`OutputMode::parse`) | Accept only canonical values `human`, `json`, `alfred-json` | `S2T2` | planned |
| Legacy mode flag surface `--mode <service-json\|alfred>` | `crates/brave-cli/src/main.rs`, `crates/bangumi-cli/src/main.rs`, `crates/bilibili-cli/src/main.rs`, `crates/cambridge-cli/src/main.rs`, `crates/spotify-cli/src/main.rs`, `crates/steam-cli/src/main.rs`, `crates/wiki-cli/src/main.rs`, `crates/youtube-cli/src/main.rs`, `crates/epoch-cli/src/main.rs`, `crates/timezone-cli/src/main.rs`, `crates/randomer-cli/src/main.rs`, `crates/quote-cli/src/main.rs` | Migrate to shared output mode contract with explicit `--output` semantics | `S2T3`, `S2T4` | planned |
| Implicit compatibility default to Alfred JSON for workflow-facing command branches | Search-family command entrypoints plus `workflow-cli script-filter` and `market-cli expr` | Preserve Alfred JSON only as explicit compatibility mode, not as hidden default behavior | `S2T3`, `S2T4` | planned |
| Crate-local duplicate envelope/error builders outside shared runtime | `crates/weather-cli/src/main.rs`, `crates/market-cli/src/main.rs`, `crates/workflow-readme-cli/src/main.rs`, search-family entrypoints listed above | Route envelope/error output through shared runtime APIs from `workflow-common` | `S2T2`, `S2T3`, `S2T4` | planned |

## Notes

- Tracking source for current command surfaces: `docs/reports/cli-command-inventory.md`.
- This file is a planning/report artifact. Deletion happens in implementation tasks `S2T2` through `S2T4`.
- Any new compatibility path added after this baseline must add a row here before merge.
