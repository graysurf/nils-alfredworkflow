# Google Search Workflow Contract

## Purpose

This document defines the runtime behavior contract for the `google-search` Alfred workflow.
It is the source of truth for query handling, Alfred item JSON shape, truncation behavior,
error-to-feedback mapping, and environment variable constraints.

## Keyword and Query Handling

- Workflow keyword (two-stage): `gg`.
- Direct Brave-search keyword: `gb`.
- Input query is read from Alfred script filter argument.
- Query normalization:
  - Trim leading/trailing whitespace.
  - Preserve internal spacing and Unicode characters as provided by user input.

Two-stage (`gg`) token grammar:

- Suggest stage input: arbitrary query text (`rust`, `rust async`, ...).
- Suggest stage output rows expose Alfred `autocomplete` tokens:
  - `res::<QUERY>`
- Search stage input: query string beginning with `res::`.
- Search stage output rows map to Brave web search results.

Direct mode (`gb`) behavior:

- Query behavior (`>= 2` characters after trim):
  - Call Brave backend (`brave-cli search --query <query>`) to fetch web results.

Shared empty/short query behavior in workflow script adapters:

- Empty query:
  - Return one non-actionable Alfred item.
- Short query (`< 2` characters after trim):
  - Return one non-actionable Alfred item and skip backend calls.

## Alfred Item JSON Contract

Top-level output must always be valid Alfred JSON:

```json
{
  "items": []
}
```

Suggest-stage item schema (two-stage `gg`):

```json
{
  "title": "Suggestion text",
  "subtitle": "Search \"Suggestion text\" | Press Tab to load search results",
  "autocomplete": "res::Suggestion text",
  "valid": false
}
```

Search-stage success item schema (`gg` second stage and `gb` direct):

```json
{
  "title": "Result title",
  "subtitle": "Truncated snippet",
  "arg": "https://example.com"
}
```

Rules:

- Suggest-stage rows:
  - `title` is required and sourced from suggestion text.
  - `autocomplete` is required and uses `res::<query>` grammar.
  - `valid` must be `false` to force stage transition via autocomplete.
- Search-stage rows:
  - `title` is required and sourced from Brave result title.
  - `subtitle` is required and sourced from normalized + truncated result description/snippet.
  - `arg` is required for result items and must be the canonical result URL.

Non-success informational/error items:

- Must still include `title` and `subtitle`.
- Must set `valid: false`.
- Must omit `arg` to prevent accidental open actions.

## Subtitle Truncation Rules

- Source text: Brave result snippet/description.
- Normalize to a single line:
  - Replace CR/LF/tab with spaces.
  - Collapse repeated spaces.
  - Trim leading/trailing spaces.
- If normalized subtitle length is `<= 120` characters: use as-is.
- If normalized subtitle length is `> 120` characters:
  - Keep first 117 characters.
  - Append `...`.
- If snippet is empty after normalization: use `No description available`.

## Error Mapping

The workflow must never crash or emit non-JSON output for handled failures.

| Scenario | Detection signal | Alfred title | Alfred subtitle | Item behavior |
| --- | --- | --- | --- | --- |
| Empty query | Query is empty after trim | `Enter a search query` | Workflow-specific guidance (`gg` or `gb`) | `valid: false` |
| Short query | Query length is `1` after trim | `Keep typing (2+ chars)` | Workflow-specific minimum-length guidance | `valid: false` |
| Suggest backend unavailable | Google suggest request/parse failure | `Google suggestions unavailable` | Retry or use `gb` direct Brave search | `valid: false` |
| Missing API key | `BRAVE_API_KEY` missing or empty | `Brave API key is missing` | `Set BRAVE_API_KEY in workflow configuration and retry.` | `valid: false` |
| Quota/rate limited | Error includes quota/rate-limit/HTTP 429 signals | `Brave API quota exceeded` | `Rate quota is exhausted. Retry later or lower BRAVE_MAX_RESULTS.` | `valid: false` |
| API unavailable | Transport/network/TLS/DNS failures or upstream `5xx` | `Brave API unavailable` | `Cannot reach Brave API now. Check network and retry.` | `valid: false` |
| Invalid workflow config | Invalid `BRAVE_MAX_RESULTS`, `BRAVE_SAFESEARCH`, or `BRAVE_COUNTRY` | `Invalid Brave workflow config` | `<underlying config error message>` | `valid: false` |

## Environment Variables and Constraints

### `BRAVE_API_KEY` (required)

- Required for live API requests.
- Must be non-empty after trimming.
- If missing/empty, return mapped missing-key Alfred error item (no API call).
- Must not be logged to stdout/stderr in plaintext.

### `BRAVE_MAX_RESULTS` (optional)

- Optional integer.
- Default: `10`.
- Parse mode: base-10 integer only.
- Guardrails:
  - Minimum effective value: `1`.
  - Maximum effective value: `20`.
  - Values outside range are clamped to `[1, 20]`.
  - Invalid values return an actionable config error item (`Invalid Brave workflow config`).

### `BRAVE_SAFESEARCH` (optional)

- Optional safe-search mode.
- Allowed values: `strict`, `moderate`, `off`.
- Default: `moderate`.
- Invalid values return an actionable config error item (`Invalid Brave workflow config`).

### `BRAVE_COUNTRY` (optional)

- Optional country bias for Brave Search API requests.
- Must be uppercase 2-letter ISO 3166-1 alpha-2 value when provided.
- Invalid values return an actionable config error item (`Invalid Brave workflow config`).

## Compatibility Notes

- Contract targets Alfred 5 script filter JSON shape.
- This contract covers `google-search` only and does not change other workflows.
