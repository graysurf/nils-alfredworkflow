# Memo Add Workflow Contract

## Goal

Provide a capture-first Alfred workflow for quick memo insertion backed by `nils-memo-cli@0.3.3`.

## Primary user behavior

- Keyword: `mm`
- `mm buy milk` -> script-filter returns actionable add row -> action runs add and persists one inbox record.
- `mm` (empty query) -> script-filter returns guidance row + `db init` action row.

## Runtime commands

The workflow runtime binary is `memo-workflow-cli` with these commands:

- `script-filter --query <text>`: returns Alfred JSON.
- `action --token <token>`: executes workflow action token.
- `add --text <text>`: direct add operation (for debug/manual use).
- `db-init`: direct db initialization operation (for debug/manual use).

## Action token contract

- `db-init`: initialize sqlite database and schema.
- `add::<raw-text>`: add one memo with raw text payload.

`action_run.sh` forwards selected Alfred `arg` token into `memo-workflow-cli action --token`.

## Workflow parameters

| Variable | Default | Required | Notes |
|---|---|---|---|
| `MEMO_DB_PATH` | `""` | No | Empty: use Alfred workflow data dir + `memo.db`; otherwise use explicit path. |
| `MEMO_SOURCE` | `"alfred"` | No | Source label stored in `inbox_items.source`. Must be non-empty after trim. |
| `MEMO_REQUIRE_CONFIRM` | `"0"` | No | Truthy (`1/true/yes/on`) adds explicit confirm row before add action. |
| `MEMO_MAX_INPUT_BYTES` | `"4096"` | No | Max input bytes for one memo. Integer range `1..=1048576`. |
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

## Error mapping

- Config/user validation failures -> exit code `2`.
- Runtime/storage failures -> exit code `1`.
- `script_filter.sh` always returns Alfred JSON; on runtime errors it emits non-actionable fallback rows.

## Validation checklist

- `cargo run -p nils-memo-workflow-cli -- script-filter --query "buy milk" | jq -e '.items | type == "array"'`
- `cargo run -p nils-memo-workflow-cli -- db-init`
- `cargo run -p nils-memo-workflow-cli -- add --text "buy milk"`
- `bash workflows/memo-add/tests/smoke.sh`
