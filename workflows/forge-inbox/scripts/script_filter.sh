#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

helper_loader=""
for candidate in \
  "$script_dir/lib/workflow_helper_loader.sh" \
  "$script_dir/../../../scripts/lib/workflow_helper_loader.sh"; do
  if [[ -f "$candidate" ]]; then
    helper_loader="$candidate"
    break
  fi
done

if [[ -z "$helper_loader" ]]; then
  printf '{"items":[{"title":"Workflow helper missing","subtitle":"Cannot locate workflow_helper_loader.sh runtime helper.","valid":false}]}\n'
  exit 0
fi

# shellcheck disable=SC1090
source "$helper_loader"

load_helper_or_exit() {
  local helper_name="$1"
  if ! wfhl_source_helper "$script_dir" "$helper_name" auto; then
    wfhl_emit_missing_helper_item_json "$helper_name"
    exit 0
  fi
}

load_helper_or_exit "script_filter_error_json.sh"
load_helper_or_exit "script_filter_query_policy.sh"

emit_item() {
  local title="$1"
  local subtitle="${2:-}"
  local icon_path="${3:-}"

  if [[ -n "$icon_path" ]]; then
    printf '{"items":[{"title":"%s","subtitle":"%s","valid":false,"icon":{"path":"%s"}}]}\n' \
      "$(sfej_json_escape "$title")" \
      "$(sfej_json_escape "$subtitle")" \
      "$(sfej_json_escape "$icon_path")"
    return
  fi

  sfej_emit_error_item_json "$title" "$subtitle"
}

trim() {
  sfqp_trim "${1-}"
}

to_lower() {
  printf '%s' "${1-}" | tr '[:upper:]' '[:lower:]'
}

