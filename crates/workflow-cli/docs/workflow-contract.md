# nils-workflow-cli workflow contract

> Status: active

## Scope

Per-subcommand JSON envelope, error-code, and exit-code contract for the `nils-workflow-cli` binary
(`workflow-cli`). `workflow-cli` is the shared CLI that backs the open-project Alfred workflow:
`script-filter`, `record-usage`, and `github-url`.

## Subcommand surface

Authoritative help is `cargo run -p nils-workflow-cli -- <subcommand> --help`. Mapping:

| Subcommand | Inputs | Output mode |
| --- | --- | --- |
| `script-filter` | `--query <QUERY>`, `--mode <open\|github>`, `--output <human\|json\|alfred-json>`, `--json` (legacy alias) | `alfred-json` (default), `human`, or `json` envelope |
| `record-usage` | `--path <PATH>` | plain text |
| `github-url` | `--path <PATH>` | plain text |

`--mode` for `script-filter` selects icon treatment (`open` for project rows, `github` for shift-routed
remote rows); it does not change the JSON envelope shape.

## Output mode contract

`script-filter` is the only subcommand with multiple output modes:

- `--output alfred-json` (default): emits Alfred Script Filter JSON (`{"items":[...]}`) on stdout. Used by
  the open-project workflow's `script_filter.sh` adapter.
- `--output human`: emits one item summary per line on stdout (intended for terminal use / debugging).
- `--output json`: emits the shared CLI envelope on stdout. The legacy `--json` flag maps to
  `--output json` and is retained for compatibility per the runtime contract.

`record-usage` and `github-url` always print plain text (no envelope, no Alfred wrapper). They are designed
for action-stage chaining where the consumer reads stdout directly.

## JSON envelope shape (script-filter --output json)

Cross-references:

- Envelope shape: [`docs/specs/cli-json-envelope-v1.md`](../../../docs/specs/cli-json-envelope-v1.md)
- Error code registry: [`docs/specs/cli-error-code-registry.md`](../../../docs/specs/cli-error-code-registry.md)
- Shared runtime contract: [`docs/specs/cli-shared-runtime-contract.md`](../../../docs/specs/cli-shared-runtime-contract.md)

Success envelope (single result branch — Alfred feedback object):

```json
{
  "schema_version": "v1",
  "command": "script-filter",
  "ok": true,
  "result": { "items": [/* alfred items */] }
}
```

Failure envelope:

```json
{
  "schema_version": "v1",
  "command": "script-filter",
  "ok": false,
  "error": {
    "code": "<reserved code from cli-error-code-registry.md>",
    "message": "<human-readable summary>"
  }
}
```

The reserved domain prefix for this crate is `NILS_WORKFLOW_` (range `001-099`); see the registry for the
seed assignments (`NILS_WORKFLOW_001`: project path not found / not a directory; `NILS_WORKFLOW_002`: git
origin / command failure).

## `github-url` host policy

`github-url` resolves the project's origin remote URL to its canonical web URL via
`workflow_common::git::web_url_for_project`:

- Origins are normalized across the three common forms: `git@<host>:<path>(.git)`,
  `ssh://git@<host>[:port]/<path>(.git)`, and `https://<host>/<path>(.git)`.
- `github.com` is the single strict case: the path must be exactly `<owner>/<repo>`.
- Any other host accepts paths with two or more segments. This unblocks GitLab subgroups, Gitea organizations,
  Bitbucket workspaces, and self-hosted instances without per-host configuration.
- Missing origin or unparseable URL → explicit error (exit code `2`).
- Canonical web URL shape: `https://<host>/<path>`.

This widening is the active behavior of `web_url_for_project` and `normalize_remote` and aligns with the
`open-project-port-parity.md` "Remote URL behavior" rule.

## Exit code semantics

Aligned with the shared runtime contract:

- `0`: success (any subcommand).
- `1`: runtime / dependency / I/O failure (e.g., usage log write error, git command failure when origin exists
  but cannot be queried).
- `2`: user / input / configuration failure (e.g., `--path` missing or not a directory, origin URL unparseable,
  unknown query).

## Configuration env vars

Resolved by `workflow_common::RuntimeConfig`:

- `PROJECT_DIRS` — comma-separated roots scanned for git projects. `$HOME` and `~` are expanded.
- `USAGE_FILE` — usage timestamp log path. `$HOME` and `~` are expanded.
- `VSCODE_PATH` — VS Code launcher path used by the workflow's action script.
- `OPEN_PROJECT_MAX_RESULTS` — optional cap on returned items.

The CLI itself does not parse env vars directly; it consumes the values surfaced by `RuntimeConfig`.

## Validation

- `cargo run -p nils-workflow-cli -- --help`
- `cargo run -p nils-workflow-cli -- script-filter --help`
- `cargo run -p nils-workflow-cli -- record-usage --help`
- `cargo run -p nils-workflow-cli -- github-url --help`
- `cargo test -p nils-workflow-cli`
- `bash scripts/cli-standards-audit.sh`
