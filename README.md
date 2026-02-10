# nils-alfredworkflow

Monorepo for Alfred workflows with shared Rust crates and thin Bash adapters.

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

- `crates/alfred-core`: Alfred feedback data model (`items`, optional `mods`, `variables`).
- `crates/alfred-plist`: `info.plist` template rendering helpers.
- `crates/workflow-common`: Shared open-project domain logic (scan, usage log, git metadata, feedback assembly).
- `crates/workflow-cli`: Shared binary for script-filter/action adapters.
- `crates/xtask`: Task runner for workflow list/lint/test/pack/new.

## Workflows

- `workflows/open-project`: parity port of `open-project-in-vscode`.
- `workflows/_template`: scaffold template used by `scripts/workflow-new.sh`.

## Open Project behavior contract

`open-project` keeps parity-sensitive behavior via environment variables:

- `PROJECT_DIRS`: comma-separated roots (supports `$HOME` and `~`).
- `USAGE_FILE`: usage timestamp log path.
- `VSCODE_PATH`: editor executable used by `action_open.sh`.

The shared CLI surface used by Alfred scripts:

- `workflow-cli script-filter --query "<query>"` -> prints Alfred JSON only.
- `workflow-cli record-usage --path "<project-path>"` -> prints plain path only.
- `workflow-cli github-url --path "<project-path>"` -> prints canonical GitHub URL only.

## Command surface

- `cargo run -p xtask -- workflow list`
- `cargo run -p xtask -- workflow lint [--id <workflow>]`
- `cargo run -p xtask -- workflow test [--id <workflow>]`
- `cargo run -p xtask -- workflow pack --id <workflow> [--install]`
- `cargo run -p xtask -- workflow pack --all`
- `cargo run -p xtask -- workflow new --id <workflow>`

## License

This project is dedicated to the public domain under [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/).
See `LICENSE` for the full legal text.
