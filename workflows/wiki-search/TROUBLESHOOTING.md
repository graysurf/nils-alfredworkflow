# wiki-search Troubleshooting

Reference: [ALFRED_WORKFLOW_DEVELOPMENT.md](../../ALFRED_WORKFLOW_DEVELOPMENT.md)

## Quick operator checks

1. Confirm latest package was used:
   - `scripts/workflow-pack.sh --id wiki-search --install`
2. Confirm Alfred workflow variables are set:
   - `WIKI_LANGUAGE` (optional, default `en`)
   - `WIKI_MAX_RESULTS` (optional, default `10`)
3. Confirm script-filter contract output is JSON:
   - `bash workflows/wiki-search/scripts/script_filter.sh "rust language" | jq -e '.items | type == "array"'`
4. Confirm queue policy is synced:
   - `bash scripts/workflow-sync-script-filter-policy.sh --check --workflows wiki-search`

## Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| `Invalid Wiki workflow config` | `WIKI_LANGUAGE` format invalid or `WIKI_MAX_RESULTS` is not a base-10 integer. | Fix variable values and retry (`WIKI_LANGUAGE` lowercase letters `2..12`, `WIKI_MAX_RESULTS` integer). |
| `Keep typing (2+ chars)` | Query is shorter than minimum length (`<2`). | Continue typing until at least 2 characters; no API request is sent before that. |
| `Wikipedia API unavailable` | Network/DNS/TLS issue, timeout, malformed upstream response, or upstream `5xx`. | Check local network/DNS, retry later, and verify Wikipedia status. |
| `No articles found` | Query is too narrow or selected language has no matching articles. | Use broader keywords or switch `WIKI_LANGUAGE`. |
| `"wiki-cli" Not Opened` / `Apple could not verify ...` | Downloaded/packaged `wiki-cli` carries `com.apple.quarantine`; Gatekeeper blocks execution. | Run quarantine cleanup command below, then retry Alfred query. |

### macOS Gatekeeper fix

```bash
WORKFLOW_DIR="$(for p in "$HOME"/Library/Application\ Support/Alfred/Alfred.alfredpreferences/workflows/*/info.plist; do
  [ -f "$p" ] || continue
  bid="$(plutil -extract bundleid raw -o - "$p" 2>/dev/null || true)"
  [ "$bid" = "com.graysurf.wiki-search" ] && dirname "$p"
done | head -n1)"

[ -n "$WORKFLOW_DIR" ] || { echo "wiki-search workflow not found"; exit 1; }
xattr -dr com.apple.quarantine "$WORKFLOW_DIR"
echo "ok: removed quarantine from $WORKFLOW_DIR"
```

Notes:

- `workflows/wiki-search/scripts/script_filter.sh` does best-effort quarantine cleanup on `wiki-cli` before execution.
- On locked-down macOS environments, manual `xattr -dr` may still be required once after install.

## Validation

- Re-run quick operator checks after any runtime/config change.
- Recommended workflow check: `bash workflows/wiki-search/tests/smoke.sh`

First-release support checklist:

- Track invalid-config and API/network failures separately.
- If API-unavailable failures spike, temporarily disable distribution of new `wiki-search` artifacts.
- Keep fallback titles/subtitles stable so support can match screenshots quickly.
- Record short incident notes for each production-facing outage window.

## Rollback guidance

Use this when Wikipedia API failures are sustained or workflow usability drops sharply.

1. Stop rollout of new `wiki-search` artifacts (pause release/distribution link).
2. Revert Wiki-search changeset(s), including:
   - `workflows/wiki-search/`
   - `crates/wiki-cli/`
   - workspace member changes in `Cargo.toml`
   - docs updates tied to rollout (`crates/wiki-cli/docs/workflow-contract.md` and workflow guides)
3. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
4. Publish known-good artifact set and post operator notice:
   - Explain that `wiki-search` is temporarily disabled.
   - Provide ETA/workaround and support contact path.
