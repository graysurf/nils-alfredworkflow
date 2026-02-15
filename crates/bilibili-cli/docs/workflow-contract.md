# Bilibili Search Workflow Contract

## Purpose

This document defines the runtime behavior contract for the `bilibili-search` Alfred workflow.
It is the source of truth for query handling, request contract, Alfred item mapping,
error-to-feedback mapping, and environment variable constraints.

## Keyword and Query Handling

- Workflow keyword: `bl` (or the configured keyword in Alfred for this workflow object).
- Input query is read from Alfred script filter argument.
- Query normalization:
  - Trim leading/trailing whitespace.
  - Preserve Unicode and internal spacing semantics from user input.
- Empty query behavior:
  - Do not call bilibili suggest endpoint.
  - Return one non-actionable Alfred item with:
    - `title = "Enter a search query"`
    - `subtitle = "Type keywords after bl to search Bilibili."`
- Short query behavior (`< 2` characters after trim):
  - Do not call bilibili suggest endpoint.
  - Return one non-actionable Alfred item with:
    - `title = "Keep typing (2+ chars)"`
    - `subtitle = "Type at least 2 characters before searching Bilibili."`
- Query behavior (`>= 2` characters after trim):
  - Call `https://s.search.bilibili.com/main/suggest` with:
    - `term=<query>`
    - `userid=<BILIBILI_UID>` when configured and non-empty

## Request Contract

- Method: `GET`
- Endpoint: `https://s.search.bilibili.com/main/suggest`
- Required query param: `term`
- Optional query param: `userid`
- Timeout: `BILIBILI_TIMEOUT_MS` effective value
- User-Agent: `BILIBILI_USER_AGENT` or default `nils-bilibili-cli/...`

## Alfred Item Mapping

Top-level output must always be valid Alfred JSON:

```json
{
  "items": []
}
```

Success item schema (suggestion row):

```json
{
  "title": "Suggestion text",
  "subtitle": "Search bilibili for Suggestion text",
  "arg": "https://search.bilibili.com/all?keyword=<percent-encoded-query>",
  "autocomplete": "Suggestion text"
}
```

Rules:

- `title` maps from suggest response `result.tag[].value`.
- `arg` must always use canonical bilibili search URL with percent-encoded query.
- URL canonicalization rule:
  - base: `https://search.bilibili.com/all`
  - query parameter: `keyword`
- Empty suggestions must include direct-search fallback row:
  - Title: `Search bilibili directly`
  - `arg`: canonical search URL for the original query.

## Error Mapping

The workflow must never crash or emit non-JSON output for handled failures.

| Scenario | Detection signal | Alfred title | Alfred subtitle | Item behavior |
| --- | --- | --- | --- | --- |
| Empty query | Query is empty after trim | `Enter a search query` | `Type keywords after bl to search Bilibili.` | `valid: false` |
| Short query | Query length is `1` after trim | `Keep typing (2+ chars)` | `Type at least 2 characters before searching Bilibili.` | `valid: false` |
| Invalid config | `BILIBILI_MAX_RESULTS` or `BILIBILI_TIMEOUT_MS` fails parsing | `Invalid Bilibili workflow config` | `Check BILIBILI_MAX_RESULTS and BILIBILI_TIMEOUT_MS, then retry.` | `valid: false` |
| No suggestions | API success but `result.tag` empty | `No suggestions found` | `Press Enter to search bilibili directly.` | first row `valid: false`, fallback row actionable |
| API unavailable | DNS/TLS/timeout/network failure, upstream `5xx`, or malformed response | `Bilibili API unavailable` | `Cannot reach bilibili now. Check network and retry.` | `valid: false` |

## Environment Variables

### `BILIBILI_UID` (optional)

- Optional user identifier forwarded as `userid` query param for personalized suggestions.
- Empty value means anonymous suggestion mode.

### `BILIBILI_MAX_RESULTS` (optional)

- Optional integer controlling max suggestion rows returned by CLI.
- Default: `10`.
- Effective range: clamp to `1..20`.

### `BILIBILI_TIMEOUT_MS` (optional)

- Optional integer request timeout in milliseconds.
- Default: `8000`.
- Effective range: clamp to `1000..30000`.

### `BILIBILI_USER_AGENT` (optional)

- Optional explicit User-Agent override for API requests.
- Empty value uses CLI default UA.

## Compatibility Notes

- Contract targets Alfred 5 script filter JSON shape.
- This contract covers `bilibili-search` only and does not change other workflows.
