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

1. Output mode selection uses the canonical `--output <value>` flag. Standard values are:
   - `human` — colored, human-readable terminal output
   - `json` — service JSON envelope (`cli-envelope@v1`)
   - `alfred-json` — Alfred script-filter feedback JSON
2. Each CLI exposes a `--output <value>` flag whose accepted values are the subset it actually implements
   (e.g. script-filter CLIs expose `--output <json|alfred-json>`; terminal CLIs expose `--output <human|json>`).
3. CLI-specific extensions (such as `google-cli`'s `plain` value for stable script-parseable text) are permitted as
   additional values on the canonical flag, but must not redefine standard values.
4. There are no compatibility aliases. `--json`, `--plain`, `--mode`, value aliases like `text` / `alfred` /
   `alfred_json` / `service-json` are forbidden.
5. Command defaults:
   - direct terminal commands default to `human`
   - script-filter compatibility commands default to `alfred-json`
   - no command may implicitly default to service JSON mode

## Forbidden Legacy Compatibility Aliases

The following aliases and flag forms are forbidden:

- Value aliases: `text`, `alfred`, `alfred_json`, `service-json`
- Legacy flag forms: `--mode`, `--json`, `--plain`, short forms `-j`, `-p` reserved as output toggles

All remaining occurrences must be migrated to canonical `--output <value>`.

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
