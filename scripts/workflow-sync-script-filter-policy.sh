#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
policy_file="$repo_root/docs/specs/script-filter-input-policy.json"
mode=""
workflows_csv=""

usage() {
  cat <<USAGE
Usage:
  scripts/workflow-sync-script-filter-policy.sh --check [--workflows <id,id,...>] [--policy <file>]
  scripts/workflow-sync-script-filter-policy.sh --apply [--workflows <id,id,...>] [--policy <file>]
USAGE
}

plist_to_json() {
  local plist_file="$1"
  if command -v plutil >/dev/null 2>&1; then
    plutil -convert json -o - "$plist_file"
    return
  fi

  python3 - "$plist_file" <<'PY'
import json
import plistlib
import sys

with open(sys.argv[1], 'rb') as f:
    payload = plistlib.load(f)
print(json.dumps(payload))
PY
}

require_bin() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || {
    echo "error: missing required binary: $name" >&2
    exit 1
  }
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --check)
    mode="check"
    shift
    ;;
  --apply)
    mode="apply"
    shift
    ;;
  --workflows)
    workflows_csv="${2:-}"
    [[ -n "$workflows_csv" ]] || {
      echo "error: --workflows requires a comma-separated value" >&2
      exit 2
    }
    shift 2
    ;;
  --policy)
    policy_file="${2:-}"
    [[ -n "$policy_file" ]] || {
      echo "error: --policy requires a value" >&2
      exit 2
    }
    shift 2
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

[[ -n "$mode" ]] || {
  echo "error: choose exactly one mode: --check or --apply" >&2
  usage >&2
  exit 2
}

[[ -f "$policy_file" ]] || {
  echo "error: policy file not found: $policy_file" >&2
  exit 1
}

require_bin jq

queue_delay_custom="$(jq -r '.defaults.queue_delay_custom' "$policy_file")"
queue_delay_mode="$(jq -r '.defaults.queue_delay_mode' "$policy_file")"
immediate_initial="$(jq -r '.defaults.immediate_initial' "$policy_file")"

[[ "$queue_delay_custom" =~ ^[0-9]+$ ]] || {
  echo "error: defaults.queue_delay_custom must be an integer" >&2
  exit 1
}
[[ "$queue_delay_mode" =~ ^[0-9]+$ ]] || {
  echo "error: defaults.queue_delay_mode must be an integer" >&2
  exit 1
}
[[ "$immediate_initial" == "true" || "$immediate_initial" == "false" ]] || {
  echo "error: defaults.immediate_initial must be true/false" >&2
  exit 1
}

mapfile -t queue_policy_workflows < <(jq -r '.targets | keys[]?' "$policy_file" | sort)
mapfile -t shared_foundation_workflows < <(jq -r '.shared_foundation.targets | keys[]?' "$policy_file" | sort)
if [[ "${#queue_policy_workflows[@]}" -eq 0 && "${#shared_foundation_workflows[@]}" -eq 0 ]]; then
  echo "error: no targets found in policy file" >&2
  exit 1
fi

declare -a target_workflows=()
if [[ -n "$workflows_csv" ]]; then
  IFS=',' read -r -a requested <<<"$workflows_csv"
  for workflow_id in "${requested[@]}"; do
    workflow_id="$(printf '%s' "$workflow_id" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -n "$workflow_id" ]] || continue
    if ! jq -e --arg wf "$workflow_id" '.targets[$wf] or .shared_foundation.targets[$wf]' "$policy_file" >/dev/null; then
      echo "error: workflow not found in policy targets: $workflow_id" >&2
      exit 1
    fi
    target_workflows+=("$workflow_id")
  done
else
  mapfile -t target_workflows < <(
    printf '%s\n' "${queue_policy_workflows[@]}" "${shared_foundation_workflows[@]}" |
      sed '/^$/d' |
      sort -u
  )
fi

if [[ "${#target_workflows[@]}" -eq 0 ]]; then
  echo "error: no workflows selected" >&2
  exit 1
fi

has_queue_policy_target() {
  local workflow_id="$1"
  jq -e --arg wf "$workflow_id" '.targets[$wf]' "$policy_file" >/dev/null
}

has_shared_foundation_target() {
  local workflow_id="$1"
  jq -e --arg wf "$workflow_id" '.shared_foundation.targets[$wf]' "$policy_file" >/dev/null
}

