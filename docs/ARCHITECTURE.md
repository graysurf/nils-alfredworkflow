# Architecture

This repository follows a workflow-monorepo pattern:

- Shared logic stays in Rust crates under `crates/`.
- Alfred integration scripts stay thin under `workflows/<id>/scripts`.
- Packaging and validation run from deterministic shell entrypoints under `scripts/`.
- `xtask` provides one stable command surface for developer workflows.

See `docs/ALFRED_WORKFLOW_MONOREPO_DESIGN.md` for the full design baseline.
