#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

default_countries_csv="AR,AT,AU,BE,BR,CA,CH,CL,CO,CZ,DE,DK,EG,ES,FI,FR,GB,GR,HK,HU,ID,IE,IL,IN,IT,JP,KR,MX,MY,NL,NO,NZ,PE,PH,PL,PT,RO,SA,SE,SG,TH,TR,TW,UA,US,VN,ZA"
default_queries_csv="dark,one piece,money heist,stranger things,愛,韓劇"

countries_csv=""
countries_file=""
queries_csv="$default_queries_csv"
threshold_percent=50
min_success_calls=2
delay_ms=350
apply_mode=0
report_dir="${AGENTS_HOME:-$HOME/.agents}/out/netflix-country-probe"
brave_cli_override=""
url_probe_title_id="80057281"

usage() {
  cat <<'USAGE'
Usage:
  scripts/netflix-country-probe.sh [options]

Options:
  --countries CSV          Country codes to probe (for example "TW,JP,KR,US").
                           Default uses a maintained common-market list.
  --countries-file PATH    Read country codes from file (one per line, '#' comments allowed).
  --queries CSV            Probe queries (comma-separated). Default:
                           dark,one piece,money heist,stranger things,愛,韓劇
  --threshold N            Minimum hit ratio (0..100) to suggest allowlist. Default: 50
  --min-success-calls N    Minimum successful API calls required per country. Default: 2
  --delay-ms N             Sleep between requests in milliseconds. Default: 350
  --report-dir PATH        Output directory. Default: $AGENTS_HOME/out/netflix-country-probe
  --brave-cli PATH         Override brave-cli binary path.
  --apply                  Apply suggested allowlist to workflows/netflix-search/scripts/country_map.sh
  -h, --help               Show this help.

Behavior:
  - Target: Netflix country-path allowlist consumed by NETFLIX_CATALOG_REGION
            (fallback BRAVE_COUNTRY) in netflix-search.
  1) URL pre-check (https://www.netflix.com/<country>/title/<id>).
  2) Brave search probe only when URL pre-check is not definite NotFound.
     US is forced-global and skips search probe.
  3) If BRAVE_COUNTRY request returns parameter-validation 422, retry once
     without BRAVE_COUNTRY (same query) after a short delay to avoid
     immediate rate-limit false negatives.

Required env:
  BRAVE_API_KEY
USAGE
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

contains_value() {
  local needle="$1"
  shift || true
  local value
  for value in "$@"; do
    if [[ "$value" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

COUNTRIES=()
add_country_code() {
  local raw="$1"
  local trimmed
  trimmed="$(trim "$raw")"
  [[ -n "$trimmed" ]] || return 0
  local upper
  upper="$(printf '%s' "$trimmed" | tr '[:lower:]' '[:upper:]')"
  if [[ ! "$upper" =~ ^[A-Z]{2}$ ]]; then
    printf 'warn: skip invalid country code: %s\n' "$raw" >&2
    return 0
  fi
  if ! contains_value "$upper" "${COUNTRIES[@]}"; then
    COUNTRIES+=("$upper")
  fi
}

QUERIES=()
add_query() {
  local raw="$1"
  local trimmed
  trimmed="$(trim "$raw")"
  [[ -n "$trimmed" ]] || return 0
  if ! contains_value "$trimmed" "${QUERIES[@]}"; then
    QUERIES+=("$trimmed")
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --countries)
    countries_csv="${2:-}"
    [[ -n "$countries_csv" ]] || {
      echo "error: --countries requires a value" >&2
      exit 2
    }
    shift 2
    ;;
  --countries-file)
    countries_file="${2:-}"
    [[ -n "$countries_file" ]] || {
      echo "error: --countries-file requires a value" >&2
      exit 2
    }
    shift 2
    ;;
  --queries)
    queries_csv="${2:-}"
    [[ -n "$queries_csv" ]] || {
      echo "error: --queries requires a value" >&2
      exit 2
    }
    shift 2
    ;;
  --threshold)
    threshold_percent="${2:-}"
    shift 2
    ;;
  --min-success-calls)
    min_success_calls="${2:-}"
    shift 2
    ;;
  --delay-ms)
    delay_ms="${2:-}"
    shift 2
    ;;
  --report-dir)
    report_dir="${2:-}"
    [[ -n "$report_dir" ]] || {
      echo "error: --report-dir requires a value" >&2
      exit 2
    }
    shift 2
    ;;
  --brave-cli)
    brave_cli_override="${2:-}"
    [[ -n "$brave_cli_override" ]] || {
      echo "error: --brave-cli requires a value" >&2
      exit 2
    }
    shift 2
    ;;
  --apply)
    apply_mode=1
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

