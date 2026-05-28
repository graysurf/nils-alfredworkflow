# Steam Search Workflow Contract

> Status: active

## Purpose

This document defines the `nils-steam-cli` runtime contract for `steam-search`: query handling,
region/language runtime config, Steam Store API usage, Alfred JSON mapping, region-switch requery
args, and deterministic error behavior.

Cross-references:

- Workflow-level Steam contract:
  [`docs/specs/steam-search-workflow-contract.md`](../../../docs/specs/steam-search-workflow-contract.md)
- Shared runtime + envelope: [`docs/specs/cli-shared-runtime-contract.md`](../../../docs/specs/cli-shared-runtime-contract.md)
- JSON envelope shape: [`docs/specs/cli-json-envelope-v1.md`](../../../docs/specs/cli-json-envelope-v1.md)
- Reserved error-code prefix (future allocation): [`docs/specs/cli-error-code-registry.md`](../../../docs/specs/cli-error-code-registry.md)

## Keyword and Query Handling

- Command: `steam-cli search --query <QUERY>`.
- Query normalization:
  - Trim leading/trailing whitespace.
  - Preserve internal spacing and Unicode content.
- Empty query behavior:
  - Do not call Steam Store API.
  - Return user error `query must not be empty` (stderr in Alfred mode).
  - The workflow Script Filter routes empty input to `steam-cli specials` instead
    of surfacing this error (see Specials Command).

## Specials Command

- Command: `steam-cli specials`.
- Lists current Steam Store specials (a discount ranking) for the configured
  region/language, used by the workflow when the query is empty.
- Source: `https://store.steampowered.com/api/featuredcategories` (official API,
  no scraping). Test override: `STEAM_FEATURED_CATEGORIES_ENDPOINT`.
- The `specials` carousel alone is capped at ~10, so the CLI merges discounted
  titles across `specials`, `top_sellers`, `new_releases`, and `coming_soon`,
  dedupes by app id, keeps only discounted items, and ranks by discount percent
  descending.
- `featuredcategories` returns integer minor units plus a currency code with no
  pre-formatted price string; the CLI formats the display price locally.
- Row count is bounded by `STEAM_SPECIALS_MAX_RESULTS` (default `30`).
- Reuses the same Alfred row contract, sorting, and strike-through pricing as
  search result rows; region-switch rows are not emitted for specials.

## Runtime Config Contract

- `STEAM_REGION`:
  - Optional, default `us`.
  - Normalized to lowercase.
  - Must be exactly two ASCII letters (`^[a-z]{2}$`).
- `STEAM_REGION_OPTIONS`:
  - Optional comma/newline list of regions for switch rows.
  - Default `[STEAM_REGION]`.
  - Tokens normalized to lowercase, deduplicated by first appearance, and order preserved.
- `STEAM_SHOW_REGION_OPTIONS`:
  - Optional bool-like switch controlling whether region rows are emitted.
  - Default `false` (region rows hidden).
  - Accepted values: `1/0`, `true/false`, `yes/no`, `on/off` (case-insensitive).
- `STEAM_MAX_RESULTS`:
  - Optional integer, default `10`.
  - Effective value clamped to `1..50`.
  - Non-integer values are config errors.
- `STEAM_SPECIALS_MAX_RESULTS`:
  - Optional integer, default `30`.
  - Bounds the `specials` discount ranking; independent of `STEAM_MAX_RESULTS`.
  - Effective value clamped to `1..50`. Non-integer values are config errors.
- `STEAM_LANGUAGE`:
  - Optional, default empty (unset).
  - Normalized to lowercase.
  - Allowed pattern: lowercase letters and `-`, length `2..24`.
- `STEAM_SEARCH_API`:
  - Optional, default `search-suggestions`.
  - Allowed values: `search-suggestions`, `searchsuggestions`, `storesearch`, `store-search`.
  - `search-suggestions` uses `IStoreQueryService/SearchSuggestions`.
  - `storesearch` uses legacy `storesearch` JSON endpoint.

Language behavior by backend:

- `search-suggestions`: language is sent as locale context (not query param `l`).
- `storesearch`: empty language omits query param `l`.

Invalid config produces user error text and exit code `2`.

