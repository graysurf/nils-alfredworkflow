# Wiki Search - Alfred Workflow

Search Wikipedia articles from Alfred and open selected pages in your browser.

## Features

- Trigger wiki search with `wk <query>`.
- Show article title and cleaned snippet directly in Alfred.
- Open selected Wikipedia article URL in your default browser with `Enter`.
- Map common failures (invalid config, API unavailable) to actionable Alfred messages.
- Tune language and result count through workflow variables.

## Configuration

Set these via Alfred's "Configure Workflow..." UI:

| Variable | Required | Default | Description |
|---|---|---|---|
| `WIKI_LANGUAGE` | No | `en` | Optional lowercase Wikipedia language code. Effective format is clamped to `^[a-z]{2,12}$`. |
| `WIKI_MAX_RESULTS` | No | `10` | Max results per query. Effective range is clamped to `1..20`. |

## Keyword

| Keyword | Behavior |
|---|---|
| `wk <query>` | Search and list Wikipedia articles, then open selected URL. |

## Advanced Runtime Parameters

| Parameter | Description |
|---|---|
| `WIKI_CLI_BIN` | Optional override path for `wiki-cli` (useful for local debugging). |
