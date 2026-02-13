# Randomer Workflow Contract

## Goal

Define the canonical behavior contract for the `randomer` workflow and `randomer-cli` runtime.
This contract is the source of truth for keyword routing, supported format invariants, Alfred item
shape, copy behavior, and error handling.

## Keyword and Query Handling

Workflow entrypoints:

| Keyword | Script | CLI command path | Primary behavior |
| --- | --- | --- | --- |
| `rr` | `workflows/randomer/scripts/script_filter.sh` | `randomer-cli list-formats --query <query> --mode alfred` | Show sample values per format. |
| `rrv` | `workflows/randomer/scripts/script_filter_types.sh` | `randomer-cli list-types --query <query> --mode alfred` | Show type keys for selector flow. |
| `rrvv` | `workflows/randomer/scripts/script_filter_expand.sh` | `randomer-cli generate --format <format> --count 10 --mode alfred` | Expand one format into 10 values. |

Query and routing rules:

- `list-formats` and `list-types` query matching is case-insensitive `contains` on format key after
  trim.
- Empty query for `rr`/`rrv` returns all supported formats in canonical order.
- Non-empty query that matches nothing returns `{"items":[]}` (no synthetic fallback row).
- `Enter` on `rr` item copies its sample value.
- `Cmd+Enter` on `rr` item opens `rrvv` and passes the selected format via
  `mods.cmd.variables.RANDOMER_FORMAT`.
- `Enter` on `rrv` item opens `rrvv` with selected format key.
- `rrvv` format resolution order:
  1. argv query (`$1`)
  2. `RANDOMER_FORMAT`
  3. `randomer_format`
  4. `alfred_workflow_query`
  5. `ALFRED_WORKFLOW_QUERY`
  6. stdin (when piped)
- `rrvv` trims surrounding whitespace. Empty effective format returns one non-actionable guidance
  item (`Select a format first`).

## Supported Types

Canonical order is stable and must remain:

1. `email`
2. `imei`
3. `unit`
4. `uuid`
5. `int`
6. `decimal`
7. `percent`
8. `currency`
9. `hex`
10. `otp`
11. `phone`

## Format Invariants

- `email`: lowercase `local@domain.com`, local length `10`, domain length `7`.
- `imei`: exactly 15 digits, checksum-valid.
- `unit`: 11 chars, pattern `[A-Z]{3}[UJZ][0-9]{7}`, checksum-valid.
- `uuid`: RFC-4122 version 4 string.
- `int`: ASCII digits only, generated from range `0..=9_999_999_999`.
- `decimal`: `<digits>.<2 digits>`.
- `percent`: `<digits>.<2 digits>%`, bounded `0.00%..100.00%`.
- `currency`: `$` prefix + comma-grouped whole part + `.00`-style 2 decimals.
- `hex`: `0x` prefix + exactly 8 uppercase hex digits.
- `otp`: exactly 6 digits, zero-padded.
- `phone`: exactly 10 digits, prefix `09` (Taiwan mobile shape).

## Alfred Item JSON Contract

All workflow script-filter paths must emit valid Alfred JSON with top-level `items` array only.

`list-formats` item contract:

```json
{
  "title": "<sample-value>",
  "subtitle": "<format> · Enter: copy sample · Cmd+Enter: show 10 values",
  "arg": "<sample-value>",
  "valid": true,
  "icon": { "path": "assets/icons/<format>.png" },
  "mods": {
    "cmd": {
      "arg": "<format>",
      "subtitle": "show 10 values for <format>",
      "variables": { "RANDOMER_FORMAT": "<format>" }
    }
  }
}
```

`list-types` item contract:

```json
{
  "title": "<format>",
  "subtitle": "sample: <sample-value> · Enter: show 10 values",
  "arg": "<format>",
  "valid": true,
  "icon": { "path": "assets/icons/<format>.png" },
  "variables": { "RANDOMER_FORMAT": "<format>" }
}
```

`generate` item contract:

```json
{
  "title": "<generated-value>",
  "subtitle": "<format>",
  "arg": "<generated-value>",
  "valid": true,
  "icon": { "path": "assets/icons/<format>.png" }
}
```

Workflow error fallback contract (wrapper scripts):

- Always return one item with `valid: false`.
- Must not emit raw stderr mixed into stdout JSON.
- Must normalize known conditions into stable guidance titles, including:
  - `randomer-cli binary not found`
  - `Randomer output format error`
  - `Select a format first`
  - `Unknown format` (expand path)

## Clipboard Behavior

- Copy action script: `workflows/randomer/scripts/action_open.sh`.
- Contract:
  - Requires one positional value argument.
  - Copies exact argument bytes to clipboard via `pbcopy`.
  - Missing argument exits `2` with usage message on stderr.

## CLI Commands, Modes, and Exit Codes

Commands:

- `randomer-cli list-formats [--query <QUERY>] [--mode <alfred|service-json>]`
- `randomer-cli list-types [--query <QUERY>] [--mode <alfred|service-json>]`
- `randomer-cli generate --format <FORMAT> [--count <COUNT>] [--mode <alfred|service-json>]`

Mode behavior:

- `alfred` (default): prints Alfred payload (`{"items":[...]}`) only.
- `service-json`: wraps output in v1 envelope:
  - success: `{"schema_version":"v1","command":"...","ok":true,"result":...,"error":null}`
  - failure: `{"schema_version":"v1","command":"...","ok":false,"result":null,"error":...}`

Exit codes:

- `0`: success
- `1`: runtime error
- `2`: user/input error (`unknown format`, invalid count such as `--count 0`)

## Environment Variables

| Variable | Scope | Required | Purpose |
| --- | --- | --- | --- |
| `RANDOMER_CLI_BIN` | workflow scripts | No | Override `randomer-cli` executable path. |
| `RANDOMER_FORMAT` | workflow scripts | No | Primary selected format handoff into `rrvv`. |
| `randomer_format` | workflow scripts | No | Legacy lowercase fallback for selected format handoff. |
| `alfred_workflow_query` / `ALFRED_WORKFLOW_QUERY` | workflow scripts | No | Alfred query fallback when argv is empty. |

No environment variable is required by `randomer-cli` itself for normal operation.