## Steam Store API Contract

- `search-suggestions` endpoint: `https://api.steampowered.com/IStoreQueryService/SearchSuggestions/v1`
  - Test override: `STEAM_SEARCH_SUGGESTIONS_ENDPOINT`
  - Query parameters:
    - `origin=https://store.steampowered.com`
    - `input_protobuf_encoded=<base64 protobuf payload>`
  - Payload includes query, region, language, and max_results.
- `storesearch` endpoint: `https://store.steampowered.com/api/storesearch`
  - Test override: `STEAM_STORE_SEARCH_ENDPOINT`
  - Query parameters:
    - `term=<query>`
    - `cc=<steam_region>`
    - `json=1`
    - `max_results=<effective max>`
    - Optional `l=<steam_language>`
- `featuredcategories` endpoint (specials): `https://store.steampowered.com/api/featuredcategories`
  - Test override: `STEAM_FEATURED_CATEGORIES_ENDPOINT`
  - Query parameters:
    - `cc=<steam_region>`
    - Optional `l=<steam_language>`
- Non-2xx responses surface status + message (when present) as runtime errors.
- Malformed success payloads return typed runtime parse errors.
- Empty and partial item arrays are handled deterministically; invalid items are skipped.
- Platform flags are guaranteed only for `storesearch`; `search-suggestions` may emit unknown platform labels.

## Alfred Item JSON Contract

Top-level output is always valid Alfred JSON:

```json
{
  "items": []
}
```

Current-region row (when `STEAM_SHOW_REGION_OPTIONS=true`):

```json
{
  "title": "Current region: US",
  "subtitle": "Searching Steam Store in US (english).",
  "valid": false
}
```

Region-switch row:

```json
{
  "title": "Search in JP region",
  "subtitle": "Press Enter to requery \"dota 2\" in JP.",
  "arg": "steam-requery:jp:dota 2",
  "valid": true
}
```

Result row (no discount):

```json
{
  "title": "Counter-Strike 2",
  "subtitle": "Free | Game",
  "arg": "https://store.steampowered.com/app/730/?cc=us&l=english"
}
```

Result row (discounted, subtitle carries strikethrough on the original price via Unicode `U+0336`):

```json
{
  "title": "Hero Siege",
  "subtitle": "NT$ 50.00 (N̶T̶$̶ 1̶5̶2̶.̶0̶0̶, -67%) | Game",
  "arg": "https://store.steampowered.com/app/35704/?cc=tw&l=tchinese"
}
```

Rules:

- When `STEAM_SHOW_REGION_OPTIONS=true`, current-region row appears first and region-switch rows follow `STEAM_REGION_OPTIONS` order exactly.
- Current-region subtitle includes language suffix only when `STEAM_LANGUAGE` is configured.
- When `STEAM_SHOW_REGION_OPTIONS=false` (default), output omits region rows and begins with result/no-result rows.
- Result rows are stable-sorted by computed `discount_percent` descending; ties and
  undiscounted results keep the backend's relevance order, with `Price unavailable` rows
  trailing.
- Subtitle format is `{final_price} ({original_strikethrough}, -{N}%) | {item_type}`
  only when both `original_price` and `final_price` are known and `final < original`;
  otherwise it falls back to the legacy `{final_price} | {item_type}` form.
- Strikethrough is rendered with Unicode `U+0336` (combining long stroke overlay)
  inserted after each non-whitespace character of the original price text.
- Discount percent is computed as `round((original - final) / original * 100)` and
  rendered as a positive integer with a leading minus sign.
- Result URLs always include region (`cc`) and include language (`l`) only when configured.
- Subtitles are single-line, whitespace-normalized, and deterministically truncated to `<= 120`
  chars.

## Error Mapping

- User/config/input errors:
  - Exit code `2`.
  - Alfred mode: `stderr` line prefixed with `error:`.
  - Service JSON mode: `{"schema_version":"v1","command":"search","ok":false,...}`.
- Runtime/API errors:
  - Exit code `1`.
  - Same output-channel contract as above by mode.

## Output Modes

- `--mode alfred` (default): outputs Alfred Script Filter JSON directly.
- `--mode service-json`: wraps success/error into `schema_version=v1` service envelope.
