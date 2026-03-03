#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/ci/ci-run-gates.sh lint
  scripts/ci/ci-run-gates.sh third-party-artifacts-audit
  scripts/ci/ci-run-gates.sh node-scraper-tests
  scripts/ci/ci-run-gates.sh test
  scripts/ci/ci-run-gates.sh package-smoke [--skip-arch-check]
  scripts/ci/ci-run-gates.sh release-package --tag <tag>
  scripts/ci/ci-run-gates.sh publish-crates --mode <dry-run|publish> --crates "<list>" [--registry <name>]
USAGE
}

die() {
  echo "error: $*" >&2
  exit 2
}

run_lint() {
  "$repo_root/scripts/workflow-lint.sh"
}

run_third_party_artifacts_audit() {
  bash "$repo_root/scripts/ci/third-party-artifacts-audit.sh" --strict
}

run_node_scraper_tests() {
  npm run test:cambridge-scraper
}

run_tests() {
  "$repo_root/scripts/workflow-test.sh"
}

run_package_smoke() {
  local skip_arch_check="$1"
  if [[ "$skip_arch_check" -eq 1 ]]; then
    export CODEX_CLI_PACK_SKIP_ARCH_CHECK=1
  fi
  "$repo_root/scripts/workflow-pack.sh" --all
}

run_release_package() {
  local tag="$1"
  bash "$repo_root/scripts/generate-third-party-artifacts.sh" --write
  bash "$repo_root/scripts/generate-third-party-artifacts.sh" --check
  "$repo_root/scripts/workflow-pack.sh" --all
  bash "$repo_root/scripts/ci/build-release-bundle.sh" --tag "$tag"
  bash "$repo_root/scripts/ci/release-bundle-third-party-audit.sh" --tag "$tag" --dist-dir dist/release-bundles
}

run_publish_crates() {
  local mode="$1"
  local crates="$2"
  local registry="$3"

  local args=(--crates "$crates")

  if [[ "$mode" == "publish" ]]; then
    if [[ -z "${CARGO_REGISTRY_TOKEN:-}" ]]; then
      echo "error: CARGO_REGISTRY_TOKEN secret is required when mode=publish" >&2
      exit 1
    fi
    args+=(--publish)
  else
    args+=(--dry-run)
  fi

  if [[ -n "$registry" ]]; then
    args+=(--registry "$registry")
  fi

  "$repo_root/scripts/publish-crates.sh" "${args[@]}"
}

[[ $# -gt 0 ]] || {
  usage >&2
  exit 2
}

command_name="${1:-}"
shift

case "$command_name" in
lint)
  [[ $# -eq 0 ]] || die "lint does not accept extra arguments"
  run_lint
  ;;
third-party-artifacts-audit)
  [[ $# -eq 0 ]] || die "third-party-artifacts-audit does not accept extra arguments"
  run_third_party_artifacts_audit
  ;;
node-scraper-tests)
  [[ $# -eq 0 ]] || die "node-scraper-tests does not accept extra arguments"
  run_node_scraper_tests
  ;;
test)
  [[ $# -eq 0 ]] || die "test does not accept extra arguments"
  run_tests
  ;;
package-smoke)
  skip_arch_check=0
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
    --skip-arch-check)
      skip_arch_check=1
      shift
      ;;
    *)
      die "unknown package-smoke argument: ${1:-}"
      ;;
    esac
  done
  run_package_smoke "$skip_arch_check"
  ;;
release-package)
  release_tag=""
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
    --tag)
      [[ $# -ge 2 ]] || die "--tag requires a value"
      release_tag="${2:-}"
      shift 2
      ;;
    *)
      die "unknown release-package argument: ${1:-}"
      ;;
    esac
  done

  [[ -n "$release_tag" ]] || die "release-package requires --tag"
  run_release_package "$release_tag"
  ;;
publish-crates)
  publish_mode=""
  publish_crates=""
  publish_registry=""

  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
    --mode)
      [[ $# -ge 2 ]] || die "--mode requires a value"
      publish_mode="${2:-}"
      shift 2
      ;;
    --crates)
      [[ $# -ge 2 ]] || die "--crates requires a value"
      publish_crates="${2:-}"
      shift 2
      ;;
    --registry)
      [[ $# -ge 2 ]] || die "--registry requires a value"
      publish_registry="${2:-}"
      shift 2
      ;;
    *)
      die "unknown publish-crates argument: ${1:-}"
      ;;
    esac
  done

  [[ "$publish_mode" == "dry-run" || "$publish_mode" == "publish" ]] || {
    die "--mode must be dry-run or publish"
  }
  [[ -n "$publish_crates" ]] || die "--crates is required"

  run_publish_crates "$publish_mode" "$publish_crates" "$publish_registry"
  ;;
-h | --help)
  usage
  ;;
*)
  die "unknown command: $command_name"
  ;;
esac
