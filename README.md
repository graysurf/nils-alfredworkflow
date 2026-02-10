# nils-alfredworkflow

Alfred workflows for macOS users.

![Quote Feed workflow screenshot](workflows/quote-feed/screenshot.png)

## Install

1. Download a `.alfredworkflow` package from the [Releases](../../releases) page.
2. Double-click the package to import it into Alfred.
3. For API-based workflows, open Alfred's `Configure Workflow...` and fill in required credentials.

## Choose by use case

- Find/open local projects: use **Open Project** (`c`, `code`, `github`)
- Search the web: use **Google Search** (`gg`)
- Search Wikipedia articles: use **Wiki Search** (`wk`)
- Search YouTube videos: use **YouTube Search** (`yt`)
- Search Spotify tracks: use **Spotify Search** (`sp`)
- Browse and copy quotes: use **Quote Feed** (`qq`)
- Convert epoch and datetime values: use **Epoch Converter** (`ts`)
- Generate random test/demo values: use **Randomer** (`rr`, `rrv`)

## Workflows

| Workflow | Keyword(s) | What it does | Requires setup |
| --- | --- | --- | --- |
| [Open Project](workflows/open-project/README.md) | `c`, `code`, `github` | Fuzzy-find local Git projects, open in editor, and jump to GitHub remotes. | Optional tuning: `OPEN_PROJECT_MAX_RESULTS` |
| [Google Search](workflows/google-search/README.md) | `gg` | Search web results (Brave backend) and open selected links. | `BRAVE_API_KEY` |
| [Wiki Search](workflows/wiki-search/README.md) | `wk` | Search Wikipedia articles and open selected page links. | No |
| [YouTube Search](workflows/youtube-search/README.md) | `yt` | Search YouTube videos and open selected videos in browser. | `YOUTUBE_API_KEY` |
| [Spotify Search](workflows/spotify-search/README.md) | `sp` | Search Spotify tracks and open selected results in Spotify app. | `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET` |
| [Quote Feed](workflows/quote-feed/README.md) | `qq` | Show cached quotes, refresh in background, and copy a selected quote. | Optional tuning: `QUOTE_DISPLAY_COUNT`, `QUOTE_REFRESH_INTERVAL`, `QUOTE_FETCH_COUNT`, `QUOTE_MAX_ENTRIES` |
| [Epoch Converter](workflows/epoch-converter/README.md) | `ts` | Convert epoch/datetime values and copy selected output. | No |
| [Randomer](workflows/randomer/README.md) | `rr`, `rrv` | Generate random values by format and copy results. | No |

## Troubleshooting

- If a workflow opens but does not run correctly, check [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
