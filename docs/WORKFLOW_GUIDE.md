# Workflow Guide

## Platform scope

- End-user workflow runtime is macOS-only because Alfred is macOS-only.
- Linux support in this repository is for development/CI validation (lint/test/package), including Ubuntu CI runners.

## Troubleshooting operating model

- Use a two-layer troubleshooting route:
  - Global standards and shared playbooks: [`ALFRED_WORKFLOW_DEVELOPMENT.md`](../ALFRED_WORKFLOW_DEVELOPMENT.md)
  - Workflow-specific runbooks: `workflows/<workflow-id>/TROUBLESHOOTING.md`
- Routing rules:
  1. Cross-workflow failures (Script Filter contract, queue policy, packaging wiring, Gatekeeper) start from global standards.
  2. Workflow-specific failures (keyword flow, workflow env vars, provider/API behavior) start from the workflow-local troubleshooting doc.
  3. If scope is unclear, start global then jump to the workflow-local `Quick operator checks` section.
- Navigation shortcuts:
  - List all workflow-local troubleshooting docs: `rg --files workflows | rg 'TROUBLESHOOTING\.md$'`
  - Open the exact workflow path: `workflows/<workflow-id>/TROUBLESHOOTING.md`

## Add a new workflow

1. `cargo run -p xtask -- workflow new --id <workflow-id>`
2. Edit `workflows/<workflow-id>/workflow.toml`.
3. Update `workflows/<workflow-id>/scripts/*.sh` adapters.
4. Implement or reuse Rust logic from `crates/workflow-common`.
5. Validate and package:
   - `cargo run -p xtask -- workflow lint --id <workflow-id>`
   - `cargo run -p xtask -- workflow test --id <workflow-id>`
   - `cargo run -p xtask -- workflow pack --id <workflow-id> --install`

## Manifest contract

Required keys in `workflow.toml`:

- `id`
- `name`
- `bundle_id`
- `version`
- `script_filter`
- `action`

Optional keys:

- `rust_binary`
- `assets`
- `readme_source`

## README sync during packaging

- `scripts/workflow-pack.sh` auto-syncs workflow README into packaged `info.plist` readme when
  `workflows/<id>/README.md` exists.
- `readme_source` can optionally override the source path (relative to workflow root) when README is
  not at the default location.
- Pack runs `nils-workflow-readme-cli convert` to copy README content into packaged `info.plist`.
- Markdown table blocks are normalized during sync (table downgrade), so packaged Alfred readme
  should not contain separators such as `|---|`.
- If the README references local images (for example `./screenshot.png`), keep those files in the
  workflow root so packaging can stage them into `build/workflows/<id>/pkg/`.
- Validation command:
  `bash -c 'scripts/workflow-pack.sh --id codex-cli && plutil -convert json -o - build/workflows/codex-cli/pkg/info.plist | jq -r ".readme" | rg -n "# Codex CLI - Alfred Workflow|\\|---\\|"'`

## Open Project workflow details

`workflows/open-project` is the reference implementation for the current `workflow-cli` contract.

### Environment defaults

- `PROJECT_DIRS = "$HOME/Project,$HOME/.config"`
- `OPEN_PROJECT_MAX_RESULTS = "30"` (clamped to `1..200`)
- `USAGE_FILE = "$HOME/.config/zsh/cache/.alfred_project_usage.log"`
- `VSCODE_PATH = "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"`

### Alfred command flow

- Keywords: `c`, `code`, `github`.
- Script filter: `workflows/open-project/scripts/script_filter.sh` -> `workflow-cli script-filter`.
- Enter flow: `action_record_usage.sh` -> `action_open.sh`.
- Shift flow: `action_record_usage.sh` -> `action_open_github.sh`.

## YouTube Search workflow details

`workflows/youtube-search` is a dedicated workflow that uses `youtube-cli` for YouTube API-backed
search feedback.

### Environment variables

