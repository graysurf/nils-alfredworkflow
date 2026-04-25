# nils-workflow-readme-cli docs

Crate-local documentation index for `nils-workflow-readme-cli`.

## Ownership

- Owning crate: `nils-workflow-readme-cli`
- Binary: `workflow-readme-cli`
- Distribution: workspace-internal only (not published to crates.io). The binary is invoked by
  `scripts/workflow-pack.sh` during workflow packaging to inject converted README content into the packaged
  Alfred `info.plist`.

## Intended Readers

- Maintainers responsible for the README → Alfred plist sync flow that runs during `scripts/workflow-pack.sh`.
- Contributors changing markdown table normalization, image-asset staging, or plist `<key>readme</key>` injection
  behavior.

## Canonical Documents

- [`../README.md`](../README.md): crate purpose, `convert` subcommand surface, environment expectations,
  exit-code map, output-mode contract, and validation commands.

## Subcommand surface

The crate exposes a single `convert` subcommand. Authoritative help output is
`cargo run -p nils-workflow-readme-cli -- convert --help`. Inputs and outputs:

- Inputs:
  - `--workflow-root <path>`: workflow source directory (typically `workflows/<id>`).
  - `--readme-source <relative path>`: README path relative to `--workflow-root` (default `README.md`).
  - `--stage-dir <path>`: packaging stage directory; local image assets are copied here under their relative path.
  - `--plist <path>`: `info.plist` to receive the converted readme content.
  - Optional: `--dry-run`, `--output <human|json>` (with `--json` legacy alias).
- Outputs:
  - Converted markdown injected into `<key>readme</key><string>...</string>` in the target plist (XML-safe escaping).
  - Local image assets staged under `--stage-dir`.
  - Human or JSON envelope progress on `stdout`.

## Why no `workflow-contract.md`

This crate is invoked at packaging time, not as a workflow runtime CLI. Its contract surface is the single
`convert` subcommand documented in `../README.md`; there is no per-workflow runtime envelope or error-code
registry to document separately.
