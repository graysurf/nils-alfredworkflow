# Release

## Version source of truth

- Workflow package versions live in `workflows/<id>/workflow.toml`.
- Rust crate versions are workspace-driven via `Cargo.toml` (`[workspace.package].version`).
- Release tag input (`vX.Y.Z`) is treated as the source for both (`X.Y.Z`).

When using `.codex/skills/release-workflow/scripts/release-workflow.sh`, the script will:

1. Sync explicit `version = "..."` entries in tracked `Cargo.toml` files.
2. Sync tracked `workflows/*/workflow.toml` versions (excluding `_template`).
3. Refresh tracked `Cargo.lock` workspace package versions (when present).
4. Commit/push version bumps (when needed), then create/push the release tag.

## Local release dry run

1. `scripts/workflow-lint.sh`
2. `scripts/workflow-test.sh`
3. `scripts/workflow-pack.sh --all`

Artifacts are written to `dist/<workflow-id>/<version>/`.

## CI release

Tag push (`v*`) triggers `.github/workflows/release.yml` and uploads built `.alfredworkflow` artifacts and checksums.
