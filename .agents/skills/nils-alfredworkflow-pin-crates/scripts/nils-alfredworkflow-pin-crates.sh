#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "${script_dir}/.." && pwd)"
repo_root="$(cd "${skill_root}/../../.." && pwd)"

version=""
targets_raw=""
use_all=0
dry_run=0
update_lock=0
list_targets=0

declare -a selected_targets=()
declare -a changed_files=()
declare -a lock_crates=()

usage() {
  cat <<'USAGE'
Usage:
  <ENTRYPOINT> --version <x.y.z> [--targets <target[,target...]>|--all] [--dry-run] [--update-lock]
  <ENTRYPOINT> --list-targets
  <ENTRYPOINT> --help

Options:
  --version <ver>         Exact version to pin (example: 0.3.7)
  --targets <list>        Comma-separated target aliases (example: codex-cli,memo-cli)
  --all                   Pin all managed targets (default if --targets omitted)
  --dry-run               Print planned changes without writing files
  --update-lock           Run cargo update --precise for cargo-managed targets
  --list-targets          Print supported targets and aliases
  -h, --help              Show this help
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

usage_error() {
  echo "error: $*" >&2
  usage >&2
  exit 2
}

target_crate() {
  case "$1" in
    codex-cli) printf '%s\n' "nils-codex-cli" ;;
    memo-cli) printf '%s\n' "nils-memo-cli" ;;
    *) return 1 ;;
  esac
}

canonical_target() {
  case "$1" in
    codex-cli|codex|nils-codex-cli) printf '%s\n' "codex-cli" ;;
    memo-cli|memo|nils-memo-cli) printf '%s\n' "memo-cli" ;;
    *) return 1 ;;
  esac
}

print_targets() {
  cat <<'TARGETS'
codex-cli
  aliases: codex-cli, codex, nils-codex-cli
  published_crate: nils-codex-cli
  kind: workflow runtime pin + docs
memo-cli
  aliases: memo-cli, memo, nils-memo-cli
  published_crate: nils-memo-cli
  kind: cargo dependency pin + docs
TARGETS
}

assert_file() {
  local file="$1"
  [[ -f "$file" ]] || die "missing required file: $file"
}

record_changed_file() {
  local file="$1"
  local existing
  for existing in "${changed_files[@]:-}"; do
    [[ "$existing" == "$file" ]] && return 0
  done
  changed_files+=("$file")
}

record_lock_crate() {
  local crate="$1"
  local existing
  for existing in "${lock_crates[@]:-}"; do
    [[ "$existing" == "$crate" ]] && return 0
  done
  lock_crates+=("$crate")
}

replace_in_file() {
  local file="$1"
  local pattern="$2"
  local replacement="$3"
  local label="$4"
  assert_file "$file"

  if [[ "$dry_run" -eq 1 ]]; then
    if ! python3 - "$file" "$pattern" <<'PY'
import pathlib
import re
import sys

path, pattern = sys.argv[1], sys.argv[2]
text = pathlib.Path(path).read_text()
sys.exit(0 if re.search(pattern, text, flags=re.MULTILINE | re.DOTALL) else 1)
PY
    then
      die "pattern not found for ${label}: $file"
    fi
    echo "dry-run: ${label} -> $file"
    record_changed_file "$file"
    return 0
  fi

  if ! python3 - "$file" "$pattern" "$replacement" <<'PY'
import pathlib
import re
import sys

path, pattern, replacement = sys.argv[1], sys.argv[2], sys.argv[3]
file_path = pathlib.Path(path)
text = file_path.read_text()
if not re.search(pattern, text, flags=re.MULTILINE | re.DOTALL):
    sys.exit(1)
updated = re.sub(pattern, lambda _m: replacement, text, flags=re.MULTILINE | re.DOTALL)
file_path.write_text(updated)
PY
  then
    die "pattern not found for ${label}: $file"
  fi
  echo "updated: ${label} -> $file"
  record_changed_file "$file"
}

pin_codex_cli() {
  local runtime_file="$repo_root/workflows/codex-cli/scripts/lib/codex_cli_runtime.sh"
  local canonical_version_file="$repo_root/scripts/lib/codex_cli_version.sh"
  local readme_file="$repo_root/workflows/codex-cli/README.md"
  local plist_file="$repo_root/workflows/codex-cli/src/info.plist.template"

  replace_in_file \
    "$canonical_version_file" \
    'if \[\[ -z "\$\{CODEX_CLI_VERSION:-\}" \]\]; then\s+CODEX_CLI_VERSION="[^"]+"' \
    "if [[ -z \"\${CODEX_CLI_VERSION:-}\" ]]; then
  CODEX_CLI_VERSION=\"${version}\"" \
    "codex canonical version pin"

  replace_in_file \
    "$runtime_file" \
    'if \[\[ -z "\$\{CODEX_CLI_VERSION:-\}" \]\]; then\s+CODEX_CLI_VERSION="[^"]+"' \
    "if [[ -z \"\${CODEX_CLI_VERSION:-}\" ]]; then
    CODEX_CLI_VERSION=\"${version}\"" \
    "codex runtime fallback version pin"

  replace_in_file \
    "$readme_file" \
    'nils-codex-cli[@.][0-9A-Za-z.+-]+' \
    "nils-codex-cli@${version}" \
    "codex readme crate pin"

  replace_in_file \
    "$readme_file" \
    'codex-cli[@.][0-9A-Za-z.+-]+' \
    "codex-cli@${version}" \
    "codex readme runtime pin"

  replace_in_file \
    "$readme_file" \
    'cargo install nils-codex-cli --version [0-9A-Za-z.+-]+' \
    "cargo install nils-codex-cli --version ${version}" \
    "codex readme install hint pin"

  replace_in_file \
    "$plist_file" \
    'cargo install nils-codex-cli --version [0-9A-Za-z.+-]+' \
    "cargo install nils-codex-cli --version ${version}" \
    "codex plist install hint pin"
}