- `YOUTUBE_API_KEY` (required): YouTube Data API v3 key.
- `YOUTUBE_MAX_RESULTS` (optional): default `10`, clamped to `1..25`.
- `YOUTUBE_REGION_CODE` (optional): 2-letter country code, uppercased before request.

### Alfred command flow

- Keyword trigger: `yt`.
- Script filter adapter: `workflows/youtube-search/scripts/script_filter.sh` ->
  `youtube-cli search --query "<query>"`.
- Enter flow: `workflows/youtube-search/scripts/action_open.sh` opens selected `arg` URL.

### Operator validation checklist

Run these before packaging/release:

- `bash workflows/youtube-search/tests/smoke.sh`
- `scripts/workflow-test.sh --id youtube-search`
- `scripts/workflow-pack.sh --id youtube-search`

Runtime checks:

- Missing `YOUTUBE_API_KEY` must return an Alfred error item (not malformed JSON).
- Quota/API failures must return non-actionable error items.
- Empty API results must return a clear `No videos found` guidance item.

## Google Search workflow details

`workflows/google-search` is a dedicated workflow that uses `brave-cli` for Brave API-backed
web search feedback while keeping the Alfred workflow name/keyword oriented to Google-style usage.

### Environment variables

- `BRAVE_API_KEY` (required): Brave Search API subscription token.
- `BRAVE_MAX_RESULTS` (optional): default `10`, clamped to `1..20`.
- `BRAVE_SAFESEARCH` (optional): `strict`, `moderate`, or `off`; default `moderate`.
- `BRAVE_COUNTRY` (optional): 2-letter country code, uppercased before request.

### Alfred command flow

- Keyword trigger: `gg`.
- Script filter adapter: `workflows/google-search/scripts/script_filter.sh` ->
  `brave-cli search --query "<query>"`.
- Enter flow: `workflows/google-search/scripts/action_open.sh` opens selected `arg` URL.

### Operator validation checklist

Run these before packaging/release:

- `bash workflows/google-search/tests/smoke.sh`
- `scripts/workflow-test.sh --id google-search`
- `scripts/workflow-pack.sh --id google-search`

Runtime checks:

- Missing `BRAVE_API_KEY` must return an Alfred error item (not malformed JSON).
- Quota/rate-limit and API/network failures must return non-actionable error items.
- Empty API results must return a clear `No results found` guidance item.

## Wiki Search workflow details

`workflows/wiki-search` is a dedicated workflow that uses `wiki-cli` for Wikipedia API-backed
article search feedback.

### Environment variables

- `WIKI_LANGUAGE` (optional): lowercase Wikipedia language code; default `en`.
- `WIKI_MAX_RESULTS` (optional): default `10`, clamped to `1..20`.

### Alfred command flow

- Keyword trigger: `wk`.
- Script filter adapter: `workflows/wiki-search/scripts/script_filter.sh` ->
  `wiki-cli search --query "<query>"`.
- Enter flow: `workflows/wiki-search/scripts/action_open.sh` opens selected `arg` URL.

### Operator validation checklist

Run these before packaging/release:

- `bash workflows/wiki-search/tests/smoke.sh`
- `scripts/workflow-test.sh --id wiki-search`
- `scripts/workflow-pack.sh --id wiki-search`

Runtime checks:

- Invalid `WIKI_LANGUAGE`/`WIKI_MAX_RESULTS` must return an Alfred config error item.
- API/network failures must return non-actionable error items.
- Empty API results must return a clear `No articles found` guidance item.

## Bilibili Search workflow details

`workflows/bilibili-search` is a dedicated workflow that uses `bilibili-cli` for bilibili
suggestion API-backed search feedback.

### Environment variables

- `BILIBILI_UID` (optional): bilibili UID passed as suggest endpoint `userid` for personalized
  ranking.
- `BILIBILI_MAX_RESULTS` (optional): default `10`, clamped to `1..20`.
- `BILIBILI_TIMEOUT_MS` (optional): default `8000`, clamped to `1000..30000`.
- `BILIBILI_USER_AGENT` (optional): explicit User-Agent override.
- `BILIBILI_CLI_BIN` (optional): executable path override for `bilibili-cli`.

