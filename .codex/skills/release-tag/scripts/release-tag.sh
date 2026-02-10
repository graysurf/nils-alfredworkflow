#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") <version> [--remote <name>] [--dry-run]

Examples:
  $(basename "$0") v0.1.0
  $(basename "$0") v0.1.1 --remote origin
  $(basename "$0") v0.2.0 --dry-run
USAGE
}

fail() {
  local code="$1"
  shift
  echo "error: $*" >&2
  exit "$code"
}

to_release_url() {
  local remote_url="$1"
  local version="$2"
  local repo_path=""

  if [[ "$remote_url" =~ ^git@github\.com:(.+)$ ]]; then
    repo_path="${BASH_REMATCH[1]}"
  elif [[ "$remote_url" =~ ^https://github\.com/(.+)$ ]]; then
    repo_path="${BASH_REMATCH[1]}"
  elif [[ "$remote_url" =~ ^ssh://git@github\.com/(.+)$ ]]; then
    repo_path="${BASH_REMATCH[1]}"
  else
    return 1
  fi

  repo_path="${repo_path%.git}"
  echo "https://github.com/${repo_path}/releases/tag/${version}"
}

ensure_release_workflow_trigger() {
  local workflow_file=".github/workflows/release.yml"
  [[ -f "$workflow_file" ]] || fail 3 "missing release workflow: $workflow_file"

  if ! grep -Eq '^[[:space:]]*tags:[[:space:]]*$' "$workflow_file"; then
    fail 3 "release workflow missing 'tags' trigger: $workflow_file"
  fi

  if ! grep -Eq 'v\*' "$workflow_file"; then
    fail 3 "release workflow does not include v* tag pattern: $workflow_file"
  fi
}

remote="origin"
dry_run=0
version=""

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --remote)
      remote="${2:-}"
      [[ -n "$remote" ]] || fail 2 "--remote requires a value"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$version" ]]; then
        version="$1"
        shift
      else
        fail 2 "unknown argument: ${1:-}"
      fi
      ;;
  esac
done

[[ -n "$version" ]] || {
  usage >&2
  exit 2
}

[[ "$version" =~ ^v[0-9]+(\.[0-9]+){2}([-.][0-9A-Za-z.-]+)?$ ]] \
  || fail 2 "invalid version '$version' (expected like v0.1.0)"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail 3 "not inside a git repository"

ensure_release_workflow_trigger

if [[ -n "$(git status --porcelain)" ]]; then
  fail 3 "working tree is not clean; commit or stash changes first"
fi

remote_url="$(git remote get-url "$remote" 2>/dev/null || true)"
[[ -n "$remote_url" ]] || fail 3 "remote '$remote' is not configured"

if git rev-parse -q --verify "refs/tags/${version}" >/dev/null; then
  fail 3 "tag already exists locally: $version"
fi

if git ls-remote --exit-code --tags "$remote" "refs/tags/${version}" >/dev/null 2>&1; then
  fail 3 "tag already exists on remote '$remote': $version"
fi

echo "release workflow: .github/workflows/release.yml"
echo "remote: $remote ($remote_url)"
echo "version: $version"

if [[ "$dry_run" -eq 1 ]]; then
  echo "dry-run: would create tag and push to trigger release workflow"
  exit 0
fi

git tag -a "$version" -m "Release $version"
git push "$remote" "refs/tags/${version}"

echo "ok: pushed tag $version to $remote"
if release_url="$(to_release_url "$remote_url" "$version")"; then
  echo "release page: $release_url"
fi
