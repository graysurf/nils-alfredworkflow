# nils-randomer-cli

CLI backend for the `randomer` workflow.

## Commands

| Command | Options | Description |
| --- | --- | --- |
| `randomer-cli list-formats` | `--query <QUERY>` | List supported formats as Alfred menu items. |
| `randomer-cli list-types` | `--query <QUERY>` | List type keys for selector flow in `rrv` mode. |
| `randomer-cli generate` | `--format <FORMAT> [--count <COUNT>]` | Generate values for a specific format. |

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

- `cargo run -p nils-randomer-cli -- --help`
- `cargo run -p nils-randomer-cli -- list-formats --help`
- `cargo run -p nils-randomer-cli -- list-types --help`
- `cargo run -p nils-randomer-cli -- generate --help`
- `cargo test -p nils-randomer-cli`
