# Memo Add - Alfred Workflow

Capture memo text quickly into SQLite-backed `nils-memo-cli` storage.

## Features

- Keyword `mm` for fast memo capture.
- Primary flow supports `add`, `update`, and `delete`.
- Empty query shows `db init` only when db is missing; otherwise shows db path + latest memo rows.
- Delete intent is hard-delete (permanent remove, no undo).
- Runtime parameters for DB path, source label, confirmation gate, and max input bytes.

## Configuration

Set these via Alfred's `Configure Workflow...` UI:

| Variable | Required | Default | Description |
|---|---|---|---|
| `MEMO_DB_PATH` | No | `(empty)` | SQLite path override. Empty uses Alfred workflow data dir, then memo-cli default path. |
| `MEMO_SOURCE` | No | `alfred` | Source label saved with each memo item. |
| `MEMO_REQUIRE_CONFIRM` | No | `0` | `1/true/yes/on` adds an explicit confirm row before add action. |
| `MEMO_MAX_INPUT_BYTES` | No | `4096` | Max bytes allowed for one memo input. |
| `MEMO_RECENT_LIMIT` | No | `8` | Number of recent rows shown when query is empty (`1..50`). |
| `MEMO_WORKFLOW_CLI_BIN` | No | `(empty)` | Optional executable path override for `memo-workflow-cli`. |

## Keyword

| Keyword | Behavior |
|---|---|
| `mm` | Show add guidance; when db is missing show `db init`, otherwise show db path and recent memo records (newest first). |
| `mm <text>` | Add memo text to database via `memo-workflow-cli action --token add::<text>`. |
| `mm update <item_id> <text>` | Update target memo via `memo-workflow-cli action --token update::<item_id>::<text>`. |
| `mm delete <item_id>` | Hard-delete target memo via `memo-workflow-cli action --token delete::<item_id>`. |

## Query intents

- Default intent: add (`mm <text>`).
- Mutation intents: `update <item_id> <text>`, `delete <item_id>`.
- Invalid mutation syntax (for example missing `item_id` or missing update text) returns non-actionable guidance rows.

## Operator CRUD verification

```bash
tmpdir="$(mktemp -d)"
db="$tmpdir/memo.db"

add_json="$(cargo run -p nils-memo-workflow-cli -- add --db "$db" --text "before" --mode json)"
item_id="$(jq -r '.result.item_id' <<<"$add_json")"

cargo run -p nils-memo-workflow-cli -- update --db "$db" --item-id "$item_id" --text "after" --mode json \
  | jq -e '.ok == true and .result.item_id == "'"$item_id"'"'

cargo run -p nils-memo-workflow-cli -- delete --db "$db" --item-id "$item_id" --mode json \
  | jq -e '.ok == true and .result.deleted == true'
```

## Validation

- `bash workflows/memo-add/tests/smoke.sh`
- `scripts/workflow-test.sh --id memo-add`
- `scripts/workflow-pack.sh --id memo-add`
