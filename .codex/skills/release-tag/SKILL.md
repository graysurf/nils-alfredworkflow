---
name: release-tag
description: Create and push a release tag to trigger GitHub Release workflow.
---

# Release Tag

## Contract

Prereqs:

- Run inside this repository git work tree.
- `git` available on `PATH`.
- Remote `origin` configured and reachable.
- Release workflow listens on `v*` tags:
  - `.github/workflows/release.yml`
  - `on.push.tags: ["v*"]`

Inputs:

- Required:
  - `<version>` (for example `v0.1.0`)
- Optional:
  - `--remote <name>` (default `origin`)
  - `--dry-run` (validate and print planned actions only)

Outputs:

- Creates an annotated git tag (`Release <version>`).
- Pushes tag to remote (`git push <remote> refs/tags/<version>`).
- Prints release URL when remote is GitHub-compatible.

Exit codes:

- `0`: success
- `1`: operational failure (`git`/remote/tag push error)
- `2`: usage error
- `3`: precondition failure (not git repo, dirty tree, missing remote, duplicate tag)

Failure modes:

- Invalid version format (must start with `v`).
- Working tree not clean.
- Tag already exists locally or on remote.
- `origin` (or provided remote) not configured.
- Push failed due to auth/permissions/network.

## Scripts (only entrypoints)

- `<PROJECT_ROOT>/.codex/skills/release-tag/scripts/release-tag.sh`

## Workflow

1. Validate repository state (`git` repo, clean tree, remote exists).
2. Validate version format and tag uniqueness (local + remote).
3. Create annotated tag `Release <version>`.
4. Push tag to remote.
5. Print success summary and release URL.
