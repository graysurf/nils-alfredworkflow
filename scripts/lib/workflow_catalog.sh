#!/usr/bin/env bash

if [[ -n "${WORKFLOW_CATALOG_HELPERS_LOADED:-}" ]]; then
  return 0
fi
WORKFLOW_CATALOG_HELPERS_LOADED=1

wfc_toml_string() {
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

wfc_list_workflow_ids() {
  local repo_root="$1"

  find "$repo_root/workflows" -mindepth 1 -maxdepth 1 -type d \
    ! -name '_template' -exec basename {} \; | sort
}

wfc_dist_latest_artifact() {
  local repo_root="$1"
  local workflow_id="$2"
  local workflow_dist="$repo_root/dist/$workflow_id"

  [[ -d "$workflow_dist" ]] || return 1

  find "$workflow_dist" -type f -name '*.alfredworkflow' | sort | tail -n 1
}
