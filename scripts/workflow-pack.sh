#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

list_only=0
pack_all=0
install_after=0
workflow_id=""

usage() {
  cat <<USAGE
Usage:
  scripts/workflow-pack.sh --list
  scripts/workflow-pack.sh --id <workflow-id> [--install]
  scripts/workflow-pack.sh --all [--install]
USAGE
}

toml_string() {
  local file="$1"
  local key="$2"
  awk -F'=' -v key="$key" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      value=$2
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

sha256_write() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" >"$file.sha256"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" >"$file.sha256"
  else
    echo "warn: sha256sum/shasum not found; skip checksum" >&2
  fi
}

list_workflows() {
  find "$repo_root/workflows" -mindepth 1 -maxdepth 1 -type d \
    ! -name '_template' -exec basename {} \; | sort
}

render_plist() {
  local template="$1"
  local output="$2"
  local bundle_id="$3"
  local name="$4"
  local version="$5"

  sed \
    -e "s|{{bundle_id}}|$bundle_id|g" \
    -e "s|{{name}}|$name|g" \
    -e "s|{{version}}|$version|g" \
    "$template" >"$output"
}

package_one() {
  local id="$1"
  local manifest="$repo_root/workflows/$id/workflow.toml"
  local workflow_root="$repo_root/workflows/$id"

  [[ -f "$manifest" ]] || {
    echo "error: missing manifest: $manifest" >&2
    return 1
  }

  local name bundle_id version rust_binary
  name="$(toml_string "$manifest" name)"
  bundle_id="$(toml_string "$manifest" bundle_id)"
  version="$(toml_string "$manifest" version)"
  rust_binary="$(toml_string "$manifest" rust_binary)"

  [[ -n "$name" ]] || {
    echo "error: missing name in $manifest" >&2
    return 1
  }
  [[ -n "$bundle_id" ]] || {
    echo "error: missing bundle_id in $manifest" >&2
    return 1
  }
  [[ -n "$version" ]] || {
    echo "error: missing version in $manifest" >&2
    return 1
  }

  if [[ -n "$rust_binary" ]]; then
    cargo build --release -p "$rust_binary"
  fi

  local stage_dir="$repo_root/build/workflows/$id/pkg"
  rm -rf "$stage_dir"
  mkdir -p "$stage_dir"

  cp -R "$workflow_root/scripts" "$stage_dir/"
  if [[ -d "$stage_dir/scripts" ]]; then
    find "$stage_dir/scripts" -type f -name '*.sh' -exec chmod +x {} +
  fi

  if [[ -d "$workflow_root/src/assets" ]]; then
    cp -R "$workflow_root/src/assets" "$stage_dir/"
  fi

  # Alfred object-level custom icons are files named by object UID (e.g. <UID>.png)
  # stored at the package root. Keep any src/*.png files at the root in sync.
  if compgen -G "$workflow_root/src/*.png" >/dev/null; then
    cp "$workflow_root"/src/*.png "$stage_dir/"
  fi

  # Alfred expects workflow icon at package root as `icon.png`.
  if [[ -f "$workflow_root/src/assets/icon.png" ]]; then
    cp "$workflow_root/src/assets/icon.png" "$stage_dir/icon.png"
  fi

  render_plist \
    "$workflow_root/src/info.plist.template" \
    "$stage_dir/info.plist" \
    "$bundle_id" \
    "$name" \
    "$version"

  if [[ -n "$rust_binary" && -f "$repo_root/target/release/$rust_binary" ]]; then
    mkdir -p "$stage_dir/bin"
    cp "$repo_root/target/release/$rust_binary" "$stage_dir/bin/$rust_binary"
  fi

  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$stage_dir/info.plist" >/dev/null
  fi

  local out_dir="$repo_root/dist/$id/$version"
  mkdir -p "$out_dir"
  local artifact="$out_dir/${name}.alfredworkflow"

  (cd "$stage_dir" && zip -rq "$artifact" .)
  sha256_write "$artifact"

  echo "ok: packaged $artifact"

  if [[ "$install_after" -eq 1 ]]; then
    open "$artifact"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --list)
    list_only=1
    shift
    ;;
  --id)
    workflow_id="${2:-}"
    [[ -n "$workflow_id" ]] || {
      echo "error: --id requires a value" >&2
      exit 2
    }
    shift 2
    ;;
  --all)
    pack_all=1
    shift
    ;;
  --install)
    install_after=1
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

if [[ "$list_only" -eq 1 ]]; then
  list_workflows
  exit 0
fi

if [[ "$pack_all" -eq 1 ]]; then
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    package_one "$id"
  done < <(list_workflows)
  exit 0
fi

if [[ -n "$workflow_id" ]]; then
  package_one "$workflow_id"
  exit 0
fi

usage >&2
exit 2
