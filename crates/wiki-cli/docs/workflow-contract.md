# Wiki Search Workflow Contract

## Purpose

This document defines the runtime behavior contract for the `wiki-search` Alfred workflow.
It is the source of truth for query handling, Alfred item JSON shape, snippet normalization
and truncation, error-to-feedback mapping, and environment variable constraints.

## Keyword and Query Handling

- Workflow keyword: `wk` (or the configured keyword in Alfred for this workflow object).
- Input query is read from Alfred script filter argument.
- Query normalization:
  - Trim leading/trailing whitespace.
  - Preserve internal spacing and Unicode characters as provided by user input.
- Empty query behavior:
  - Do not call MediaWiki API.
  - Return one non-actionable Alfred item with:
    - `title = "Enter a search query"`
    - `subtitle = "Type keywords after wk to search Wikipedia."`
- Short query behavior (`< 2` characters after trim):
  - Do not call MediaWiki API.
  - Return one non-actionable Alfred item with:
    - `title = "Keep typing (2+ chars)"`
    - `subtitle = "Type at least 2 characters before searching Wikipedia."`
- Query behavior (`>= 2` characters after trim):
  - Call MediaWiki Action API `https://{language}.wikipedia.org/w/api.php` with:
    - `action=query`
    - `list=search`
    - `format=json`
    - `utf8=1`
    - `srsearch=<query>`
    - `srlimit=<WIKI_MAX_RESULTS effective value>`
    - `srprop=snippet`

## Alfred Item JSON Contract

Top-level output must always be valid Alfred JSON:

```json
{
  "items": []
}
```

Success item schema (article result):

```json
{
  "title": "Article title",
  "subtitle": "Normalized and truncated snippet",
  "arg": "https://{language}.wikipedia.org/?curid={pageid}"
}
```

Rules:

- `title` is required and sourced from MediaWiki search result `title`.
- `subtitle` is required and sourced from normalized + truncated MediaWiki `snippet`.
- `arg` is required for result items and must be the canonical article URL.
- Canonical URL format must be exactly `https://{language}.wikipedia.org/?curid={pageid}`.

Non-success informational/error items:

- Must still include `title` and `subtitle`.
- Must set `valid: false`.
- Must omit `arg` to prevent accidental open actions.

## Snippet Normalization and Truncation

- Source text: MediaWiki `snippet` field (HTML fragment).
- Normalize to a single line:
  - Remove all HTML tags, including search highlight tags such as
    `<span class="searchmatch">...</span>`.
  - Decode common HTML entities: `&quot;`, `&#39;`, `&amp;`, `&lt;`, `&gt;`, `&nbsp;`.
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
| Empty query | Query is empty after trim | `Enter a search query` | `Type keywords after wk to search Wikipedia.` | `valid: false` |
| Short query | Query length is `1` after trim | `Keep typing (2+ chars)` | `Type at least 2 characters before searching Wikipedia.` | `valid: false` |
| Invalid config | `WIKI_LANGUAGE` fails validation or `WIKI_MAX_RESULTS` cannot be parsed as base-10 integer | `Invalid Wiki workflow config` | `Check WIKI_LANGUAGE and WIKI_MAX_RESULTS, then retry.` | `valid: false` |
| No results | API succeeds but returns zero search items | `No articles found` | `Try broader keywords or switch WIKI_LANGUAGE.` | `valid: false` |
| API unavailable | DNS/TLS/timeout/network failure, upstream `5xx`, or malformed API response | `Wikipedia API unavailable` | `Cannot reach Wikipedia now. Check network and retry.` | `valid: false` |

## Environment Variables and Constraints

### `WIKI_LANGUAGE` (optional)

- Optional lowercase Wikipedia language code used as the subdomain for both API host and canonical article URL host.
- Default: `en`.
- Input is trimmed and lowercased before validation.
- Allowed format: lowercase ASCII letters only, length `2..12` (`^[a-z]{2,12}$`).
- Invalid values return an actionable config error item (`Invalid Wiki workflow config`).

### `WIKI_MAX_RESULTS` (optional)

- Optional integer controlling MediaWiki `srlimit`.
- Default: `10`.
- Parse mode: base-10 integer only.
- Effective value is clamped to `1..20`.
- Values below `1` clamp to `1`; values above `20` clamp to `20`.
- Non-integer values return an actionable config error item (`Invalid Wiki workflow config`).

## Compatibility Notes

- Contract targets Alfred 5 script filter JSON shape.
- This contract covers `wiki-search` only and does not change other workflows.
- Canonical URL strategy is `curid`-based and independent of localized page title slugs.
