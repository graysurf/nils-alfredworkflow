# Troubleshooting Index

Use this file as a quick routing index. Operational standards remain in
`ALFRED_WORKFLOW_DEVELOPMENT.md`; workflow-specific runbooks live under
`workflows/<workflow-id>/TROUBLESHOOTING.md`.

## Global checks

- `scripts/workflow-lint.sh`
- `scripts/workflow-test.sh`
- `scripts/workflow-pack.sh --all`

## Workflow-local runbooks

- `workflows/bilibili-search/TROUBLESHOOTING.md`
- `workflows/wiki-search/TROUBLESHOOTING.md`
- `workflows/google-search/TROUBLESHOOTING.md`
- `workflows/youtube-search/TROUBLESHOOTING.md`
- `workflows/bangumi-search/TROUBLESHOOTING.md`

## Bilibili quick route

- Runtime checks: `bash workflows/bilibili-search/tests/smoke.sh`
- Packaging check: `scripts/workflow-pack.sh --id bilibili-search`
- If failures persist, follow rollback steps in
  `workflows/bilibili-search/TROUBLESHOOTING.md`.
