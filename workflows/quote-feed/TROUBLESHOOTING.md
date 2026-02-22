# quote-feed Troubleshooting

Reference: [ALFRED_WORKFLOW_DEVELOPMENT.md](../../ALFRED_WORKFLOW_DEVELOPMENT.md)

## Quick operator checks

1. Confirm latest package was used:
   - `scripts/workflow-pack.sh --id quote-feed --install`
2. Confirm Alfred workflow variables are valid:
   - `QUOTE_DISPLAY_COUNT` (optional, default `3`)
   - `QUOTE_REFRESH_INTERVAL` (optional, default `1h`, format `<positive-int><s|m|h>`)
   - `QUOTE_FETCH_COUNT` (optional, default `5`)
   - `QUOTE_MAX_ENTRIES` (optional, default `100`)
   - `QUOTE_DATA_DIR` (optional, default empty: overrides cache directory when set)
3. Confirm script-filter contract output is JSON:
   - `bash workflows/quote-feed/scripts/script_filter.sh "" | jq -e '.items | type == "array"'`
4. Confirm cache files are written to the workflow storage path:
   - preferred when set: `$QUOTE_DATA_DIR/quotes.txt` and `$QUOTE_DATA_DIR/quotes.timestamp`
   - otherwise preferred: `$ALFRED_WORKFLOW_DATA/quotes.txt` and `$ALFRED_WORKFLOW_DATA/quotes.timestamp`
   - fallback: `${TMPDIR:-/tmp}/nils-quote-feed/quotes.txt` and `${TMPDIR:-/tmp}/nils-quote-feed/quotes.timestamp`

## Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| `Invalid Quote workflow config` | One or more `QUOTE_*` variables are invalid (for example `QUOTE_REFRESH_INTERVAL=90x`). | Fix variable values in workflow config and retry. |
| `quote-cli binary not found` | Packaged binary missing, wrong runtime path, or invalid `QUOTE_CLI_BIN`. | Re-pack workflow, or set `QUOTE_CLI_BIN` to an executable `quote-cli` path. |
| `Quote refresh unavailable` | ZenQuotes request failed due to network/DNS/TLS/timeout/upstream `5xx`. | Retry later; cached quotes continue to work when local cache exists. |
| `No quotes cached yet` | New install with empty cache and no successful refresh yet. | Retry after network is available, or run again after refresh interval window. |
| `No quotes match query` | Query text is too narrow for current local cache. | Clear query or use broader keywords. |
| `"quote-cli" Not Opened` / `Apple could not verify ...` | Downloaded/packaged `quote-cli` carries `com.apple.quarantine`; Gatekeeper blocks execution. | Run `./workflow-clear-quarantine-standalone.sh --id quote-feed` (from release assets), then retry Alfred query. |

## Validation

- Re-run quick operator checks after any runtime/config change.
- Recommended workflow check: `bash workflows/quote-feed/tests/smoke.sh`

## Rollback guidance

Use this when quote-feed rollout quality drops and temporary fallback is required.

1. Stop rollout of new `quote-feed` artifacts (pause release/distribution link).
2. Disable/remove installed `quote-feed` workflow from Alfred.
3. Revert quote-feed changeset(s), including:
   - `workflows/quote-feed/`
   - `crates/quote-cli/`
   - workspace member changes in `Cargo.toml`
   - docs updates tied to rollout (`crates/quote-cli/docs/workflow-contract.md`, troubleshooting, workflow guides)
4. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
5. If rollback must preserve previous shell-login quote behavior, continue using legacy bootstrap source:
   - `/Users/terry/.config/zsh/bootstrap/quote-init.zsh`