expand_home_path() {
  local value="${1-}"

  case "$value" in
  "~")
    if [[ -n "${HOME:-}" ]]; then
      printf '%s\n' "${HOME%/}"
      return 0
    fi
    ;;
  \~/*)
    if [[ -n "${HOME:-}" ]]; then
      printf '%s/%s\n' "${HOME%/}" "${value#\~/}"
      return 0
    fi
    ;;
  esac

  printf '%s\n' "$value"
}

normalize_provider_mode() {
  local value
  value="$(to_lower "$(trim "${1-}")")"
  case "$value" in
  all | both | mixed)
    printf 'all\n'
    ;;
  gh | github)
    printf 'gh\n'
    ;;
  glab | gitlab)
    printf 'glab\n'
    ;;
  *)
    return 1
    ;;
  esac
}

normalize_item_mode() {
  local value
  value="$(to_lower "$(trim "${1-}")")"
  case "$value" in
  all | work)
    printf 'all\n'
    ;;
  pr | prs | mr | mrs)
    printf 'pr\n'
    ;;
  issue | issues)
    printf 'issue\n'
    ;;
  *)
    return 1
    ;;
  esac
}

parsed_provider_mode=""
parsed_item_mode=""
parsed_filter=""

parse_query() {
  local query="$1"
  local -a tokens=()
  local -a filter_tokens=()
  local idx=0
  local token=""
  local lower=""

  parsed_provider_mode=""
  parsed_item_mode=""
  parsed_filter=""

  # Alfred query parsing is intentionally shell-token simple: leading mode
  # tokens are commands, all remaining text is a local row filter.
  read -r -a tokens <<<"$query"

  while [[ "$idx" -lt "${#tokens[@]}" ]]; do
    token="${tokens[$idx]}"
    lower="$(to_lower "$token")"

    case "$lower" in
    all)
      if [[ -z "$parsed_provider_mode" ]]; then
        parsed_provider_mode="all"
      elif [[ -z "$parsed_item_mode" ]]; then
        parsed_item_mode="all"
      else
        break
      fi
      ;;
    both | mixed)
      parsed_provider_mode="all"
      ;;
    gh | github)
      parsed_provider_mode="gh"
      ;;
    glab | gitlab)
      parsed_provider_mode="glab"
      ;;
    work)
      parsed_item_mode="all"
      ;;
    pr | prs | mr | mrs)
      parsed_item_mode="pr"
      ;;
    issue | issues)
      parsed_item_mode="issue"
      ;;
    *)
      break
      ;;
    esac

    idx=$((idx + 1))
  done

  while [[ "$idx" -lt "${#tokens[@]}" ]]; do
    filter_tokens+=("${tokens[$idx]}")
    idx=$((idx + 1))
  done

  parsed_filter="$(trim "${filter_tokens[*]:-}")"
}

resolve_limit() {
  local raw="${FORGE_INBOX_LIMIT:-30}"
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    if [[ "$raw" -lt 1 ]]; then
      printf '1\n'
    elif [[ "$raw" -gt 100 ]]; then
      printf '100\n'
    else
      printf '%s\n' "$raw"
    fi
    return 0
  fi

  printf '30\n'
}

resolve_bool() {
  local raw
  raw="$(to_lower "$(trim "${1-}")")"

  case "$raw" in
  1 | true | yes | on)
    printf '1\n'
    ;;
  "" | 0 | false | no | off)
    printf '0\n'
    ;;
  *)
    return 1
    ;;
  esac
}

resolve_forge_cli() {
  local configured
  configured="$(trim "${FORGE_CLI_BIN:-}")"
  configured="$(expand_home_path "$configured")"

  if [[ -n "$configured" ]]; then
    if [[ -x "$configured" ]]; then
      printf '%s\n' "$configured"
      return 0
    fi

    printf 'configured FORGE_CLI_BIN is not executable: %s\n' "$configured" >&2
    return 1
  fi

  local resolved=""
  resolved="$(command -v forge-cli 2>/dev/null || true)"
  if [[ -n "$resolved" && -x "$resolved" ]]; then
    printf '%s\n' "$resolved"
    return 0
  fi

  printf 'forge-cli binary not found; set FORGE_CLI_BIN or install forge-cli on PATH\n' >&2
  return 1
}

render_forge_payload() {
  local payload="$1"
  local item_mode="$2"
  local filter_text="$3"
  local configured_warning="$4"
  local provider_mode="$5"

  jq -c \
    --arg itemMode "$item_mode" \
    --arg filterText "$filter_text" \
    --arg configuredWarning "$configured_warning" \
    --arg providerMode "$provider_mode" \
    '
def clean:
  tostring
  | gsub("[\r\n]+"; " ")
  | gsub("[[:space:]]+"; " ")
  | gsub("^ "; "")
  | gsub(" $"; "");

def text_value:
  if . == null then ""
  elif type == "array" then map(tostring) | join(", ")
  elif type == "object" then (.login // .username // .name // .id // "" | tostring)
  else tostring
  end
  | clean;

def target_type:
  (.source // "") as $source
  | (.url // "") as $url
  | if $source == "github_search_prs" then "pr"
    elif $source == "github_search_issues" then "issue"
    elif $source == "gitlab_merge_requests" then "pr"
    elif $source == "gitlab_issues" then "issue"
    elif $source == "gitlab_todos" then
      if ($url | test("/-/merge_requests/|/pull/")) then "pr"
      elif ($url | test("/-/issues/|/issues/")) then "issue"
      else "other"
      end
    else "other"
    end;

def provider_label:
  (.provider // "") as $provider
  | (.host // "") as $host
  | if ($provider | ascii_downcase) == "github" then "GitHub"
    elif ($provider | ascii_downcase) == "gitlab" then
      if $host == "" then "GitLab" else "GitLab " + $host end
    else ($provider | text_value)
    end;

def provider_warning_label:
  (.provider // .name // "provider" | tostring | ascii_downcase) as $provider
  | if $provider == "github" then "GitHub"
    elif $provider == "gitlab" then "GitLab"
    elif $provider == "" then "Provider"
    else ($provider | ascii_upcase)
    end;

def type_label:
  (.source // "") as $source
  | if $source == "github_search_prs" then "GitHub PR"
    elif $source == "github_search_issues" then "GitHub Issue"
    elif $source == "gitlab_merge_requests" then "GitLab MR"
    elif $source == "gitlab_issues" then "GitLab Issue"
    elif $source == "gitlab_todos" and target_type == "pr" then "GitLab MR Todo"
    elif $source == "gitlab_todos" and target_type == "issue" then "GitLab Issue Todo"
    elif $source == "gitlab_todos" then "GitLab Todo"
    else (provider_label + " Item")
    end;

def reasons_label:
  (.reasons // .reason // .kind // []) as $reasons
  | if ($reasons | type) == "array" then ($reasons | map(tostring) | join(", "))
    else ($reasons | tostring)
    end
  | clean;

def item_title:
  (.number // .iid // "") as $number
  | (.title // "(untitled)") as $title
  | ($number | text_value) as $number_text
  | ($title | text_value) as $title_text
  | if $number_text != "" then "#\($number_text) \($title_text)"
    else $title_text
    end
  | clean;

def reference_title:
  (.repo // .repository // "") as $repo
  | (.number // .iid // "") as $number
  | (.title // "(untitled)") as $title
  | ($repo | text_value) as $repo_text
  | ($number | text_value) as $number_text
  | ($title | text_value) as $title_text
  | if $repo_text != "" and $number_text != "" then "\($repo_text)#\($number_text) \($title_text)"
    elif $repo_text != "" then "\($repo_text) \($title_text)"
    elif $number_text != "" then "#\($number_text) \($title_text)"
    else $title_text
    end
  | clean;

def item_subtitle:
  (.repo // .repository // "" | text_value) as $repo_text
  |
  [
    ($repo_text | if . == "" then empty else . end),
    type_label,
    (reasons_label | if . == "" then empty else . end),
    ((.updated_at // .updated // .created_at // "") | text_value | if . == "" then empty else "updated " + . end),
    ((.author // .assignee // "") | text_value | if . == "" then empty else . end)
  ]
  | join(" | ");

def icon_fields_for_provider($provider):
  ($provider | ascii_downcase) as $provider
  | if $provider == "github" then
      {icon: {path: "assets/icon-github.png"}}
    elif $provider == "gitlab" then
      {icon: {path: "assets/icon-gitlab.png"}}
    else {}
    end;

def provider_icon_fields:
  icon_fields_for_provider(.provider // "");

def mode_icon_fields:
  if $providerMode == "gh" then icon_fields_for_provider("github")
  elif $providerMode == "glab" then icon_fields_for_provider("gitlab")
  else {}
  end;

def action_token($action):
  {
    action: $action,
    url: (.url // ""),
    provider: (.provider // ""),
    host: (.host // ""),
    repo: (.repo // .repository // ""),
    number: (.number // .iid // ""),
    title: (.title // ""),
    source: (.source // "")
  }
  + if $action == "copy-md" then {markdown: ("[" + reference_title + "](" + (.url // "") + ")")} else {} end
  | tojson;

def searchable:
  [
    (.title // ""),
    (.repo // .repository // ""),
    (.number // .iid // ""),
    (.author // ""),
    (.provider // ""),
    (reasons_label),
    (.source // "")
  ]
  | map(text_value)
  | join(" ")
  | ascii_downcase;

def warning_text:
  if type == "string" then .
  elif type == "object" then (.message // .error.message // .error // .detail // tostring)
  else tostring
  end
  | clean;

def warning_row($title; $subtitle):
  {
    title: $title,
    subtitle: $subtitle,
    valid: false
  };

def item_row:
  (.url // "") as $url
  | ({
      title: item_title,
      subtitle: item_subtitle,
      arg: action_token("open"),
      valid: ($url != ""),
      mods: {
        cmd: {
          valid: ($url != ""),
          arg: action_token("copy-url"),
          subtitle: "Copy URL"
        },
        alt: {
          valid: ($url != ""),
          arg: action_token("copy-md"),
          subtitle: "Copy Markdown reference"
        }
      }
    } + provider_icon_fields);

($filterText | ascii_downcase) as $needle
| [
    if $configuredWarning != "" then
      warning_row("Set FORGE_INBOX_GITLAB_HOST"; $configuredWarning) + icon_fields_for_provider("gitlab")
    else empty end
  ] as $configured_warning_rows
| [
    (.data.providers // [])[]?
    | select(.ok == false)
    | warning_row((provider_warning_label + " query failed"); ((.error.message // .error // "Provider query failed") | warning_text)) + provider_icon_fields
  ] as $provider_warning_rows
| [
    ((.warnings // .data.warnings // [])[]?)
    | warning_row("forge-cli warning"; warning_text)
  ] as $top_warning_rows
| [
    (.data.items // [])[]?
    | target_type as $target
    | select($itemMode == "all" or $target == $itemMode)
    | select($needle == "" or (searchable | contains($needle)))
    | item_row
  ] as $item_rows
| ($configured_warning_rows + $provider_warning_rows + $top_warning_rows + $item_rows) as $rows
| if ($rows | length) == 0 then
    {items: [warning_row("No inbox items"; "Try a broader provider, item, or text filter.") + mode_icon_fields]}
  else
    {items: $rows}
  end
' <<<"$payload"
}

query="$(sfqp_resolve_query_input "${1-}")"
if [[ "$query" == "(null)" ]]; then
  query=""
fi
query="$(trim "$query")"

parse_query "$query"

default_provider_raw="${FORGE_INBOX_PROVIDER_MODE:-all}"
default_item_raw="${FORGE_INBOX_ITEM_MODE:-all}"
fixed_provider_raw="${FORGE_INBOX_FIXED_PROVIDER_MODE:-}"

default_provider_mode=""
if ! default_provider_mode="$(normalize_provider_mode "$default_provider_raw")"; then
  emit_item "Invalid FORGE_INBOX_PROVIDER_MODE" "Use all, gh, or glab."
  exit 0
fi

default_item_mode=""
if ! default_item_mode="$(normalize_item_mode "$default_item_raw")"; then
  emit_item "Invalid FORGE_INBOX_ITEM_MODE" "Use all, pr, or issue."
  exit 0
fi

fixed_provider_mode=""
if [[ -n "$(trim "$fixed_provider_raw")" ]]; then
  if ! fixed_provider_mode="$(normalize_provider_mode "$fixed_provider_raw")"; then
    emit_item "Invalid FORGE_INBOX_FIXED_PROVIDER_MODE" "Use all, gh, or glab."
    exit 0
  fi
fi

provider_mode="${fixed_provider_mode:-${parsed_provider_mode:-$default_provider_mode}}"
item_mode="${parsed_item_mode:-$default_item_mode}"
filter_text="$parsed_filter"
limit="$(resolve_limit)"
gitlab_host="$(trim "${FORGE_INBOX_GITLAB_HOST:-}")"
configured_warning=""
show_config_warnings=""

if ! show_config_warnings="$(resolve_bool "${FORGE_INBOX_SHOW_CONFIG_WARNINGS:-false}")"; then
  emit_item "Invalid FORGE_INBOX_SHOW_CONFIG_WARNINGS" "Use true or false."
  exit 0
fi

declare -a argv=()

if [[ "$provider_mode" == "glab" && -z "$gitlab_host" ]]; then
  if [[ "$show_config_warnings" == "1" ]]; then
    emit_item "Set FORGE_INBOX_GITLAB_HOST" "GitLab-only mode requires an explicit GitLab host." "assets/icon-gitlab.png"
  else
    printf '{"items":[]}\n'
  fi
  exit 0
fi

forge_cli=""
if ! forge_cli="$(resolve_forge_cli 2> >(sed 's/^/error: /' >&2))"; then
  emit_item "forge-cli binary not found" "Set FORGE_CLI_BIN or install forge-cli on PATH."
  exit 0
fi

case "$provider_mode" in
gh)
  argv=("$forge_cli" "--provider" "github" "--format" "json" "inbox" "list" "--limit" "$limit")
  ;;
glab)
  argv=("$forge_cli" "--provider" "gitlab" "--format" "json" "inbox" "list" "--gitlab-host" "$gitlab_host" "--limit" "$limit")
  ;;
all)
  if [[ -n "$gitlab_host" ]]; then
    argv=("$forge_cli" "--format" "json" "inbox" "list" "--gitlab-host" "$gitlab_host" "--limit" "$limit")
  else
    argv=("$forge_cli" "--provider" "github" "--format" "json" "inbox" "list" "--limit" "$limit")
    if [[ "$show_config_warnings" -eq 1 ]]; then
      configured_warning="Mixed mode needs FORGE_INBOX_GITLAB_HOST for GitLab; showing GitHub-only results."
    fi
  fi
  ;;
*)
  emit_item "Invalid provider mode" "Use all, gh, or glab."
  exit 0
  ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  emit_item "jq is required" "Install jq so the workflow can parse forge-cli JSON output."
  exit 0
fi

stderr_file="$(mktemp "${TMPDIR:-/tmp}/forge-inbox-stderr.XXXXXX")"
trap 'rm -f "$stderr_file"' EXIT

set +e
payload="$("${argv[@]}" 2>"$stderr_file")"
rc=$?
set -e

stderr_text="$(sfej_normalize_error_message "$(cat "$stderr_file" 2>/dev/null || true)")"

if [[ "$rc" -ne 0 ]]; then
  if [[ -z "$stderr_text" ]]; then
    stderr_text="forge-cli exited with status $rc"
  fi
  emit_item "forge-cli inbox failed" "$stderr_text"
  exit 0
fi

if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$payload"; then
  emit_item "forge-cli returned invalid JSON" "Check FORGE_CLI_BIN and forge-cli version."
  exit 0
fi

if ! jq -e '.ok == true and (.data.items | type == "array")' >/dev/null 2>&1 <<<"$payload"; then
  message="$(jq -r '.error.message // .error // .message // "forge-cli returned an unsuccessful envelope"' <<<"$payload" 2>/dev/null || true)"
  message="$(sfej_normalize_error_message "$message")"
  emit_item "forge-cli inbox failed" "$message"
  exit 0
fi

if ! render_forge_payload "$payload" "$item_mode" "$filter_text" "$configured_warning" "$provider_mode"; then
  emit_item "forge-cli output parse failed" "The inbox JSON envelope could not be rendered for Alfred."
fi
