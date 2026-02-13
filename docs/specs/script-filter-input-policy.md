# Script Filter Input Policy (Shared)

## Defaults

- `queue_delay_seconds`: `1 second`
- `queue_delay_mode`: `0`
- `queue_delay_custom`: `1`
- `queuedelayimmediatelyinitially`: `false`
- `min_query_chars`: `2`

## Canonical Mapping

For the target workflows in this repository, the 1-second Script Filter delay policy is encoded as:

- `<key>queuedelaymode</key><integer>0</integer>`
- `<key>queuedelaycustom</key><integer>1</integer>`
- `<key>queuedelayimmediatelyinitially</key><false/>`

This means:

- first-character immediate execution is disabled;
- queue delay defaults to 1 second;
- backend/expensive branches should require at least 2 query characters.

## Evidence Notes

- Alfred Script Filter UI exposes queue delay and immediate-run behavior as separate controls; plist stores both controls via `queuedelay*` keys.
- Local Alfred-exported workflows under `~/Library/Application Support/Alfred/Alfred.alfredpreferences/workflows/*/info.plist` use the same key family (`queuedelaycustom`, `queuedelaymode`, `queuedelayimmediatelyinitially`) with integer delay values (`1`, `2`, `3`).
- Repository target templates currently use `queuedelaycustom=3` and `queuedelayimmediatelyinitially=true`; this policy standardizes them to 1-second delay + no immediate first run.

## Target Scope

The single source of truth for target workflow/object scope is:

- `docs/specs/script-filter-input-policy.json`

The shared helper runtime contract is:

- source: `scripts/lib/script_filter_query_policy.sh`
- package destination: `scripts/lib/script_filter_query_policy.sh`