### Alfred command flow

- Keyword trigger: `bl`.
- Script filter adapter: `workflows/bilibili-search/scripts/script_filter.sh` ->
  `bilibili-cli query --input "<query>" --mode alfred`.
- Enter flow: `workflows/bilibili-search/scripts/action_open.sh` opens selected `arg` URL.

### Operator validation checklist

Run these before packaging/release:

- `bash workflows/bilibili-search/tests/smoke.sh`
- `scripts/workflow-test.sh --id bilibili-search`
- `scripts/workflow-pack.sh --id bilibili-search`

Runtime checks:

- Script filter must always return valid Alfred JSON fallback items on failure.
- Invalid `BILIBILI_MAX_RESULTS`/`BILIBILI_TIMEOUT_MS` must map to config guidance rows.
- Empty suggest results must still expose a direct-search fallback row.

## Cambridge Dict workflow details

`workflows/cambridge-dict` is a dedicated workflow that uses `cambridge-cli` plus a bundled
Playwright scraper (`scripts/cambridge_scraper.mjs`) for Cambridge Dictionary lookups.

### Environment variables

- `CAMBRIDGE_DICT_MODE` (optional): `english` or `english-chinese-traditional`; default `english`.
- `CAMBRIDGE_MAX_RESULTS` (optional): default `8`, clamped to `1..20`.
- `CAMBRIDGE_TIMEOUT_MS` (optional): default `8000`, clamped to `1000..30000`.
- `CAMBRIDGE_HEADLESS` (optional): `true` or `false`; default `true`.
- `CAMBRIDGE_CLI_BIN` (optional): executable path override for `cambridge-cli`.

### Alfred command flow

- Keyword trigger: `cd`.
- Script filter adapter: `workflows/cambridge-dict/scripts/script_filter.sh` ->
  `cambridge-cli query --input "<query>"`.
- Candidate stage emits `autocomplete` token `def::WORD`.
- Detail stage is triggered by `def::WORD` and returns rows with URL `arg`.
- Enter flow: `workflows/cambridge-dict/scripts/action_open.sh` opens selected URL.

### Operator validation checklist

Run these before packaging/release:

- `npm run test:cambridge-scraper`
- `bash workflows/cambridge-dict/tests/smoke.sh`
- `scripts/workflow-test.sh --id cambridge-dict`
- `scripts/workflow-pack.sh --id cambridge-dict`

Runtime checks:

- Script filter must always return valid Alfred JSON fallback items on failure.
- Missing Node/Playwright runtime must map to actionable non-crashing error items.
- Smoke tests remain deterministic and offline by default (fixture/stub based, no live Cambridge request).

## Bangumi Search workflow details

`workflows/bangumi-search` is a dedicated workflow that uses `bangumi-cli` for API-first Bangumi
subject search. It also includes a future Playwright bridge scaffold (`scripts/bangumi_scraper.mjs`)
that is currently disabled by default.

### Environment variables

- `BANGUMI_API_KEY` (optional): API token for authenticated requests; default empty.
- `BANGUMI_MAX_RESULTS` (optional): default `10`, clamped to `1..20`.
- `BANGUMI_TIMEOUT_MS` (optional): default `8000`, clamped to `1000..30000`.
- `BANGUMI_USER_AGENT` (optional): explicit User-Agent override; default empty (use CLI default).
- `BANGUMI_CACHE_DIR` (optional): image-cache directory override.
- `BANGUMI_IMAGE_CACHE_TTL_SECONDS` (optional): default `86400`.
- `BANGUMI_IMAGE_CACHE_MAX_MB` (optional): default `128`.
- `BANGUMI_API_FALLBACK` (optional): `auto`, `never`, or `always`; default `auto`.
- `BANGUMI_CLI_BIN` (optional): executable path override for `bangumi-cli`.