if [[ -n "$countries_csv" && -n "$countries_file" ]]; then
  echo "error: --countries and --countries-file are mutually exclusive" >&2
  exit 2
fi

if ! is_integer "$threshold_percent" || ((threshold_percent < 0 || threshold_percent > 100)); then
  echo "error: --threshold must be integer 0..100" >&2
  exit 2
fi

if ! is_integer "$min_success_calls" || ((min_success_calls < 1)); then
  echo "error: --min-success-calls must be integer >= 1" >&2
  exit 2
fi

if ! is_integer "$delay_ms"; then
  echo "error: --delay-ms must be integer >= 0" >&2
  exit 2
fi

if [[ -z "${BRAVE_API_KEY:-}" ]]; then
  echo "error: BRAVE_API_KEY is required" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 2
fi

if [[ -n "$countries_file" ]]; then
  [[ -f "$countries_file" ]] || {
    echo "error: countries file not found: $countries_file" >&2
    exit 2
  }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    add_country_code "$line"
  done <"$countries_file"
elif [[ -n "$countries_csv" ]]; then
  while IFS= read -r token || [[ -n "$token" ]]; do
    add_country_code "$token"
  done < <(printf '%s\n' "$countries_csv" | tr ',' '\n')
else
  while IFS= read -r token || [[ -n "$token" ]]; do
    add_country_code "$token"
  done < <(printf '%s\n' "$default_countries_csv" | tr ',' '\n')
fi

while IFS= read -r token || [[ -n "$token" ]]; do
  add_query "$token"
done < <(printf '%s\n' "$queries_csv" | tr ',' '\n')

if [[ "${#COUNTRIES[@]}" -eq 0 ]]; then
  echo "error: no valid country codes to probe" >&2
  exit 2
fi

if [[ "${#QUERIES[@]}" -eq 0 ]]; then
  echo "error: no valid queries to probe" >&2
  exit 2
fi

resolve_brave_cli() {
  if [[ -n "$brave_cli_override" ]]; then
    if [[ -x "$brave_cli_override" ]]; then
      printf '%s\n' "$brave_cli_override"
      return 0
    fi
    echo "error: --brave-cli is not executable: $brave_cli_override" >&2
    exit 2
  fi

  if [[ -n "${BRAVE_CLI_BIN:-}" && -x "${BRAVE_CLI_BIN:-}" ]]; then
    printf '%s\n' "$BRAVE_CLI_BIN"
    return 0
  fi

  if [[ -x "$repo_root/target/release/brave-cli" ]]; then
    printf '%s\n' "$repo_root/target/release/brave-cli"
    return 0
  fi

  cargo build --release -p nils-brave-cli >/dev/null
  if [[ -x "$repo_root/target/release/brave-cli" ]]; then
    printf '%s\n' "$repo_root/target/release/brave-cli"
    return 0
  fi

  echo "error: brave-cli binary not found after build" >&2
  exit 1
}

