# YouTube Search - Alfred Workflow

Search YouTube videos from Alfred and open selected videos in your browser.

## Screenshot

![YouTube Search workflow screenshot](./screenshot.png)

## Features

- Trigger YouTube search with `yt <query>`.
- Show video title and description in Alfred results.
- Open selected YouTube watch URL in your default browser with `Enter`.
- Short query guard: `<2` characters shows `Keep typing (2+ chars)` and skips API calls.
- Script Filter queue policy: 1 second delay with initial immediate run disabled.
- Map common failures (missing API key, quota exceeded, API unavailable, invalid config) to actionable Alfred messages.
- Tune result count and region targeting through workflow variables.

## Configuration

Set these via Alfred's "Configure Workflow..." UI:

| Variable | Required | Default | Description |
|---|---|---|---|
| `YOUTUBE_API_KEY` | Yes | (empty) | YouTube Data API v3 key. |
| `YOUTUBE_MAX_RESULTS` | No | `10` | Max results per query. Effective range is clamped to `1..25`. |
| `YOUTUBE_REGION_CODE` | No | (empty) | Optional ISO 3166-1 alpha-2 region code (for example `US`, `TW`, `JP`). |

## Keyword

| Keyword | Behavior |
|---|---|
| `yt <query>` | Search and list videos, then open selected YouTube URL. |

## Advanced Runtime Parameters

| Parameter | Description |
|---|---|
| `YOUTUBE_CLI_BIN` | Optional override path for `youtube-cli` (useful for local debugging). |

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).
