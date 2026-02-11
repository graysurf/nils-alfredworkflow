# nils-epoch-cli

CLI backend for the `epoch-converter` workflow.

## Commands

| Command | Options | Description |
| --- | --- | --- |
| `epoch-cli convert` | `--query <QUERY>` | Convert epoch/date-time values and print Alfred Script Filter JSON. |

## Environment Variables

- None required by this crate.

## Output Contract

- `stdout`: Alfred Script Filter JSON payload.
- `stderr`: user/runtime error text.
- Exit codes: `0` success, `1` runtime error, `2` user/input error.

## Standards Status

- README/command docs: compliant.
- JSON service envelope (`schema_version/command/ok`): not yet migrated.
- Default human-readable mode: not yet migrated (legacy JSON-first workflow contract).

## Validation

- `cargo run -p nils-epoch-cli -- --help`
- `cargo run -p nils-epoch-cli -- convert --help`
- `cargo test -p nils-epoch-cli`
