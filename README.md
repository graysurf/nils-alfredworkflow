# nils-alfredworkflow

Alfred workflows for macOS users.

![Quote Feed workflow screenshot](workflows/quote-feed/screenshot.png)

## Install

1. Download a `.alfredworkflow` package from the [Releases](../../releases) page.
2. Double-click the package to import it into Alfred.
3. For API-based workflows, open Alfred's `Configure Workflow...` and fill in required credentials.

## Choose by use case

- Search the web: use **Google Search** (`gg`)
- Search YouTube videos: use **YouTube Search** (`yt`)
- Search Spotify tracks: use **Spotify Search** (`sp`)
- Search Wikipedia articles: use **Wiki Search** (`wk`)
- Search Cambridge dictionary entries: use **Cambridge Dict** (`cd`)
- Evaluate market expressions with FX/crypto conversion: use **Market Expression** (`mx`)
- Browse and copy quotes: use **Quote Feed** (`qq`)
- Find/open local projects: use **Open Project** (`c`, `code`, `github`)
- Convert epoch and datetime values: use **Epoch Converter** (`ts`)
- Show current time across timezones: use **Multi Timezone** (`tz`)
- Generate random test/demo values: use **Randomer** (`rr`, `rrv`)

## Workflows

| Workflow | Keyword(s) | What it does | Requires setup |
| --- | --- | --- | --- |
| [Google Search](workflows/google-search/README.md) | `gg` | Search web results (Brave backend) and open selected links. | `BRAVE_API_KEY` |
| [YouTube Search](workflows/youtube-search/README.md) | `yt` | Search YouTube videos and open selected videos in browser. | `YOUTUBE_API_KEY` |
| [Spotify Search](workflows/spotify-search/README.md) | `sp` | Search Spotify tracks and open selected results in Spotify app. | `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET` |
| [Wiki Search](workflows/wiki-search/README.md) | `wk` | Search Wikipedia articles and open selected page links. | No |
| [Cambridge Dict](workflows/cambridge-dict/README.md) | `cd` | Two-stage Cambridge dictionary lookup (candidate -> detail) with Enter-to-open entry URL. | Node + Playwright runtime for scraper backend |
| [Market Expression](workflows/market-expression/README.md) | `mx` | Evaluate market expressions (numeric: `+ - * /`, assets: `+ -`) with FX/crypto conversion and copy selected rows. | Optional tuning: `MARKET_CLI_BIN`, `MARKET_DEFAULT_FIAT` |
| [Quote Feed](workflows/quote-feed/README.md) | `qq` | Show cached quotes, refresh in background, and copy a selected quote. | Optional tuning: `QUOTE_DISPLAY_COUNT`, `QUOTE_REFRESH_INTERVAL`, `QUOTE_FETCH_COUNT`, `QUOTE_MAX_ENTRIES`, `QUOTE_DATA_DIR` |
| [Open Project](workflows/open-project/README.md) | `c`, `code`, `github` | Fuzzy-find local Git projects, open in editor, and jump to GitHub remotes. | Optional tuning: `OPEN_PROJECT_MAX_RESULTS` |
| [Epoch Converter](workflows/epoch-converter/README.md) | `ts` | Convert epoch/datetime values and copy selected output. | No |
| [Multi Timezone](workflows/multi-timezone/README.md) | `tz` | Show current time across one or more IANA timezones and copy selected output. | Optional tuning: `TIMEZONE_CLI_BIN`, `MULTI_TZ_ZONES`, `MULTI_TZ_LOCAL_OVERRIDE` |
| [Randomer](workflows/randomer/README.md) | `rr`, `rrv` | Generate random values by format and copy results. | No |

## Troubleshooting

- If a workflow opens but does not run correctly, check [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
