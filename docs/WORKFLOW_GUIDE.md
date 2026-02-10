# Workflow Guide

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

## Open Project workflow details

`workflows/open-project` is the reference implementation for the current `workflow-cli` contract.

### Environment defaults

- `PROJECT_DIRS = "$HOME/Project,$HOME/.config"`
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

### Validation checklist

Run these before packaging/release:

- `cargo test -p workflow-common`
- `cargo test -p workflow-cli`
- `bash workflows/open-project/tests/smoke.sh`
- `scripts/workflow-test.sh --id open-project`
- `scripts/workflow-pack.sh --id open-project`
