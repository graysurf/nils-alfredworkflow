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

## Workflow: open-project

### Quick operator checks

1. Confirm latest package was installed:
   - `scripts/workflow-pack.sh --id open-project --install`
2. Confirm you are testing the current installed workflow copy:
   - Resolve installed path by `bundleid=com.graysurf.open-project`.
3. Inspect runtime node config in installed `info.plist`:
   - Script nodes should use external script mode (`config.type=8`) with expected `scriptfile`.
4. Run scripts directly from the installed workflow directory:
   - `./scripts/script_filter.sh "" | jq '.items | length'`
5. Verify action-chain payload handoff:
   - Confirm `Script Filter -> Record Usage -> Open` keeps path args without trailing newline.

### Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| Looks successful, but deleting old workflow breaks behavior. | Validation accidentally hit an old installed workflow copy. | Locate installed workflow by `bundleid` before testing and verify target path explicitly. |
| Script Filter finishes with no items. | `scriptfile` is set but node `config.type` stayed `0` (inline mode). | Set Script Filter / Action node `config.type=8` for external script mode, then re-pack/reinstall. |
| Error: `No such file or directory: /Users/.../Application` | Command path with spaces was unquoted (`$workflow_cli ...`). | Quote executable path (`"$workflow_cli" ...`) and verify JSON output from installed script. |
| Repo list works, but Enter open fails with `not a directory`. | Action chain passed path with trailing newline to open action. | Ensure `record_usage` emits path without trailing newline; keep strict directory check in open action. |
| Script Filter failure shows blank UI. | Failure path only writes stderr and returns no Alfred JSON response. | Add fallback error item JSON in `script_filter.sh` so failures still render in Alfred. |
| `"workflow-cli" Not Opened` / `Apple could not verify ...` | Packaged binary carries `com.apple.quarantine`; Gatekeeper blocks execution. | Clear quarantine on installed workflow package (or rely on runtime best-effort cleanup) and retry. |

### Installed-workflow debug commands (open-project)

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

### Icon setup (open-project)

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

### Regression guardrails (open-project)

When touching workflow runtime wiring (`info.plist.template` or script chain), always run:

- `scripts/workflow-lint.sh`
- `bash workflows/open-project/tests/smoke.sh`
- `scripts/workflow-pack.sh --id open-project --install`

### macOS Gatekeeper fix (open-project)

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

### Rollback guidance (open-project)

Use this when open-project behavior regresses and a fast fallback is required.

1. Stop rollout of new `open-project` artifacts (pause release/distribution link).
2. Revert open-project changeset(s), including:
   - `workflows/open-project/`
   - `crates/workflow-cli/`
   - related docs updates tied to open-project rollout.
3. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
4. Publish known-good artifact set and post operator notice.

## Workflow: youtube-search

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

### Rollback guidance (youtube-search)

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

## Workflow: google-search

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

### Rollback guidance (google-search)

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

## Workflow: wiki-search

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

### Rollback guidance (wiki-search)

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

## Workflow: epoch-converter

### Quick operator checks

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

### Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| `epoch-cli binary not found` | Packaged binary missing or runtime path mismatch. | Re-pack workflow, or set `EPOCH_CLI_BIN` to executable path. |
| `Invalid input` | Unsupported query format. | Use epoch integer or supported datetime format (`YYYY-MM-DD HH:MM[:SS]`). |
| Clipboard rows do not appear on empty query | Clipboard tool unavailable/empty clipboard/unparseable clipboard text. | Confirm clipboard has parseable epoch/datetime content; behavior is best-effort. |
| Local/UTC rows differ unexpectedly | Timezone expectation mismatch or DST boundary. | Verify local timezone and compare against UTC rows; test with explicit date+time. |

### macOS Gatekeeper fix (epoch-converter)

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

### Rollback guidance (epoch-converter)

Use this when conversion output is incorrect or workflow is unstable.

1. Stop rollout of new `epoch-converter` artifacts (pause release/distribution link).
2. Disable/remove installed `epoch-converter` workflow from Alfred.
3. Re-enable the previous `snooze92.epoch.converter` workflow (or re-import previous known-good `.alfredworkflow`).
4. Revert epoch-converter changeset(s), including:
   - `workflows/epoch-converter/`
   - `crates/epoch-cli/`
   - workspace member update in `Cargo.toml`
   - related docs updates (`docs/epoch-converter-contract.md`, workflow guides)
5. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`

## Workflow: multi-timezone

### Quick operator checks

1. Confirm latest package was used:
   - `scripts/workflow-pack.sh --id multi-timezone --install`
2. Confirm Alfred workflow variables are valid:
   - `TIMEZONE_CLI_BIN` (optional; executable timezone-cli override path)
   - `MULTI_TZ_ZONES` (optional; comma/newline separated IANA timezone IDs)
   - `MULTI_TZ_LOCAL_OVERRIDE` (optional; default `Europe/London`, used in local fallback mode)
3. Confirm script-filter contract output is JSON:
   - `bash workflows/multi-timezone/scripts/script_filter.sh "Asia/Taipei,America/New_York" | jq -e '.items | type == "array"'`
4. Confirm empty-query fallback behavior:
   - `MULTI_TZ_ZONES="" MULTI_TZ_LOCAL_OVERRIDE="Asia/Taipei" bash workflows/multi-timezone/scripts/script_filter.sh "" | jq -e '.items[0].uid == "Asia/Taipei"'`

### Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| `Invalid timezone` | Query/config includes non-IANA timezone IDs (for example typos such as `Asia/Taipe` or unsupported zones). | Replace with valid IANA timezone IDs (`Region/City`, for example `Asia/Taipei`) and keep comma/newline separators only. |
| `timezone-cli binary not found` | Packaged binary missing, `TIMEZONE_CLI_BIN` points to non-executable path, or runtime path resolution failed. | Re-pack workflow, or set `TIMEZONE_CLI_BIN` to an executable `timezone-cli` path and retry. |
| `Timezone runtime failure` | `timezone-cli` hit runtime/IO failure (timeout/internal error/panic). | Retry query, inspect stderr from `script_filter.sh`, and verify `timezone-cli` build/runtime integrity. |
| Empty `tz` query shows unexpected local timezone or `UTC` | Query and `MULTI_TZ_ZONES` are both empty, so fallback chain uses `MULTI_TZ_LOCAL_OVERRIDE` first (default `Europe/London`); terminal fallback is `UTC` when all probes fail. | Set `MULTI_TZ_ZONES` or `MULTI_TZ_LOCAL_OVERRIDE` for deterministic output; otherwise treat `UTC` as expected safe fallback. |

### macOS Gatekeeper fix (multi-timezone)

```bash
WORKFLOW_DIR="$(for p in "$HOME"/Library/Application\ Support/Alfred/Alfred.alfredpreferences/workflows/*/info.plist; do
  [ -f "$p" ] || continue
  bid="$(plutil -extract bundleid raw -o - "$p" 2>/dev/null || true)"
  [ "$bid" = "com.graysurf.multi-timezone" ] && dirname "$p"
done | head -n1)"

