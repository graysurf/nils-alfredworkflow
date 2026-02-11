#!/usr/bin/env bash
set -euo pipefail

stage_dir=""
workflow_root=""
expected_version="${CODEX_CLI_BUNDLE_VERSION:-0.3.2}"
skip_version_check="${CODEX_CLI_PACK_SKIP_VERSION_CHECK:-0}"
skip_arch_check="${CODEX_CLI_PACK_SKIP_ARCH_CHECK:-0}"

usage() {
  cat <<USAGE
Usage:
  prepare_package.sh --stage-dir <path> --workflow-root <path>
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --stage-dir)
    stage_dir="${2:-}"
    [[ -n "$stage_dir" ]] || {
      echo "error: --stage-dir requires a value" >&2
      exit 2
    }
    shift 2
    ;;
  --workflow-root)
    workflow_root="${2:-}"
    [[ -n "$workflow_root" ]] || {
      echo "error: --workflow-root requires a value" >&2
      exit 2
    }
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "error: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

[[ -n "$stage_dir" ]] || {
  usage >&2
  exit 2
}

[[ -n "$workflow_root" ]] || {
  usage >&2
  exit 2
}

resolve_source_bin() {
  if [[ -n "${CODEX_CLI_PACK_BIN:-}" ]]; then
    if [[ ! -x "${CODEX_CLI_PACK_BIN}" ]]; then
      echo "error: CODEX_CLI_PACK_BIN is not executable: ${CODEX_CLI_PACK_BIN}" >&2
      exit 1
    fi
    printf '%s\n' "${CODEX_CLI_PACK_BIN}"
    return 0
  fi

  local resolved
  resolved="$(command -v codex-cli 2>/dev/null || true)"
  if [[ -n "$resolved" && -x "$resolved" ]]; then
    printf '%s\n' "$resolved"
    return 0
  fi

  cat >&2 <<EOF
error: codex-cli binary not found for packaging codex-cli workflow
hint: install expected version with:
  cargo install nils-codex-cli --version ${expected_version}
or set:
  CODEX_CLI_PACK_BIN=/absolute/path/to/codex-cli
EOF
  exit 1
}

parse_semver_from_text() {
  local text="$1"
  if [[ "$text" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

validate_version() {
  local source_bin="$1"
  local version_line
  version_line="$("$source_bin" --version 2>/dev/null | head -n1 || true)"
  local actual_version
  actual_version="$(parse_semver_from_text "$version_line" || true)"

  if [[ -z "$actual_version" ]]; then
    echo "error: unable to detect codex-cli version from: $version_line" >&2
    exit 1
  fi

  if [[ "$actual_version" != "$expected_version" ]]; then
    echo "error: codex-cli version mismatch (expected $expected_version, got $actual_version)" >&2
    exit 1
  fi
}

supports_arm64() {
  local source_bin="$1"

  if command -v lipo >/dev/null 2>&1; then
    local archs
    archs="$(lipo -archs "$source_bin" 2>/dev/null || true)"
    if [[ "$archs" == *"arm64"* ]]; then
      return 0
    fi
  fi

  if command -v file >/dev/null 2>&1; then
    local info
    info="$(file -b "$source_bin" 2>/dev/null || true)"
    if [[ "$info" == *"arm64"* ]]; then
      return 0
    fi
  fi

  return 1
}

validate_arch() {
  local source_bin="$1"
  local host_os
  host_os="$(uname -s 2>/dev/null || printf '')"
  if [[ "$host_os" != "Darwin" ]]; then
    cat >&2 <<EOF
error: codex-cli bundled runtime is configured for macOS arm64 packaging
hint: run packaging on Apple Silicon macOS, or set CODEX_CLI_PACK_SKIP_ARCH_CHECK=1 for non-release local checks
EOF
    exit 1
  fi

  if ! supports_arm64 "$source_bin"; then
    echo "error: codex-cli binary does not appear to contain arm64 architecture: $source_bin" >&2
    exit 1
  fi
}

source_bin="$(resolve_source_bin)"

if [[ "$skip_version_check" != "1" ]]; then
  validate_version "$source_bin"
fi

if [[ "$skip_arch_check" != "1" ]]; then
  validate_arch "$source_bin"
fi

mkdir -p "$stage_dir/bin"
cp "$source_bin" "$stage_dir/bin/codex-cli"
chmod +x "$stage_dir/bin/codex-cli"

echo "ok: bundled codex-cli from $source_bin"
