#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "${script_dir}/.." && pwd)"
entrypoint="${skill_root}/scripts/release-tag.sh"

if [[ ! -f "${skill_root}/SKILL.md" ]]; then
  echo "error: missing SKILL.md" >&2
  exit 1
fi
if [[ ! -f "$entrypoint" ]]; then
  echo "error: missing scripts/release-tag.sh" >&2
  exit 1
fi

if [[ ! -x "$entrypoint" ]]; then
  echo "error: entrypoint is not executable: $entrypoint" >&2
  exit 1
fi

"$entrypoint" --help >/dev/null

set +e
"$entrypoint" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "error: expected usage exit code 2 when version is missing, got $rc" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo_dir="$tmp_dir/repo"
remote_dir="$tmp_dir/remote.git"
mkdir -p "$repo_dir"

git init -q --bare "$remote_dir"
git init -q "$repo_dir"
cd "$repo_dir"

git config user.name "release-skill-test"
git config user.email "release-skill-test@example.com"

mkdir -p .github/workflows
cat > .github/workflows/release.yml <<'EOF'
name: Release
on:
  push:
    tags:
      - "v*"
EOF

echo "hello" > README.md
git add -A
git commit -q -m "init"
git remote add origin "$remote_dir"
git push -q -u origin HEAD:main

"$entrypoint" v0.1.0 --dry-run >/dev/null
if git rev-parse -q --verify refs/tags/v0.1.0 >/dev/null 2>&1; then
  echo "error: dry-run should not create local tags" >&2
  exit 1
fi

"$entrypoint" v0.1.0 >/dev/null
git rev-parse -q --verify refs/tags/v0.1.0 >/dev/null
git ls-remote --exit-code --tags origin refs/tags/v0.1.0 >/dev/null

set +e
"$entrypoint" v0.1.0 >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -ne 3 ]]; then
  echo "error: expected duplicate tag to fail with exit code 3, got $rc" >&2
  exit 1
fi

echo "ok: project skill smoke checks passed"
