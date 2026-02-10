# Binary Dependencies

This document lists required local tools for development, linting, testing, and packaging.

## Required tools

- Rust toolchain (`rustup`, `cargo`, `rustc`)
- Rust components: `rustfmt`, `clippy`, `llvm-tools-preview`
- Cargo tools: `cargo-nextest`, `cargo-llvm-cov`
- Shell tooling: `shellcheck`, `shfmt`
- Packaging/runtime: `zip`, `unzip`, `open` (macOS) / `xdg-open` (Linux)

## Install (macOS)

```bash
# Rust + cargo tools used by this repo
scripts/setup-rust-tooling.sh

# Shell tools
brew install shellcheck shfmt

# Packaging helpers
brew install zip unzip
```

## Install (Ubuntu/Debian)

```bash
# Base build + shell tools
sudo apt-get update
sudo apt-get install -y build-essential pkg-config libssl-dev shellcheck shfmt zip unzip

# Rust + cargo tools used by this repo
scripts/setup-rust-tooling.sh
```

## Verify

```bash
rustc --version
cargo --version
cargo fmt --version
cargo clippy --version
cargo nextest --version
cargo llvm-cov --version
shellcheck --version
shfmt --version
zip -v | head -n 1
```
