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

extract_version_value() {
  local file="$1"
  awk -F'=' '
    /^[[:space:]]*version[[:space:]]*=/ {
      value=$2
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

set_explicit_version() {
  local file="$1"
  local target_version="$2"
  local tmp_file
  tmp_file="$(mktemp)"

  if ! awk -v target="$target_version" '
    BEGIN { replaced = 0 }
    {
      if (!replaced && $0 ~ /^[[:space:]]*version[[:space:]]*=[[:space:]]*"/) {
        print "version = \"" target "\""
        replaced = 1
      } else {
        print $0
      }
    }
    END {
      if (!replaced) {
        exit 2
      }
    }
  ' "$file" >"$tmp_file"; then
    rm -f "$tmp_file"
    fail 1 "failed to update explicit version field in $file"
  fi

  mv "$tmp_file" "$file"
}

collect_version_targets() {
  local semver="$1"
  local file current
  VERSION_TARGET_FILES=()
  VERSION_TARGET_DESC=()

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    current="$(extract_version_value "$file")"
    [[ -n "$current" ]] || continue
    if [[ "$current" != "$semver" ]]; then
      VERSION_TARGET_FILES+=("$file")
      VERSION_TARGET_DESC+=("$file: $current -> $semver")
    fi
  done < <(git ls-files '*Cargo.toml')

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    current="$(extract_version_value "$file")"
    [[ -n "$current" ]] || continue
    if [[ "$current" != "$semver" ]]; then
      VERSION_TARGET_FILES+=("$file")
      VERSION_TARGET_DESC+=("$file: $current -> $semver")
    fi
  done < <(
    git ls-files 'workflows/*/workflow.toml' \
      | awk '$0 != "workflows/_template/workflow.toml"'
  )
}

refresh_cargo_lock_if_present() {
  local semver="$1"
  local lock_file="Cargo.lock"

  if ! git ls-files --error-unmatch "$lock_file" >/dev/null 2>&1; then
    return 0
  fi

  command -v cargo >/dev/null 2>&1 || fail 3 "cargo is required to refresh Cargo.lock"
  cargo update --workspace >/dev/null

  if ! git diff --quiet -- "$lock_file"; then
    VERSION_TARGET_FILES+=("$lock_file")
    VERSION_TARGET_DESC+=("$lock_file: sync workspace package versions to $semver")
  fi
}

ensure_upstream_ready() {
  local remote="$1"
  local upstream_ref counts behind_count ahead_count upstream_remote

  upstream_ref="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  [[ -n "$upstream_ref" ]] || fail 3 "current branch has no upstream; set upstream before release"

  upstream_remote="${upstream_ref%%/*}"
  [[ "$upstream_remote" == "$remote" ]] \
    || fail 3 "current upstream remote is '$upstream_remote' (expected '$remote')"

  counts="$(git rev-list --left-right --count "${upstream_ref}...HEAD")"
  read -r behind_count ahead_count <<<"$counts"
  if [[ -z "$behind_count" || -z "$ahead_count" ]]; then
    fail 3 "failed to parse ahead/behind counts for ${upstream_ref}"
  fi

  if (( behind_count != 0 )); then
    fail 3 "local branch is behind ${upstream_ref}; pull/rebase before release"
  fi

  RELEASE_UPSTREAM_BRANCH="${upstream_ref#*/}"
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

semver="${version#v}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail 3 "not inside a git repository"

ensure_release_workflow_trigger

if [[ -n "$(git status --porcelain)" ]]; then
  fail 3 "working tree is not clean; commit or stash changes first"
fi

remote_url="$(git remote get-url "$remote" 2>/dev/null || true)"
[[ -n "$remote_url" ]] || fail 3 "remote '$remote' is not configured"
ensure_upstream_ready "$remote"

if git rev-parse -q --verify "refs/tags/${version}" >/dev/null; then
  fail 3 "tag already exists locally: $version"
fi

if git ls-remote --exit-code --tags "$remote" "refs/tags/${version}" >/dev/null 2>&1; then
  fail 3 "tag already exists on remote '$remote': $version"
fi

collect_version_targets "$semver"

echo "release workflow: .github/workflows/release.yml"
echo "remote: $remote ($remote_url)"
echo "tag version: $version"
echo "package version: $semver"
if [[ "${#VERSION_TARGET_DESC[@]}" -gt 0 ]]; then
  echo "version sync targets:"
  printf '  - %s\n' "${VERSION_TARGET_DESC[@]}"
else
  echo "version sync targets: already up to date"
fi

if [[ "$dry_run" -eq 1 ]]; then
  echo "dry-run: would sync versions, commit/push if needed, then create and push tag"
  exit 0
fi

if [[ "${#VERSION_TARGET_FILES[@]}" -gt 0 ]]; then
  for target_file in "${VERSION_TARGET_FILES[@]}"; do
    set_explicit_version "$target_file" "$semver"
  done

  refresh_cargo_lock_if_present "$semver"

  if ! command -v semantic-commit >/dev/null 2>&1; then
    fail 3 "semantic-commit is required to commit version bump changes"
  fi

  git add "${VERSION_TARGET_FILES[@]}"
  cat <<EOF | semantic-commit commit
chore(release): bump version to ${semver}

- Sync Cargo and workflow manifest versions to ${semver}.
- Refresh Cargo.lock workspace package versions when present.
EOF

  git push "$remote" "HEAD:${RELEASE_UPSTREAM_BRANCH}"
  echo "ok: pushed version bump commit to $remote/${RELEASE_UPSTREAM_BRANCH}"
fi

git tag -a "$version" -m "Release $version"
git push "$remote" "refs/tags/${version}"

echo "ok: pushed tag $version to $remote"
if release_url="$(to_release_url "$remote_url" "$version")"; then
  echo "release page: $release_url"
fi
