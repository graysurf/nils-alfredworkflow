# Release

## Version source of truth

Each workflow owns its version in `workflows/<id>/workflow.toml`.

## Local release dry run

1. `scripts/workflow-lint.sh`
2. `scripts/workflow-test.sh`
3. `scripts/workflow-pack.sh --all`

Artifacts are written to `dist/<workflow-id>/<version>/`.

## CI release

Tag push (`v*`) triggers `.github/workflows/release.yml` and uploads built `.alfredworkflow` artifacts and checksums.
