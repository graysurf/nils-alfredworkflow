#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/publish-crates.sh [options]

Options:
  --dry-run            Validate with `cargo publish --dry-run` (default).
  --publish            Publish to registry after dry-run passes for all crates.
  --crate NAME         Add one crate (repeatable).
  --crates "A B,C"     Add multiple crates (space/comma separated).
  --list-file PATH     Read default crate order from a file.
  --registry NAME      Optional cargo registry name (blank = crates.io).
  --skip-existing      In --publish mode, skip crates already published at this version (default; crates.io only).
  --no-skip-existing   In --publish mode, fail if a crate version already exists.
  --allow-dirty        Allow a dirty working tree when mode is --publish.
  -h, --help           Show help.

Default crate list file:
  release/crates-io-publish-order.txt
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

note() {
  echo "info: $*" >&2
}

contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

selected_crate_version() {
  local metadata_path="$1"
  local crate="$2"
  python3 - "$metadata_path" "$crate" <<'PY'
from __future__ import annotations

import json
import sys

metadata_path, crate = sys.argv[1], sys.argv[2]
with open(metadata_path, "r", encoding="utf-8") as fp:
    metadata = json.load(fp)
for pkg in metadata["packages"]:
    if pkg.get("name") == crate:
        print(pkg["version"])
        raise SystemExit(0)
raise SystemExit(1)
PY
}

crate_version_exists_on_crates_io() {
  local crate="$1"
  local version="$2"
  python3 - "$crate" "$version" <<'PY'
from __future__ import annotations

import sys
import urllib.error
import urllib.request

crate, version = sys.argv[1], sys.argv[2]
url = f"https://crates.io/api/v1/crates/{crate}/{version}"
try:
    urllib.request.urlopen(url, timeout=15)
except urllib.error.HTTPError as exc:
    if exc.code == 404:
        raise SystemExit(1)
    raise
raise SystemExit(0)
PY
}

append_crates_from_words() {
  local raw="$1"
  local item
  raw="${raw//,/ }"
  for item in $raw; do
    [[ -n "$item" ]] || continue
    selected_crates+=("$item")
  done
}

append_crates_from_file() {
  local path="$1"
  [[ -f "$path" ]] || die "default crate list not found: $path"

  local line trimmed
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="$(printf '%s' "$line" | sed -E 's/[[:space:]]*#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -n "$trimmed" ]] || continue
    selected_crates+=("$trimmed")
  done <"$path"
}

mode="dry-run"
allow_dirty=0
list_file="release/crates-io-publish-order.txt"
registry=""
skip_existing=1
declare -a selected_crates=()

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
  --dry-run)
    mode="dry-run"
    shift
    ;;
  --publish)
    mode="publish"
    shift
    ;;
  --crate)
    [[ $# -ge 2 ]] || die "--crate requires a value"
    selected_crates+=("${2:-}")
    shift 2
    ;;
  --crates)
    [[ $# -ge 2 ]] || die "--crates requires a value"
    append_crates_from_words "${2:-}"
    shift 2
    ;;
  --list-file)
    [[ $# -ge 2 ]] || die "--list-file requires a value"
    list_file="${2:-}"
    shift 2
    ;;
  --registry)
    [[ $# -ge 2 ]] || die "--registry requires a value"
    registry="${2:-}"
    shift 2
    ;;
  --skip-existing)
    skip_existing=1
    shift
    ;;
  --no-skip-existing)
    skip_existing=0
    shift
    ;;
  --allow-dirty)
    allow_dirty=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die "unknown argument: ${1:-}"
    ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$repo_root" ]] || die "must run inside a git work tree"
cd "$repo_root"

if [[ ${#selected_crates[@]} -eq 0 ]]; then
  append_crates_from_file "$list_file"
fi

declare -a deduped_crates=()
for crate in "${selected_crates[@]}"; do
  [[ "$crate" =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid crate name: '$crate'"
  if ! contains "$crate" "${deduped_crates[@]}"; then
    deduped_crates+=("$crate")
  fi
done
selected_crates=("${deduped_crates[@]}")

[[ ${#selected_crates[@]} -gt 0 ]] || die "no crates selected"

metadata_file="$(mktemp)"
trap 'rm -f "$metadata_file"' EXIT
cargo metadata --format-version 1 --no-deps >"$metadata_file"

python3 - "$metadata_file" "${selected_crates[@]}" <<'PY'
from __future__ import annotations

import json
import sys

metadata_path = sys.argv[1]
selected = sys.argv[2:]
with open(metadata_path, "r", encoding="utf-8") as fp:
    metadata = json.load(fp)
packages = {pkg["name"]: pkg for pkg in metadata["packages"]}

errors: list[str] = []

for name in selected:
    pkg = packages.get(name)
    if pkg is None:
        errors.append(f"selected crate '{name}' is not in this workspace")
        continue
    if pkg.get("publish") == []:
        errors.append(f"selected crate '{name}' has publish=false")

order = {name: idx for idx, name in enumerate(selected)}
for name in selected:
    pkg = packages.get(name)
    if pkg is None:
        continue
    for dep in pkg.get("dependencies", []):
        dep_name = dep.get("name")
        if dep.get("path") and dep_name in order and order[dep_name] > order[name]:
            errors.append(
                f"publish order invalid: '{name}' depends on '{dep_name}', "
                "so dependency must appear earlier in the crate list"
            )

if errors:
    for err in errors:
        print(f"error: {err}", file=sys.stderr)
    raise SystemExit(1)
PY

if [[ "$mode" == "publish" && "$allow_dirty" -eq 0 ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    die "working tree is not clean; commit/stash changes or use --allow-dirty"
  fi
fi

declare -a cargo_args=(--locked)
if [[ -n "$registry" ]]; then
  cargo_args+=(--registry "$registry")
fi
if [[ "$allow_dirty" -eq 1 ]]; then
  cargo_args+=(--allow-dirty)
fi

note "mode: $mode"
note "crates: ${selected_crates[*]}"
if [[ -n "$registry" ]]; then
  note "registry: $registry"
else
  note "registry: crates.io (default)"
fi

if [[ "$mode" == "publish" ]]; then
  for crate in "${selected_crates[@]}"; do
    if [[ "$skip_existing" -eq 1 && -z "$registry" ]]; then
      version="$(selected_crate_version "$metadata_file" "$crate")" ||
        die "failed to resolve version for crate '$crate'"
      if crate_version_exists_on_crates_io "$crate" "$version"; then
        note "[publish] skip ${crate} v${version} (already published on crates.io)"
        continue
      fi
    fi
    note "[dry-run] cargo publish -p ${crate} --dry-run ${cargo_args[*]}"
    cargo publish -p "$crate" --dry-run "${cargo_args[@]}"
    note "[publish] cargo publish -p ${crate} ${cargo_args[*]}"
    cargo publish -p "$crate" "${cargo_args[@]}"
  done
  note "publish finished for: ${selected_crates[*]}"
else
  for crate in "${selected_crates[@]}"; do
    note "[dry-run] cargo publish -p ${crate} --dry-run ${cargo_args[*]}"
    cargo publish -p "$crate" --dry-run "${cargo_args[@]}"
  done
  note "dry-run finished for: ${selected_crates[*]}"
fi
