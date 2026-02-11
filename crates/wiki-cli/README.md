# nils-wiki-cli

CLI backend for the `wiki-search` workflow.

## Commands

| Command | Options | Description |
| --- | --- | --- |
| `wiki-cli search` | `--query <QUERY>` | Search Wikipedia articles and print Alfred Script Filter JSON. |

## Environment Variables

- Optional: `WIKI_LANGUAGE`, `WIKI_MAX_RESULTS`

## Output Contract

- `stdout`: Alfred Script Filter JSON payload.
- `stderr`: user/runtime error text.
- Exit codes: `0` success, `1` runtime/API error, `2` user/config/input error.

## Standards Status

- README/command docs: compliant.
- JSON service envelope (`schema_version/command/ok`): not yet migrated.
- Default human-readable mode: not yet migrated (legacy JSON-first workflow contract).

## Validation

- `cargo run -p nils-wiki-cli -- --help`
- `cargo run -p nils-wiki-cli -- search --help`
- `cargo test -p nils-wiki-cli`
