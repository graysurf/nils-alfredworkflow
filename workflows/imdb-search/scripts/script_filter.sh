#!/usr/bin/env bash
set -euo pipefail

resolve_helper() {
  local helper_name="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local git_repo_root=""
  git_repo_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"

  local candidates=(
    "$script_dir/lib/$helper_name"
    "$script_dir/../../../scripts/lib/$helper_name"
  )
  if [[ -n "$git_repo_root" ]]; then
    candidates+=("$git_repo_root/scripts/lib/$helper_name")
  fi

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

error_json_helper="$(resolve_helper "script_filter_error_json.sh" || true)"
if [[ -z "$error_json_helper" ]]; then
  printf '{"items":[{"title":"Workflow helper missing","subtitle":"Cannot locate script_filter_error_json.sh runtime helper.","valid":false}]}\n'
  exit 0
fi
# shellcheck disable=SC1090
source "$error_json_helper"

query_policy_helper="$(resolve_helper "script_filter_query_policy.sh" || true)"
if [[ -z "$query_policy_helper" ]]; then
  sfej_emit_error_item_json "Workflow helper missing" "Cannot locate script_filter_query_policy.sh runtime helper."
  exit 0
fi
# shellcheck disable=SC1090
source "$query_policy_helper"

resolve_imdb_section() {
  local value
  value="$(printf '%s' "${IMDB_SEARCH_SECTION:-tt}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

  case "$value" in
  tt | nm | co | ev | ep | kw)
    printf '%s\n' "$value"
    ;;
  *)
    printf 'tt\n'
    ;;
  esac
}

resolve_max_results() {
  local raw value
  raw="${IMDB_MAX_RESULTS:-8}"
  if [[ ! "$raw" =~ ^[0-9]+$ ]]; then
    printf '8\n'
    return
  fi

  value="$raw"
  if ((value < 1)); then
    value=1
  fi
  if ((value > 20)); then
    value=20
  fi
  printf '%s\n' "$value"
}

urlencode_query() {
  local value="${1-}"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$value" <<'PY'
import sys
import urllib.parse

print(urllib.parse.quote(sys.argv[1], safe=""))
PY
    return 0
  fi

  value="${value//%/%25}"
  value="${value// /%20}"
  value="${value//+/%2B}"
  value="${value//&/%26}"
  value="${value//#/%23}"
  value="${value//\?/%3F}"
  printf '%s\n' "$value"
}

resolve_suggest_prefix() {
  local query="$1"
  local first
  first="$(printf '%s' "$query" | cut -c1 | tr '[:upper:]' '[:lower:]')"

  if [[ "$first" =~ ^[a-z0-9]$ ]]; then
    printf '%s\n' "$first"
    return
  fi

  printf '_\n'
}

build_search_url() {
  local query="$1"
  local section="$2"
  local encoded
  encoded="$(urlencode_query "$query")"
  printf 'https://www.imdb.com/find/?q=%s&s=%s&ref_=fn_%s\n' "$encoded" "$section" "$section"
}

fetch_suggestions_json() {
  local query="$1"

  if [[ -n "${IMDB_SUGGEST_PAYLOAD_FILE:-}" && -f "${IMDB_SUGGEST_PAYLOAD_FILE}" ]]; then
    cat "${IMDB_SUGGEST_PAYLOAD_FILE}"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "curl not found" >&2
    return 1
  fi

  local encoded prefix url err_file
  encoded="$(urlencode_query "$query")"
  prefix="$(resolve_suggest_prefix "$query")"
  url="https://v2.sg.media-imdb.com/suggestion/${prefix}/${encoded}.json"
  err_file="${TMPDIR:-/tmp}/imdb-search-suggest.err.$$.$RANDOM"

  if curl -fsSL --connect-timeout 4 --max-time 8 "$url" 2>"$err_file"; then
    rm -f "$err_file"
    return 0
  fi

  cat "$err_file" >&2
  rm -f "$err_file"
  return 1
}

emit_fallback_item() {
  local query="$1"
  local search_url="$2"
  local subtitle="$3"

  printf '{"items":[{"title":"%s","subtitle":"%s","arg":"%s","valid":true}]}' \
    "$(sfej_json_escape "Search IMDb: $query")" \
    "$(sfej_json_escape "$subtitle")" \
    "$(sfej_json_escape "$search_url")"
  printf '\n'
}

