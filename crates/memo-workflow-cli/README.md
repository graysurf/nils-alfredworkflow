# nils-memo-workflow-cli

Workflow adapter CLI for Alfred memo capture actions backed by `nils-memo-cli@0.4.6`.

## Commands

| Command | Options | Description |
| --- | --- | --- |
| `memo-workflow-cli script-filter` | `--query <TEXT>` | Render Alfred script-filter JSON items for add/db-init/recent-list rows. |
| `memo-workflow-cli action` | `--token <TOKEN> [--mode <text|json>]` | Execute an Alfred action token (`db-init`, `add::<text>`, `update::<item_id>::<text>`, `delete::<item_id>`, `copy::<item_id>`, `copy-json::<item_id>`). |
| `memo-workflow-cli add` | `--text <TEXT> [--db <PATH>] [--source <LABEL>] [--mode <text|json>]` | Add one memo row directly. |
| `memo-workflow-cli update` | `--item-id <ID> --text <TEXT> [--db <PATH>] [--mode <text|json>]` | Update one memo row directly. |
| `memo-workflow-cli delete` | `--item-id <ID> [--db <PATH>] [--mode <text|json>]` | Hard-delete one memo row directly. |
| `memo-workflow-cli list` | `[--db <PATH>] [--limit <N>] [--offset <N>] [--mode <text|json>]` | List memo rows in newest-first order. |
| `memo-workflow-cli search` | `--query <TEXT> [--match <fts|prefix|contains>] [--limit <N>] [--offset <N>] [--db <PATH>] [--mode <text|json>]` | Search memo rows by query text (`fts` default, `prefix`, or `contains`). |
| `memo-workflow-cli db-init` | `[--db <PATH>] [--mode <text|json>]` | Initialize sqlite storage and migrations. |

## Environment Variables

- `MEMO_DB_PATH`
- `MEMO_SOURCE`
- `MEMO_REQUIRE_CONFIRM`
- `MEMO_MAX_INPUT_BYTES`
- `MEMO_RECENT_LIMIT`
- `MEMO_SEARCH_MATCH` (`fts`, `prefix`, `contains`; default `fts`)

## Output Contract

- `script-filter`: Alfred Script Filter JSON object on `stdout`.
- `add` / `db-init` / `action` in text mode: one-line human result on `stdout`.
- `add` / `update` / `delete` / `db-init` / `list` / `search` / `action` in JSON mode:
  `{ schema_version, command, ok, result, error }` envelope on `stdout`.
- `stderr`: error diagnostics only.
- Exit codes: `0` success, `2` user/config/usage errors, `1` runtime/storage failures.

## Standards Status

- README/command docs: compliant.
- Explicit output modes (`text|json`): compliant.
- Contract tests: present (`tests/cli_contract.rs`).

## Documentation

- [`docs/README.md`](docs/README.md)
- [`docs/workflow-contract.md`](docs/workflow-contract.md)

## Validation

- `cargo run -p nils-memo-workflow-cli -- --help`
- `cargo test -p nils-memo-workflow-cli`
- `cargo clippy -p nils-memo-workflow-cli --all-targets -- -D warnings`
