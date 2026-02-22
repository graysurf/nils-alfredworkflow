# netflix-search Troubleshooting

Reference: [ALFRED_WORKFLOW_DEVELOPMENT.md](../../ALFRED_WORKFLOW_DEVELOPMENT.md)

## Quick operator checks

1. Confirm latest package was used:
   - `scripts/workflow-pack.sh --id netflix-search --install`
2. Confirm Alfred workflow variables are set:
   - `BRAVE_API_KEY` (required)
   - `BRAVE_MAX_RESULTS` (optional)
   - `BRAVE_SAFESEARCH` (optional)
   - `NETFLIX_CATALOG_REGION` (optional)
   - `BRAVE_COUNTRY` (optional)
3. Confirm script-filter output is JSON:
   - `bash workflows/netflix-search/scripts/script_filter.sh "dark" | jq -e '.items | type == "array"'`
4. Confirm queue policy is synced:
   - `bash scripts/workflow-sync-script-filter-policy.sh --check --workflows netflix-search`
5. (Optional) Probe country-path allowlist candidates:
   - `bash scripts/netflix-country-probe.sh`
   - Probe uses URL pre-check first and skips search for definite `NotFound` countries (and `US` forced-global).

Recommended variable intent:

- `NETFLIX_CATALOG_REGION=VN`: decide Netflix catalog/content region.
- `BRAVE_COUNTRY` is optional: decide Brave ranking/locale bias.

## Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| `Enter a search query` | Query is empty after trim. | Type keywords after `nf` or `netflix` and retry. |
| `Keep typing (2+ chars)` | Query is shorter than minimum length (`<2`). | Continue typing until at least 2 characters; no API request is sent before that. |
| `Brave API key is missing` | `BRAVE_API_KEY` is empty/missing. | Set a valid token in workflow config, then retry. |
| `Brave API rate limited` | Rate limit/quota exhausted (`429`/quota signals). | Wait and retry later, reduce query frequency, and lower `BRAVE_MAX_RESULTS`. |
| `Brave API unavailable` | Network/DNS/TLS issue, timeout, or upstream `5xx`. | Check local network/DNS, retry later, and verify Brave API status. |
| `Netflix Search error` with `422 ... validate request parameter` | Configured `BRAVE_COUNTRY` is not accepted by Brave API in current context. | Workflow retries once without `BRAVE_COUNTRY` automatically. If still unstable, set `BRAVE_COUNTRY` to empty or `US`, and keep catalog targeting with `NETFLIX_CATALOG_REGION`. |
| `No results found` | Query is too narrow or filters are restrictive. | Use broader keywords or adjust `NETFLIX_CATALOG_REGION` / `BRAVE_COUNTRY` / `BRAVE_SAFESEARCH`. |
| Mostly English Netflix titles | Current Netflix site scope maps to global title scope (`site:netflix.com/title`) or search index is English-heavy. | Set `NETFLIX_CATALOG_REGION=TW` (or another mapped country path). You can keep `BRAVE_COUNTRY` for separate Brave locale bias. |
| `"brave-cli" Not Opened` / `Apple could not verify ...` | Downloaded/packaged `brave-cli` carries `com.apple.quarantine`; Gatekeeper blocks execution. | Run `./workflow-clear-quarantine-standalone.sh --id netflix-search` (from release assets), then retry Alfred query. |

## Validation

- Re-run quick operator checks after any runtime/config change.
- Recommended workflow check: `bash workflows/netflix-search/tests/smoke.sh`

## Rollback guidance

Use this when Brave API failures are sustained or workflow usability drops sharply.

1. Stop rollout of new `netflix-search` artifacts (pause release/distribution link).
2. Revert Netflix-search changeset(s), including:
   - `workflows/netflix-search/`
   - docs updates tied to rollout
3. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
4. Publish known-good artifact set and post operator notice:
   - Explain that `netflix-search` is temporarily disabled.
   - Provide ETA/workaround and support contact path.
