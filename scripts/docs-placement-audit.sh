#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

strict_warnings=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/docs-placement-audit.sh [--strict]

Options:
  --strict   Treat warnings as failures.
  -h, --help Show help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --strict)
    strict_warnings=1
    shift
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

hard_failures=0
warnings=0

repo_pass() {
  local message="$1"
  printf 'PASS [repo] %s\n' "$message"
}

repo_warn() {
  local message="$1"
  printf 'WARN [repo] %s\n' "$message"
  warnings=$((warnings + 1))
}

repo_fail() {
  local message="$1"
  printf 'FAIL [repo] %s\n' "$message"
  hard_failures=$((hard_failures + 1))
}

crate_pass() {
  local crate="$1"
  local message="$2"
  printf 'PASS [%s] %s\n' "$crate" "$message"
}

crate_fail() {
  local crate="$1"
  local message="$2"
  printf 'FAIL [%s] %s\n' "$crate" "$message"
  hard_failures=$((hard_failures + 1))
}

package_name_from_cargo() {
  local cargo_toml="$1"

  awk '
    /^\[package\][[:space:]]*$/ { in_package=1; next }
    in_package && /^\[/ { in_package=0 }
    in_package && /^[[:space:]]*name[[:space:]]*=/ {
      line=$0
      sub(/^[[:space:]]*name[[:space:]]*=[[:space:]]*"/, "", line)
      sub(/".*$/, "", line)
      print line
      exit
    }
  ' "$cargo_toml"
}

is_crate_specific_root_doc() {
  local filename="$1"

  case "$filename" in
  *contract*.md | *expression-rules*.md | *port-parity*.md)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

echo "== Docs placement audit =="

publish_order_file="$repo_root/release/crates-io-publish-order.txt"
if [[ -f "$publish_order_file" ]]; then
  repo_pass "publish order file present: release/crates-io-publish-order.txt"
else
  repo_fail "missing release/crates-io-publish-order.txt"
fi

echo
echo "== Publishable crate required docs =="

declare -A package_to_crate_dir=()
mapfile -t cargo_tomls < <(find "$repo_root/crates" -mindepth 2 -maxdepth 2 -type f -name 'Cargo.toml' | sort)

if [[ ${#cargo_tomls[@]} -eq 0 ]]; then
  repo_fail "no crates/*/Cargo.toml found"
fi

for cargo_toml in "${cargo_tomls[@]}"; do
  package_name="$(package_name_from_cargo "$cargo_toml")"
  crate_dir="$(dirname "$cargo_toml")"

  if [[ -z "$package_name" ]]; then
    repo_fail "unable to resolve [package].name from ${cargo_toml#"$repo_root"/}"
    continue
  fi

  if [[ -n "${package_to_crate_dir[$package_name]:-}" ]]; then
    repo_fail "duplicate package.name '$package_name' across crates/"
    continue
  fi

  package_to_crate_dir["$package_name"]="$crate_dir"
done

publishable_packages=()
if [[ -f "$publish_order_file" ]]; then
  mapfile -t publishable_packages < <(awk '/^[[:space:]]*#/ { next } /^[[:space:]]*$/ { next } { print $1 }' "$publish_order_file")
fi

if [[ ${#publishable_packages[@]} -eq 0 ]]; then
  repo_fail "publish order is empty: release/crates-io-publish-order.txt"
fi

declare -A seen_publishable=()
for package_name in "${publishable_packages[@]}"; do
  if [[ -n "${seen_publishable[$package_name]:-}" ]]; then
    repo_fail "duplicate package in publish order: $package_name"
    continue
  fi
  seen_publishable["$package_name"]=1

  crate_dir="${package_to_crate_dir[$package_name]:-}"
  if [[ -z "$crate_dir" ]]; then
    crate_fail "$package_name" "missing crate directory for publishable package (check Cargo.toml name)"
    continue
  fi

  readme_path="$crate_dir/README.md"
  docs_index_path="$crate_dir/docs/README.md"

  if [[ -f "$readme_path" ]]; then
    crate_pass "$package_name" "required doc present: ${readme_path#"$repo_root"/}"
  else
    crate_fail "$package_name" "required doc missing: ${readme_path#"$repo_root"/}"
  fi

  if [[ -f "$docs_index_path" ]]; then
    crate_pass "$package_name" "required doc present: ${docs_index_path#"$repo_root"/}"
  else
    crate_fail "$package_name" "required doc missing: ${docs_index_path#"$repo_root"/}"
  fi
done

echo
echo "== Root docs placement =="

mapfile -t root_doc_paths < <(find "$repo_root/docs" -mindepth 1 -maxdepth 1 -type f -name '*.md' | sort)
crate_specific_root_detected=0

for root_doc_path in "${root_doc_paths[@]}"; do
  filename="$(basename "$root_doc_path")"
  rel_path="${root_doc_path#"$repo_root"/}"

  if ! is_crate_specific_root_doc "$filename"; then
    continue
  fi

  crate_specific_root_detected=1
  repo_fail "crate-specific root docs file is not allowed: $rel_path (move under crates/<crate>/docs/)"
done

if [[ $crate_specific_root_detected -eq 0 ]]; then
  repo_pass "no crate-specific root docs detected"
fi

echo
printf 'Summary: hard_failures=%d warnings=%d strict=%s\n' \
  "$hard_failures" \
  "$warnings" \
  "$([[ $strict_warnings -eq 1 ]] && echo true || echo false)"

if [[ $hard_failures -gt 0 ]]; then
  echo "Result: FAIL (hard failures detected)"
  exit 1
fi

if [[ $strict_warnings -eq 1 && $warnings -gt 0 ]]; then
  echo "Result: FAIL (strict mode treats warnings as failures)"
  exit 1
fi

if [[ $warnings -gt 0 ]]; then
  echo "Result: PASS with warnings (run with --strict to enforce warnings)"
else
  echo "Result: PASS"
fi
