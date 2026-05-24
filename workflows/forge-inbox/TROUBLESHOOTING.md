# Forge Inbox Troubleshooting

Reference: [ALFRED_WORKFLOW_DEVELOPMENT.md](../../ALFRED_WORKFLOW_DEVELOPMENT.md)

## Quick Operator Checks

Run from the repository root.

```bash
ls -l \
  workflows/forge-inbox/scripts/script_filter.sh \
  workflows/forge-inbox/scripts/action_open.sh

command -v forge-cli || true
forge-cli inbox status --gitlab-host gitlab.gamania.com

FORGE_INBOX_GITLAB_HOST=gitlab.gamania.com \
FORGE_INBOX_GITLAB_VPN=required \
FORGE_INBOX_GITLAB_VPN_CHECK=tcp:gitlab.gamania.com:443 \
FORGE_INBOX_GITLAB_VPN_CHECK_TIMEOUT=5s \
  bash workflows/forge-inbox/scripts/script_filter.sh "all all" |
  jq -e '.items | type == "array"'

rg -n "workflow_helper_loader|wfhl_source_helper" \
  workflows/forge-inbox/scripts/script_filter.sh \
  workflows/forge-inbox/scripts/action_open.sh
rg -n "workflow_smoke_helpers" workflows/forge-inbox/tests/smoke.sh
```

## Common Failures And Actions

| Symptom | Likely cause | Action |
| --- | --- | --- |
| `forge-cli binary not found` | `forge-cli` is not on `PATH` and `FORGE_CLI_BIN` is empty or not executable. | Install `forge-cli`, fix `PATH`, or set `FORGE_CLI_BIN` to an executable path. |
| `Set FORGE_INBOX_GITLAB_HOST` | GitLab mode is selected without an explicit host. | Set `FORGE_INBOX_GITLAB_HOST` to the target GitLab host. |
| GitLab host warning row is hidden | Mixed mode fallback warning rows are disabled by default. | Set `FORGE_INBOX_SHOW_CONFIG_WARNINGS=true` to show non-blocking config warnings. |
| GitLab row waits too long when VPN is down | GitLab readiness variables are empty, so the workflow reaches the backend timeout. | Set `FORGE_INBOX_GITLAB_VPN=required`, `FORGE_INBOX_GITLAB_VPN_CHECK=tcp:<host>:443`, and `FORGE_INBOX_GITLAB_VPN_CHECK_TIMEOUT=5s`. |
| `vpn_unavailable` / `vpn_probe_failed` | The configured readiness probe cannot reach the GitLab host or the command/openvpn check failed. | Connect VPN first, then rerun the same `forge-cli inbox list` command in Terminal. |
| `forge-cli inbox failed` | Provider auth, network, host, or CLI runtime failure. | Run the same `forge-cli inbox list` command in Terminal and fix provider auth or host config first. |
| `forge-cli returned invalid JSON` | The configured binary is not the expected runtime or emitted non-JSON output. | Check `FORGE_CLI_BIN`, update `forge-cli`, or remove the override to use `PATH`. |
| `jq is required` | The Script Filter cannot parse the CLI JSON envelope. | Install `jq` on the machine that runs Alfred. |
| Empty inbox row | The selected provider/item/text filters produced no rows. | Broaden the query, switch item mode to `all`, or run `forge-cli inbox status` to verify provider results. |

## Validation

```bash
bash workflows/forge-inbox/tests/smoke.sh
bash scripts/workflow-lint.sh --id forge-inbox
scripts/workflow-test.sh --id forge-inbox --skip-workspace-tests
bash scripts/docs-placement-audit.sh --strict
bash scripts/ci/markdownlint-audit.sh --strict
```

## Rollback Guidance

1. Re-install a previous known-good package from `dist/forge-inbox/` if one
   exists.
2. Clear or reset `FORGE_CLI_BIN`, `FORGE_INBOX_PROVIDER_MODE`,
   `FORGE_INBOX_ITEM_MODE`, `FORGE_INBOX_GITLAB_HOST`,
   GitLab VPN/readiness/cache variables, `FORGE_INBOX_SHOW_CONFIG_WARNINGS`,
   and `FORGE_INBOX_LIMIT` in Alfred workflow variables.
3. If a source regression remains, revert only `workflows/forge-inbox/` on a
   branch and rerun the validation commands above.
