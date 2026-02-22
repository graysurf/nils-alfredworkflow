# youtube-search Troubleshooting

Reference: [ALFRED_WORKFLOW_DEVELOPMENT.md](../../ALFRED_WORKFLOW_DEVELOPMENT.md)

## Quick operator checks

1. Confirm latest package was used:
   - `scripts/workflow-pack.sh --id youtube-search --install`
2. Confirm Alfred workflow variables are set:
   - `YOUTUBE_API_KEY` (required)
   - `YOUTUBE_MAX_RESULTS` (optional)
   - `YOUTUBE_REGION_CODE` (optional)
3. Confirm script-filter contract output is JSON:
   - `bash workflows/youtube-search/scripts/script_filter.sh "rust tutorial" | jq -e '.items | type == "array"'`
4. Confirm queue policy is synced:
   - `bash scripts/workflow-sync-script-filter-policy.sh --check --workflows youtube-search`

## Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| `YouTube API key is missing` | `YOUTUBE_API_KEY` is empty/missing. | Set a valid key in workflow config, then retry. |
| `Keep typing (2+ chars)` | Query is shorter than minimum length (`<2`). | Continue typing until at least 2 characters; no API request is sent before that. |
| `YouTube quota exceeded` | Daily quota exhausted (`quotaExceeded`, `dailyLimitExceeded`). | Wait for quota reset, reduce query frequency, and lower `YOUTUBE_MAX_RESULTS`. |
| `YouTube API unavailable` | Network issue, DNS/TLS issue, timeout, or upstream `5xx`. | Check local network/DNS, retry later, and verify YouTube API status. |
| `No videos found` | Query is too narrow or region filter excludes results. | Use broader keywords or clear/change `YOUTUBE_REGION_CODE`. |
| `"youtube-cli" Not Opened` / `Apple could not verify ...` | Downloaded/packaged `youtube-cli` carries `com.apple.quarantine`; Gatekeeper blocks execution. | Run `scripts/workflow-clear-quarantine.sh --id youtube-search`, then retry Alfred query. |

## Validation

- Re-run quick operator checks after any runtime/config change.
- Recommended workflow check: `bash workflows/youtube-search/tests/smoke.sh`

First-release support checklist:

- Track missing-key errors separately from API/network failures.
- If quota failures spike, lower default `YOUTUBE_MAX_RESULTS` and notify operators.
- Keep fallback item titles/subtitles stable so support can match screenshots quickly.
- Record a short incident note for each production-facing outage window.

## Rollback guidance

Use this when API failures are sustained or workflow usability drops sharply.

1. Stop rollout of new `youtube-search` artifacts (pause release/distribution link).
2. Revert YouTube search changeset(s), including:
   - `workflows/youtube-search/`
   - `crates/youtube-cli/`
   - workspace member changes in `Cargo.toml`
   - docs updates tied to rollout (`crates/youtube-cli/docs/workflow-contract.md` and rollout references)
3. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
4. Publish known-good artifact set and post operator notice:
   - Explain that `youtube-search` is temporarily disabled.
   - Provide ETA/workaround and support contact path.
