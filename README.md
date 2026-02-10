# nils-alfredworkflow

Alfred workflows for macOS users.

## Install

1. Download a `.alfredworkflow` package from the [Releases](../../releases) page.
2. Double-click the package to import it into Alfred.
3. For API-based workflows, open Alfred's `Configure Workflow...` and fill in required credentials.

## Choose by use case

- Find/open local projects: use **Open Project** (`c`, `code`, `github`)
- Search the web: use **Google Search** (`gg`)
- Search YouTube videos: use **YouTube Search** (`yt`)
- Search Spotify tracks: use **Spotify Search** (`sp`)
- Convert epoch and datetime values: use **Epoch Converter** (`ts`)
- Generate random test/demo values: use **Randomer** (`rr`, `rrv`)

## Workflows

| Workflow | Keyword(s) | What it does | Requires setup |
| --- | --- | --- | --- |
| [Open Project](workflows/open-project/README.md) | `c`, `code`, `github` | Fuzzy-find local Git projects, open in editor, and jump to GitHub remotes. | No |
| [Google Search](workflows/google-search/README.md) | `gg` | Search web results (Brave backend) and open selected links. | `BRAVE_API_KEY` |
| [YouTube Search](workflows/youtube-search/README.md) | `yt` | Search YouTube videos and open selected videos in browser. | `YOUTUBE_API_KEY` |
| [Spotify Search](workflows/spotify-search/README.md) | `sp` | Search Spotify tracks and open selected results in Spotify app. | `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET` |
| [Epoch Converter](workflows/epoch-converter/README.md) | `ts` | Convert epoch/datetime values and copy selected output. | No |
| [Randomer](workflows/randomer/README.md) | `rr`, `rrv` | Generate random values by format and copy results. | No |

## Troubleshooting

- If a workflow opens but does not run correctly, check [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
