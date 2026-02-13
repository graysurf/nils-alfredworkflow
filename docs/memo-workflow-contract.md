# Memo Add Workflow Contract

## Goal

Provide a capture-first Alfred workflow for quick memo insertion backed by `nils-memo-cli@0.3.5`.

## Primary user behavior

- Keyword: `mm`
- `mm buy milk` -> script-filter returns actionable add row -> action runs add and persists one inbox record.
- `mm update itm_00000001 buy oat milk` -> script-filter returns actionable update row.
- `mm delete itm_00000001` -> script-filter returns actionable delete row.
- `mm` (empty query, db missing) -> script-filter returns guidance row + `db init` action row.
- `mm` (empty query, db exists) -> script-filter returns guidance row + db path info row + recent memo rows (newest first).

## Runtime commands

The workflow runtime binary is `memo-workflow-cli` with these commands:

- `script-filter --query <text>`: returns Alfred JSON.
- `action --token <token>`: executes workflow action token.
- `add --text <text>`: direct add operation (for debug/manual use).
- `update --item-id <id> --text <text>`: direct update operation (for debug/manual use).
- `delete --item-id <id>`: direct delete operation (for debug/manual use).
- `db-init`: direct db initialization operation (for debug/manual use).
- `list --limit <n> --offset <n>`: direct newest-first memo query (for debug/manual use).

## Action token contract

- `db-init`: initialize sqlite database and schema.
- `add::<raw-text>`: add one memo with raw text payload.
- `update::<item-id>::<raw-text>`: update one memo row by item id.
- `delete::<item-id>`: delete one memo row by item id.

`update` token parsing splits only the first two `::` delimiters, so update text keeps raw suffix bytes.
Malformed update/delete token shapes are handled as user errors.

`action_run.sh` forwards selected Alfred `arg` token into `memo-workflow-cli action --token`.

## Workflow parameters

| Variable | Default | Required | Notes |
|---|---|---|---|
| `MEMO_DB_PATH` | `""` | No | Empty: use Alfred workflow data dir + `memo.db`; otherwise use explicit path. |
| `MEMO_SOURCE` | `"alfred"` | No | Source label stored in `inbox_items.source`. Must be non-empty after trim. |
| `MEMO_REQUIRE_CONFIRM` | `"0"` | No | Truthy (`1/true/yes/on`) adds explicit confirm row before add action. |
| `MEMO_MAX_INPUT_BYTES` | `"4096"` | No | Max input bytes for one memo. Integer range `1..=1048576`. |
| `MEMO_RECENT_LIMIT` | `"8"` | No | Count of recent rows shown for empty query. Integer range `1..=50`. |
| `MEMO_WORKFLOW_CLI_BIN` | `""` | No | Optional absolute binary override for workflow runtime. |

## DB init semantics

- `db init` is idempotent.
- First run creates parent directory and sqlite file if missing.
- Repeated runs keep schema stable and return success.
- Runtime should surface readable errors for permission/path failures.

## Add semantics

- Input text is trimmed before validation.
- Empty text is rejected as usage/user error.
- Oversize text (> `MEMO_MAX_INPUT_BYTES`) is rejected as usage/user error.
- Success path persists one row and returns item id/timestamp acknowledgment.

## Update semantics

- Query intent form: `update <item_id> <new text>`.
- Requires valid `item_id` and non-empty update text.
- Invalid `item_id` or malformed update syntax is rejected as usage/user error.
- Success path updates target row text and returns updated metadata acknowledgment.

## Delete semantics

- Query intent form: `delete <item_id>`.
- Delete uses hard-delete semantics (row is permanently removed; no soft-delete/undo path).
- Invalid/missing `item_id` or malformed delete syntax is rejected as usage/user error.
- Success path returns deletion acknowledgment for the target item id.

## Query semantics

- Empty query with existing db includes a recent-records section so users can verify latest captures immediately.
- Recent records default to `MEMO_RECENT_LIMIT=8` and are ordered by `created_at DESC`, then `item_id DESC`.
- Recent record rows and db path row are informational (`valid=false`), while `db init` stays actionable when db is missing.
- Non-empty query defaults to add unless explicit `update` / `delete` intent prefix is matched.
- Malformed mutation query syntax returns non-actionable guidance rows instead of malformed JSON.

## Error mapping

- Config/user validation failures -> exit code `2`.
- Runtime/storage failures -> exit code `1`.
- `script_filter.sh` always returns Alfred JSON; on runtime errors it emits non-actionable fallback rows.

## Validation checklist

- `cargo run -p nils-memo-workflow-cli -- script-filter --query "buy milk" | jq -e '.items | type == "array"'`
- `cargo run -p nils-memo-workflow-cli -- script-filter --query "" | jq -e '.items | type == "array" and length >= 2'`
- `cargo run -p nils-memo-workflow-cli -- script-filter --query "update itm_00000001 revised text" | jq -e '.items[0].arg | startswith("update::")'`
- `cargo run -p nils-memo-workflow-cli -- script-filter --query "delete itm_00000001" | jq -e '.items[0].arg | startswith("delete::")'`
- `cargo run -p nils-memo-workflow-cli -- db-init`
- `cargo run -p nils-memo-workflow-cli -- add --text "buy milk"`
- `tmpdir="$(mktemp -d)" && db="$tmpdir/memo.db" && add_json="$(cargo run -p nils-memo-workflow-cli -- add --db "$db" --text "before" --mode json)" && item_id="$(jq -r '.result.item_id' <<<"$add_json")" && cargo run -p nils-memo-workflow-cli -- update --db "$db" --item-id "$item_id" --text "after" --mode json`
- `tmpdir="$(mktemp -d)" && db="$tmpdir/memo.db" && add_json="$(cargo run -p nils-memo-workflow-cli -- add --db "$db" --text "to-delete" --mode json)" && item_id="$(jq -r '.result.item_id' <<<"$add_json")" && cargo run -p nils-memo-workflow-cli -- delete --db "$db" --item-id "$item_id" --mode json`
- `cargo run -p nils-memo-workflow-cli -- list --limit 8 --mode json`
- `bash workflows/memo-add/tests/smoke.sh`
