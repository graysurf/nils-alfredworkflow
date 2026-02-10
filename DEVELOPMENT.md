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
- Run shared workflow CLI: `cargo run -p workflow-cli -- --help`
- List workflows: `cargo run -p xtask -- workflow list`

## Formatting and linting

- Format check: `cargo fmt --all -- --check`
- Format fix: `cargo fmt --all`
- Lint: `cargo clippy --workspace --all-targets -- -D warnings`
- Full lint entrypoint: `scripts/workflow-lint.sh`

## Testing

### Required before committing

- All commands in **Formatting and linting** must pass.
- `cargo test --workspace`
- `scripts/workflow-test.sh`
- For changes under `workflows/cambridge-dict/scripts/` or `package.json`:
  - `npm run test:cambridge-scraper`
- For changes under `workflows/cambridge-dict/`:
  - `bash workflows/cambridge-dict/tests/smoke.sh`

### CI-style test reporting (optional)

- If `cargo nextest` is missing, run `scripts/setup-rust-tooling.sh`
- Run CI-style tests + generate JUnit:
  - `cargo nextest run --profile ci --workspace`

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

- If Gatekeeper still blocks execution, follow `TROUBLESHOOTING.md` section `macOS Gatekeeper fix (youtube-search)`.