compact_text_file() {
  tr '\n' ' ' <"$1" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

truncate_text() {
  local value="$1"
  local limit="${2:-180}"
  if ((${#value} > limit)); then
    printf '%s...' "${value:0:limit}"
    return 0
  fi
  printf '%s' "$value"
}

append_note() {
  local note="${1:-}"
  [[ -n "$note" ]] || return 0
  if [[ -z "$notes" ]]; then
    notes="$note"
  else
    notes+=", $note"
  fi
}

URL_PROBE_STATUS=""
URL_PROBE_NOTE=""
probe_country_url() {
  local country_upper="$1"
  local error_file="$2"

  URL_PROBE_STATUS=""
  URL_PROBE_NOTE=""

  local country_lower
  country_lower="$(printf '%s' "$country_upper" | tr '[:upper:]' '[:lower:]')"
  local probe_url="https://www.netflix.com/${country_lower}/title/${url_probe_title_id}"
  local output

  if ! output="$(curl -sS -L --max-time 15 -o /dev/null -w '%{http_code}\t%{url_effective}' "$probe_url" 2>"$error_file")"; then
    URL_PROBE_STATUS="url_error"
    URL_PROBE_NOTE="$(truncate_text "$(compact_text_file "$error_file")")"
    return 0
  fi

  local http_code="unknown"
  local final_url=""
  if [[ "$output" == *$'\t'* ]]; then
    http_code="${output%%$'\t'*}"
    final_url="${output#*$'\t'}"
  fi

  local final_lower
  final_lower="$(printf '%s' "$final_url" | tr '[:upper:]' '[:lower:]')"
  if [[ "$final_lower" == *"/notfound"* ]]; then
    URL_PROBE_STATUS="notfound"
    URL_PROBE_NOTE="http=${http_code}; final=$(truncate_text "$final_url")"
    return 0
  fi

  URL_PROBE_STATUS="ok"
  URL_PROBE_NOTE="http=${http_code}; final=$(truncate_text "$final_url")"
}

RESULT_STATUS=""
RESULT_NOTE=""
RESULT_FALLBACK_USED=0
classify_search_json() {
  local output_json="$1"
  if ! jq -e '.items | type == "array"' "$output_json" >/dev/null 2>&1; then
    RESULT_STATUS="api_error"
    if [[ -n "$RESULT_NOTE" ]]; then
      RESULT_NOTE+="; invalid-json-shape"
    else
      RESULT_NOTE="invalid-json-shape"
    fi
    return 0
  fi

  if jq -e '[.items[]?.title] | any(. != "No results found")' "$output_json" >/dev/null 2>&1; then
    RESULT_STATUS="hit"
    return 0
  fi

  RESULT_STATUS="no_results"
  return 0
}

probe_query() {
  local brave_cli="$1"
  local country_upper="$2"
  local query="$3"
  local output_json="$4"
  local error_file="$5"

  RESULT_STATUS=""
  RESULT_NOTE=""
  RESULT_FALLBACK_USED=0

  local country_lower
  country_lower="$(printf '%s' "$country_upper" | tr '[:upper:]' '[:lower:]')"
  local site_query="site:netflix.com/${country_lower}/title ${query}"

  if BRAVE_COUNTRY="$country_upper" BRAVE_SAFESEARCH="off" "$brave_cli" search --query "$site_query" --mode alfred >"$output_json" 2>"$error_file"; then
    classify_search_json "$output_json"
    return 0
  fi

  local err_text
  err_text="$(compact_text_file "$error_file")"
  local err_lower
  err_lower="$(printf '%s' "$err_text" | tr '[:upper:]' '[:lower:]')"
  if [[ "$err_lower" == *"429"* || "$err_lower" == *"rate limit"* || "$err_lower" == *"rate-limit"* || "$err_lower" == *"quota"* ]]; then
    RESULT_STATUS="rate_limited"
    RESULT_NOTE="$err_text"
    return 0
  fi

  if [[ "$err_lower" == *"422"* && "$err_lower" == *"validate request parameter"* ]]; then
    RESULT_FALLBACK_USED=1
    local fallback_delay_ms
    fallback_delay_ms="$delay_ms"
    if ((fallback_delay_ms < 1000)); then
      fallback_delay_ms=1000
    fi
    local fallback_delay_seconds
    fallback_delay_seconds="$(awk -v ms="$fallback_delay_ms" 'BEGIN { printf "%.3f", ms / 1000 }')"
    sleep "$fallback_delay_seconds"

    if BRAVE_SAFESEARCH="off" "$brave_cli" search --query "$site_query" --mode alfred >"$output_json" 2>"$error_file"; then
      RESULT_NOTE="fallback-no-country(country-param-422)"
      classify_search_json "$output_json"
      return 0
    fi

    local fallback_err_text
    fallback_err_text="$(compact_text_file "$error_file")"
    local fallback_err_lower
    fallback_err_lower="$(printf '%s' "$fallback_err_text" | tr '[:upper:]' '[:lower:]')"
    if [[ "$fallback_err_lower" == *"429"* || "$fallback_err_lower" == *"rate limit"* || "$fallback_err_lower" == *"rate-limit"* || "$fallback_err_lower" == *"quota"* ]]; then
      RESULT_STATUS="rate_limited"
      RESULT_NOTE="fallback-no-country(country-param-422); ${fallback_err_text}"
      return 0
    fi

    RESULT_STATUS="api_error"
    RESULT_NOTE="fallback-no-country(country-param-422)-failed; ${fallback_err_text}"
    return 0
  fi

  RESULT_STATUS="api_error"
  RESULT_NOTE="$err_text"
  return 0
}

write_country_map() {
  local suggested_file="$1"
  local map_file="$repo_root/workflows/netflix-search/scripts/country_map.sh"
  local generated_at
  generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

  {
    echo '#!/usr/bin/env bash'
    echo '# shellcheck shell=bash'
    echo '#'
    echo '# Netflix regional path allowlist for:'
    echo '#   site:netflix.com/<country>/title'
    echo '#'
    echo '# Used by: NETFLIX_CATALOG_REGION in workflows/netflix-search'
    echo '# Fallback: BRAVE_COUNTRY when NETFLIX_CATALOG_REGION is empty/invalid'
    echo '#'
    echo '# Generated by scripts/netflix-country-probe.sh'
    echo "# Generated at: $generated_at"
    echo '#'
    echo '# Notes:'
    echo '# - Keep codes lowercase.'
    echo '# - us intentionally remains global (site:netflix.com/title).'
    echo
    echo 'NETFLIX_REGIONAL_TITLE_COUNTRIES=('
    while IFS= read -r country || [[ -n "$country" ]]; do
      [[ -n "$country" ]] || continue
      [[ "$country" == "us" ]] && continue
      printf '  "%s"\n' "$country"
    done <"$suggested_file"
    echo ')'
    cat <<'EOF'

nfs_country_uses_regional_title_path() {
  local country="${1:-}"
  local code
  for code in "${NETFLIX_REGIONAL_TITLE_COUNTRIES[@]}"; do
    if [[ "$code" == "$country" ]]; then
      return 0
    fi
  done
  return 1
}
EOF
  } >"$map_file"
}

mkdir -p "$report_dir"
tmp_root="$(mktemp -d "$report_dir/tmp.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

brave_cli="$(resolve_brave_cli)"
delay_seconds="$(awk -v ms="$delay_ms" 'BEGIN { printf "%.3f", ms / 1000 }')"

timestamp="$(date '+%Y%m%d-%H%M%S')"
report_file="$report_dir/netflix-country-probe-${timestamp}.md"
rows_file="$report_dir/netflix-country-probe-${timestamp}.tsv"
suggested_file="$report_dir/netflix-country-allowlist-${timestamp}.txt"

: >"$rows_file"
: >"$suggested_file"

total_requests=0
total_url_probes=0
skipped_search_countries=0
total_country_param_fallbacks=0

for country in "${COUNTRIES[@]}"; do
  hit_count=0
  no_results_count=0
  api_error_count=0
  rate_limited_count=0
  last_note=""
  notes=""
  country_param_fallback_count=0

  country_lower="$(printf '%s' "$country" | tr '[:upper:]' '[:lower:]')"
  suggested="no"
  should_run_search=1
  url_probe_status=""

  total_url_probes=$((total_url_probes + 1))
  url_error_file="$tmp_root/${country}_url.err"
  probe_country_url "$country" "$url_error_file"
  url_probe_status="$URL_PROBE_STATUS"

  case "$url_probe_status" in
  ok) ;;
  notfound)
    should_run_search=0
    append_note "url-notfound-skip-search"
    append_note "$URL_PROBE_NOTE"
    ;;
  url_error)
    append_note "url-probe-error"
    append_note "$URL_PROBE_NOTE"
    ;;
  *)
    append_note "url-probe-unknown"
    ;;
  esac

  if [[ "$country_lower" == "us" ]]; then
    should_run_search=0
    append_note "forced-global-skip-search"
  fi

  if [[ "$should_run_search" -eq 1 ]]; then
    query_index=0
    for query in "${QUERIES[@]}"; do
      query_index=$((query_index + 1))
      total_requests=$((total_requests + 1))

      output_json="$tmp_root/${country}_${query_index}.json"
      error_file="$tmp_root/${country}_${query_index}.err"
      probe_query "$brave_cli" "$country" "$query" "$output_json" "$error_file"

      case "$RESULT_STATUS" in
      hit)
        hit_count=$((hit_count + 1))
        if [[ "$RESULT_FALLBACK_USED" -eq 1 ]]; then
          country_param_fallback_count=$((country_param_fallback_count + 1))
          total_country_param_fallbacks=$((total_country_param_fallbacks + 1))
        fi
        ;;
      no_results)
        no_results_count=$((no_results_count + 1))
        if [[ "$RESULT_FALLBACK_USED" -eq 1 ]]; then
          country_param_fallback_count=$((country_param_fallback_count + 1))
          total_country_param_fallbacks=$((total_country_param_fallbacks + 1))
        fi
        ;;
      rate_limited)
        rate_limited_count=$((rate_limited_count + 1))
        last_note="$RESULT_NOTE"
        if [[ "$RESULT_FALLBACK_USED" -eq 1 ]]; then
          country_param_fallback_count=$((country_param_fallback_count + 1))
          total_country_param_fallbacks=$((total_country_param_fallbacks + 1))
        fi
        ;;
      api_error)
        api_error_count=$((api_error_count + 1))
        last_note="$RESULT_NOTE"
        if [[ "$RESULT_FALLBACK_USED" -eq 1 ]]; then
          country_param_fallback_count=$((country_param_fallback_count + 1))
          total_country_param_fallbacks=$((total_country_param_fallbacks + 1))
        fi
        ;;
      *)
        api_error_count=$((api_error_count + 1))
        last_note="unexpected probe status"
        ;;
      esac

      if [[ "$delay_ms" -gt 0 ]]; then
        sleep "$delay_seconds"
      fi
    done
  else
    skipped_search_countries=$((skipped_search_countries + 1))
  fi

  successful_calls=$((hit_count + no_results_count))
  success_percent=0
  success_percent_text="n/a"
  if ((successful_calls > 0)); then
    success_percent=$((hit_count * 100 / successful_calls))
    success_percent_text="${success_percent}%"
  fi

  if [[ "$country_lower" == "us" || "$url_probe_status" == "notfound" ]]; then
    :
  elif ((successful_calls < min_success_calls)); then
    append_note "insufficient-samples(${successful_calls})"
  elif ((success_percent >= threshold_percent)); then
    suggested="yes"
    printf '%s\n' "$country_lower" >>"$suggested_file"
  fi

  if ((rate_limited_count > 0)); then
    append_note "rate-limited(${rate_limited_count})"
  fi

  if ((api_error_count > 0)); then
    append_note "api-error(${api_error_count})"
  fi

  if ((country_param_fallback_count > 0)); then
    append_note "fallback-no-country(${country_param_fallback_count})"
  fi

  if [[ -n "$last_note" ]]; then
    append_note "last=$(truncate_text "$last_note")"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$country" \
    "$url_probe_status" \
    "$hit_count" \
    "$no_results_count" \
    "$api_error_count" \
    "$rate_limited_count" \
    "$success_percent_text" \
    "$suggested" \
    "$notes" >>"$rows_file"
