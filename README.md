# nils-alfredworkflow

Monorepo skeleton for managing multiple Alfred workflows with shared Rust crates and thin Bash glue.

## Quick start

1. Bootstrap Rust + cargo tools:
   - `scripts/setup-rust-tooling.sh`
2. Validate workspace:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
3. Package one workflow:
   - `cargo run -p xtask -- workflow pack --id open-project`
4. Package all workflows:
   - `cargo run -p xtask -- workflow pack --all`

## Workspace crates

- `crates/alfred-core`: Alfred feedback data model.
- `crates/alfred-plist`: `info.plist` template rendering helpers.
- `crates/workflow-common`: Shared domain logic reused by workflow adapters.
- `crates/workflow-cli`: Shared binary for script filter/action glue.
- `crates/xtask`: Task runner for workflow list/lint/test/pack/new.

## Workflow layout

- `workflows/open-project`: first concrete workflow skeleton.
- `workflows/github-open`: second workflow skeleton to validate monorepo flow.
- `workflows/_template`: scaffold template used by `scripts/workflow-new.sh`.

## Command surface

- `cargo run -p xtask -- workflow list`
- `cargo run -p xtask -- workflow lint [--id <workflow>]`
- `cargo run -p xtask -- workflow test [--id <workflow>]`
- `cargo run -p xtask -- workflow pack --id <workflow> [--install]`
- `cargo run -p xtask -- workflow pack --all`
- `cargo run -p xtask -- workflow new --id <workflow>`
