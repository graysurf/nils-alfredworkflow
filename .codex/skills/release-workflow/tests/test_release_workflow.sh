#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "${script_dir}/.." && pwd)"
entrypoint="${skill_root}/scripts/release-workflow.sh"

if [[ ! -f "${skill_root}/SKILL.md" ]]; then
  echo "error: missing SKILL.md" >&2
  exit 1
fi
if [[ ! -f "$entrypoint" ]]; then
  echo "error: missing scripts/release-workflow.sh" >&2
  exit 1
fi

if [[ ! -x "$entrypoint" ]]; then
  echo "error: entrypoint is not executable: $entrypoint" >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1; then
  echo "error: node is required for release-workflow package version sync checks" >&2
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

cat > Cargo.toml <<'EOF'
[workspace]
members = ["crates/demo"]
resolver = "2"

[workspace.package]
version = "0.1.0"
EOF

mkdir -p crates/demo
cat > crates/demo/Cargo.toml <<'EOF'
[package]
name = "demo"
version.workspace = true
edition = "2024"
EOF
mkdir -p crates/demo/src
cat > crates/demo/src/lib.rs <<'EOF'
pub fn answer() -> u32 {
    42
}
EOF

mkdir -p workflows/open-project
cat > workflows/open-project/workflow.toml <<'EOF'
id = "open-project"
name = "Open Project"
bundle_id = "com.graysurf.open-project"
version = "0.1.0"
script_filter = "script_filter.sh"
action = "action_open.sh"
EOF

cat > package.json <<'EOF'
{
  "name": "release-workflow-test",
  "version": "0.1.0"
}
EOF

cat > package-lock.json <<'EOF'
{
  "name": "release-workflow-test",
  "version": "0.1.0",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "release-workflow-test",
      "version": "0.1.0"
    }
  }
}
EOF

echo "hello" > README.md
cargo check --workspace >/dev/null
git add -A
git commit -q -m "init"
git remote add origin "$remote_dir"
git push -q -u origin HEAD:main

"$entrypoint" v0.2.0 --dry-run >/dev/null
if git rev-parse -q --verify refs/tags/v0.2.0 >/dev/null 2>&1; then
  echo "error: dry-run should not create local tags" >&2
  exit 1
fi
if ! rg -n '^version = "0.1.0"$' Cargo.toml workflows/open-project/workflow.toml Cargo.lock >/dev/null; then
  echo "error: dry-run should not mutate version files" >&2
  exit 1
fi
if ! rg -n '"version": "0.1.0"' package.json package-lock.json >/dev/null; then
  echo "error: dry-run should not mutate package version files" >&2
  exit 1
fi

"$entrypoint" v0.2.0 >/dev/null
git rev-parse -q --verify refs/tags/v0.2.0 >/dev/null
git ls-remote --exit-code --tags origin refs/tags/v0.2.0 >/dev/null
rg -n '^version = "0.2.0"$' Cargo.toml workflows/open-project/workflow.toml Cargo.lock >/dev/null
rg -n '"version": "0.2.0"' package.json package-lock.json >/dev/null
git log -1 --pretty=%s | rg '^chore\(release\): bump version to 0.2.0$' >/dev/null
if ! git diff-tree --no-commit-id --name-only -r HEAD | rg '^Cargo.lock$' >/dev/null; then
  echo "error: expected release bump commit to include Cargo.lock" >&2
  exit 1
fi
if ! git diff-tree --no-commit-id --name-only -r HEAD | rg '^package-lock\.json$' >/dev/null; then
  echo "error: expected release bump commit to include package-lock.json" >&2
  exit 1
fi
local_head="$(git rev-parse HEAD)"
remote_main="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
if [[ "$local_head" != "$remote_main" ]]; then
  echo "error: expected version bump commit to be pushed to origin/main" >&2
  exit 1
fi

set +e
"$entrypoint" v0.2.0 >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -ne 3 ]]; then
  echo "error: expected duplicate tag to fail with exit code 3, got $rc" >&2
  exit 1
fi

echo "ok: project skill smoke checks passed"
