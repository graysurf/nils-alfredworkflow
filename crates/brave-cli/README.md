# nils-brave-cli

CLI backend for the `google-search` workflow using Brave Search API.

## Commands

| Command | Options | Description |
| --- | --- | --- |
| `brave-cli search` | `--query <QUERY>` | Search Brave web results and print Alfred Script Filter JSON. |

## Environment Variables

- Required: `BRAVE_API_KEY`
- Optional: `BRAVE_MAX_RESULTS`, `BRAVE_SAFESEARCH`, `BRAVE_COUNTRY`

## Output Contract

- `stdout`: Alfred Script Filter JSON payload.
- `stderr`: user/runtime error text.
- Exit codes: `0` success, `1` runtime error, `2` user/config error.

## Standards Status

- README/command docs: compliant.
- JSON service envelope (`schema_version/command/ok`): not yet migrated.
- Default human-readable mode: not yet migrated (legacy JSON-first workflow contract).

## Documentation

- [`docs/README.md`](docs/README.md)
- [`docs/workflow-contract.md`](docs/workflow-contract.md)

## Validation

- `cargo run -p nils-brave-cli -- --help`
- `cargo run -p nils-brave-cli -- search --help`
- `cargo test -p nils-brave-cli`
