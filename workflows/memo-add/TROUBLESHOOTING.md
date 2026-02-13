# memo-add Troubleshooting

Reference: [ALFRED_WORKFLOW_DEVELOPMENT.md](../../ALFRED_WORKFLOW_DEVELOPMENT.md)

## Quick operator checks

1. Confirm latest package was used:
   - `scripts/workflow-pack.sh --id memo-add --install`
2. Confirm Alfred workflow variables are valid:
   - `MEMO_DB_PATH` (optional, default empty)
   - `MEMO_SOURCE` (optional, default `alfred`)
   - `MEMO_REQUIRE_CONFIRM` (optional, default `0`)
   - `MEMO_MAX_INPUT_BYTES` (optional, default `4096`)
   - `MEMO_RECENT_LIMIT` (optional, default `8`, range `1..50`)
   - `MEMO_WORKFLOW_CLI_BIN` (optional, default empty)
3. Confirm script-filter JSON contract:
   - `bash workflows/memo-add/scripts/script_filter.sh "buy milk" | jq -e '.items | type == "array"'`
   - `bash workflows/memo-add/scripts/script_filter_search.sh "milk" | jq -e '.items | type == "array"'`
4. Confirm db init and CRUD action behavior:
   - `bash workflows/memo-add/scripts/action_run.sh "db-init"`
   - `bash workflows/memo-add/scripts/action_run.sh "add::buy milk"`
   - `bash workflows/memo-add/scripts/action_run.sh "update::itm_00000001::buy oat milk"`
   - `bash workflows/memo-add/scripts/action_run.sh "delete::itm_00000001"`

## Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| `Invalid Memo workflow config` | Invalid `MEMO_*` values (for example non-integer `MEMO_MAX_INPUT_BYTES`). | Fix workflow variables and retry. |
| `memo-workflow-cli binary not found` | Package missing binary or invalid `MEMO_WORKFLOW_CLI_BIN`. | Re-pack workflow, or set `MEMO_WORKFLOW_CLI_BIN` to executable path. |
| `add requires a non-empty memo text` | Empty/whitespace query was sent to add action. | Enter non-empty memo text after `mm`. |
| `memo text exceeds MEMO_MAX_INPUT_BYTES` | Query text length exceeded configured max bytes. | Increase `MEMO_MAX_INPUT_BYTES` or shorten memo content. |
| `invalid item_id` | Update/delete target id is malformed or does not exist in current DB. | Re-run `mm` to read recent ids, then retry with exact `itm_########` id in the same `MEMO_DB_PATH`. |
| `Invalid mutation syntax` / `malformed update/delete token` | Query/token does not match required grammar (`update <item_id> <text>`, `delete <item_id>`, `update::<item_id>::<text>`, `delete::<item_id>`). | Fix mutation syntax and retry; malformed syntax should return guidance/error rows, not executable actions. |
| `Type search text after keyword` | `mmq` or `search` intent was called without query text. | Enter search text after `mmq` (for example `mmq milk`). |
| `invalid MEMO_SEARCH_MATCH` | `MEMO_SEARCH_MATCH` is not one of `fts`, `prefix`, or `contains`. | Set `MEMO_SEARCH_MATCH` to a valid mode (default `fts`). |
| `memo action failed` | `action_run.sh` received a bad token, or runtime returned exit `1`/`2`. | Run token directly for diagnostics: `memo-workflow-cli action --token "<token>"`; fix user/config error first, then re-run Alfred action. |
| `invalid MEMO_RECENT_LIMIT` | `MEMO_RECENT_LIMIT` is not an integer in `1..50`. | Set a valid integer (for example `8`) and retry `mm`. |
| Empty query shows no recent rows after successful add | Wrong DB path/source is being used between add and query. | Verify `MEMO_DB_PATH`, rerun `db-init`, then run `mm` again. |
| `database open failed` / `database write failed` | Target DB path not writable or parent directory inaccessible. | Update `MEMO_DB_PATH` to writable path and rerun `db-init`. |

## Validation

- Re-run quick operator checks after any runtime/config change.
- Recommended workflow check: `bash workflows/memo-add/tests/smoke.sh`

## Rollback guidance

Use this when memo-add behavior regresses and operators need a fast fallback.

1. Stop rollout of new `memo-add` artifacts (pause release/distribution link).
2. Disable/remove installed `memo-add` workflow from Alfred until the fallback package is ready.
3. Revert memo-add changeset(s), including:
   - `workflows/memo-add/`
   - `crates/memo-workflow-cli/`
   - workspace member changes in `Cargo.toml`
   - docs updates tied to rollout (`crates/memo-workflow-cli/docs/workflow-contract.md`, workflow guides, troubleshooting)
4. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
5. Publish known-good artifact set and post operator notice.
