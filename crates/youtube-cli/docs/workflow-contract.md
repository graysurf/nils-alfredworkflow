# YouTube Search Workflow Contract

## Purpose

This document defines the runtime behavior contract for the `youtube-search` Alfred workflow.
It is the source of truth for query handling, Alfred item JSON shape, truncation behavior,
error-to-feedback mapping, and environment variable constraints.

## Keyword and Query Handling

- Workflow keyword: `yt` (or the configured keyword in Alfred for this workflow object).
- Input query is read from Alfred script filter argument.
- Query normalization:
  - Trim leading/trailing whitespace.
  - Preserve internal spacing and Unicode characters as provided by user input.
- Empty query behavior:
  - Do not call YouTube API.
  - Return one non-actionable Alfred item with:
    - `title = "Enter a search query"`
    - `subtitle = "Type keywords after yt to search YouTube."`
- Short query behavior (`< 2` characters after trim):
  - Do not call YouTube API.
  - Return one non-actionable Alfred item with:
    - `title = "Keep typing (2+ chars)"`
    - `subtitle = "Type at least 2 characters before searching YouTube."`
- Query behavior (`>= 2` characters after trim):
  - Call YouTube Data API v3 `search.list` with `part=snippet` and `type=video`.

## Alfred Item JSON Contract

Top-level output must always be valid Alfred JSON:

```json
{
  "items": []
}
```

Success item schema (video result):

```json
{
  "title": "Video title",
  "subtitle": "Truncated description",
  "arg": "https://www.youtube.com/watch?v=<videoId>"
}
```

Rules:

- `title` is required and sourced from `snippet.title`.
- `subtitle` is required and sourced from normalized + truncated `snippet.description`.
- `arg` is required for result items and must be a canonical YouTube watch URL.
- URL format must be exactly `https://www.youtube.com/watch?v=<videoId>`.

Non-success informational/error items:

- Must still include `title` and `subtitle`.
- Must set `valid: false`.
- Must omit `arg` to prevent accidental open actions.

## Subtitle Truncation Rules

- Source text: `snippet.description`.
- Normalize to a single line:
  - Replace CR/LF/tab with spaces.
  - Collapse repeated spaces.
  - Trim leading/trailing spaces.
- If normalized subtitle length is `<= 120` characters: use as-is.
- If normalized subtitle length is `> 120` characters:
  - Keep first 117 characters.
  - Append `...`.
- If description is empty after normalization: use `No description available`.

## Error Mapping

The workflow must never crash or emit non-JSON output for handled failures.

| Scenario | Detection signal | Alfred title | Alfred subtitle | Item behavior |
| --- | --- | --- | --- | --- |
| Empty query | Query is empty after trim | `Enter a search query` | `Type keywords after yt to search YouTube.` | `valid: false` |
| Short query | Query length is `1` after trim | `Keep typing (2+ chars)` | `Type at least 2 characters before searching YouTube.` | `valid: false` |
| Missing API key | `YOUTUBE_API_KEY` missing or empty | `YouTube API key is missing` | `Set YOUTUBE_API_KEY in workflow configuration and retry.` | `valid: false` |
| Quota exceeded | API error reason includes `quotaExceeded` or `dailyLimitExceeded` | `YouTube quota exceeded` | `Daily quota is exhausted. Retry later or lower YOUTUBE_MAX_RESULTS.` | `valid: false` |
| API unavailable | DNS/TLS/timeout/network failure or upstream `5xx` | `YouTube API unavailable` | `Cannot reach YouTube API now. Check network and retry.` | `valid: false` |
| Empty results | API succeeds but returns zero video items | `No videos found` | `Try broader keywords or a different region.` | `valid: false` |
| Invalid workflow config | Invalid `YOUTUBE_MAX_RESULTS` or `YOUTUBE_REGION_CODE` | `Invalid YouTube workflow config` | `<underlying config error message>` | `valid: false` |

## Environment Variables and Constraints

### `YOUTUBE_API_KEY` (required)

- Required for all live API requests.
- Must be non-empty after trimming.
- If missing/empty, return mapped missing-key Alfred error item (no API call).
- Must not be logged to stdout/stderr in plaintext.

### `YOUTUBE_MAX_RESULTS` (optional)

- Optional integer.
- Default: `10`.
- Parse mode: base-10 integer only.
- Guardrails:
  - Minimum effective value: `1`.
  - Maximum effective value: `25`.
  - Values outside range are clamped to `[1, 25]`.
  - Invalid values return an actionable config error item (`Invalid YouTube workflow config`).

### `YOUTUBE_REGION_CODE` (optional)

- Optional region filter passed as YouTube `regionCode`.
- Must be a 2-letter ISO 3166-1 alpha-2 country code.
- Input is uppercased before request construction.
- Invalid values return an actionable config error item (`Invalid YouTube workflow config`).

## Compatibility Notes

- Contract targets Alfred 5 script filter JSON shape.
- This contract covers `youtube-search` only and does not change `open-project` behavior.
