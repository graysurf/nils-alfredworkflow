# Development Troubleshooting

## Purpose

- Record recurring development/runtime issues and their fixes in this repository.
- Provide a reusable debugging playbook for future changes (not limited to one workflow).

## Quick Triage Checklist

1. Confirm you are testing the current installed artifact, not an older workflow copy.
2. Inspect generated `info.plist` shape and key runtime fields (`type`, `scriptfile`, `connections`).
3. Run scripts directly from the installed workflow directory to isolate Alfred UI factors.
4. Verify action-chain payload handoff (arg formatting, newline/whitespace safety).
5. Add regression assertions into smoke tests when a bug is fixed.

## Case Log

### Case: open-project migration (2026-02-10)

| ID | Symptom | Root Cause | Fix | Verification |
| --- | --- | --- | --- | --- |
| OP-01 | Looked successful, but deleting old workflow broke behavior. | Validation accidentally hit old installed workflow. | Locate installed workflow by `bundleid` before testing. | Resolve `bundleid=com.graysurf.open-project` under Alfred workflows directory. |
| OP-02 | Script Filter finished with no items. | `scriptfile` was set but node `config.type` stayed `0` (inline mode). | Set Script Filter / Action node `config.type=8` for external script mode. | `plutil ... | jq` confirms `config.type == 8`. |
| OP-03 | Error: `No such file or directory: /Users/.../Application` | Command path with spaces was unquoted (`$workflow_cli ...`). | Quote executable path (`"$workflow_cli" ...`). | Run installed `./scripts/script_filter.sh ""` and confirm JSON output. |
| OP-04 | Repo list works, Enter open fails with `not a directory`. | Action chain passed path with trailing newline to open action. | Ensure `record_usage` outputs path without trailing newline; keep strict directory check in open action. | Alfred log shows Script Filter -> Record Usage -> Open completes. |
| OP-05 | Script Filter failure produced blank UI. | Failure path only wrote stderr, no valid Alfred JSON response. | Add fallback error item JSON in `script_filter.sh`. | Deliberately break CLI path and verify `Open Project error` item appears. |
| OP-06 | macOS popup: `"workflow-cli" Not Opened` / `Apple could not verify ...`. | Downloaded release artifact carried `com.apple.quarantine`; Gatekeeper blocked unsigned binary in workflow package. | Runtime scripts now clear quarantine on `workflow-cli` before execution (`xattr -d com.apple.quarantine`). | Trigger Script Filter once after install; workflow loads without Gatekeeper popup. |

## Installed-Workflow Debug Commands

```bash
# 1) Find installed workflow directory by bundle id
for p in "$HOME"/Library/Application\ Support/Alfred/Alfred.alfredpreferences/workflows/*/info.plist; do
  [ -f "$p" ] || continue
  bid=$(plutil -extract bundleid raw -o - "$p" 2>/dev/null || true)
  [ "$bid" = "com.graysurf.open-project" ] && echo "$(dirname "$p")"
done

# 2) Inspect runtime script node config
plutil -convert json -o - "$WORKFLOW_DIR/info.plist" \
  | jq '.objects[] | select(.type=="alfred.workflow.input.scriptfilter") | {uid, config: {type:.config.type, scriptfile:.config.scriptfile}}'

# 3) Execute installed script directly
cd "$WORKFLOW_DIR"
./scripts/script_filter.sh "" | jq '.items | length'
```

## Icon Setup (Workflow Object / Result Items)

Alfred has two different icon layers. If icon behavior looks inconsistent, verify which layer you are changing.

### A) Workflow object icon (Script Filter node icon in Alfred canvas)

- Rule: place a PNG at workflow package root with filename `<OBJECT_UID>.png`.
- Example in this repo: `8F3399E3-951A-4DC0-BC7D-CFA83C1E1F76.png` is the `github` Script Filter object icon.

Find Script Filter object UIDs:

```bash
plutil -convert json -o - "$WORKFLOW_DIR/info.plist" \
  | jq -r '.objects[] | select(.type=="alfred.workflow.input.scriptfilter") | "\(.config.keyword)\t\(.uid)"'
```

Add/replace one object icon manually (installed workflow):

