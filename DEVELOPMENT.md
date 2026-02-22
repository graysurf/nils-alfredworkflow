# Development Guide

## Platform scope

- Alfred runtime checks (workflow install, keyword execution, Gatekeeper/quarantine fixes) are macOS-only.
- Development and CI quality gates (`lint`, `test`, `pack`) are expected to run on Linux as well.
- CI baseline uses Ubuntu (`.github/workflows/ci.yml`), and tooling bootstrap supports Debian/Ubuntu (`scripts/setup-rust-tooling.sh`).

## Setup

- If Rust/cargo (or required cargo tools) are not installed yet, run:
  - `scripts/setup-rust-tooling.sh`
- For workflows that use Node + Playwright tooling, run:
  - `scripts/setup-node-playwright.sh`
  - Add `--install-browser` only when you need live Playwright scraping checks.
- Manual setup fallback:
  - Install Rust via rustup (stable toolchain).
  - Ensure `rustfmt` and `clippy` components are installed:
    - `rustup component add rustfmt clippy`
  - Install Node.js (>=20) and run:
    - `npm ci`

## Build and run

- Build workspace: `cargo build`
- Run shared workflow CLI: `cargo run -p nils-workflow-cli -- --help`
- List workflows: `cargo run -p xtask -- workflow list`

## Formatting and linting

- Format check: `cargo fmt --all -- --check`
- Format fix: `cargo fmt --all`
- Lint: `cargo clippy --workspace --all-targets -- -D warnings`
- CLI standards audit: `scripts/cli-standards-audit.sh`
- Full lint entrypoint (includes `cli-standards-audit`): `scripts/workflow-lint.sh`
- Shared foundation audit (also included in full lint entrypoint): `bash scripts/workflow-shared-foundation-audit.sh --check`
- Script Filter policy check (queue + shared foundation wiring): `bash scripts/workflow-sync-script-filter-policy.sh --check`

### CLI standards audit

- Hard-fail checks (must pass in CI): required standards docs, crate README presence, crate `description` metadata, and standards gate wiring.
- Warning checks (migration tracking): explicit json-mode indicators, envelope key assertions, and README standards sections.
- To enforce warnings as failures: `scripts/cli-standards-audit.sh --strict`

### Documentation placement

- Canonical policy: `docs/specs/crate-docs-placement-policy.md`
- Required placement gate before commit: `bash scripts/docs-placement-audit.sh --strict`
- Placement rule: crate-owned docs belong in `crates/<crate-name>/docs/`; workspace-level docs belong in allowed root `docs/` categories.

#### Contributor checklist (required before commit)

- [ ] For every new publishable crate, required docs exist: `crates/<crate-name>/README.md` and `crates/<crate-name>/docs/README.md`.
- [ ] For every new markdown file, ownership/path classification is complete (`workspace-level` vs `crate-specific`) and the file path follows the policy.
- [ ] Documentation placement audit passes: `bash scripts/docs-placement-audit.sh --strict`.

## Testing

### Required before committing

- Recommended pre-commit sequence:
  - `scripts/workflow-lint.sh`
  - `bash scripts/workflow-sync-script-filter-policy.sh --check`
  - `cargo test --workspace`
  - `scripts/workflow-test.sh`
- For workflow-specific or CLI-specific checks (for example live smoke or probe scripts), run the
  validation steps documented in the corresponding `workflows/<workflow-id>/README.md`.

### Alfred Script Filter guardrail

- For workflows where Script Filter output is already fully controlled by our CLI/script JSON, keep
  `alfredfiltersresults=false` in `info.plist.template`.
- Do not set `alfredfiltersresults=true` unless you explicitly need Alfred-side secondary filtering.
- Reason: `alfredfiltersresults=true` can hide valid workflow items when Alfred query propagation
  falls back to null/empty argument paths, making the workflow appear broken even though script
  output is correct.
- Validation checklist for any workflow plist change:
  - `scripts/workflow-pack.sh --id <workflow-id>`
  - `plutil -convert json -o - build/workflows/<workflow-id>/pkg/info.plist | jq -e '(.objects[] | select(.type == "alfred.workflow.input.scriptfilter") | .config.alfredfiltersresults) == false'`

### CI-style test reporting (optional)

- If `cargo nextest` is missing, run `scripts/setup-rust-tooling.sh`
- Run CI-style tests + generate JUnit:
  - `cargo nextest run --profile ci --workspace`

### Workflow-specific optional manual checks

- Workflow/CLI-specific optional checks (for example live endpoint smoke tests and probe scripts)
  are maintained in each workflow README.
- Reference workflow docs under `workflows/<workflow-id>/README.md`.

## Coverage (optional)

- Install tools:

  ```bash
  scripts/setup-rust-tooling.sh
  ```

- Generate coverage artifacts:

  ```bash
  mkdir -p target/coverage
  cargo llvm-cov nextest --profile ci --workspace --lcov --output-path target/coverage/lcov.info
  cargo llvm-cov report --html --output-dir target/coverage
  ```

## Packaging

- Pack one workflow:
  - `scripts/workflow-pack.sh --id <workflow-id>`
- Pack and install:
  - `scripts/workflow-pack.sh --id <workflow-id> --install`
- Pack all workflows:
  - `scripts/workflow-pack.sh --all`

### Crates.io runtime packaging policy

- When a workflow bundles a runtime binary published on crates.io, packaging scripts must follow this order:
  1. Prefer explicit local override (for example `*_PACK_BIN`).
  2. Then use local PATH binary.
  3. If binary is missing or not the pinned version, auto-install the pinned crate version from crates.io via `cargo install --locked --root <cache-root>` and bundle that installed binary.
- This policy avoids accidental version drift while keeping packaging reproducible across machines.

### External crate exact-pin policy

- Third-party crates used by workspace crates must be exact-pinned (for example `foo = "=1.2.3"`), not loose semver ranges.
- Add or update external crates with exact version syntax:
  - `cargo add <crate>@=<version>`
- For reproducibility, commit both `Cargo.toml` and `Cargo.lock` updates together after the pin change.

## Rust crate publishing (crates.io)

- Dry-run publish checks (all crates from `release/crates-io-publish-order.txt`):
  - `scripts/publish-crates.sh --dry-run`
- Dry-run publish checks (single crate):
  - `scripts/publish-crates.sh --dry-run --crates "<crate-name>"`
- Publish all crates in dependency order:
  - `CARGO_REGISTRY_TOKEN=... scripts/publish-crates.sh --publish`
- Publish a subset:
  - `scripts/publish-crates.sh --publish --crates "nils-alfred-core nils-workflow-common"`

## macOS acceptance (Gatekeeper / quarantine)

- For workflows that bundle executables, include a quarantine check during final acceptance on
  macOS.
- If Gatekeeper blocks execution, start with `ALFRED_WORKFLOW_DEVELOPMENT.md` and then follow the
  matching workflow-local troubleshooting file (`workflows/<workflow-id>/TROUBLESHOOTING.md`) and
  README acceptance steps.
