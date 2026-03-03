# CLI Standards Mapping (Repo Policy)

## Scope

- Applies to all CLI crates under `crates/*-cli`.
- Maps external standards into local migration rules for this repository.
- Policy baseline references:
  - `new-cli-crate-development-standard.md`
  - `cli-service-json-contract-guideline-v1.md`
  - `docs/specs/cli-shared-runtime-contract.md` (shared runtime contract)
  - `docs/reports/crate-legacy-removal-matrix.md` (legacy removal matrix)

## Normative Decisions

| Topic | Local policy decision | Migration note |
| --- | --- | --- |
| Shared runtime contract | The shared runtime contract in `docs/specs/cli-shared-runtime-contract.md` is the canonical implementation contract for output mode behavior and envelope/error semantics. | Contract-affecting changes must update both this file and the shared runtime contract. |
| Output mode selector | Canonical output mode selector is `--output <human\|json\|alfred-json>`. | `--json` remains compatibility-only and must be removed per the legacy removal matrix. |
| Default output | Default output should be `human-readable` for direct terminal usage. | Script-filter compatibility commands may keep explicit `alfred-json` paths only while tracked migration rows are open. |
| Machine output | Service-oriented output must be opt-in via explicit JSON output mode. | JSON mode uses one shared envelope (`schema_version`, `command`, `ok`, payload). |
| Alfred compatibility | Alfred consumers must use explicit compatibility mode (`--output alfred-json`). | Crate-specific legacy mode aliases must be removed as tracked by the matrix. |
| Envelope shape | Required top-level keys in JSON mode: `schema_version`, `command`, `ok`, and exactly one of `result`/`results`/`error`. | Legacy top-level `items`-only payloads are transitional and compatibility-only. |
| Error contract | Failure payload must include `error.code`, `error.message`, optional `error.details`. | Runtime stderr remains human-oriented; machine clients must consume JSON envelope. |
| Exit code semantics | Keep current repo behavior: `0=success`, `1=runtime/dependency`, `2=user/input/config`. | Revisit only with explicit RFC and multi-crate rollout plan. |
| Secret safety | Never include secrets/tokens in `result`, `error.message`, or `error.details`. | Contract tests must include secret-redaction assertions for JSON paths. |
| Forbidden legacy aliases | New code must not add output aliases such as `text`, `alfred`, `alfred_json`, or `--mode service-json` forms. | Existing occurrences must be tracked in `docs/reports/crate-legacy-removal-matrix.md` until removed. |

## Native google-cli note

- `google-cli` is a native Rust crate with package `nils-google-cli` and scoped support for `auth/gmail/drive`.
- Native contract owner: `docs/specs/google-cli-native-contract.md`.
- Local policy for this crate:
  - default output remains human-readable native text
  - `--plain` emits stable native text unchanged
  - `--json` emits the repo envelope around native payloads
  - native-owned errors must use stable `NILS_GOOGLE_*` codes (`NILS_GOOGLE_002`-`004` remain reserved)

## Transitional Exceptions (Time-bounded)

| Exception | Allowed until | Owner | Sunset action |
| --- | --- | --- | --- |
| Legacy Alfred JSON shape (top-level `items`) for existing workflow `script_filter` callers. | 2026-09-30 | Workflow maintainers (`crates/*-cli` + `workflows/*`) | Migrate all script calls to explicit compatibility flags and remove implicit JSON defaults. |
| `--json` compatibility flag across crates that already support `--output json`. | 2026-09-30 | Crate maintainers in Sprint 2 lanes | Remove `--json` flags and keep only canonical output mode selector. |
| Mixed output commands in `workflow-cli` (`script-filter` JSON + action commands plain text). | 2026-12-31 | `workflow-cli` maintainers | Keep mixed behavior documented; add explicit JSON envelope mode for service consumption only. |

Every open exception must have a matching row in `docs/reports/crate-legacy-removal-matrix.md`.
Any exception extension after its date requires a dedicated PR updating this document and the migration plan.

## Ownership And Change Control

- Policy owner: repository maintainers responsible for CLI crates and workflow scripts.
- Required change set for policy updates:
  - Update this file.
  - Update `docs/specs/cli-shared-runtime-contract.md`.
  - Update `docs/reports/crate-legacy-removal-matrix.md`.
  - Update `docs/reports/cli-command-inventory.md` if command/consumer mapping changes.
  - Update `docs/specs/cli-json-envelope-v1.md` and/or `docs/specs/cli-error-code-registry.md` if contract changes.
  - Keep `scripts/cli-standards-audit.sh` checks aligned with policy changes.
- Review control:
  - At least one maintainer approval is required for any contract-affecting PR.
  - PR description must include backward-compatibility impact and rollback plan.

## Compliance Checklist

- Every CLI command has documented output mode behavior (`human-readable`, `json`, `alfred-json`, compatibility mode where needed).
- Every service JSON response conforms to envelope v1.
- Every machine error has stable `error.code` from the registry.
- Every temporary compatibility path is tracked in the legacy removal matrix with owner + removal task.
- Every migration PR updates tests and docs together.
