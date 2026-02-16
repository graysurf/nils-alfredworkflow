# Workflow Guide Migration Matrix

This matrix maps every `##` section in `docs/WORKFLOW_GUIDE.md` to its post-decommission owner.

| source section | owner | destination | decision | rationale |
| --- | --- | --- | --- | --- |
| Platform scope | Workspace dev guide | `DEVELOPMENT.md` | drop | Already canonically defined in development/runtime scope docs; avoid duplicate global copies. |
| Troubleshooting operating model | Global troubleshooting policy | `ALFRED_WORKFLOW_DEVELOPMENT.md` | move | Keep cross-workflow routing rules and troubleshooting entry-point policy in one global standard file. |
| Add a new workflow | Global workflow governance | `ALFRED_WORKFLOW_DEVELOPMENT.md` | move | Onboarding/scaffolding is cross-workflow policy and should remain globally discoverable. |
| Manifest contract | Global workflow governance | `ALFRED_WORKFLOW_DEVELOPMENT.md` | move | Manifest key contract is shared packaging governance, not workflow-local behavior. |
| README sync during packaging | Global packaging governance | `ALFRED_WORKFLOW_DEVELOPMENT.md` | move | `readme_source` packaging behavior applies repo-wide and must stay in a global owner doc. |
| Open Project workflow details | Workflow-local docs | `workflows/open-project/README.md` + `workflows/open-project/TROUBLESHOOTING.md` | drop | Existing workflow README/TROUBLESHOOTING already own env defaults, command flow, and operational checks. |
| YouTube Search workflow details | Workflow-local docs | `workflows/youtube-search/README.md` + `workflows/youtube-search/TROUBLESHOOTING.md` | drop | Existing workflow-local docs already cover variables, behavior, runtime checks, and rollback. |
| Google Search workflow details | Workflow-local docs | `workflows/google-search/README.md` + `workflows/google-search/TROUBLESHOOTING.md` | drop | Existing workflow-local docs already cover variables, two-stage/direct flow, checks, and rollback handling. |
| Netflix Search workflow details | Workflow-local docs | `workflows/netflix-search/README.md` + `workflows/netflix-search/TROUBLESHOOTING.md` | drop | Existing workflow-local docs already cover region mapping behavior, variables, checks, and rollback. |
| Wiki Search workflow details | Workflow-local docs | `workflows/wiki-search/README.md` + `workflows/wiki-search/TROUBLESHOOTING.md` | drop | Existing workflow-local docs already cover variables, command flow, error handling, and validation checks. |
| Bilibili Search workflow details | Workflow-local docs | `workflows/bilibili-search/README.md` + `workflows/bilibili-search/TROUBLESHOOTING.md` | drop | Existing workflow-local docs already cover config, flow, deterministic checks, and rollback. |
| Cambridge Dict workflow details | Workflow-local docs | `workflows/cambridge-dict/README.md` + `workflows/cambridge-dict/TROUBLESHOOTING.md` | drop | Existing workflow-local docs already cover config, two-stage flow, runtime bootstrap, tests, and rollback. |
| Bangumi Search workflow details | Workflow-local docs | `workflows/bangumi-search/README.md` + `workflows/bangumi-search/TROUBLESHOOTING.md` | drop | Existing workflow-local docs already cover API-first behavior, type grammar, checks, and rollback notes. |
| Epoch Converter workflow details | Workflow-local docs | `workflows/epoch-converter/README.md` + `workflows/epoch-converter/TROUBLESHOOTING.md` | drop | Existing workflow-local docs already cover env/flow/output rows/validation and troubleshooting. |
| Multi Timezone workflow details | Workflow-local docs | `workflows/multi-timezone/README.md` + `workflows/multi-timezone/TROUBLESHOOTING.md` | drop | Existing workflow-local docs already cover fallback chain, env vars, checks, and rollback guidance. |
| Quote Feed workflow details | Workflow-local docs | `workflows/quote-feed/README.md` + `workflows/quote-feed/TROUBLESHOOTING.md` | drop | Existing workflow-local docs already cover env vars, flow, validation, and runtime failure handling. |
| Memo Add workflow details | Workflow-local docs | `workflows/memo-add/README.md` + `workflows/memo-add/TROUBLESHOOTING.md` | drop | Existing workflow-local docs already cover keywords, query intents, CRUD checks, and troubleshooting. |
| Codex CLI workflow details | Workflow-local docs | `workflows/codex-cli/README.md` + `workflows/codex-cli/TROUBLESHOOTING.md` | drop | Workflow guide content is partially stale against current runtime docs; keep single owner in workflow-local docs. |

## Historical references policy

- Decision: leave historical references under `docs/plans/` and `docs/reports/` as-is for this migration.
- Rationale: they are archival artifacts, not active operator entry points; rewriting all historical references would expand scope without operational benefit.
