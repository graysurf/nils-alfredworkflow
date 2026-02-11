# CLI JSON Envelope v1

## Purpose

Defines one shared JSON envelope for all service-consumed CLI `--json` outputs across `crates/*-cli`.

## Required Top-level Keys

Every JSON response must include:

- `schema_version` (string): fixed to `cli-envelope@v1`.
- `command` (string): stable command identifier (for example `weather.today`).
- `ok` (boolean): `true` for success, `false` for failure.
- Exactly one payload branch:
  - Success single object: `result`
  - Success list: `results`
  - Failure: `error`

## Success Envelope

### Single result

```json
{
  "schema_version": "cli-envelope@v1",
  "command": "weather.today",
  "ok": true,
  "result": {
    "location": "Taipei",
    "temp_c": 21.4
  }
}
```

### Multiple results

```json
{
  "schema_version": "cli-envelope@v1",
  "command": "quote.feed",
  "ok": true,
  "results": [
    { "text": "stay hungry", "author": "steve jobs" },
    { "text": "simplicity is hard", "author": "alan kay" }
  ]
}
```

## Failure Envelope

```json
{
  "schema_version": "cli-envelope@v1",
  "command": "spotify.search",
  "ok": false,
  "error": {
    "code": "NILS_SPOTIFY_002",
    "message": "spotify credentials are missing",
    "details": {
      "missing_env": ["SPOTIFY_CLIENT_ID", "SPOTIFY_CLIENT_SECRET"]
    }
  }
}
```

## Error Object Contract

- `error.code` (string, required): stable machine code from `docs/specs/cli-error-code-registry.md`.
- `error.message` (string, required): human-readable summary safe for logs/UI.
- `error.details` (object, optional): structured context; must not include secrets.

## Compatibility And Deprecation Policy

- Legacy Alfred JSON (top-level `items`) is compatibility-only for workflow consumers.
- New service clients must consume envelope v1 immediately.
- Deprecation timeline:
  - Default JSON-first behavior is removed per crate after workflow compatibility flags are shipped.
  - Legacy shape sunset target is 2026-09-30 (see `docs/specs/cli-standards-mapping.md`).

## Validation Requirements

- Contract tests must assert required keys: `schema_version`, `command`, `ok`.
- Success tests must assert either `result` or `results`.
- Failure tests must assert `error`, `error.code`, and safe `error.details` behavior.
