# nils-workflow-cli

Shared CLI for open-project workflow actions and script-filter rendering.

## Commands

| Command | Options | Description |
| --- | --- | --- |
| `workflow-cli script-filter` | `--query <QUERY> [--mode <open|github>]` | Render Alfred script-filter JSON. |
| `workflow-cli record-usage` | `--path <PATH>` | Record usage timestamp for a selected project path. |
| `workflow-cli github-url` | `--path <PATH>` | Resolve project origin URL to canonical GitHub URL. |

## Environment Variables

Configured via `workflow-common` runtime config:

- `PROJECT_DIRS`, `USAGE_FILE`, `VSCODE_PATH`, `OPEN_PROJECT_MAX_RESULTS`

## Output Contract

- `script-filter`: Alfred Script Filter JSON on `stdout`.
- `record-usage` / `github-url`: plain text value on `stdout`.
- `stderr`: user/runtime error text.
- Exit codes: `0` success, `1` runtime error, `2` user/input error.

## Standards Status

- README/command docs: compliant.
- Human-readable mode: partially compliant (non-script-filter commands already plain text).
- JSON service envelope (`schema_version/command/ok`): not yet migrated for `script-filter`.

## Documentation

- [`docs/README.md`](docs/README.md)
- [`Open Project Port Parity contract`](../../crates/workflow-cli/docs/README.md#canonical-documents)

## Validation

- `cargo run -p nils-workflow-cli -- --help`
- `cargo run -p nils-workflow-cli -- script-filter --help`
- `cargo run -p nils-workflow-cli -- record-usage --help`
- `cargo run -p nils-workflow-cli -- github-url --help`
- `cargo test -p nils-workflow-cli`