render_suggestion_items() {
  local query="$1"
  local search_url="$2"
  local max_results="$3"
  local payload="$4"

  python3 - "$query" "$search_url" "$max_results" "$payload" <<'PY'
import json
import sys
import urllib.parse

query = sys.argv[1]
search_url = sys.argv[2]
max_results = int(sys.argv[3])
payload = sys.argv[4]


def detail_url(imdb_id: str, title: str) -> str:
    if imdb_id.startswith("tt"):
        return f"https://www.imdb.com/title/{imdb_id}/"
    if imdb_id.startswith("nm"):
        return f"https://www.imdb.com/name/{imdb_id}/"
    if imdb_id.startswith("co"):
        return f"https://www.imdb.com/company/{imdb_id}/"
    if imdb_id.startswith("ev"):
        return f"https://www.imdb.com/event/{imdb_id}/"
    if imdb_id.startswith("kw"):
        return "https://www.imdb.com/search/keyword/?keywords=" + urllib.parse.quote(title, safe="")
    return search_url


def build_subtitle(entry: dict) -> str:
    parts = []
    kind = entry.get("q")
    year = entry.get("y")
    cast = entry.get("s")
    if kind:
        parts.append(str(kind))
    if year:
        parts.append(str(year))
    if cast:
        parts.append(str(cast))
    if not parts:
        return "Open on IMDb"
    return " • ".join(parts)

items = []
parse_error = False

try:
    data = json.loads(payload)
except Exception:
    data = {}
    parse_error = True

for entry in (data.get("d") or []):
    title = entry.get("l")
    imdb_id = entry.get("id")
    if not title or not imdb_id:
        continue

    items.append(
        {
            "title": title,
            "subtitle": build_subtitle(entry),
            "arg": detail_url(imdb_id, title),
            "valid": True,
        }
    )
    if len(items) >= max_results:
        break

items.append(
    {
        "title": f"Search IMDb: {query}",
        "subtitle": (
            "Suggestions parse failed; open full IMDb results page."
            if parse_error
            else "Open full IMDb results page."
        ),
        "arg": search_url,
        "valid": True,
    }
)

print(json.dumps({"items": items}, ensure_ascii=False))
PY
}

query="$(sfqp_resolve_query_input "${1:-}")"
query="$(sfqp_trim "$query")"

if [[ -z "$query" ]]; then
  sfej_emit_error_item_json "Enter a title keyword" "Type keywords after im to search IMDb."
  exit 0
fi

if sfqp_is_short_query "$query" 2; then
  sfqp_emit_short_query_item_json \
    2 \
    "Keep typing (2+ chars)" \
    "Type at least %s characters before searching IMDb."
  exit 0
fi

imdb_section="$(resolve_imdb_section)"
search_url="$(build_search_url "$query" "$imdb_section")"
max_results="$(resolve_max_results)"

if ! command -v python3 >/dev/null 2>&1; then
  emit_fallback_item "$query" "$search_url" "python3 not found; press Enter to open IMDb search."
  exit 0
fi

suggest_payload=""
if ! suggest_payload="$(fetch_suggestions_json "$query")"; then
  emit_fallback_item "$query" "$search_url" "Suggestions unavailable now; press Enter to open IMDb search."
  exit 0
fi

if [[ -z "$suggest_payload" ]]; then
  emit_fallback_item "$query" "$search_url" "No suggestions returned; press Enter to open IMDb search."
  exit 0
fi

if rendered_json="$(render_suggestion_items "$query" "$search_url" "$max_results" "$suggest_payload" 2>/dev/null)"; then
  if command -v jq >/dev/null 2>&1; then
    if jq -e '.items | type == "array" and length >= 1' >/dev/null <<<"$rendered_json"; then
      printf '%s\n' "$rendered_json"
      exit 0
    fi
  else
    printf '%s\n' "$rendered_json"
    exit 0
  fi
fi

emit_fallback_item "$query" "$search_url" "Suggestions parse failed; press Enter to open IMDb search."