### Alfred command flow

- Keyword trigger: `bgm`.
- Script filter adapter: `workflows/bangumi-search/scripts/script_filter.sh` ->
  `bangumi-cli query --input "<query>" --mode alfred`.
- Enter flow: `workflows/bangumi-search/scripts/action_open.sh` opens selected `arg` URL.
- Type grammar: `[type] query`, where type is one of `all|book|anime|music|game|real`.

### Operator validation checklist

Run these before packaging/release:

- `node --test workflows/bangumi-search/scripts/tests/bangumi_scraper_contract.test.mjs`
- `bash workflows/bangumi-search/tests/smoke.sh`
- `scripts/workflow-test.sh --id bangumi-search`
- `scripts/workflow-pack.sh --id bangumi-search`

Runtime checks:

- Script filter must always return valid Alfred JSON fallback items on failure.
- `scripts/script_filter.sh` must not reference `bangumi_scraper.mjs` in default runtime path.
- Playwright bridge scaffold remains disabled by default unless explicit rollout gates are met.

## Epoch Converter workflow details

`workflows/epoch-converter` is a local conversion workflow that uses `epoch-cli` for epoch/datetime
conversion and copy-ready Alfred items.

### Environment variables

- `EPOCH_CLI_BIN` (optional): absolute executable path override for `epoch-cli`.

### Alfred command flow

- Keyword trigger: `ts`.
- Script filter adapter: `workflows/epoch-converter/scripts/script_filter.sh` ->
  `epoch-cli convert --query "<query>"`.
- Enter flow: `workflows/epoch-converter/scripts/action_copy.sh` copies selected `arg` via `pbcopy`.

### Operator validation checklist

Run these before packaging/release:

- `bash workflows/epoch-converter/tests/smoke.sh`
- `scripts/workflow-test.sh --id epoch-converter`
- `scripts/workflow-pack.sh --id epoch-converter`

Runtime checks:

- Empty query should return current timestamp rows (plus optional clipboard-derived rows), not malformed JSON.
- Epoch input output should include `Local formatted (YYYY-MM-DD HH:MM:SS)` row.
- Invalid input and missing `epoch-cli` should return non-actionable error items.

## Multi Timezone workflow details

`workflows/multi-timezone` is a dedicated workflow that uses `timezone-cli` for IANA timezone-based
current-time lookup and copy-ready Alfred items.

### Environment variables

- `TIMEZONE_CLI_BIN` (optional): absolute executable path override for `timezone-cli`.
- `MULTI_TZ_ZONES` (optional): default timezone list for empty query; supports comma/newline
  separated IANA timezone IDs.
- `MULTI_TZ_LOCAL_OVERRIDE` (optional, default `Europe/London`): local timezone override used when
  query/config zones are both empty.

### Alfred command flow

- Keyword trigger: `tz`.
- Script filter adapter: `workflows/multi-timezone/scripts/script_filter.sh` ->
  `timezone-cli now --query "<query>" --config-zones "$MULTI_TZ_ZONES"`.
- Enter flow: `workflows/multi-timezone/scripts/action_copy.sh` copies selected `arg` via `pbcopy`.

### Operator validation checklist

Run these before packaging/release:

- `bash workflows/multi-timezone/tests/smoke.sh`
- `scripts/workflow-test.sh --id multi-timezone`
- `scripts/workflow-pack.sh --id multi-timezone`

Runtime checks:

- Missing `timezone-cli` must return a non-actionable `timezone-cli binary not found` error item.
- Invalid timezone input must return an `Invalid timezone` guidance item.
- Empty query should use `MULTI_TZ_ZONES`; if empty, fallback to local timezone resolution in
  `timezone-cli` (starting from default `MULTI_TZ_LOCAL_OVERRIDE=Europe/London`).

## Quote Feed workflow details

`workflows/quote-feed` is a dedicated workflow that uses `quote-cli` for cached quote browsing
and interval-based ZenQuotes refresh.

