# epoch-converter Troubleshooting

Reference: [ALFRED_WORKFLOW_DEVELOPMENT.md](../../ALFRED_WORKFLOW_DEVELOPMENT.md)

## Quick operator checks

1. Confirm latest package was installed:
   - `scripts/workflow-pack.sh --id epoch-converter --install`
2. Confirm migration state from the old workflow:
   - Old bundle id: `snooze92.epoch.converter`
   - New bundle id: `com.graysurf.epoch-converter`
   - If both workflows use keyword `ts`, Alfred routing can be unpredictable.
3. Confirm script-filter contract output is JSON:
   - `bash workflows/epoch-converter/scripts/script_filter.sh "1700000000" | jq -e '.items | type == "array"'`
4. Confirm expected output rows on epoch input:
   - `Local ISO-like`
   - `UTC ISO-like`
   - `Local formatted (YYYY-MM-DD HH:MM:SS)`

## Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| `epoch-cli binary not found` | Packaged binary missing or runtime path mismatch. | Re-pack workflow, or set `EPOCH_CLI_BIN` to executable path. |
| `Invalid input` | Unsupported query format. | Use epoch integer or supported datetime format (`YYYY-MM-DD HH:MM[:SS]`). |
| Clipboard rows do not appear on empty query | Clipboard tool unavailable/empty clipboard/unparseable clipboard text. | Confirm clipboard has parseable epoch/datetime content; behavior is best-effort. |
| Local/UTC rows differ unexpectedly | Timezone expectation mismatch or DST boundary. | Verify local timezone and compare against UTC rows; test with explicit date+time. |

### macOS Gatekeeper fix

If installed release workflow shows `"epoch-cli" Not Opened`, remove quarantine on the installed workflow package:

```bash
WORKFLOW_DIR="$(for p in "$HOME"/Library/Application\ Support/Alfred/Alfred.alfredpreferences/workflows/*/info.plist; do
  [ -f "$p" ] || continue
  bid="$(plutil -extract bundleid raw -o - "$p" 2>/dev/null || true)"
  [ "$bid" = "com.graysurf.epoch-converter" ] && dirname "$p"
done | head -n1)"

[ -n "$WORKFLOW_DIR" ] || { echo "epoch-converter workflow not found"; exit 1; }
xattr -dr com.apple.quarantine "$WORKFLOW_DIR"
echo "ok: removed quarantine from $WORKFLOW_DIR"
```

Notes:

- `workflows/epoch-converter/scripts/script_filter.sh` does best-effort quarantine cleanup on `epoch-cli` before execution.
- On locked-down macOS environments, manual `xattr -dr` may still be required once after install.

## Validation

- Re-run quick operator checks after any runtime/config change.
- Recommended workflow check: `bash workflows/epoch-converter/tests/smoke.sh`

## Rollback guidance

Use this when conversion output is incorrect or workflow is unstable.

1. Stop rollout of new `epoch-converter` artifacts (pause release/distribution link).
2. Disable/remove installed `epoch-converter` workflow from Alfred.
3. Re-enable the previous `snooze92.epoch.converter` workflow (or re-import previous known-good `.alfredworkflow`).
4. Revert epoch-converter changeset(s), including:
   - `workflows/epoch-converter/`
   - `crates/epoch-cli/`
   - workspace member update in `Cargo.toml`
   - related docs updates (`crates/epoch-cli/docs/workflow-contract.md`, workflow guides)
5. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
