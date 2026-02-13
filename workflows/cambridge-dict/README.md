# Cambridge Dict - Alfred Workflow

Search Cambridge Dictionary from Alfred with a two-stage flow (candidate -> definition detail) and open the selected Cambridge page.

## Screenshot

![Cambridge Dict workflow screenshot](./screenshot.png)

## Features

- Trigger dictionary lookup with `cd <query>`.
- Candidate stage returns headwords and sets Alfred `autocomplete` tokens like `def::open`.
- Detail stage renders definitions from the selected entry.
- Press `Enter` on detail rows to open the entry URL from `arg`.
- Short query guard: `<2` characters shows `Keep typing (2+ chars)` and skips backend calls.
- Uses `cambridge-cli` as the Alfred bridge and Playwright scraper backend.

## Configuration

Set these via Alfred's "Configure Workflow..." UI:

| Variable | Required | Default | Description |
|---|---|---|---|
| `CAMBRIDGE_DICT_MODE` | No | `english` | Dictionary mode. Allowed values: `english`, `english-chinese-traditional`. |
| `CAMBRIDGE_MAX_RESULTS` | No | `8` | Max candidate rows in suggest stage. Effective range is clamped to `1..20`. |
| `CAMBRIDGE_TIMEOUT_MS` | No | `8000` | Playwright timeout in milliseconds. Effective range is clamped to `1000..30000`. |
| `CAMBRIDGE_HEADLESS` | No | `true` | Playwright headless mode flag. Allowed values: `true`, `false`. |

## Keyword

| Keyword | Behavior |
|---|---|
| `cd <query>` | Candidate stage via `cambridge-cli query --input <query>`; selecting candidate transitions with `def::WORD` autocomplete token. |

## Advanced Runtime Parameters

| Parameter | Description |
|---|---|
| `CAMBRIDGE_CLI_BIN` | Optional absolute executable path override for `cambridge-cli`. |
| `CAMBRIDGE_SCRAPER_SCRIPT` | Exported by `script_filter.sh` to point to bundled `scripts/cambridge_scraper.mjs`. |

## Runtime bootstrap

After installing workflow artifact into Alfred, install workflow-local Playwright runtime once:

- `scripts/setup-cambridge-workflow-runtime.sh`

## Deterministic tests (no live network by default)

- Node fixture tests: `npm run test:cambridge-scraper`
- Workflow smoke: `bash workflows/cambridge-dict/tests/smoke.sh`

Live scraping checks are intentionally not part of default smoke gates.

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).
