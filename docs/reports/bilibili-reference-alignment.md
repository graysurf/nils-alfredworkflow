# bilibili Reference Alignment (`alfred-web-search-suggest` -> `nils-alfredworkflow`)

## Reference sources (read-only)

- `/Users/terry/Project/graysurf/alfred-web-search-suggest/src/bilibili.php`
- `/Users/terry/Project/graysurf/alfred-web-search-suggest/src/info.plist`
- `/Users/terry/Project/graysurf/alfred-web-search-suggest/README.md`

## Observed reference behavior

- Suggest endpoint: `https://s.search.bilibili.com/main/suggest`
- Required query parameter: `term=<query>`
- Optional personalization parameter: `userid=<bilibili_uid>`
- Suggestion row source: `result.tag[].value`
- Direct search URL pattern: `https://search.bilibili.com/all?keyword=<query>`
- Alfred keyword in reference workflow: `bl`

## Parity mapping in this repo

- Workflow keyword remains `bl` (`workflows/bilibili-search/src/info.plist.template`).
- Suggest endpoint/params preserved:
  - `term` always sent
  - `userid` sent only when `BILIBILI_UID` is non-empty
- Suggestion row mapping preserved:
  - `title` from `result.tag[].value`
  - open URL remains canonical `search.bilibili.com/all?keyword=...`
- Personalization remains optional and best-effort.

## Intentional adaptations for monorepo standards

- Runtime architecture is migrated to Rust CLI + thin shell adapter:
  - CLI: `crates/bilibili-cli`
  - Script filter adapter: `workflows/bilibili-search/scripts/script_filter.sh`
- Error handling is standardized to non-crashing Alfred JSON fallback items.
- Query coalescing/cache policy is standardized through shared helpers:
  - `scripts/lib/script_filter_async_coalesce.sh`
  - `scripts/lib/script_filter_search_driver.sh`
- Config naming is aligned to uppercase workflow vars (`BILIBILI_*`) instead of legacy lowercase vars.
