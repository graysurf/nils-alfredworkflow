# Epoch Converter Workflow Contract

## Purpose

This document defines the runtime behavior contract for the `epoch-converter` Alfred workflow.
It is the source of truth for query parsing, conversion output rows, Alfred item JSON shape,
copy-action behavior, and fallback error mapping.

## Keyword and Query Handling

- Workflow keyword: `ts` (or the configured keyword in Alfred for this workflow object).
- Input query is read from Alfred script filter argument.
- Query normalization:
  - Trim leading/trailing whitespace for parsing.
  - Preserve original value in error context where practical.
- Empty query behavior:
  - `epoch-cli` must return current timestamp rows (`s`, `ms`, `us`, `ns`).
  - Workflow should best-effort parse clipboard text and append conversion rows with
    `(clipboard)` label prefix.
- Non-empty query behavior:
  - Attempt parse as epoch integer (auto infer `s/ms/us/ns` by magnitude).
  - If not epoch, attempt parse as datetime input.
  - If parse fails, return one non-actionable Alfred error item.

## Supported Input Formats

Epoch:

- `1700000000` (seconds)
- `1700000000123` (milliseconds)
- `1700000000123456` (microseconds)
- `1700000000123456789` (nanoseconds)

Datetime:

- `YYYY-MM-DD`
- `YYYY-MM-DD HH:MM`
- `YYYY-MM-DD HH:MM:SS`
- `YYYY-MM-DD HH:MM:SS.subseconds`
- `YYYY-MM-DDTHH:MM`
- `YYYY-MM-DDTHH:MM:SS`
- `YYYY-MM-DDTHH:MM:SS.subseconds`
- `HH:MM`, `HH:MM:SS`, `HH:MM:SS.subseconds` (resolved against local current date)

## Conversion Output Contract

For valid epoch input, output rows must include:

1. `Local ISO-like`
2. `UTC ISO-like`
3. `Local formatted (YYYY-MM-DD HH:MM:SS)` (the additional formatted date row)

For valid datetime input, output rows must include:

1. `Local epoch (s)`
2. `Local epoch (ms)`
3. `Local epoch (us)`
4. `Local epoch (ns)`
5. `UTC epoch (s)`
6. `UTC epoch (ms)`
7. `UTC epoch (us)`
8. `UTC epoch (ns)`

For empty query, output rows must include:

1. `Now epoch (s)`
2. `Now epoch (ms)`
3. `Now epoch (us)`
4. `Now epoch (ns)`

Clipboard rows (when parseable) must be prefixed with `(clipboard)` in subtitle labels.

## Alfred Item JSON Contract

Top-level output must always be valid Alfred JSON:

```json
{
  "items": []
}
```

Success item schema:

```json
{
  "title": "Converted value",
  "subtitle": "Conversion row label",
  "arg": "Converted value",
  "valid": true
}
```

Rules:

- `title` is required and equals the conversion value.
- `subtitle` is required and equals the conversion row label.
- `arg` is required for success rows and equals the copy payload.
- `valid` is explicitly `true` for success rows.

Error/informational fallback items:

- Must include `title` and `subtitle`.
- Must set `valid: false`.
- Must not include `arg`.

## Action Handling Contract

- `action_copy.sh` accepts one argument (selected item `arg` value).
- Missing/empty argument:
  - Print usage to stderr.
  - Exit with code `2`.
- Valid argument:
  - Copy exact bytes to clipboard via `pbcopy`.
  - Do not append extra newline.

## Error Mapping

The workflow must never crash or emit malformed JSON for handled failures.

| Scenario | Detection signal | Alfred title | Alfred subtitle | Item behavior |
| --- | --- | --- | --- | --- |
| Missing binary | `epoch-cli binary not found` | `epoch-cli binary not found` | `Package workflow or set EPOCH_CLI_BIN to an executable epoch-cli path.` | `valid: false` |
| Invalid input | Parse failure (`unsupported query format`, parse error, out-of-range) | `Invalid input` | `Use epoch (s/ms/us/ns) or datetime (YYYY-MM-DD HH:MM[:SS]).` | `valid: false` |
| Runtime failure | Internal IO/runtime errors | `Epoch Converter runtime failure` | `epoch-cli failed during conversion. Retry or inspect stderr details.` | `valid: false` |
| Generic failure | Any other stderr case | `Epoch Converter error` | `<normalized error message>` | `valid: false` |

## Environment Variables

### `EPOCH_CLI_BIN` (optional)

- Optional override path for `epoch-cli` executable.
- Resolution order:
  1. `EPOCH_CLI_BIN` (if executable)
  2. Packaged binary `./bin/epoch-cli`
  3. `target/release/epoch-cli`
  4. `target/debug/epoch-cli`

## Compatibility Notes

- Contract targets Alfred 5 script filter JSON shape.
- Runtime targets macOS 13+ and shell adapters bundled with this repository.
- This contract intentionally includes parity behavior from installed
  `snooze92.epoch.converter`, plus the added formatted date output row.
