# nils-cambridge-cli

CLI backend for the `cambridge-dict` workflow.

## Commands

| Command | Options | Description |
| --- | --- | --- |
| `cambridge-cli query` | `--input <INPUT>` | Query Cambridge dictionary and print Alfred Script Filter JSON. |

## Environment Variables

- Required: `CAMBRIDGE_SCRAPER_SCRIPT`
- Optional: `CAMBRIDGE_DICT_MODE`, `CAMBRIDGE_MAX_RESULTS`, `CAMBRIDGE_TIMEOUT_MS`, `CAMBRIDGE_HEADLESS`, `CAMBRIDGE_NODE_BIN`

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

- `cargo run -p nils-cambridge-cli -- --help`
- `cargo run -p nils-cambridge-cli -- query --help`
- `cargo test -p nils-cambridge-cli`
