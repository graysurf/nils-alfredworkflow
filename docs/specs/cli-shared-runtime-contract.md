# CLI Shared Runtime Contract (Sprint 2)

> Status: active

## Scope

- This shared runtime contract applies to CLI crates under `crates/*-cli` and shared runtime helpers in
  `crates/workflow-common`.
- The contract freezes canonical output mode behavior, service JSON envelope shape, and error/exit semantics used by
  Sprint 2 crate refactors.
- Legacy compatibility cleanup is tracked in crate `README.md` standards sections and enforced by
  `scripts/cli-standards-audit.sh`.

## Canonical Output Mode Contract

1. Output mode selection must use canonical values:
   - `human`
   - `json`
   - `alfred-json`
2. Commands with mixed rendering support must expose `--output <human|json|alfred-json>` as the canonical selector.
3. `--json` is a temporary compatibility alias that maps only to `--output json`; new code must not introduce additional
   aliases.
4. Conflict handling is mandatory: combining `--json` with non-json explicit output mode must fail with a user/input
   error.
5. Command defaults:
   - direct terminal commands default to `human`
   - script-filter compatibility commands may default to `alfred-json` until migration rows are closed
   - no command may implicitly default to service JSON mode

## Forbidden Legacy Compatibility Aliases

The following aliases and branches are forbidden for new implementations and are scheduled for deletion where currently
present:

- Value aliases: `text`, `alfred`, `alfred_json`
- Legacy mode flag forms: `--mode service-json`, `--mode alfred`
- Implicit JSON-first default behavior for script-filter command paths

All remaining occurrences must be tracked in crate `README.md` standards sections until removed.

## JSON Envelope And Error Contract

- Service JSON output must include top-level keys:
  - `schema_version`
  - `command`
  - `ok`
  - exactly one payload branch: `result`, `results`, or `error`
- Failure payload shape:
  - required `error.code` (stable machine code from `docs/specs/cli-error-code-registry.md`)
  - required `error.message`
  - optional `error.details` (must be secret-safe)
- Runtime must redact token/secret/password-like content before emitting machine or human-visible error strings.

## Exit Code Semantics

- `0`: success
- `1`: runtime/dependency/provider failure
- `2`: user/input/config failure

## Shared Runtime Ownership Boundary

- Canonical shared runtime module: `crates/workflow-common/src/output_contract.rs`.
- Crate entrypoints should consume shared helpers for:
  - output mode resolution
  - success/error envelope builders
  - sensitive-value redaction
- Crate-local duplicate output contract implementations are transitional and must be removed per Sprint 2 tasks.

## Linked Standards

- `docs/specs/cli-json-envelope-v1.md`
- `docs/specs/cli-error-code-registry.md`
- `scripts/cli-standards-audit.sh`
