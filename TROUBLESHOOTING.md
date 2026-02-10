# Development Troubleshooting

## Purpose

- Record recurring development/runtime issues and their fixes in this repository.
- Provide a reusable debugging playbook for future changes (not limited to one workflow).
- Platform split reminder: Alfred runtime issues are macOS-focused; Linux references are mainly for CI/test environments.

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
| `"youtube-cli" Not Opened` / `Apple could not verify ...` | Downloaded/packaged `youtube-cli` carries `com.apple.quarantine`; Gatekeeper blocks execution. | Run quarantine cleanup command below, then retry Alfred query. |

### macOS Gatekeeper fix (youtube-search)

```bash
WORKFLOW_DIR="$(for p in "$HOME"/Library/Application\ Support/Alfred/Alfred.alfredpreferences/workflows/*/info.plist; do
  [ -f "$p" ] || continue
  bid="$(plutil -extract bundleid raw -o - "$p" 2>/dev/null || true)"
  [ "$bid" = "com.graysurf.youtube-search" ] && dirname "$p"
done | head -n1)"

[ -n "$WORKFLOW_DIR" ] || { echo "youtube-search workflow not found"; exit 1; }
xattr -dr com.apple.quarantine "$WORKFLOW_DIR"
echo "ok: removed quarantine from $WORKFLOW_DIR"
```

Notes:

- `workflows/youtube-search/scripts/script_filter.sh` now does best-effort quarantine cleanup on `youtube-cli` before execution.
- On locked-down macOS environments, manual `xattr -dr` may still be required once after install.

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

## Google Search rollout support (Brave backend)

### Quick operator checks

1. Confirm latest package was used:
   - `scripts/workflow-pack.sh --id google-search --install`
2. Confirm Alfred workflow variables are set:
   - `BRAVE_API_KEY` (required)
   - `BRAVE_MAX_RESULTS` (optional)
   - `BRAVE_SAFESEARCH` (optional)
   - `BRAVE_COUNTRY` (optional)
3. Confirm script-filter contract output is JSON:
   - `bash workflows/google-search/scripts/script_filter.sh "rust language" | jq -e '.items | type == "array"'`

### Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| `Brave API key is missing` | `BRAVE_API_KEY` is empty/missing. | Set a valid token in workflow config, then retry. |
| `Brave API quota exceeded` | Rate limit/quota exhausted (`429`/quota errors). | Wait and retry later, reduce query frequency, and lower `BRAVE_MAX_RESULTS`. |
| `Brave API unavailable` | Network/DNS/TLS issue, timeout, or upstream `5xx`. | Check local network/DNS, retry later, and verify Brave API status. |
| `No results found` | Query is too narrow or country/safesearch filters are restrictive. | Use broader keywords or adjust `BRAVE_COUNTRY`/`BRAVE_SAFESEARCH`. |
| `"brave-cli" Not Opened` / `Apple could not verify ...` | Downloaded/packaged `brave-cli` carries `com.apple.quarantine`; Gatekeeper blocks execution. | Run quarantine cleanup command below, then retry Alfred query. |

### macOS Gatekeeper fix (google-search)

```bash
WORKFLOW_DIR="$(for p in "$HOME"/Library/Application\ Support/Alfred/Alfred.alfredpreferences/workflows/*/info.plist; do
  [ -f "$p" ] || continue
  bid="$(plutil -extract bundleid raw -o - "$p" 2>/dev/null || true)"
  [ "$bid" = "com.graysurf.google-search" ] && dirname "$p"
done | head -n1)"

[ -n "$WORKFLOW_DIR" ] || { echo "google-search workflow not found"; exit 1; }
xattr -dr com.apple.quarantine "$WORKFLOW_DIR"
echo "ok: removed quarantine from $WORKFLOW_DIR"
```

Notes:

- `workflows/google-search/scripts/script_filter.sh` does best-effort quarantine cleanup on `brave-cli` before execution.
- On locked-down macOS environments, manual `xattr -dr` may still be required once after install.

### First-release support checklist

- Track missing-key, quota/rate-limit, and API/network errors separately.
- If quota/rate-limit errors spike, lower default `BRAVE_MAX_RESULTS` and notify operators.
- Keep fallback titles/subtitles stable so support can match screenshots quickly.
- Record short incident notes for each production-facing outage window.

### Emergency rollback (google-search)

