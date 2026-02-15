#!/usr/bin/env bash
# Shared async-search Script Filter orchestration driver.
# This helper centralizes cache/coalesce/pending flow only.
# Each workflow keeps backend fetch details and error mapping locally.

sfsd_fetch_and_emit() {
  local query="$1"
  local cache_ttl_seconds="$2"
  local fetch_fn="$3"
  local error_fn="$4"

  local json_output err_msg
  local err_file="${TMPDIR:-/tmp}/script-filter-search-driver.err.$$.$RANDOM"
  if json_output="$("$fetch_fn" "$query" 2>"$err_file")"; then
    if [[ "$cache_ttl_seconds" -gt 0 ]]; then
      sfac_store_cache_result "$query" "ok" "$json_output" || true
    fi
    rm -f "$err_file"
    printf '%s\n' "$json_output"
    return 0
  fi

  err_msg="$(cat "$err_file")"
  rm -f "$err_file"
  if [[ "$cache_ttl_seconds" -gt 0 ]]; then
    sfac_store_cache_result "$query" "err" "$err_msg" || true
  fi
  "$error_fn" "$err_msg"
}

sfsd_run_search_flow() {
  local query="$1"
  local workflow_key="$2"
  local cache_fallback="$3"
  local cache_ttl_env="$4"
  local settle_env="$5"
  local rerun_env="$6"
  local pending_title="$7"
  local pending_subtitle="$8"
  local fetch_fn="$9"
  local error_fn="${10}"

  sfac_init_context "$workflow_key" "$cache_fallback"
  local cache_ttl_seconds settle_seconds rerun_seconds
  # Keep same-query cache disabled by default for live-typing Script Filters.
  # Current flow checks cache before settle-window coalescing; defaulting to 0
  # avoids stale prefix hits surfacing ahead of the final query.
  cache_ttl_seconds="$(sfac_resolve_positive_int_env "$cache_ttl_env" "0")"
  settle_seconds="$(sfac_resolve_non_negative_number_env "$settle_env" "2")"
  rerun_seconds="$(sfac_resolve_non_negative_number_env "$rerun_env" "0.4")"

  if sfac_load_cache_result "$query" "$cache_ttl_seconds"; then
    if [[ "$SFAC_CACHE_STATUS" == "ok" ]]; then
      printf '%s\n' "$SFAC_CACHE_PAYLOAD"
    else
      "$error_fn" "$SFAC_CACHE_PAYLOAD"
    fi
    return 0
  fi

  if [[ "$settle_seconds" == "0" || "$settle_seconds" == "0.0" ]]; then
    sfsd_fetch_and_emit "$query" "$cache_ttl_seconds" "$fetch_fn" "$error_fn"
    return 0
  fi

  if ! sfac_wait_for_final_query "$query" "$settle_seconds"; then
    sfac_emit_pending_item_json "$pending_title" "$pending_subtitle" "$rerun_seconds"
    return 0
  fi

  sfsd_fetch_and_emit "$query" "$cache_ttl_seconds" "$fetch_fn" "$error_fn"
  return 0
}
