# Steam Search Workflow Contract

> Status: active

## Goal

- Define the `steam-search` source contract, region semantics, and fallback behavior.
- Lock what must use shared helper foundations versus what must stay local to Steam domain logic.

## Source Contract (Steam Store)

- Default search source: `https://api.steampowered.com/IStoreQueryService/SearchSuggestions/v1`.
- Optional legacy search source: `https://store.steampowered.com/api/storesearch`.
- Specials (empty-query) source: `https://store.steampowered.com/api/featuredcategories`
  (`specials.items[]`), an official endpoint (no scraping).
- Backend selector: `STEAM_SEARCH_API` (`search-suggestions` default, `storesearch` legacy).
- Request contract:
  - Always preserve query, region/country, language, and max-results semantics across backends.
  - `search-suggestions` sends these via protobuf payload.
  - `storesearch` sends these via query params (`term`, `cc`, optional `l`, `max_results`).
- Response parsing contract:
  - Parse only fields needed for Alfred rows (app id, title, URL, price/platform text when available).
  - Treat missing optional fields as partial-success rows, not fatal parser errors.

## Region Semantics

- Region values are two-letter country codes used for Steam `cc`.
- `STEAM_REGION` defines the default region for search calls.
- `STEAM_REGION_OPTIONS` defines switchable region rows and preserves configured order.
- `STEAM_SHOW_REGION_OPTIONS` controls whether region rows are shown; default is off (`0`).
- Action requery rows use the `steam-requery:<region>:<query>` argument contract.
- Region switching persists override state in workflow cache/data and re-runs the current keyword query.

## Empty Query Behavior (Specials)

- When the query is empty, the workflow shows the current Steam Store specials
  (discounted titles) instead of a guidance row.
- Specials are fetched via `steam-cli specials`, mapped to the same Alfred row
  contract as search, and ranked by discount percent descending with
  strike-through original prices.
- `featuredcategories` returns integer minor units plus a currency code and no
  pre-formatted price string; the CLI renders the display price locally.
- The `specials` carousel alone is capped at ~10. The CLI merges the discounted
  titles across every featured section (`specials`, `top_sellers`,
  `new_releases`, `coming_soon`), dedupes by app id, and keeps only items that
  carry a discount, so a single official request yields a larger ranking. This
  is still front-page-featured discounts, not a full store-wide leaderboard.
- Row count is bounded by `STEAM_SPECIALS_MAX_RESULTS` (default `30`, clamped
  `1..50`), independent of the search `STEAM_MAX_RESULTS` knob.
- Submitting an empty query clears any region override and uses the configured
  `STEAM_REGION`.
- Cover art: specials rows show the `small_capsule_image` as the Alfred row
  icon. Because Alfred icons must be local files, the CLI caches covers under
  `<ALFRED_WORKFLOW_CACHE>/steam-covers/<app_id>.jpg` (parallel, best-effort,
  24h freshness) and emits the local path. Caching official CDN assets that the
  API already references is not scraping. Covers can be disabled with
  `STEAM_SHOW_COVERS=0`; uncached rows render without an icon.

## Fallback And Error Strategy

- No scraping requirements are allowed for this workflow contract.
- If Steam request fails (network, timeout, DNS/TLS, or non-2xx):
  - emit a deterministic Alfred error item;
  - keep action rows non-destructive and retry-safe;
  - preserve original query text for retry.
- If payload parsing fails:
  - emit a deterministic malformed-response error item;
  - do not crash script adapters.
- If results are empty:
  - emit a deterministic no-results row;
  - include region-switch rows only when `STEAM_SHOW_REGION_OPTIONS` is enabled.

## Shared Helper Adoption Matrix

| Area | Contract | Ownership |
| --- | --- | --- |
| Helper loading | Must use `scripts/lib/workflow_helper_loader.sh` (`wfhl_source_helper`). | Shared helper |
| Search orchestration | Must use `scripts/lib/script_filter_search_driver.sh` (`sfsd_run_search_flow`) for cache/coalesce flow. | Shared helper |
| Query normalization | Must use `scripts/lib/script_filter_query_policy.sh` for input/query guards. | Shared helper |
| Action requery parse/persist/trigger | Must use `scripts/lib/workflow_action_requery.sh`. | Shared helper |
| URL open action | Must use `scripts/lib/workflow_action_open_url.sh`. | Shared helper |
| Steam endpoint choice/params | API URL selection (`search-suggestions`/`storesearch`) and Steam-specific response mapping. | Must stay local |
| Steam error interpretation text | Steam-specific row titles/subtitles and user guidance copy. | Must stay local |
| Steam ranking/selection rules | Ordering and domain-specific display choices. | Must stay local |

## Local-Only Boundary

- Steam provider semantics must stay local:
  - endpoint-specific field mapping;
  - region/language defaults specific to Steam;
  - Steam domain ranking and wording rules.
- Shared helper extraction must not move provider-specific parsing or ranking logic into `scripts/lib`.
