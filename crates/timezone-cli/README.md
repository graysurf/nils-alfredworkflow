# nils-timezone-cli

CLI backend for the `multi-timezone` workflow.

## Commands

| Command | Options | Description |
| --- | --- | --- |
| `timezone-cli now` | `--query <QUERY> --config-zones <CONFIG_ZONES>` | Render timezone rows for Alfred workflow usage. |

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

- `cargo run -p nils-timezone-cli -- --help`
- `cargo run -p nils-timezone-cli -- now --help`
- `cargo test -p nils-timezone-cli`
