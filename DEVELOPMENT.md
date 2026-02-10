# Development Guide

## Setup

- If Rust/cargo (or required cargo tools) are not installed yet, run:
  - `scripts/setup-rust-tooling.sh`
- Manual setup fallback:
  - Install Rust via rustup (stable toolchain).
  - Ensure `rustfmt` and `clippy` components are installed:
    - `rustup component add rustfmt clippy`

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