Use this when Brave API failures are sustained or workflow usability drops sharply.

1. Stop rollout of new `google-search` artifacts (pause release/distribution link).
2. Revert Google-search changeset(s), including:
   - `workflows/google-search/`
   - `crates/brave-cli/`
   - workspace member changes in `Cargo.toml`
   - docs updates tied to rollout (`docs/google-search-contract.md` and rollout references)
3. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
4. Publish known-good artifact set and post operator notice:
   - Explain that `google-search` is temporarily disabled.
   - Provide ETA/workaround and support contact path.

## Wiki Search rollout support

### Quick operator checks

1. Confirm latest package was used:
   - `scripts/workflow-pack.sh --id wiki-search --install`
2. Confirm Alfred workflow variables are set:
   - `WIKI_LANGUAGE` (optional, default `en`)
   - `WIKI_MAX_RESULTS` (optional, default `10`)
3. Confirm script-filter contract output is JSON:
   - `bash workflows/wiki-search/scripts/script_filter.sh "rust language" | jq -e '.items | type == "array"'`

### Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| `Invalid Wiki workflow config` | `WIKI_LANGUAGE` format invalid or `WIKI_MAX_RESULTS` is not a base-10 integer. | Fix variable values and retry (`WIKI_LANGUAGE` lowercase letters `2..12`, `WIKI_MAX_RESULTS` integer). |
| `Wikipedia API unavailable` | Network/DNS/TLS issue, timeout, malformed upstream response, or upstream `5xx`. | Check local network/DNS, retry later, and verify Wikipedia status. |
| `No articles found` | Query is too narrow or selected language has no matching articles. | Use broader keywords or switch `WIKI_LANGUAGE`. |
| `"wiki-cli" Not Opened` / `Apple could not verify ...` | Downloaded/packaged `wiki-cli` carries `com.apple.quarantine`; Gatekeeper blocks execution. | Run quarantine cleanup command below, then retry Alfred query. |

### macOS Gatekeeper fix (wiki-search)

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

### First-release support checklist

- Track invalid-config and API/network failures separately.
- If API-unavailable failures spike, temporarily disable distribution of new `wiki-search` artifacts.
- Keep fallback titles/subtitles stable so support can match screenshots quickly.
- Record short incident notes for each production-facing outage window.

### Emergency rollback (wiki-search)

Use this when Wikipedia API failures are sustained or workflow usability drops sharply.

1. Stop rollout of new `wiki-search` artifacts (pause release/distribution link).
2. Revert Wiki-search changeset(s), including:
   - `workflows/wiki-search/`
   - `crates/wiki-cli/`
   - workspace member changes in `Cargo.toml`
   - docs updates tied to rollout (`docs/wiki-search-contract.md` and workflow guides)
3. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
4. Publish known-good artifact set and post operator notice:
   - Explain that `wiki-search` is temporarily disabled.
   - Provide ETA/workaround and support contact path.

## Epoch Converter rollout support

### Migration notes (from installed `snooze92.epoch.converter`)

- Old bundle id: `snooze92.epoch.converter`
- New bundle id: `com.graysurf.epoch-converter`
- Both workflows can coexist. If both enable keyword `ts`, Alfred may route unpredictably.
- Recommended migration:
  1. Install new package: `scripts/workflow-pack.sh --id epoch-converter --install`
  2. Disable old workflow or change one side's keyword to avoid conflicts.
  3. Verify output contract on epoch input:
     - Includes `Local ISO-like`
     - Includes `UTC ISO-like`
     - Includes `Local formatted (YYYY-MM-DD HH:MM:SS)`

### Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| `epoch-cli binary not found` | Packaged binary missing or runtime path mismatch. | Re-pack workflow, or set `EPOCH_CLI_BIN` to executable path. |
| `Invalid input` | Unsupported query format. | Use epoch integer or supported datetime format (`YYYY-MM-DD HH:MM[:SS]`). |
| Clipboard rows do not appear on empty query | Clipboard tool unavailable/empty clipboard/unparseable clipboard text. | Confirm clipboard has parseable epoch/datetime content; behavior is best-effort. |
| Local/UTC rows differ unexpectedly | Timezone expectation mismatch or DST boundary. | Verify local timezone and compare against UTC rows; test with explicit date+time. |

### Emergency rollback (epoch-converter)

