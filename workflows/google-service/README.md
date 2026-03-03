# Google Service - Alfred Workflow

Manage Google auth accounts and Drive search/download from Alfred using `google-cli` native commands.

## Scope

Implemented now:

- `login` (remote step 1/2 and manual mode)
- `switch` (workflow-local active account)
- `remove` (with optional confirmation)
- `drive search` (keyword: `gsd`, Enter=download, Cmd+Enter=open Drive web search)
- `open Drive home` from `gsd`
- Docs Editors files are auto-exported on download (`document -> docx`, `spreadsheet -> xlsx`, `presentation -> pptx`).

## Keywords

| Keyword | Behavior |
| --- | --- |
| `gs` | Show one status row: current account (active account first, otherwise native default account). |
| `gsa` | Auth command menu with login/switch/remove rows, then account rows. |
| `gsd` | Drive home row + Drive search rows (Enter download, Cmd+Enter open Drive web search). |

## Query examples

| Query | Result |
| --- | --- |
| `gs` | Show current account row. |
| `gsa` | Show command rows (`Google Service Auth Login/Switch/Remove`) and account rows. |
| `gsa login you@example.com` | Run remote login step 1 (`auth add --remote --step 1`). |
| `gsa login <callback-url>` | Finish remote login step 2 (account auto-resolved from saved state). |
| `gsa login you@example.com http://localhost/?state=...&code=...` | Finish remote login step 2 by directly pasting callback URL. |
| `gsa login you@example.com --manual --code <code>` | Run manual login flow. |
| `gsa switch you@example.com` | Set workflow active account to selected account. |
| `gsa remove you@example.com` | Remove account (confirmation by default). |
| `gsa remove --yes you@example.com` | Remove account without workflow confirmation dialog. |
| `gsd` | Show `Open Google Drive Home` and search usage row. |
| `gsd open` | Open Google Drive home page in browser. |
| `gsd search keyboard` | Run `google-cli drive search keyboard`; Enter downloads selected file; Cmd+Enter opens Drive web search page. |

## Notifications

- Success notifications are shown for `login`, `switch`, `remove`, and Drive download.
- Failure notifications are also shown (for example invalid token/state, missing account, or CLI/auth errors).

## Active account model

- Native account/token source of truth remains `google-cli` auth storage.
- Workflow keeps an extra local pointer for active account switching:
  - path: `$ALFRED_WORKFLOW_DATA/active-account.v1.json`
- Rebalance behavior after remove:
  1. keep current active account if still present
  2. else use native `default_account`
  3. else use first account in `auth list`
  4. else clear active pointer

## Runtime requirements

- `google-cli` resolution order:
  1. `GOOGLE_CLI_BIN` absolute path override
  2. bundled workflow runtime `bin/google-cli`
  3. local dev binaries (`target/release/google-cli`, `target/debug/google-cli`)
- `jq` is required for JSON parsing in script runtime.

For local development, build crate runtime:

```bash
cargo build -p nils-google-cli
```

## Configuration

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `GOOGLE_CLI_BIN` | No | empty | Optional absolute path override for `google-cli`. |
| `GOOGLE_CLI_CONFIG_DIR` | No | empty | Optional auth config root override. If empty and `~/.config/google/credentials` exists, workflow auto-uses that path. |
| `GOOGLE_CLI_KEYRING_MODE` | No | empty | Optional token backend mode (`keyring`, `file`, `fail`, `keyring-strict`). |
| `GOOGLE_DRIVE_DOWNLOAD_DIR` | No | `~/Downloads` | Optional download destination override for `gsd` download action. |
| `GOOGLE_AUTH_REMOVE_CONFIRM` | No | `1` | Require confirmation dialog before remove when possible. |

## Validation

Run before packaging/release:

- `bash workflows/google-service/tests/smoke.sh`
- `bash scripts/workflow-sync-script-filter-policy.sh --check --workflows google-service`
- `scripts/workflow-pack.sh --id google-service`

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).