### Environment variables

- `QUOTE_DISPLAY_COUNT` (optional): default `3`, clamped to `1..20`.
- `QUOTE_REFRESH_INTERVAL` (optional): default `1h`, format `<positive-int><s|m|h>`.
- `QUOTE_FETCH_COUNT` (optional): default `5`, clamped to `1..20`.
- `QUOTE_MAX_ENTRIES` (optional): default `100`, clamped to `1..1000`.
- `QUOTE_DATA_DIR` (optional): default empty; when set, overrides quote cache directory.
- `QUOTE_CLI_BIN` (optional): absolute executable path override for `quote-cli`.

### Alfred command flow

- Keyword trigger: `qq` (supports optional query filter).
- Script filter adapter: `workflows/quote-feed/scripts/script_filter.sh` ->
  `quote-cli feed --query "<query>"`.
- Enter flow: `workflows/quote-feed/scripts/action_copy.sh` copies selected `arg` via `pbcopy`.

### Operator validation checklist

Run these before packaging/release:

- `bash workflows/quote-feed/tests/smoke.sh`
- `scripts/workflow-test.sh --id quote-feed`
- `scripts/workflow-pack.sh --id quote-feed`

Runtime checks:

- Invalid `QUOTE_*` values must return `Invalid Quote workflow config` Alfred error items.
- Missing `quote-cli` must return a non-actionable `quote-cli binary not found` error item.
- ZenQuotes/network refresh failures must return `Quote refresh unavailable`; cached quotes should
  still be shown when available.

## Memo Add workflow details

`workflows/memo-add` is a dedicated workflow that uses `memo-workflow-cli` and
`nils-memo-cli@0.3.8` storage primitives for fast memo capture/search.

### Environment variables

- `MEMO_DB_PATH` (optional): sqlite path override; default empty (auto-resolve).
- `MEMO_SOURCE` (optional): source label for new memo rows; default `alfred`.
- `MEMO_REQUIRE_CONFIRM` (optional): confirmation gate flag; default `0`.
- `MEMO_MAX_INPUT_BYTES` (optional): default `4096`, valid `1..=1048576`.
- `MEMO_RECENT_LIMIT` (optional): default `8`, valid `1..=50`, controls empty-query recent row count.
- `MEMO_SEARCH_MATCH` (optional): default `fts`, allowed `fts|prefix|contains` for `mmq/search` default mode.
- `MEMO_WORKFLOW_CLI_BIN` (optional): absolute executable path override for `memo-workflow-cli`.

### Alfred command flow

- Keyword triggers: `mm`, `mmr`, `mma`, `mmu`, `mmd`, `mmc`, `mmq`.
- Command-entry adapter: `workflows/memo-add/scripts/script_filter_entry.sh` ->
  static command menu for memo keywords.
- Intent script-filter adapter: `workflows/memo-add/scripts/script_filter.sh` ->
  `memo-workflow-cli script-filter --query "<query>"` (used by `mma/mmu/mmd/mmc/mmq` wrappers).
- Search keyword adapter: `workflows/memo-add/scripts/script_filter_search.sh` ->
  defaults to prepending `search` intent for plain queries, but passes through explicit intents (`item|update|delete|copy|search`) for follow-up manage steps.
- Latest-list keyword adapter: `workflows/memo-add/scripts/script_filter_recent.sh` ->
  renders recent memo rows (newest first), and maps numeric input to item-id lookup.
- Enter flow: `workflows/memo-add/scripts/action_run.sh` ->
  `memo-workflow-cli action --token "<token>"`.