done

if [[ -s "$suggested_file" ]]; then
  sorted_file="$tmp_root/suggested.sorted"
  LC_ALL=C sort -u "$suggested_file" >"$sorted_file"
  mv "$sorted_file" "$suggested_file"
fi

{
  echo "# Netflix Country Probe Report"
  echo
  echo "- Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "- brave-cli: \`$brave_cli\`"
  echo "- Countries tested: ${#COUNTRIES[@]}"
  echo "- URL probes: $total_url_probes"
  echo "- Queries per country: ${#QUERIES[@]}"
  echo "- Search requests sent: $total_requests"
  echo "- Countries skipped before search: $skipped_search_countries"
  echo "- Country-parameter fallback calls: $total_country_param_fallbacks"
  echo "- Threshold: ${threshold_percent}%"
  echo "- Minimum successful API calls: $min_success_calls"
  echo "- Delay between requests: ${delay_ms}ms"
  echo
  echo "## Queries"
  local_query_index=0
  for query in "${QUERIES[@]}"; do
    local_query_index=$((local_query_index + 1))
    echo "- q${local_query_index}: \`$query\`"
  done
  echo
  echo "## Per-country result"
  echo
  echo "| Country | URL probe | Hits | No results | API errors | Rate-limited | Success % | Suggested | Notes |"
  echo "|---|---|---:|---:|---:|---:|---:|---|---|"
  while IFS=$'\t' read -r country url_probe_status hit_count no_results_count api_error_count rate_limited_count success_percent_text suggested notes; do
    echo "| $country | $url_probe_status | $hit_count | $no_results_count | $api_error_count | $rate_limited_count | $success_percent_text | $suggested | $notes |"
  done <"$rows_file"
  echo
  echo "## Suggested allowlist"
  echo
  if [[ -s "$suggested_file" ]]; then
    echo '```text'
    cat "$suggested_file"
    echo '```'
  else
    echo "_No countries met threshold._"
  fi
} >"$report_file"

echo "report: $report_file"
echo "rows: $rows_file"
echo "suggested allowlist: $suggested_file"

if [[ "$apply_mode" -eq 1 ]]; then
  if [[ ! -s "$suggested_file" ]]; then
    echo "warn: no suggested countries to apply; keep existing country_map.sh" >&2
    exit 0
  fi
  write_country_map "$suggested_file"
  echo "applied: $repo_root/workflows/netflix-search/scripts/country_map.sh"
fi