check_queue_policy_target() {
  local workflow_id="$1"
  local template
  template="$(jq -r --arg wf "$workflow_id" '.targets[$wf].template' "$policy_file")"
  [[ -n "$template" && "$template" != "null" ]] || {
    echo "error: missing template for $workflow_id" >&2
    return 1
  }
  [[ "$template" = /* ]] || template="$repo_root/$template"
  [[ -f "$template" ]] || {
    echo "error: template file not found for $workflow_id: $template" >&2
    return 1
  }

  local uids_json
  uids_json="$(jq -c --arg wf "$workflow_id" '.targets[$wf].object_uids' "$policy_file")"
  [[ "$uids_json" != "null" ]] || {
    echo "error: missing object_uids for $workflow_id" >&2
    return 1
  }

  local plist_json
  plist_json="$(plist_to_json "$template")"

  if ! jq -e --argjson expected "$uids_json" '
    ([.objects[] | select(.type=="alfred.workflow.input.scriptfilter") | .uid] | sort) == ($expected | sort)
  ' >/dev/null <<<"$plist_json"; then
    echo "error: script filter uid set mismatch for $workflow_id" >&2
    return 1
  fi

  if ! jq -e \
    --argjson expected "$uids_json" \
    --argjson expected_custom "$queue_delay_custom" \
    --argjson expected_mode "$queue_delay_mode" \
    --argjson expected_immediate "$immediate_initial" '
    [
      $expected[] as $uid |
      .objects[] |
      select(.uid == $uid and .type == "alfred.workflow.input.scriptfilter") |
      (
        .config.queuedelaycustom == $expected_custom and
        .config.queuedelaymode == $expected_mode and
        .config.queuedelayimmediatelyinitially == $expected_immediate
      )
    ] | all
  ' >/dev/null <<<"$plist_json"; then
    echo "error: queue policy mismatch for $workflow_id" >&2
    return 1
  fi

  echo "ok: queue policy matches for $workflow_id"
}

apply_queue_policy_target() {
  local workflow_id="$1"
  local template
  template="$(jq -r --arg wf "$workflow_id" '.targets[$wf].template' "$policy_file")"
  [[ "$template" = /* ]] || template="$repo_root/$template"
  [[ -f "$template" ]] || {
    echo "error: template file not found for $workflow_id: $template" >&2
    return 1
  }

  local immediate_tag="<false/>"
  if [[ "$immediate_initial" == "true" ]]; then
    immediate_tag="<true/>"
  fi

  perl -0pi -e 's#(<key>queuedelaycustom</key>\s*<integer>)[0-9]+(</integer>)#${1}'"$queue_delay_custom"'${2}#g' "$template"
  perl -0pi -e 's#(<key>queuedelaymode</key>\s*<integer>)[0-9]+(</integer>)#${1}'"$queue_delay_mode"'${2}#g' "$template"
  perl -0pi -e 's#(<key>queuedelayimmediatelyinitially</key>\s*)<(?:true|false)/>#${1}'"$immediate_tag"'#g' "$template"

  echo "ok: applied queue policy to $workflow_id"
}

check_shared_foundation_target() {
  local workflow_id="$1"
  local script_filter_path
  script_filter_path="$(jq -r --arg wf "$workflow_id" '.shared_foundation.targets[$wf].script_filter' "$policy_file")"
  [[ -n "$script_filter_path" && "$script_filter_path" != "null" ]] || {
    echo "error: missing shared_foundation target script_filter for $workflow_id" >&2
    return 1
  }
  [[ "$script_filter_path" = /* ]] || script_filter_path="$repo_root/$script_filter_path"
  [[ -f "$script_filter_path" ]] || {
    echo "error: shared_foundation script_filter not found for $workflow_id: $script_filter_path" >&2
    return 1
  }

  local -a profiles=()
  mapfile -t profiles < <(jq -r --arg wf "$workflow_id" '.shared_foundation.targets[$wf].requires[]?' "$policy_file")
  if [[ "${#profiles[@]}" -eq 0 ]]; then
    echo "error: missing shared_foundation requires profiles for $workflow_id" >&2
    return 1
  fi

  local profile_name
  for profile_name in "${profiles[@]}"; do
    local profile_source
    profile_source="$(jq -r --arg name "$profile_name" '.shared_foundation.profiles[$name].source' "$policy_file")"
    [[ -n "$profile_source" && "$profile_source" != "null" ]] || {
      echo "error: missing shared_foundation profile source: $profile_name" >&2
      return 1
    }

    local profile_source_path="$profile_source"
    [[ "$profile_source_path" = /* ]] || profile_source_path="$repo_root/$profile_source_path"
    [[ -f "$profile_source_path" ]] || {
      echo "error: shared_foundation profile source not found ($profile_name): $profile_source_path" >&2
      return 1
    }

    local -a markers=()
    mapfile -t markers < <(jq -r --arg name "$profile_name" '.shared_foundation.profiles[$name].required_markers[]?' "$policy_file")
    if [[ "${#markers[@]}" -eq 0 ]]; then
      echo "error: missing required_markers for shared_foundation profile: $profile_name" >&2
      return 1
    fi

    local marker
    for marker in "${markers[@]}"; do
      if ! rg -F -q -- "$marker" "$script_filter_path"; then
        echo "error: shared foundation mismatch for $workflow_id ($profile_name): missing marker '$marker' in $script_filter_path" >&2
        return 1
      fi
    done
  done

  local -a prohibited_patterns=()
  mapfile -t prohibited_patterns < <(jq -r '.shared_foundation.prohibited_patterns[]?' "$policy_file")
  local blocked_pattern
  for blocked_pattern in "${prohibited_patterns[@]}"; do
    if rg -F -q -- "$blocked_pattern" "$script_filter_path"; then
      echo "error: prohibited shared_foundation placeholder found for $workflow_id: '$blocked_pattern' in $script_filter_path" >&2
      return 1
    fi
  done

  echo "ok: shared foundation policy matches for $workflow_id"
}

for workflow_id in "${target_workflows[@]}"; do
  if has_queue_policy_target "$workflow_id"; then
    if [[ "$mode" == "apply" ]]; then
      apply_queue_policy_target "$workflow_id"
    fi
    check_queue_policy_target "$workflow_id"
  fi

  if has_shared_foundation_target "$workflow_id"; then
    check_shared_foundation_target "$workflow_id"
  fi
done
