# nils-market-cli

CLI backend for market data (`fx`, `crypto`) and market-expression workflow support.

## Commands

| Command | Options | Description |
| --- | --- | --- |
| `market-cli fx` | `--base <BASE> --quote <QUOTE> --amount <AMOUNT>` | Query fiat exchange rate (Frankfurter). |
| `market-cli crypto` | `--base <BASE> --quote <QUOTE> --amount <AMOUNT>` | Query crypto spot price (Coinbase primary, Kraken fallback). |
| `market-cli expr` | `--query <QUERY> [--default-fiat <DEFAULT_FIAT>]` | Evaluate market expressions and return Alfred Script Filter JSON. |

## Environment Variables

- Optional cache override: `MARKET_CACHE_DIR`
- Alfred fallback cache paths: `ALFRED_WORKFLOW_CACHE`, `ALFRED_WORKFLOW_DATA`

## Output Contract

- `fx` / `crypto`: deterministic JSON object on `stdout`.
- `expr`: Alfred Script Filter JSON on `stdout`.
- `stderr`: user/runtime error text.
- Exit codes: `0` success, `1` runtime/provider error, `2` user/input error.

### Provider stack (no API key)

- FX: Frankfurter (`24h` TTL)
- Crypto: Coinbase primary + Kraken fallback (`5m` TTL)
- Freshness states: `live`, `cache_fresh`, `cache_stale_fallback`

## Standards Status

- README/command docs: compliant.
- JSON service envelope (`schema_version/command/ok`): not yet migrated.
- Default human-readable mode: partially migrated (still JSON-first for `fx/crypto`).

## Documentation

- [`docs/README.md`](docs/README.md)
- [`docs/workflow-contract.md`](docs/workflow-contract.md)
- [`docs/expression-rules.md`](docs/expression-rules.md)

## Validation

- `cargo run -p nils-market-cli -- --help`
- `cargo run -p nils-market-cli -- fx --help`
- `cargo run -p nils-market-cli -- crypto --help`
- `cargo run -p nils-market-cli -- expr --help`
- `cargo test -p nils-market-cli`
