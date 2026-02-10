#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/setup-rust-tooling.sh [--toolchain CHANNEL] [--force] [--help]

Install/update the Rust toolchain and repo-required cargo tooling:
  - rustup + cargo
  - rustfmt, clippy, llvm-tools-preview
  - cargo-nextest
  - cargo-llvm-cov

Options:
  --toolchain CHANNEL  Rust toolchain channel (default: from rust-toolchain.toml, fallback: stable)
  --force              Force re-install cargo tools
  -h, --help           Show this help
USAGE
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
default_toolchain="stable"
apt_updated=0
os_name="$(uname -s)"
linux_id=""
linux_like=""

if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  linux_id="${ID:-}"
  linux_like="${ID_LIKE:-}"
fi

if [[ -f "$repo_root/rust-toolchain.toml" ]]; then
  parsed_toolchain="$(
    awk -F'"' '/^[[:space:]]*channel[[:space:]]*=/{print $2; exit}' "$repo_root/rust-toolchain.toml"
  )"
  if [[ -n "$parsed_toolchain" ]]; then
    default_toolchain="$parsed_toolchain"
  fi
fi

toolchain="$default_toolchain"
force_install=0

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
  --toolchain)
    if [[ -z "${2:-}" ]]; then
      echo "error: --toolchain requires a value" >&2
      exit 2
    fi
    toolchain="${2}"
    shift 2
    ;;
  --force)
    force_install=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "error: unknown argument: ${1:-}" >&2
    usage >&2
    exit 2
    ;;
  esac
done

run() {
  local -a cmd=("$@")
  echo "+ ${cmd[*]}"
  "${cmd[@]}"
}

run_privileged() {
  local -a cmd=("$@")
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    run "${cmd[@]}"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    run sudo "${cmd[@]}"
    return
  fi

  return 1
}

ensure_apt_packages() {
  local -a packages=("$@")

  if ! command -v apt-get >/dev/null 2>&1; then
    return 1
  fi

  if [[ "$apt_updated" -eq 0 ]]; then
    run_privileged apt-get update
    apt_updated=1
  fi

  run_privileged apt-get install -y --no-install-recommends "${packages[@]}"
}

is_debian_family() {
  [[ "$linux_id" == "ubuntu" || "$linux_id" == "debian" || "$linux_like" == *debian* ]]
}

ensure_download_client() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return
  fi

  if is_debian_family && ensure_apt_packages ca-certificates curl; then
    return
  fi

  echo "error: rustup is missing and neither curl nor wget is available on PATH" >&2
  echo "hint: install curl (Ubuntu: apt-get install curl ca-certificates)" >&2
  exit 2
}

download_file() {
  local url="$1"
  local out="$2"
  if command -v curl >/dev/null 2>&1; then
    run curl --proto '=https' --tlsv1.2 -sSf "$url" -o "$out"
    return
  fi
  run wget -qO "$out" "$url"
}

ensure_native_build_prereqs() {
  if command -v cc >/dev/null 2>&1; then
    return
  fi

  if is_debian_family && ensure_apt_packages build-essential pkg-config libssl-dev; then
    if command -v cc >/dev/null 2>&1; then
      return
    fi
  fi

  if [[ "$os_name" == "Darwin" ]]; then
    if ! xcode-select -p >/dev/null 2>&1; then
      echo "error: missing Xcode Command Line Tools required to compile cargo tools" >&2
      echo "hint: run: xcode-select --install" >&2
      exit 2
    fi
    return
  fi

  echo "error: missing native build prerequisite (cc)" >&2
  echo "hint: install build tools before rerunning this script" >&2
  exit 2
}

ensure_rustup() {
  if command -v rustup >/dev/null 2>&1; then
    return
  fi

  ensure_download_client
  installer="$(mktemp)"
  trap 'rm -f "$installer"' EXIT
  download_file https://sh.rustup.rs "$installer"
  run sh "$installer" -y --profile default --default-toolchain "$toolchain"
}

ensure_cargo_on_path() {
  if command -v cargo >/dev/null 2>&1; then
    return
  fi

  if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.cargo/env"
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    echo "error: cargo is not on PATH after rustup install" >&2
    echo "hint: source \$HOME/.cargo/env and re-run this script" >&2
    exit 2
  fi
}

setup_sccache() {
  local sccache_bin=""
  if ! sccache_bin="$(command -v sccache 2>/dev/null)"; then
    return
  fi

  if [[ -z "${RUSTC_WRAPPER:-}" ]]; then
    export RUSTC_WRAPPER="$sccache_bin"
  fi

  if [[ "${RUSTC_WRAPPER:-}" == "$sccache_bin" || "${RUSTC_WRAPPER:-}" == "sccache" ]]; then
    if [[ -z "${SCCACHE_DIR:-}" ]]; then
      export SCCACHE_DIR="$HOME/.cache/sccache"
    fi
    run mkdir -p "$SCCACHE_DIR"
    echo "ok: using sccache (SCCACHE_DIR=$SCCACHE_DIR)"
  fi
}

install_cargo_tool() {
  local package="$1"
  local subcommand="$2"

  if [[ "$force_install" -eq 0 ]] && cargo "$subcommand" --version >/dev/null 2>&1; then
    echo "ok: cargo $subcommand already installed; skipping $package"
    return
  fi

  local -a cmd=(cargo install --locked "$package")
  if [[ "$force_install" -eq 1 ]]; then
    cmd=(cargo install --locked --force "$package")
  fi
  run "${cmd[@]}"
}

main() {
  ensure_rustup
  ensure_cargo_on_path
  setup_sccache
  ensure_native_build_prereqs

  run rustup toolchain install "$toolchain"
  run rustup component add --toolchain "$toolchain" rustfmt clippy llvm-tools-preview

  install_cargo_tool cargo-nextest nextest
  install_cargo_tool cargo-llvm-cov llvm-cov

  echo
  echo "Rust tooling bootstrap completed."
  run rustc --version
  run cargo --version
  run cargo nextest --version
  run cargo llvm-cov --version
}

main
