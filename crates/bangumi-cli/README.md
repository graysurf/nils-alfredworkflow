# nils-bangumi-cli

CLI backend for the `bangumi-search` workflow.

## Commands

| Command | Options | Description |
| --- | --- | --- |
| `bangumi-cli query` | `--input <INPUT>` | Parse `[type] query` and print Alfred Script Filter JSON. |
| `bangumi-cli search` | `--query <QUERY> [--type <TYPE>]` | Explicit typed search entrypoint for non-Alfred callers. |

## Environment Variables

- Optional: `BANGUMI_API_KEY`, `BANGUMI_MAX_RESULTS`, `BANGUMI_TIMEOUT_MS`, `BANGUMI_USER_AGENT`
- Optional: `BANGUMI_CACHE_DIR`, `BANGUMI_IMAGE_CACHE_TTL_SECONDS`, `BANGUMI_IMAGE_CACHE_MAX_MB`
- Optional: `BANGUMI_API_FALLBACK` (`auto`, `never`, `always`)
- Future bridge (disabled by default): `BANGUMI_SCRAPER_ENABLE`, `BANGUMI_SCRAPER_SCRIPT`

## Output Contract

- `stdout`: Alfred Script Filter JSON payload (`query --mode alfred`) or typed JSON payload (`search`).
- `stderr`: user/runtime error text.
- Exit codes: `0` success, `1` runtime/API error, `2` user/config/input error.

## Standards Status

- README/command docs: compliant.
- JSON service envelope (`schema_version/command/ok`): not yet migrated.
- Default human-readable mode: not yet migrated (legacy JSON-first workflow contract).

## Documentation

- [`docs/README.md`](docs/README.md)
- [`docs/workflow-contract.md`](docs/workflow-contract.md)
- [`docs/playwright-bridge-design.md`](docs/playwright-bridge-design.md)

## Validation

- `cargo run -p nils-bangumi-cli -- --help`
- `cargo run -p nils-bangumi-cli -- query --help`
- `cargo test -p nils-bangumi-cli`
