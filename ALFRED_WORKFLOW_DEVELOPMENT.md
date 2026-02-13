# Alfred Workflow Development Standard

## Purpose

This document defines repository-wide Alfred workflow development and troubleshooting standards.
Use this file for cross-workflow runtime rules and global operator playbooks.

## Documentation Ownership Model

### Layer 1: Global standards (this file)

In scope:
- Cross-workflow runtime behavior and standards (Script Filter contract, queue policy, Gatekeeper handling).
- Shared troubleshooting procedures reusable across workflows.
- Governance policy for documentation ownership and migration rules.

Out of scope:
- Workflow-specific API failure handling or workflow-specific variable semantics.
- Workflow-specific smoke command variants that only apply to one workflow.

### Layer 2: Workflow-local troubleshooting

Location:
- `workflows/<workflow-id>/TROUBLESHOOTING.md`

In scope:
- Workflow-specific `Quick operator checks`, `Common failures and actions`, `Validation`, and `Rollback guidance`.
- Workflow-specific operator commands, runtime overrides, and known failure signatures.

Out of scope:
- Repository-wide standards duplicated verbatim across all workflows.

### Layer 3: Development flow and quality gates

Location:
- `DEVELOPMENT.md`

In scope:
- Build/lint/test/pack/release commands and contribution gate expectations.
- CI-oriented quality requirements and commit-time checks.

Out of scope:
- Detailed troubleshooting knowledge base content.

## Shared Troubleshooting Standards

Use these standards in all workflow troubleshooting documents.

### Required sections for each workflow troubleshooting file

Every `workflows/<workflow-id>/TROUBLESHOOTING.md` must include:
- `## Quick operator checks`
- `## Common failures and actions`
- `## Validation`
- `## Rollback guidance`

### Script Filter JSON contract

- Script Filter scripts must always return valid Alfred JSON, including failure paths.
- Fallback errors should be non-actionable rows (`valid=false`) with clear operator guidance.
- Keep payload arguments newline-safe for action-chain handoff.

### `alfredfiltersresults` guardrail

- Keep `alfredfiltersresults=false` when Script Filter output is fully controlled by script JSON.
- Do not enable Alfred secondary filtering unless there is an explicit functional need.
- Validation command:
  - `plutil -convert json -o - build/workflows/<workflow-id>/pkg/info.plist | jq -e '(.objects[] | select(.type == "alfred.workflow.input.scriptfilter") | .config.alfredfiltersresults) == false'`

### `config.type` and `scriptfile` guardrail

- Script Filter and script action nodes that use external files must set `config.type=8`.
- Validate expected `scriptfile` wiring in installed `info.plist` before issue triage.

### Script Filter queue policy

- Keep queue behavior synchronized with repository policy tooling.
- Validation command:
  - `bash scripts/workflow-sync-script-filter-policy.sh --check --workflows <workflow-id>`
- Remediation command:
  - `bash scripts/workflow-sync-script-filter-policy.sh --apply --workflows <workflow-id>`

### Shared Script Filter helper libraries (`scripts/lib`)

- Shared Script Filter runtime helpers are:
  - `scripts/lib/script_filter_query_policy.sh` (`sfqp_*`)
  - `scripts/lib/script_filter_async_coalesce.sh` (`sfac_*`)
- `scripts/workflow-pack.sh` must stage both helper files into packaged workflows at `scripts/lib/`.
- Script Filter adapters should resolve packaged helper first, then local-repo fallback for development/tests.
- If a required helper file cannot be resolved at runtime, emit a non-crashing Alfred error item (`valid=false`) and exit successfully (`exit 0`).

### `sfqp_*` query policy usage standard

- Normalize input via `sfqp_resolve_query_input` and `sfqp_trim` before validation/backend calls.
- Enforce short-query guardrails with `sfqp_is_short_query` and return operator guidance via `sfqp_emit_short_query_item_json`.
- Keep JSON error rows newline-safe and non-actionable through helper emitters.

### `sfac_*` async coalesce usage standard

- Initialize workflow-scoped context before cache/coalesce operations:
  - `sfac_init_context "<workflow-id>" "<fallback-cache-dir>"`
- Resolve tunables with helper validators (avoid inline parsing):
  - cache TTL: `sfac_resolve_positive_int_env "<PREFIX>_QUERY_CACHE_TTL_SECONDS" "10"`
  - settle window: `sfac_resolve_non_negative_number_env "<PREFIX>_QUERY_COALESCE_SETTLE_SECONDS" "2"`
  - rerun interval: `sfac_resolve_non_negative_number_env "<PREFIX>_QUERY_COALESCE_RERUN_SECONDS" "0.4"`
