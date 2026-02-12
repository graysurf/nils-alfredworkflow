# Memo Add - Alfred Workflow

Capture memo text quickly into SQLite-backed `nils-memo-cli` storage.

## Features

- Keyword `mm` for fast memo capture.
- Primary flow is `add` (one Enter to save memo text).
- Empty query shows `db init` plus latest memo rows (newest -> oldest).
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
| `mm` | Show add guidance, a `db init` action row, and recent memo records (newest first). |
| `mm <text>` | Add memo text to database via `memo-workflow-cli action --token add::<text>`. |

## Validation

- `bash workflows/memo-add/tests/smoke.sh`
- `scripts/workflow-test.sh --id memo-add`
- `scripts/workflow-pack.sh --id memo-add`