Use this when conversion output is incorrect or workflow is unstable.

1. Disable/remove installed `epoch-converter` workflow from Alfred.
2. Re-enable the previous `snooze92.epoch.converter` workflow (or re-import previous known-good `.alfredworkflow`).
3. Revert epoch-converter changeset(s), including:
   - `workflows/epoch-converter/`
   - `crates/epoch-cli/`
   - workspace member update in `Cargo.toml`
   - related docs updates (`docs/epoch-converter-contract.md`, workflow guides)
4. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`

## Quote Feed rollout support

### Quick operator checks

1. Confirm latest package was used:
   - `scripts/workflow-pack.sh --id quote-feed --install`
2. Confirm Alfred workflow variables are valid:
   - `QUOTE_DISPLAY_COUNT` (optional, default `3`)
   - `QUOTE_REFRESH_INTERVAL` (optional, default `1h`, format `<positive-int><s\|m\|h>`)
   - `QUOTE_FETCH_COUNT` (optional, default `5`)
   - `QUOTE_MAX_ENTRIES` (optional, default `100`)
3. Confirm script-filter contract output is JSON:
   - `bash workflows/quote-feed/scripts/script_filter.sh "" | jq -e '.items | type == "array"'`
4. Confirm cache files are written to the workflow storage path:
   - preferred: `$alfred_workflow_data/quotes.txt` and `$alfred_workflow_data/quotes.timestamp`
   - fallback: `${TMPDIR:-/tmp}/nils-quote-feed/quotes.txt` and `${TMPDIR:-/tmp}/nils-quote-feed/quotes.timestamp`

### Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| `Invalid Quote workflow config` | One or more `QUOTE_*` variables are invalid (for example `QUOTE_REFRESH_INTERVAL=90x`). | Fix variable values in workflow config and retry. |
| `quote-cli binary not found` | Packaged binary missing, wrong runtime path, or invalid `QUOTE_CLI_BIN`. | Re-pack workflow, or set `QUOTE_CLI_BIN` to an executable `quote-cli` path. |
| `Quote refresh unavailable` | ZenQuotes request failed due to network/DNS/TLS/timeout/upstream `5xx`. | Retry later; cached quotes continue to work when local cache exists. |
| `No quotes cached yet` | New install with empty cache and no successful refresh yet. | Retry after network is available, or run again after refresh interval window. |
| `No quotes match query` | Query text is too narrow for current local cache. | Clear query or use broader keywords. |
| `"quote-cli" Not Opened` / `Apple could not verify ...` | Downloaded/packaged `quote-cli` carries `com.apple.quarantine`; Gatekeeper blocks execution. | Run quarantine cleanup command below, then retry Alfred query. |

### macOS Gatekeeper fix (quote-feed)

```bash
WORKFLOW_DIR="$(for p in "$HOME"/Library/Application\ Support/Alfred/Alfred.alfredpreferences/workflows/*/info.plist; do
  [ -f "$p" ] || continue
  bid="$(plutil -extract bundleid raw -o - "$p" 2>/dev/null || true)"
  [ "$bid" = "com.graysurf.quote-feed" ] && dirname "$p"
done | head -n1)"

[ -n "$WORKFLOW_DIR" ] || { echo "quote-feed workflow not found"; exit 1; }
xattr -dr com.apple.quarantine "$WORKFLOW_DIR"
echo "ok: removed quarantine from $WORKFLOW_DIR"
```

Notes:

- `workflows/quote-feed/scripts/script_filter.sh` does best-effort quarantine cleanup on `quote-cli` before execution.
- On locked-down macOS environments, manual `xattr -dr` may still be required once after install.

### Optional rollback guidance (quote-feed)

Use this when quote-feed rollout quality drops and temporary fallback is required.

1. Stop rollout of new `quote-feed` artifacts (pause release/distribution link).
2. Disable/remove installed `quote-feed` workflow from Alfred.
3. Revert quote-feed changeset(s), including:
   - `workflows/quote-feed/`
   - `crates/quote-cli/`
   - workspace member changes in `Cargo.toml`
   - docs updates tied to rollout (`docs/quote-workflow-contract.md`, troubleshooting, workflow guides)
4. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
5. If rollback must preserve previous shell-login quote behavior, continue using legacy bootstrap source:
   - `/Users/terry/.config/zsh/bootstrap/quote-init.zsh`