[ -n "$WORKFLOW_DIR" ] || { echo "multi-timezone workflow not found"; exit 1; }
xattr -dr com.apple.quarantine "$WORKFLOW_DIR"
echo "ok: removed quarantine from $WORKFLOW_DIR"
```

Notes:

- `workflows/multi-timezone/scripts/script_filter.sh` does best-effort quarantine cleanup on resolved `timezone-cli` path before execution.
- On macOS, local-timezone detection may call `/usr/sbin/systemsetup -gettimezone`; probe failures are non-fatal and continue through fallback chain.
- If all local-timezone probes fail, `timezone-cli` intentionally falls back to `UTC` instead of returning a hard error.
- `workflows/multi-timezone/scripts/action_copy.sh` uses `pbcopy`, so copy action runtime is macOS-only (Linux usage is for CI/test validation).

### Rollback guidance (multi-timezone)

Use this when timezone output is unstable or local fallback behavior regresses.

1. Stop rollout of new `multi-timezone` artifacts (pause release/distribution link).
2. Revert Multi Timezone changeset(s), including:
   - `workflows/multi-timezone/`
   - `crates/timezone-cli/`
   - workspace member changes in `Cargo.toml`
   - docs updates tied to rollout (`docs/multi-timezone-contract.md`, `docs/WORKFLOW_GUIDE.md`, and troubleshooting references)
3. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
4. Publish known-good artifact set and post operator notice:
   - Explain that `multi-timezone` is temporarily disabled.
   - Provide ETA/workaround and support contact path.

## Workflow: quote-feed

### Quick operator checks

1. Confirm latest package was used:
   - `scripts/workflow-pack.sh --id quote-feed --install`
2. Confirm Alfred workflow variables are valid:
   - `QUOTE_DISPLAY_COUNT` (optional, default `3`)
   - `QUOTE_REFRESH_INTERVAL` (optional, default `1h`, format `<positive-int><s\|m\|h>`)
   - `QUOTE_FETCH_COUNT` (optional, default `5`)
   - `QUOTE_MAX_ENTRIES` (optional, default `100`)
   - `QUOTE_DATA_DIR` (optional, default empty: overrides cache directory when set)
3. Confirm script-filter contract output is JSON:
   - `bash workflows/quote-feed/scripts/script_filter.sh "" | jq -e '.items | type == "array"'`
4. Confirm cache files are written to the workflow storage path:
   - preferred when set: `$QUOTE_DATA_DIR/quotes.txt` and `$QUOTE_DATA_DIR/quotes.timestamp`
   - otherwise preferred: `$alfred_workflow_data/quotes.txt` and `$alfred_workflow_data/quotes.timestamp`
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

### Rollback guidance (quote-feed)

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

## Workflow: memo-add

### Quick operator checks

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

### Common failures and actions

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

## Workflow: cambridge-dict

### Quick operator checks

1. Confirm latest package was used:
   - `scripts/workflow-pack.sh --id cambridge-dict --install`
2. Confirm Alfred workflow variables are valid:
   - `CAMBRIDGE_DICT_MODE` (`english` or `english-chinese-traditional`)
   - `CAMBRIDGE_MAX_RESULTS` (optional, default `8`)
   - `CAMBRIDGE_TIMEOUT_MS` (optional, default `8000`)
   - `CAMBRIDGE_HEADLESS` (optional, default `true`)
3. Confirm installed workflow runtime is available:
   - `scripts/setup-cambridge-workflow-runtime.sh --check-only --skip-browser`
4. Confirm deterministic workflow/Node checks pass:
   - `npm run test:cambridge-scraper`
   - `bash workflows/cambridge-dict/tests/smoke.sh`

### Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| `cambridge-cli binary not found` | Packaged binary missing or runtime path mismatch. | Re-pack workflow, or set `CAMBRIDGE_CLI_BIN` to executable path. |
| `Node/Playwright runtime unavailable` | `node` missing, workflow-local `playwright` package missing, or Chromium browser not installed for live scraping. | Run `scripts/setup-cambridge-workflow-runtime.sh` and retry. |
| `Cambridge anti-bot challenge` | Cambridge returned Cloudflare/anti-bot page. | Retry later, reduce query frequency, or open Cambridge page directly in browser. |
| `Cambridge cookie consent required` | Cookie wall rendered instead of dictionary content. | Open Cambridge Dictionary in browser once, accept cookies, then retry Alfred query. |
| `Cambridge request timed out` | Timeout too low for current network/page latency. | Increase `CAMBRIDGE_TIMEOUT_MS` and retry. |
| `Invalid Cambridge workflow config` | Invalid mode/max-results/timeout/headless values. | Correct `CAMBRIDGE_*` variables in Alfred config. |

### Deterministic vs live checks

- Default smoke/test commands are fixture/stub based and do not require live Cambridge network calls.
- If you need to validate live scraping behavior, run manual checks separately and treat failures as external-site noise unless reproduced with fixtures.

### Rollback guidance (cambridge-dict)

Use this when anti-bot/cookie/network volatility makes the workflow unstable.

1. Stop rollout of new `cambridge-dict` artifacts.
2. Revert Cambridge workflow changeset(s), including:
   - `workflows/cambridge-dict/`
   - `docs/cambridge-dict-contract.md`
   - docs updates in `README.md`, `docs/WORKFLOW_GUIDE.md`, and `TROUBLESHOOTING.md`
3. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