pin_memo_cli() {
  local cargo_file="$repo_root/crates/memo-workflow-cli/Cargo.toml"
  local crate_readme_file="$repo_root/crates/memo-workflow-cli/README.md"
  local workflow_readme_file="$repo_root/workflows/memo-add/README.md"
  local workflow_guide_file="$repo_root/docs/WORKFLOW_GUIDE.md"
  local workflow_contract_file="$repo_root/crates/memo-workflow-cli/docs/workflow-contract.md"

  replace_in_file \
    "$cargo_file" \
    'nils-memo-cli = "=[^"]+"' \
    "nils-memo-cli = \"=${version}\"" \
    "memo cargo dependency pin"

  replace_in_file \
    "$crate_readme_file" \
    'nils-memo-cli@[0-9A-Za-z.+-]+' \
    "nils-memo-cli@${version}" \
    "memo crate readme pin"

  replace_in_file \
    "$workflow_readme_file" \
    'nils-memo-cli@[0-9A-Za-z.+-]+' \
    "nils-memo-cli@${version}" \
    "memo workflow readme pin"

  if [[ -f "$workflow_guide_file" ]]; then
    replace_in_file \
      "$workflow_guide_file" \
      'nils-memo-cli@[0-9A-Za-z.+-]+' \
      "nils-memo-cli@${version}" \
      "memo workflow guide pin"
  else
    echo "note: optional file missing, skipped memo workflow guide pin: $workflow_guide_file"
  fi

  replace_in_file \
    "$workflow_contract_file" \
    'nils-memo-cli@[0-9A-Za-z.+-]+' \
    "nils-memo-cli@${version}" \
    "memo workflow contract pin"

  record_lock_crate "nils-memo-cli"
}

resolve_targets() {
  declare -A dedup=()
  local token canonical
  if [[ "$use_all" -eq 1 || -z "$targets_raw" ]]; then
    selected_targets=("codex-cli" "memo-cli")
    return 0
  fi

  IFS=',' read -r -a raw_tokens <<<"$targets_raw"
  for token in "${raw_tokens[@]}"; do
    token="${token//[[:space:]]/}"
    [[ -n "$token" ]] || continue
    canonical="$(canonical_target "$token")" || usage_error "unknown target alias: $token"
    if [[ -z "${dedup[$canonical]:-}" ]]; then
      dedup["$canonical"]=1
      selected_targets+=("$canonical")
    fi
  done

  [[ "${#selected_targets[@]}" -gt 0 ]] || usage_error "no valid targets resolved"
}

run_lock_sync() {
  local crate
  [[ "$update_lock" -eq 1 ]] || return 0
  [[ "${#lock_crates[@]}" -gt 0 ]] || return 0

  if [[ "$dry_run" -eq 1 ]]; then
    for crate in "${lock_crates[@]}"; do
      echo "dry-run: cargo update -p ${crate} --precise ${version}"
    done
    return 0
  fi

  command -v cargo >/dev/null 2>&1 || die "cargo is required when --update-lock is enabled"
  for crate in "${lock_crates[@]}"; do
    echo "running: cargo update -p ${crate} --precise ${version}"
    cargo update -p "$crate" --precise "$version"
  done
}

print_summary() {
  local target
  echo "summary:"
  echo "  version: ${version}"
  echo "  dry_run: ${dry_run}"
  echo "  update_lock: ${update_lock}"
  echo "  targets:"
  for target in "${selected_targets[@]}"; do
    echo "    - ${target} (crate: $(target_crate "$target"))"
  done
  echo "  files:"
  for target in "${changed_files[@]:-}"; do
    echo "    - ${target}"
  done
}

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --version)
      [[ $# -ge 2 ]] || usage_error "--version requires a value"
      version="$2"
      shift 2
      ;;
    --targets)
      [[ $# -ge 2 ]] || usage_error "--targets requires a value"
      targets_raw="$2"
      shift 2
      ;;
    --all)
      use_all=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --update-lock)
      update_lock=1
      shift
      ;;
    --list-targets)
      list_targets=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage_error "unknown argument: ${1:-}"
      ;;
  esac
done

if [[ "$list_targets" -eq 1 ]]; then
  print_targets
  exit 0
fi

[[ -n "$version" ]] || usage_error "--version is required unless --list-targets is used"
if [[ "$version" != *[![:space:]]* ]]; then
  usage_error "--version cannot be empty"
fi
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]]; then
  usage_error "invalid version format: $version"
fi
if [[ "$use_all" -eq 1 && -n "$targets_raw" ]]; then
  usage_error "--all and --targets cannot be used together"
fi

git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "repo root is not a git work tree: $repo_root"
resolve_targets

for target in "${selected_targets[@]}"; do
  case "$target" in
    codex-cli) pin_codex_cli ;;
    memo-cli) pin_memo_cli ;;
    *) usage_error "unsupported target: $target" ;;
  esac
done

run_lock_sync
print_summary
