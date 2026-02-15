# IMDb Search Troubleshooting

Reference: [ALFRED_WORKFLOW_DEVELOPMENT.md](../../ALFRED_WORKFLOW_DEVELOPMENT.md)

## Quick operator checks

Run from repository root.

```bash
ls -l \
  workflows/imdb-search/scripts/script_filter.sh \
  workflows/imdb-search/scripts/action_open.sh

bash workflows/imdb-search/scripts/script_filter.sh "inception" | jq -e '.items | type == "array"'
bash workflows/imdb-search/scripts/action_open.sh "https://www.imdb.com/find/?q=inception&s=tt&ref_=fn_tt"
cat workflows/imdb-search/workflow.toml
```

## Common failures and actions

| Symptom | Likely cause | Action |
| --- | --- | --- |
| `Workflow helper missing` row in Alfred | Shared helper scripts were not packaged or repo path fallback is unavailable. | Re-run `scripts/workflow-pack.sh --id imdb-search` and reinstall artifact. |
| No IMDb suggestion rows, only one `Search IMDb: ...` row | IMDb suggestion endpoint is temporarily unavailable, network blocked, or runtime lacks `python3`/`curl`. | Retry later and verify `python3` + `curl` are available; fallback row still works for direct search. |
| `Enter a title keyword` row | Query is empty/whitespace only. | Type a keyword after `im` or `imdb`, then retry. |
| `Keep typing (2+ chars)` row | Query length is below minimum guard (`<2`). | Enter at least 2 characters before searching. |
| Browser opens wrong IMDb category | `IMDB_SEARCH_SECTION` is set unexpectedly. | Set `IMDB_SEARCH_SECTION=tt` (or another allowed code) in workflow variables. |

## Validation

```bash
bash workflows/imdb-search/tests/smoke.sh
scripts/workflow-test.sh --id imdb-search
scripts/workflow-pack.sh --id imdb-search
```

## Rollback guidance

1. Re-install previous known-good artifact from `dist/imdb-search/<version>/`.
2. Reset workflow variable `IMDB_SEARCH_SECTION` to `tt`.
3. If regression remains, roll back `workflows/imdb-search/` and rerun Validation commands.