- Empty query returns guidance + `db-init` row + latest memo rows (newest first).
- Intent examples:
  - `mm` -> command entry menu (Enter on row appends suffix and switches directly to target keyword).
  - `mmr` -> show recent memo rows (newest first).
  - `mmr 123` -> open memo item action menu for id `123` (full menu: copy/update/delete).
  - `mmu` / `mmd` / `mmc` -> show recent memo rows (newest first; same default as `mmr`).
  - `mmq` -> search mode keyword (`search <query>` intent).
  - `mmu 123` -> update flow for id `123` (single update row).
  - `mmd 123` -> delete flow for id `123` (single delete row).
  - `mmc 123` -> copy flow for id `123` (single copy row).
  - `mmq milk` -> always return non-actionable search rows; Enter routes to `item <item_id>` action menu.
  - `mma buy milk` -> add token (`add::<text>`).
  - `mmu itm_00000001 buy oat milk` -> update token (`update::<item_id>::<text>`).
  - `mmd itm_00000001` -> delete token (`delete::<item_id>`; hard-delete).
  - `mmc itm_00000001` -> copy token (`copy::<item_id>`).
  - malformed mutation query (`mmu <id>`, `mmd <id> <extra>`, `mmc <id> <extra>`) -> non-actionable guidance row.

### Operator validation checklist

Run these before packaging/release:

- `bash workflows/memo-add/tests/smoke.sh`
- `scripts/workflow-test.sh --id memo-add`
- `scripts/workflow-pack.sh --id memo-add`

Runtime checks:

- `mmr` view must include one actionable `db init` row when DB is missing, or recent list rows when DB exists.
- `mmu` / `mmd` / `mmc` with empty query must render the same newest-first recent list behavior as `mmr`.
- `mmq` empty query must return non-actionable search guidance row.
- `mmr <id>` returns full item menu rows (copy/update/delete); `mmq <query>` rows stay non-actionable and route via `autocomplete=item <item_id>`.
- multi-hit search rows must be non-destructive (`valid=false`) and route by `autocomplete=item <item_id>`.
- Invalid `MEMO_*` values must return a non-actionable config error item.
- Add action must persist one row and return success text from action script.
- Invalid `item_id` for update/delete/copy must be rejected as user error (non-actionable Alfred error item).
- Malformed mutation query/token syntax must not crash and must return guidance or action error text.

## Codex CLI workflow details

`workflows/codex-cli` bundles `codex-cli` from crate `nils-codex-cli@0.3.8`
into the packaged `.alfredworkflow` artifact (release-coupled runtime version).

### Environment variables

- `CODEX_CLI_BIN` (optional): absolute executable path override for `codex-cli`.
- `CODEX_SECRET_DIR` (optional): secret directory override for `auth save` / `auth remove` / `auth use` /
  `diag` operations.
  If empty, runtime fallback is `$XDG_CONFIG_HOME/codex_secrets` or `~/.config/codex_secrets`.
- `CODEX_SHOW_ASSESSMENT` (optional): default `0`; set to truthy value (`1/true/yes/on`) to show
  assessment rows by default in script filter results.
- `CODEX_DIAG_CACHE_TTL_SECONDS` (optional): default `300`; cache TTL in seconds for
  `cxau` / `cxd` / `cxda` auto refresh (`0` means always refresh before render).
- `CODEX_DIAG_CACHE_BLOCK_WAIT_SECONDS` (optional): default `15`; maximum seconds to wait when
  another process is already refreshing the same diag cache mode.
- `CODEX_LOGIN_TIMEOUT_SECONDS` (optional): login timeout in seconds, default `60`
  (valid range `1..3600`).
- `CODEX_API_KEY` (optional): API key source for `auth login --api-key`; if unset on macOS,
  action script prompts via AppleScript dialog.
- `CODEX_SAVE_CONFIRM` (optional): default enabled (`1`); when enabled and `--yes` is not set,
  save action asks confirmation before writing.
- `CODEX_REMOVE_CONFIRM` (optional): default enabled (`1`); when enabled and `--yes` is not set,
  remove action asks confirmation, then executes `auth remove --yes`.
- `CODEX_CLI_PACK_BIN` (packaging only, optional): explicit source binary path for bundling.
- `CODEX_CLI_PACK_INSTALL_ROOT` (packaging only, optional): override the auto-install root used when
  pinned crates.io runtime install is needed.