- Async flow contract:
  1. Try `sfac_load_cache_result`.
  2. If query is not final yet, return pending row via `sfac_emit_pending_item_json` with `rerun`.
  3. On backend completion, write cache via `sfac_store_cache_result` for both success (`ok`) and error (`err`) paths.

### Workflow package/install command standard (macOS)

- Use `scripts/workflow-pack-install.sh --id <workflow-id>` as the canonical operator command when you need to rebuild and install the latest artifact.
- For repeated local debug loops, set `WORKFLOW_PACK_ID=<workflow-id>` (for example in `.env`) and run `scripts/workflow-pack-install.sh`.
- Use `scripts/workflow-install.sh <workflow-id>` only when re-installing an already-built artifact from `dist/` without rebuilding.
- `scripts/workflow-pack.sh --id <workflow-id> --install` remains the low-level primitive; troubleshooting docs should prefer the wrapper above for consistency.

### Installed-workflow debug checklist

1. Confirm the latest package was installed (`scripts/workflow-pack-install.sh --id <workflow-id>`).
2. Locate installed workflow directory by bundle id in Alfred preferences.
3. Inspect installed `info.plist` node runtime wiring (`type`, `scriptfile`, `connections`).
4. Execute installed scripts directly from workflow directory to isolate Alfred UI factors.
5. Reproduce and verify action-chain payload handoff with exact query/arg values.

### Gatekeeper and quarantine handling (macOS)

If a bundled binary is blocked by Gatekeeper (`Not Opened` / `Apple could not verify`):

```bash
WORKFLOW_DIR="$(for p in "$HOME"/Library/Application\ Support/Alfred/Alfred.alfredpreferences/workflows/*/info.plist; do
  [ -f "$p" ] || continue
  bid="$(plutil -extract bundleid raw -o - "$p" 2>/dev/null || true)"
  [ "$bid" = "<bundle-id>" ] && dirname "$p"
done | head -n1)"

[ -n "$WORKFLOW_DIR" ] || { echo "workflow not found"; exit 1; }
xattr -dr com.apple.quarantine "$WORKFLOW_DIR"
```

### Generic rollback principles

1. Stop rollout/distribution of the affected workflow.
2. Revert workflow-specific code and workflow-specific docs in one rollback changeset.
3. Rebuild and run repository validation gates (`scripts/workflow-lint.sh`, `scripts/workflow-test.sh`, packaging checks).
4. Republish known-good artifact and notify operators with scope/ETA.

## Troubleshooting Documentation Map

### Global standards

- Cross-workflow runtime and troubleshooting standards are defined in this file:
  - `ALFRED_WORKFLOW_DEVELOPMENT.md`

### Workflow-local runbooks

- `workflows/_template/TROUBLESHOOTING.md`
- `workflows/cambridge-dict/TROUBLESHOOTING.md`
- `workflows/codex-cli/TROUBLESHOOTING.md`
- `workflows/epoch-converter/TROUBLESHOOTING.md`
- `workflows/google-search/TROUBLESHOOTING.md`
- `workflows/market-expression/TROUBLESHOOTING.md`
- `workflows/memo-add/TROUBLESHOOTING.md`
- `workflows/multi-timezone/TROUBLESHOOTING.md`
- `workflows/open-project/TROUBLESHOOTING.md`
- `workflows/quote-feed/TROUBLESHOOTING.md`
- `workflows/randomer/TROUBLESHOOTING.md`
- `workflows/spotify-search/TROUBLESHOOTING.md`
- `workflows/weather/TROUBLESHOOTING.md`
- `workflows/wiki-search/TROUBLESHOOTING.md`
- `workflows/youtube-search/TROUBLESHOOTING.md`

### Reference policy

- Active entry-point documents (`README.md`, `DEVELOPMENT.md`, `docs/WORKFLOW_GUIDE.md`, `AGENT_DOCS.toml`) must link to:
  - `ALFRED_WORKFLOW_DEVELOPMENT.md` for global standards.
  - `workflows/<workflow-id>/TROUBLESHOOTING.md` for workflow-specific operations.

## Rollout Rehearsal Checklist

A maintainer should complete the following flow in under three minutes:
1. Open `README.md` and follow troubleshooting navigation to global standards.
2. Jump from workflow README to local `TROUBLESHOOTING.md`.
3. Run `agent-docs resolve --context project-dev --strict --format checklist`.
4. Confirm rollback path in the target workflow's `Rollback guidance` section is actionable.

## Validation

- `agent-docs resolve --context startup --strict --format checklist`
- `agent-docs resolve --context project-dev --strict --format checklist`
- `rg -n "Troubleshooting|Validation|Rollback guidance" workflows/*/TROUBLESHOOTING.md`
