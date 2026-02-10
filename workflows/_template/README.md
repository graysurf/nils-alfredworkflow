# Workflow Template - Alfred Workflow Scaffold

Starter scaffold for creating a new workflow in this monorepo.

## Features

- Includes baseline workflow files: `workflow.toml`, `src/info.plist.template`, `scripts/`, and `tests/smoke.sh`.
- Keeps script-filter and action script structure aligned with existing workflows.
- Uses the same packaging conventions expected by `scripts/workflow-pack.sh`.

## Template Parameters

Update these fields before packaging a new workflow:

| Field | File | Description |
|---|---|---|
| `id` | `workflow.toml` | Workflow id slug (used for packaging path and identifiers). |
| `name` | `workflow.toml` | Human-readable workflow name shown in Alfred. |
| `bundle_id` | `workflow.toml` | Unique Alfred bundle id (`com.example.<id>` style). |
| `script_filter` | `workflow.toml` | Script file name for script filter entrypoint. |
| `action` | `workflow.toml` | Script file name for action entrypoint. |
| `rust_binary` | `workflow.toml` | Binary name packaged into `bin/` for runtime scripts. |

## Example Configuration Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `EXAMPLE_VAR` | No | `example` | Demonstration variable placeholder. Replace with real workflow settings. |

## Usage Notes

- This folder is a template, not a final end-user workflow.
- After scaffolding, replace placeholder values (for example `__WORKFLOW_ID__`) and update scripts/tests accordingly.

