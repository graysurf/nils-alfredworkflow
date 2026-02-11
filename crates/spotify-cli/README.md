# nils-spotify-cli

CLI backend for the `spotify-search` workflow.

## Commands

| Command | Options | Description |
| --- | --- | --- |
| `spotify-cli search` | `--query <QUERY>` | Search Spotify tracks and print Alfred Script Filter JSON. |

## Environment Variables

- Required: `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET`
- Optional: `SPOTIFY_MAX_RESULTS`, `SPOTIFY_MARKET`

## Output Contract

- `stdout`: Alfred Script Filter JSON payload.
- `stderr`: user/runtime error text.
- Exit codes: `0` success, `1` runtime/API error, `2` user/config error.

## Standards Status

- README/command docs: compliant.
- JSON service envelope (`schema_version/command/ok`): not yet migrated.
- Default human-readable mode: not yet migrated (legacy JSON-first workflow contract).

## Validation

- `cargo run -p nils-spotify-cli -- --help`
- `cargo run -p nils-spotify-cli -- search --help`
- `cargo test -p nils-spotify-cli`
