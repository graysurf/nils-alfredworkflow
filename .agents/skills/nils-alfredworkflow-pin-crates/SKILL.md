---
name: nils-alfredworkflow-pin-crates
description: Pin managed crates and workflow runtime crate versions to an exact release.
---

# Pin Crates

## Contract

Prereqs:

- Run inside this repository work tree.
- `bash`, `git`, `perl`, and `python3` available on `PATH`.
- Managed target files must exist in the project layout.

Inputs:

- Required:
  - `--version <x.y.z|pre-release>`
- Optional:
  - `--targets <target[,target...]>`
  - `--all` (pin all managed targets; default when `--targets` omitted)
  - `--dry-run` (validate and print planned updates without writing files)
  - `--update-lock` (run `cargo update -p <crate> --precise <version>` for cargo targets)
  - `--list-targets`

Managed targets:

- `codex-cli`
  - aliases: `codex-cli`, `codex`, `nils-codex-cli`
  - published crate: `nils-codex-cli`
  - updates: codex workflow runtime pin + related docs text
- `memo-cli`
  - aliases: `memo-cli`, `memo`, `nils-memo-cli`
  - published crate: `nils-memo-cli`
  - updates: cargo dependency pin + related docs text

Outputs:

- Prints deterministic change summary:
  - selected targets
  - resolved published crate names
  - touched files
  - lockfile update status
- On non-dry-run mode, writes version pins to mapped files.

Exit codes:

- `0`: success
- `1`: runtime failure
- `2`: usage error

Failure modes:

- `--version` missing (except `--list-targets`).
- Unknown target alias in `--targets`.
- Invalid semver-like version format.
- Required file missing.
- Pattern replacement expected by mapping not found.
- `cargo update` failed when `--update-lock` is enabled.

## Scripts (only entrypoints)

- `<PROJECT_ROOT>/.agents/skills/nils-alfredworkflow-pin-crates/scripts/nils-alfredworkflow-pin-crates.sh`

## Workflow

1. Resolve repo root and parse flags.
2. Resolve user-provided target aliases to managed targets.
3. Apply file updates for each target:
   - `codex-cli`: runtime script and docs pin strings.
   - `memo-cli`: cargo dependency and docs pin strings.
4. Optionally run lock sync (`--update-lock`) for cargo targets.
5. Print summary with touched files and crates.
