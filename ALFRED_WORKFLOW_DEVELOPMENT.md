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

### Installed-workflow debug checklist

1. Confirm the latest package was installed (`scripts/workflow-pack.sh --id <workflow-id> --install`).
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

## Legacy Troubleshooting Migration Map

This map defines destination ownership after retiring root `TROUBLESHOOTING.md`.

### Shared sections moved to global standards

| Legacy root section | Destination |
| --- | --- |
| `Purpose` | `ALFRED_WORKFLOW_DEVELOPMENT.md` |
| `Quick Triage Checklist` | `ALFRED_WORKFLOW_DEVELOPMENT.md` (`Installed-workflow debug checklist`) |
| Shared Gatekeeper/quarantine principles | `ALFRED_WORKFLOW_DEVELOPMENT.md` |
| Shared Script Filter guardrails (`alfredfiltersresults`, `config.type`, queue policy) | `ALFRED_WORKFLOW_DEVELOPMENT.md` |
| Generic rollback principles | `ALFRED_WORKFLOW_DEVELOPMENT.md` |

### Workflow sections moved to workflow-local troubleshooting

| Legacy root workflow section | Destination |
| --- | --- |
| `Workflow: open-project` | `workflows/open-project/TROUBLESHOOTING.md` |
| `Workflow: youtube-search` | `workflows/youtube-search/TROUBLESHOOTING.md` |
| `Workflow: google-search` | `workflows/google-search/TROUBLESHOOTING.md` |
| `Workflow: wiki-search` | `workflows/wiki-search/TROUBLESHOOTING.md` |
| `Workflow: epoch-converter` | `workflows/epoch-converter/TROUBLESHOOTING.md` |
| `Workflow: multi-timezone` | `workflows/multi-timezone/TROUBLESHOOTING.md` |
| `Workflow: quote-feed` | `workflows/quote-feed/TROUBLESHOOTING.md` |
| `Workflow: memo-add` | `workflows/memo-add/TROUBLESHOOTING.md` |
| `Workflow: cambridge-dict` | `workflows/cambridge-dict/TROUBLESHOOTING.md` |

### Workflows without legacy root section (baseline docs required)

- `workflows/codex-cli/TROUBLESHOOTING.md`
- `workflows/market-expression/TROUBLESHOOTING.md`
- `workflows/spotify-search/TROUBLESHOOTING.md`
- `workflows/weather/TROUBLESHOOTING.md`
- `workflows/randomer/TROUBLESHOOTING.md`
- `workflows/_template/TROUBLESHOOTING.md`

## Historical Reference Policy

Policy decision:
- Preserve historical references to root `TROUBLESHOOTING.md` in archived plans/reports unless a document is actively maintained and requires navigation fixes.
- For active entry-point documents (`README.md`, `DEVELOPMENT.md`, `docs/WORKFLOW_GUIDE.md`, `AGENT_DOCS.toml`), references must point to global standards and workflow-local troubleshooting docs.

Rationale:
- Preserves historical traceability in archival planning artifacts.
- Avoids unnecessary churn in completed plans while keeping current operator navigation accurate.

## Rollout Rehearsal Checklist

A maintainer should complete the following flow in under three minutes:
1. Open `README.md` and follow troubleshooting navigation to global standards.
2. Jump from workflow README to local `TROUBLESHOOTING.md`.
3. Run `agent-docs resolve --context project-dev --strict --format checklist`.
4. Confirm rollback path is a single revert of this migration changeset.

## Validation

- `agent-docs resolve --context startup --strict --format checklist`
- `agent-docs resolve --context project-dev --strict --format checklist`
- `rg -n "Troubleshooting|Validation|Rollback guidance" workflows/*/TROUBLESHOOTING.md`
