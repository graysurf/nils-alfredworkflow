# nils-bilibili-cli

CLI backend for the `bilibili-search` workflow.

## Commands

| Command | Options | Description |
| --- | --- | --- |
| `bilibili-cli query` | `--input <QUERY>` | Query bilibili suggestions from workflow-style input and print Alfred Script Filter JSON. |
| `bilibili-cli search` | `--query <QUERY>` | Alias command for explicit query callers; returns Alfred Script Filter JSON. |

## Environment Variables

- Optional: `BILIBILI_UID`, `BILIBILI_MAX_RESULTS`, `BILIBILI_TIMEOUT_MS`, `BILIBILI_USER_AGENT`

## Output Contract

- `stdout`: Alfred Script Filter JSON payload.
- `stderr`: user/runtime error text.
- Exit codes: `0` success, `1` runtime/API error, `2` user/config/input error.

## Standards Status

- README/command docs: compliant.
- JSON service envelope (`schema_version/command/ok`): not yet migrated.
- Default human-readable mode: not yet migrated (legacy JSON-first workflow contract).

## Documentation

- [`docs/README.md`](docs/README.md)
- [`docs/workflow-contract.md`](docs/workflow-contract.md)

## Validation

- `cargo run -p nils-bilibili-cli -- --help`
- `cargo run -p nils-bilibili-cli -- query --help`
- `cargo test -p nils-bilibili-cli`
