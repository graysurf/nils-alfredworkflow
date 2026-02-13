# nils-youtube-cli

CLI backend for the `youtube-search` workflow.

## Commands

| Command | Options | Description |
| --- | --- | --- |
| `youtube-cli search` | `--query <QUERY>` | Search YouTube videos and print Alfred Script Filter JSON. |

## Environment Variables

- Required: `YOUTUBE_API_KEY`
- Optional: `YOUTUBE_MAX_RESULTS`, `YOUTUBE_REGION_CODE`

## Output Contract

- `stdout`: Alfred Script Filter JSON payload.
- `stderr`: user/runtime error text.
- Exit codes: `0` success, `1` runtime/API error, `2` user/config/input error.

## Standards Status

- README/command docs: compliant.
- JSON service envelope (`schema_version/command/ok`): not yet migrated.
- Default human-readable mode: not yet migrated (legacy JSON-first workflow contract).

## Documentation

- [`docs/README.md`](docs/README.md)
- [`docs/workflow-contract.md`](docs/workflow-contract.md)

## Validation

- `cargo run -p nils-youtube-cli -- --help`
- `cargo run -p nils-youtube-cli -- search --help`
- `cargo test -p nils-youtube-cli`
