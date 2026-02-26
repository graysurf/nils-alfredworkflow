# steam-search Troubleshooting

Reference: [ALFRED_WORKFLOW_DEVELOPMENT.md](../../ALFRED_WORKFLOW_DEVELOPMENT.md)

## Quick operator checks

1. Confirm latest package was used:
   - `scripts/workflow-pack.sh --id steam-search --install`
2. Confirm Alfred workflow variables are set:
   - `STEAM_REGION` (optional, default `US`)
   - `STEAM_REGION_OPTIONS` (optional, default `US,JP,TW`)
   - `STEAM_MAX_RESULTS` (optional, default `10`)
3. Confirm script-filter output is JSON:
   - `bash workflows/steam-search/scripts/script_filter.sh "portal 2" | jq -e '.items | type == "array"'`
4. Confirm queue/shared-foundation policy is synced:
   - `bash scripts/workflow-sync-script-filter-policy.sh --check --workflows steam-search`

## Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| `Invalid Steam workflow config` | `STEAM_REGION` or `STEAM_REGION_OPTIONS` contains invalid region code, or `STEAM_MAX_RESULTS` is not numeric. | Fix values and retry. Region values must be two-letter country codes. |
| `Keep typing (2+ chars)` | Query is shorter than minimum length (`<2`). | Continue typing until at least 2 characters. |
| `Steam API unavailable` | Network/DNS/TLS issue, timeout, malformed upstream response, or upstream `5xx`. | Check local network/DNS, retry later, and verify Steam Store availability. |
| `No games found` | Query is too narrow for current region. | Use broader keywords or press a `Search in <REGION> region` row to requery in another region. |
| `"steam-cli" Not Opened` / `Apple could not verify ...` | Downloaded/packaged `steam-cli` has `com.apple.quarantine`; Gatekeeper blocks execution. | Run `./workflow-clear-quarantine-standalone.sh --id steam-search`, then retry Alfred query. |

## Validation

- Re-run quick operator checks after runtime/config updates.
- Recommended workflow check: `bash workflows/steam-search/tests/smoke.sh`

## Rollback guidance

Use this when Steam API failures are sustained or workflow usability drops sharply.

1. Stop rollout of new `steam-search` artifacts.
2. Revert `workflows/steam-search/` and `crates/steam-cli/` changeset(s).
3. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
4. Publish known-good artifacts and notify operators.
