# nils-alfredworkflow

Monorepo for Alfred workflows with shared Rust crates and thin Bash adapters.

## Quick start

1. Bootstrap Rust + cargo tools:
   - `scripts/setup-rust-tooling.sh`
2. Validate workspace:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
3. Package one workflow:
   - `cargo run -p xtask -- workflow pack --id open-project`
4. Package all workflows:
   - `cargo run -p xtask -- workflow pack --all`

## Workspace crates

- `crates/alfred-core`: Alfred feedback data model (`items`, optional `mods`, `variables`).
- `crates/alfred-plist`: `info.plist` template rendering helpers.
- `crates/workflow-common`: Shared open-project domain logic (scan, usage log, git metadata, feedback assembly).
- `crates/workflow-cli`: Shared binary for script-filter/action adapters.
- `crates/xtask`: Task runner for workflow list/lint/test/pack/new.

## Workflows

- `workflows/open-project`: parity port of `open-project-in-vscode`.
- `workflows/_template`: scaffold template used by `scripts/workflow-new.sh`.
- `workflows/google-search`: Alfred keyword search for Google-style web results (Brave API backend).
- `workflows/youtube-search`: Alfred keyword search for YouTube videos (API-key based).
- `workflows/spotify-search`: Alfred keyword search for Spotify tracks (Client Credentials flow).
- `workflows/epoch-converter`: Alfred epoch/datetime converter with copy-on-enter actions.

## Google Search quick start

1. Package + install:
   - `cargo run -p xtask -- workflow pack --id google-search --install`
2. In Alfred workflow variables, set:
   - `BRAVE_API_KEY` (required)
   - `BRAVE_MAX_RESULTS` (optional, default `10`, clamped to `1..20`)
   - `BRAVE_SAFESEARCH` (optional, default `moderate`, allowed `strict|moderate|off`)
   - `BRAVE_COUNTRY` (optional, 2-letter country code, e.g. `US`, `TW`)
3. Use keyword in Alfred:
   - `gg <query>`

Operator notes:

- `google-search` uses Brave Search API as backend and returns web results.
- If rate limits are hit frequently, reduce `BRAVE_MAX_RESULTS` and retry with lower request frequency.
- Contract and error mapping are defined in `docs/google-search-contract.md`.

## YouTube Search quick start

1. Package + install:
   - `cargo run -p xtask -- workflow pack --id youtube-search --install`
2. In Alfred workflow variables, set:
   - `YOUTUBE_API_KEY` (required)
   - `YOUTUBE_MAX_RESULTS` (optional, default `10`, clamped to `1..25`)
   - `YOUTUBE_REGION_CODE` (optional, 2-letter country code, e.g. `US`, `TW`)
3. Use keyword in Alfred:
   - `yt <query>`

Operator notes:

- Each `search.list` request consumes YouTube quota (high cost endpoint).
- If you hit quota often, reduce `YOUTUBE_MAX_RESULTS` and avoid rapid repeated queries.
- Contract and error mapping are defined in `docs/youtube-search-contract.md`.

## Spotify Search quick start

1. Copy-paste package + validation flow:
   - `scripts/workflow-test.sh --id spotify-search`
   - `scripts/workflow-pack.sh --id spotify-search --install`
2. Required credentials (Alfred workflow variables):
   - `SPOTIFY_CLIENT_ID`
   - `SPOTIFY_CLIENT_SECRET`
3. Optional tuning (Alfred workflow variables):
   - `SPOTIFY_MAX_RESULTS` (optional, default `10`, clamped to `1..50`)
   - `SPOTIFY_MARKET` (optional, 2-letter country code, e.g. `US`, `TW`)
4. Use keyword in Alfred:
   - `sp query-text`

Operator notes:

- `spotify-search` is search-only MVP: query tracks and open Spotify URLs in browser.
- `SPOTIFY_CLIENT_SECRET` is stored locally in Alfred variables; treat the machine as trusted.
- Contract and error mapping are defined in `docs/spotify-search-contract.md`.

## Epoch Converter quick start

1. Package + install:
   - `scripts/workflow-test.sh --id epoch-converter`
   - `scripts/workflow-pack.sh --id epoch-converter --install`
2. Use keyword in Alfred:
   - `ts <epoch-or-datetime>`
   - `ts` (show current epoch rows + best-effort clipboard conversion rows)
3. Select any row and press Enter to copy the value.

Operator notes:

- Epoch input includes an extra formatted row: `Local formatted (YYYY-MM-DD HH:MM:SS)`.
- If `epoch-cli` is not found in packaged/debug/release path, set optional workflow variable `EPOCH_CLI_BIN`.
- Contract and error mapping are defined in `docs/epoch-converter-contract.md`.

## Open Project behavior contract

`open-project` keeps parity-sensitive behavior via environment variables:

- `PROJECT_DIRS`: comma-separated roots (supports `$HOME` and `~`).
- `USAGE_FILE`: usage timestamp log path.
- `VSCODE_PATH`: editor executable used by `action_open.sh`.

The shared CLI surface used by Alfred scripts:

- `workflow-cli script-filter --query "<query>"` -> prints Alfred JSON only.
- `workflow-cli record-usage --path "<project-path>"` -> prints plain path only.
- `workflow-cli github-url --path "<project-path>"` -> prints canonical GitHub URL only.

## Command surface

- `cargo run -p xtask -- workflow list`
- `cargo run -p xtask -- workflow lint [--id <workflow>]`
- `cargo run -p xtask -- workflow test [--id <workflow>]`
- `cargo run -p xtask -- workflow pack --id <workflow> [--install]`
- `cargo run -p xtask -- workflow pack --all`
- `cargo run -p xtask -- workflow new --id <workflow>`

## License

This project is dedicated to the public domain under [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/).
See `LICENSE` for the full legal text.
