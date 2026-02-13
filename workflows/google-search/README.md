# Google Search - Alfred Workflow

Search web results from Alfred using Brave Search API and open selected links in your browser.

## Screenshot

![Google Search workflow screenshot](./screenshot.png)

## Features

- Trigger web search with `gg <query>`.
- Show result title and snippet directly in Alfred.
- Open selected URL in your default browser with `Enter`.
- Short query guard: `<2` characters shows `Keep typing (2+ chars)` and skips API calls.
- Script Filter queue policy: 1 second delay with initial immediate run disabled.
- Script-level guardrails: async query coalescing (final query priority) and short TTL cache reduce duplicate API calls while typing.
- Map common failures (missing API key, rate limiting, API unavailable, invalid config) to actionable Alfred messages.
- Tune result count, safe search mode, and country bias through workflow variables.

## Configuration

Set these via Alfred's "Configure Workflow..." UI:

| Variable | Required | Default | Description |
|---|---|---|---|
| `BRAVE_API_KEY` | Yes | (empty) | Brave Search API subscription token. |
| `BRAVE_MAX_RESULTS` | No | `10` | Max results per query. Effective range is clamped to `1..20`. |
| `BRAVE_SAFESEARCH` | No | `moderate` | Safe search mode: `strict`, `moderate`, or `off`. |
| `BRAVE_COUNTRY` | No | (empty) | Optional uppercase ISO 3166-1 alpha-2 country code (for example `US`, `TW`, `JP`). |

## Keyword

| Keyword | Behavior |
|---|---|
| `gg <query>` | Search and list web results, then open selected URL. |

## Advanced Runtime Parameters

| Parameter | Description |
|---|---|
| `BRAVE_CLI_BIN` | Optional override path for `brave-cli` (useful for local debugging). |
| `BRAVE_QUERY_CACHE_TTL_SECONDS` | Optional same-query cache TTL (seconds). Default `10`. |
| `BRAVE_QUERY_COALESCE_SETTLE_SECONDS` | Optional coalesce settle window (seconds). Default `2`. |
| `BRAVE_QUERY_COALESCE_RERUN_SECONDS` | Optional Alfred rerun interval while waiting for async result. Default `0.4`. |

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).