```bash
cp /path/to/github-icon.png "$WORKFLOW_DIR/<OBJECT_UID>.png"
```

Project source location (so packaging keeps it):

- Put file at `workflows/open-project/src/<OBJECT_UID>.png`
- `scripts/workflow-pack.sh` copies `src/*.png` to package root.

### B) Script Filter result-item icon (icon shown for each row in result list)

- Rule: emit `icon.path` in Script Filter JSON item.
- For open-project GitHub mode, this is handled by:
  - `workflows/open-project/scripts/script_filter_github.sh`
  - `workflow-cli script-filter --mode github`
  - feedback item icon path: `assets/icon-github.png`

Quick check:

```bash
cd "$WORKFLOW_DIR"
./scripts/script_filter_github.sh "" | jq -r '.items[0].icon.path'
```

## Regression Guardrails

When touching workflow runtime wiring (`info.plist.template` or script chain), always run:

- `scripts/workflow-lint.sh`
- `bash workflows/open-project/tests/smoke.sh`
- `scripts/workflow-pack.sh --id open-project --install`

## macOS Gatekeeper / Quarantine Fix

If installed release workflow shows `"workflow-cli" Not Opened`, remove quarantine on the installed workflow package:

```bash
WORKFLOW_DIR="$(for p in "$HOME"/Library/Application\ Support/Alfred/Alfred.alfredpreferences/workflows/*/info.plist; do
  [ -f "$p" ] || continue
  bid="$(plutil -extract bundleid raw -o - "$p" 2>/dev/null || true)"
  [ "$bid" = "com.graysurf.open-project" ] && dirname "$p"
done | head -n1)"

[ -n "$WORKFLOW_DIR" ] || { echo "workflow not found"; exit 1; }
xattr -dr com.apple.quarantine "$WORKFLOW_DIR"
echo "ok: removed quarantine from $WORKFLOW_DIR"
```

Notes:

- Runtime scripts also perform best-effort quarantine cleanup on `bin/workflow-cli` automatically.
- This issue only applies to macOS Gatekeeper; Linux runners are unaffected.

## YouTube Search rollout support

### Quick operator checks

1. Confirm latest package was used:
   - `scripts/workflow-pack.sh --id youtube-search --install`
2. Confirm Alfred workflow variables are set:
   - `YOUTUBE_API_KEY` (required)
   - `YOUTUBE_MAX_RESULTS` (optional)
   - `YOUTUBE_REGION_CODE` (optional)
3. Confirm script-filter contract output is JSON:
   - `bash workflows/youtube-search/scripts/script_filter.sh "rust tutorial" | jq -e '.items | type == "array"'`

### Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| `YouTube API key is missing` | `YOUTUBE_API_KEY` is empty/missing. | Set a valid key in workflow config, then retry. |
| `YouTube quota exceeded` | Daily quota exhausted (`quotaExceeded`, `dailyLimitExceeded`). | Wait for quota reset, reduce query frequency, and lower `YOUTUBE_MAX_RESULTS`. |
| `YouTube API unavailable` | Network issue, DNS/TLS issue, timeout, or upstream `5xx`. | Check local network/DNS, retry later, and verify YouTube API status. |
| `No videos found` | Query is too narrow or region filter excludes results. | Use broader keywords or clear/change `YOUTUBE_REGION_CODE`. |

### First-release support checklist

- Track missing-key errors separately from API/network failures.
- If quota failures spike, lower default `YOUTUBE_MAX_RESULTS` and notify operators.
- Keep fallback item titles/subtitles stable so support can match screenshots quickly.
- Record a short incident note for each production-facing outage window.

### Emergency rollback (youtube-search)

Use this when API failures are sustained or workflow usability drops sharply.

1. Stop rollout of new `youtube-search` artifacts (pause release/distribution link).
2. Revert YouTube search changeset(s), including:
   - `workflows/youtube-search/`
   - `crates/youtube-cli/`
   - workspace member changes in `Cargo.toml`
   - docs updates tied to rollout (`docs/youtube-search-contract.md` and rollout references)
3. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
4. Publish known-good artifact set and post operator notice:
   - Explain that `youtube-search` is temporarily disabled.
   - Provide ETA/workaround and support contact path.
