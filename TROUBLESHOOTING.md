# Troubleshooting Index

## Routing policy

This file is a **curated routing index**, not a full mirror of all workflow runbooks. Use it to find the closest
playbook for the failure at hand and pivot quickly.

- Inclusion rule: list workflows that have called maintainer attention recently (live operator escalations, repeated
  third-party drift, or workflow-specific quick routes worth surfacing). The full enumeration of every workflow
  runbook lives in [`ALFRED_WORKFLOW_DEVELOPMENT.md`](ALFRED_WORKFLOW_DEVELOPMENT.md) under
  *Troubleshooting Documentation Map → Workflow-local runbooks*.
- Operational standards (Script Filter contract, queue policy, packaging wiring, Gatekeeper) remain canonical in
  [`ALFRED_WORKFLOW_DEVELOPMENT.md`](ALFRED_WORKFLOW_DEVELOPMENT.md).
- Workflow-specific runbooks live at `workflows/<workflow-id>/TROUBLESHOOTING.md`; reach them via this index or via
  the full list in `ALFRED_WORKFLOW_DEVELOPMENT.md`.

## Global checks

- `scripts/workflow-lint.sh`
- `scripts/workflow-test.sh`
- `scripts/workflow-pack.sh --all`

## Third-party artifacts route

Use this route for `THIRD_PARTY_LICENSES.md` / `THIRD_PARTY_NOTICES.md` drift, runtime crates.io metadata lookup
failures, or CI/release third-party artifact
gate failures.

1. Regenerate and verify artifacts:
   - `bash scripts/generate-third-party-artifacts.sh --write`
   - `bash scripts/generate-third-party-artifacts.sh --check`
2. If generator output includes `failed to fetch runtime crate metadata from crates.io`:
   - Verify network access and retry:
     - `bash scripts/generate-third-party-artifacts.sh --write`
   - Confirm runtime crate pin source:
     - `sed -n '1,120p' scripts/lib/codex_cli_version.sh`
3. Re-run CI/release gate checks locally:
   - `bash scripts/ci/third-party-artifacts-audit.sh --strict`
   - `bash scripts/ci/release-bundle-third-party-audit.sh --tag <tag> --dist-dir dist/release-bundles`
4. If failures persist, follow release-specific guidance:
   - `docs/specs/third-party-artifacts-contract-v1.md`
   - `docs/RELEASE.md` (`Third-party artifacts gate remediation`)

## Curated workflow-local runbooks

The workflows below are surfaced because they have triggered repeated operator escalations or have workflow-specific
quick routes worth surfacing. For the canonical list of every runbook, see
[`ALFRED_WORKFLOW_DEVELOPMENT.md`](ALFRED_WORKFLOW_DEVELOPMENT.md).

- `workflows/bangumi-search/TROUBLESHOOTING.md`
- `workflows/bilibili-search/TROUBLESHOOTING.md`
- `workflows/google-search/TROUBLESHOOTING.md`
- `workflows/google-service/TROUBLESHOOTING.md`
- `workflows/wiki-search/TROUBLESHOOTING.md`
- `workflows/youtube-search/TROUBLESHOOTING.md`

## Bilibili quick route

- Runtime checks: `bash workflows/bilibili-search/tests/smoke.sh`
- Packaging check: `scripts/workflow-pack.sh --id bilibili-search`
- If failures persist, follow rollback steps in
  `workflows/bilibili-search/TROUBLESHOOTING.md`.