### Alfred command flow

- Keyword triggers:
  - `cx`: command palette (auth/use/save/remove/diag)
  - `cxa`: auth-focused alias
  - `cxau`: auth use-focused alias (current + all JSON picker)
  - `cxd`: diag-focused alias
  - `cxda`: diag all-accounts JSON-focused alias
  - `cxs`: save-focused alias
  - `cxr`: remove-focused alias
- Script filter adapter: `workflows/codex-cli/scripts/script_filter.sh` provides command
  assessment + executable items, plus cached diag result rendering.
- Enter flow: `workflows/codex-cli/scripts/action_open.sh` runs mapped command tokens.

Supported actions in this workflow:

- `auth login`
- `auth login --api-key`
- `auth login --device-code`
- `auth use <secret>`
- `auth save [--yes] <secret.json>`
- `auth remove [--yes] <secret.json>`
- `diag rate-limits` presets (`default`, `--cached`, `--one-line`, `--all`, `--all --json`,
  `--all --async --jobs 4`)

Diag result behavior:

- `cxd` / `cxda` menu blocks to refresh diag cache when cache is missing/expired, then renders.
- Stale diag cache is not rendered for `cxau` / `cxd` / `cxda`.
- `cxd` default refresh/action uses `diag rate-limits --json` and parses single-account rows.
- `cxda result` parses JSON output and renders one account per row.
- `cxda result` rows are sorted by `weekly_reset_epoch` ascending (earliest reset first).
- Parsed row subtitle format is `<email> | reset <weekly_reset_local>`.

Auth use behavior:

- `cxau` first row shows current secret JSON parsed from `codex-cli auth current` output.
- Remaining rows list `*.json` files from `CODEX_SECRET_DIR` fallback path.
- When no saved `*.json` exists, `cxau` still shows current `auth.json` info (for example email).
- Selecting a row runs `codex-cli auth use <secret>`.
- `cxau alpha` runs `codex-cli auth use alpha` directly.

No `CODEX_SECRET_DIR` saved secrets behavior:

- `cxda` falls back from `diag rate-limits --all --json` to `diag rate-limits --json`
  (current auth diagnostic).
- `cxd` / `cxda` menu still renders current auth hint rows before secret-directory setup.

Runtime resolution order:

1. `CODEX_CLI_BIN`
2. bundled `./bin/codex-cli`
3. `PATH` `codex-cli` fallback

Packaging resolution order for bundled `codex-cli@0.3.8`:

1. `CODEX_CLI_PACK_BIN` (if set)
2. local `PATH` `codex-cli`
3. auto-install pinned `nils-codex-cli@0.3.8` from crates.io via `cargo install --locked --root <cache-root>`

### Operator validation checklist

Run these before packaging/release:

- `bash workflows/codex-cli/tests/smoke.sh`
- `scripts/workflow-test.sh --id codex-cli`
- `scripts/workflow-pack.sh --id codex-cli`

Runtime checks:

- End-user import from release artifact should run without extra install.
- Bundled runtime target is macOS arm64.
- `save` secret file names must reject path traversal and invalid characters.
- `use` secret names must reject path traversal and invalid characters.
- `save` without `--yes` should require explicit confirmation unless `CODEX_SAVE_CONFIRM=0`.
- `remove` without `--yes` should require explicit confirmation unless `CODEX_REMOVE_CONFIRM=0`.
- Login actions should honor `CODEX_LOGIN_TIMEOUT_SECONDS` (default 60s).
- `diag --all --json` parsed rows should be sorted by earliest weekly reset first.
- Action script must preserve non-zero exit status when `codex-cli` fails.

### Validation checklist

Run these before packaging/release:

- `cargo test -p nils-workflow-common`
- `cargo test -p nils-workflow-cli`
- `bash workflows/open-project/tests/smoke.sh`
- `scripts/workflow-test.sh --id open-project`
- `scripts/workflow-pack.sh --id open-project`
