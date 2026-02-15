# IMDb Search - Alfred Workflow

Search IMDb directly from Alfred and open results in your browser.

## Screenshot

![IMDb Search workflow screenshot](./screenshot.png)

## Features

- Trigger search with `im <query>` or `imdb <query>`.
- Shows live IMDb suggestion rows while typing.
- Press `Enter` on a suggestion to open the matched IMDb detail page.
- Keeps one fallback row (`Search IMDb: <query>`) to open full IMDb find results.
- Short query guard: `<2` characters shows `Keep typing (2+ chars)`.
- Empty query guard: shows `Enter a title keyword` instead of opening empty results.
- Script Filter queue policy: 1 second delay with initial immediate run disabled.

## Configuration

Set these via Alfred's "Configure Workflow..." UI:

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `IMDB_SEARCH_SECTION` | No | `tt` | IMDb find category. Allowed values: `tt` (titles), `nm` (names), `co` (companies), `ev` (events), `ep` (episodes), `kw` (keywords). Invalid values fall back to `tt`. |
| `IMDB_MAX_RESULTS` | No | `8` | Maximum number of suggestion rows. Parsed as integer and clamped to `1..20`. |

## Keyword

| Keyword | Behavior |
| --- | --- |
| `im <query>` | Build IMDb find URL and open result page on Enter. |
| `imdb <query>` | Same behavior as `im`. |

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).
