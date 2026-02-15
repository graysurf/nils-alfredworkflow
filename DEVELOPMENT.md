# Development Guide

## Platform scope

- Alfred runtime checks (workflow install, keyword execution, Gatekeeper/quarantine fixes) are macOS-only.
- Development and CI quality gates (`lint`, `test`, `pack`) are expected to run on Linux as well.
- CI baseline uses Ubuntu (`.github/workflows/ci.yml`), and tooling bootstrap supports Debian/Ubuntu (`scripts/setup-rust-tooling.sh`).

## Setup

- If Rust/cargo (or required cargo tools) are not installed yet, run:
  - `scripts/setup-rust-tooling.sh`
- For Node + Playwright scraper tooling (`cambridge-dict`), run:
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

### CLI standards audit

- Hard-fail checks (must pass in CI): required standards docs, crate README presence, crate `description` metadata, and standards gate wiring.
- Warning checks (migration tracking): explicit json-mode indicators, envelope key assertions, and README standards sections.
- To enforce warnings as failures: `scripts/cli-standards-audit.sh --strict`

### Documentation placement

- Policy spec: `docs/specs/crate-docs-placement-policy.md`
- Legacy root doc lifecycle decision (normative): root compatibility stubs are not kept; migrate references to canonical crate docs, then remove the root legacy file. See `docs/specs/crate-docs-placement-policy.md` (`Legacy root doc lifecycle decision`) and `docs/reports/crate-doc-migration-inventory.md` (`Legacy root docs removal status`).
- This section is normative for all contributors when adding a new crate or a new markdown file.
- For every new publishable crate, you must add `crates/<crate-name>/README.md` and `crates/<crate-name>/docs/README.md` in the same change before adding crate-specific docs.
- Crate-owned docs must live under `crates/<crate-name>/docs/`; do not place crate-owned docs under root `docs/`.
- For every new markdown file, classify it as workspace-level or crate-specific first, then place it in the canonical path defined by the policy.

#### Contributor checklist (required before commit)

- [ ] For every new publishable crate, required docs exist: `crates/<crate-name>/README.md` and `crates/<crate-name>/docs/README.md`.
- [ ] For every new markdown file, ownership/path classification is complete (`workspace-level` vs `crate-specific`) and crate-specific files are not under root `docs/`.
- [ ] Run documentation placement audit before commit: `bash scripts/docs-placement-audit.sh --strict`.

## Testing

### Required before committing

- Recommended pre-commit sequence:
  - `scripts/workflow-lint.sh`
  - `cargo test --workspace`
  - `scripts/workflow-test.sh`
- For changes under `workflows/cambridge-dict/scripts/` or `package.json`:
  - `npm run test:cambridge-scraper`
- For changes under `workflows/cambridge-dict/`:
  - `bash workflows/cambridge-dict/tests/smoke.sh`

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

### Market CLI live smoke (optional manual)

- Live endpoint sanity check script:
  - `bash scripts/market-cli-live-smoke.sh`
- This is optional maintainer validation for `market-cli` provider freshness/contract behavior.
- It is not required for commit gates or CI pass/fail.

### Weather CLI live smoke (optional manual)

- Live endpoint sanity check script:
  - `bash scripts/weather-cli-live-smoke.sh`
- This is optional maintainer validation for `weather-cli` provider/fallback/contract behavior.
- It is not required for commit gates or CI pass/fail.

### Netflix country-map probe (optional manual)

- Manual probe + allowlist recommendation:
  - `bash scripts/netflix-country-probe.sh`
  - Two-stage probe: URL pre-check first, then Brave search probe only for non-`NotFound` countries.
  - `US` is treated as forced-global and skips search probe.
- Apply suggested allowlist to Netflix workflow runtime map:
  - `bash scripts/netflix-country-probe.sh --apply`
- This is optional maintainer maintenance and is not required for commit gates or CI pass/fail.

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
  - `scripts/workflow-pack.sh --id open-project`
- Pack and install:
  - `scripts/workflow-pack.sh --id open-project --install`
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
  - `scripts/publish-crates.sh --dry-run --crates "nils-weather-cli"`
- Publish all crates in dependency order:
  - `CARGO_REGISTRY_TOKEN=... scripts/publish-crates.sh --publish`
- Publish a subset:
  - `scripts/publish-crates.sh --publish --crates "nils-alfred-core nils-workflow-common"`

## macOS acceptance (Gatekeeper / quarantine)

- For workflows that bundle executables (for example `youtube-search`), include a quarantine check during final acceptance on macOS.
- Recommended one-time cleanup + smoke check for `youtube-search` after install:

  ```bash
  WORKFLOW_DIR="$(for p in "$HOME"/Library/Application\ Support/Alfred/Alfred.alfredpreferences/workflows/*/info.plist; do
    [ -f "$p" ] || continue
    bid="$(plutil -extract bundleid raw -o - "$p" 2>/dev/null || true)"
    [ "$bid" = "com.graysurf.youtube-search" ] && dirname "$p"
  done | head -n1)"

  [ -n "$WORKFLOW_DIR" ] || { echo "youtube-search workflow not found"; exit 1; }
  xattr -dr com.apple.quarantine "$WORKFLOW_DIR"
  "$WORKFLOW_DIR/scripts/script_filter.sh" "rust tutorial" | jq -e '.items | type == "array"'
  ```

- If Gatekeeper still blocks execution, start with `ALFRED_WORKFLOW_DEVELOPMENT.md` and then follow the matching workflow-local troubleshooting file (`workflows/<workflow-id>/TROUBLESHOOTING.md`).
