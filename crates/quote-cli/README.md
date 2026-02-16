# nils-quote-cli

CLI backend for the `quote-feed` workflow.

## Commands

| Command | Options | Description |
| --- | --- | --- |
| `quote-cli feed` | `--query <QUERY>` | Build quote feed items and print Alfred Script Filter JSON. |

## Environment Variables

- Optional: `QUOTE_DISPLAY_COUNT`, `QUOTE_REFRESH_INTERVAL`, `QUOTE_FETCH_COUNT`, `QUOTE_MAX_ENTRIES`, `QUOTE_DATA_DIR`, `ALFRED_WORKFLOW_DATA`

## Output Contract

- `stdout`: Alfred Script Filter JSON payload.
- `stderr`: user/runtime error text.
- Exit codes: `0` success, `1` runtime/storage/network error, `2` user/config error.

## Standards Status

- README/command docs: compliant.
- JSON service envelope (`schema_version/command/ok`): not yet migrated.
- Default human-readable mode: not yet migrated (legacy JSON-first workflow contract).

## Documentation

- [`docs/README.md`](docs/README.md)
- [`docs/workflow-contract.md`](docs/workflow-contract.md)

## Validation

- `cargo run -p nils-quote-cli -- --help`
- `cargo run -p nils-quote-cli -- feed --help`
- `cargo test -p nils-quote-cli`
