# Architecture

Repository architecture baseline:

- Workspace monorepo with shared Rust crates under `crates/`.
- Workflow adapters under `workflows/<id>/scripts` stay thin; domain logic lives in Rust crates.
- Shared runtime shell mechanics live in `scripts/lib/`.
- Packaging and validation use deterministic entrypoints under `scripts/` and `xtask`.
- Runtime target is Alfred on macOS; development/CI validation supports Linux and macOS.

For operator standards and command gates, see:

- `ALFRED_WORKFLOW_DEVELOPMENT.md`
- `DEVELOPMENT.md`
