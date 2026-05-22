# forge-cli Inbox Alfred Workflow Implementation Handoff

- Status: design confirmed for implementation planning
- Date: 2026-05-22
- Source: user discussion about turning the completed `forge-cli inbox` surface
  into an Alfred workflow, local `forge-cli inbox` help / dry-run output,
  `nils-cli` forge inbox source notes, and `nils-alfredworkflow` workflow
  development standards.
- Intended next step: create an implementation plan for a new
  `nils-alfredworkflow` workflow that consumes `forge-cli inbox --format json`.

## Purpose

Add an Alfred workflow that shows the user's personal GitHub / GitLab work
inbox without re-implementing provider queries in Alfred scripts.

The workflow is a UI consumer of the already-normalized `forge-cli inbox` JSON
contract. It should make common inbox slices fast to inspect:

- GitHub only, GitLab only, or GitHub + GitLab combined.
- PR / MR only, issue only, or PR / MR + issue together.

## Source Tags

- `[U1]` User wants three provider modes: `gh`, `glab`, and mixed `gh + glab`.
- `[U2]` User wants three item modes: issue, PR, and PR + issue together.
- `[U3]` User asked to settle the design this round through
  `discussion-to-implementation-doc` and `code-review-specialists`, not to
  implement the workflow yet.
- `[F1]` `nils-cli/docs/plans/forge-cli-inbox/forge-cli-inbox-discussion-source.md`
  defines `forge-cli inbox` as the source of truth for provider querying,
  normalization, ranking, JSON output, and partial provider failure behavior.
- `[F2]` Local `forge-cli inbox --help` exposes `status`, `list`, and `next`;
  `inbox list --help` exposes `--provider github|gitlab`, `--gitlab-host`,
  repeatable reason-style `--kind`, and `--limit`.
- `[F3]` Local `forge-cli --format json --dry-run inbox list --gitlab-host
  gitlab.gamania.com --limit 3` shows that omitting `--provider` queries both
  GitHub and GitLab, while `--provider github` and `--provider gitlab` narrow
  the provider set.
- `[F4]` `ALFRED_WORKFLOW_DEVELOPMENT.md` requires Script Filters to always
  return valid Alfred JSON and route workflow-specific behavior to
  workflow-local docs.
- `[F5]` `workflows/codex-cli` demonstrates an external-CLI Alfred workflow
  pattern: optional binary override, packaged/PATH fallback where applicable,
  JSON parsing in the Script Filter, and action scripts that receive compact
  action tokens.
- `[A1]` User reported live `forge-cli inbox status --gitlab-host
  gitlab.gamania.com` output on 2026-05-22: GitHub returned 4 items, GitLab
  returned 0 items, and the command completed successfully.
- `[I1]` Because current `forge-cli inbox --kind` filters reasons
  (`review`, `assigned`, `todo`, `authored`, `involved`) rather than item type,
  Alfred PR / issue filtering should be a display-layer filter in v1.

## Confirmed Facts

- `forge-cli inbox` already supports the provider-mode requirement:
  - no `--provider`: mixed GitHub + GitLab;
  - `--provider github`: GitHub only;
  - `--provider gitlab`: GitLab only. `[F2][F3]`
- `forge-cli inbox` already returns normalized item rows with provider,
  host, kind, reasons, repo, number, title, URL, author, and source according to
  the upstream source document. `[F1]`
- Current `forge-cli inbox --kind` is not an issue/PR filter. It is a reason
  filter and must not be overloaded in the Alfred workflow. `[F2][I1]`
- GitHub PR rows and issue rows are distinguishable by `source`:
  `github_search_prs` versus `github_search_issues`. `[F1]`
- GitLab MR rows and issue rows are distinguishable by `source`:
  `gitlab_merge_requests` versus `gitlab_issues`. GitLab todo rows use
  `gitlab_todos` and need URL-based target inference when the workflow wants to
  include them in PR / issue slices. `[F1][I1]`
- Alfred should not call `gh` or `glab` directly for this workflow. Provider
  access, auth reuse, host propagation, error redaction, dedupe, partial
  success, and bounded limits belong to `forge-cli`. `[F1]`
- Live CLI evidence shows the target `forge-cli inbox` command is usable with
  the intended company GitLab host; implementation should report concrete
  runtime issues only if new failures appear during workflow validation. `[A1]`

## Decisions

- Create a new workflow under `workflows/forge-inbox/`.
- Use one primary Script Filter keyword: `fi`.
- Keep `forge-cli inbox list --format json` as the primary data source for v1.
  Do not use `status` as the main render path because rows need item URLs.
- Do not add a `forge-cli` CLI change for item type filtering in this workflow
  slice. Implement PR / issue filtering in Alfred using normalized `source` and
  URL inference.
- Keep `forge-cli inbox --kind` available only for optional future
  reason-filter controls. Do not map Alfred `pr` or `issue` mode to `--kind`.
- Provider mode is translated to CLI flags:
  - `all`: no `--provider`;
  - `gh`: `--provider github`;
  - `glab`: `--provider gitlab`.
- GitLab modes require an explicit workflow GitLab host configuration when
  running outside a Git repository. If GitLab-only mode has no configured host,
  show a non-actionable configuration row and do not invoke `forge-cli`.
- Mixed mode without a configured GitLab host should degrade to GitHub-only
  results plus a non-actionable GitLab-host configuration warning row. It must
  not query GitLab through the CLI default host.
- The repository default should stay portable. Do not hardcode a private GitLab
  host in scripts. Expose `FORGE_INBOX_GITLAB_HOST`; local installations can set
  it to the company host.
- `all` item mode includes PR / MR rows, issue rows, and GitLab todo rows.
- `pr` item mode includes:
  - `github_search_prs`;
  - `gitlab_merge_requests`;
  - `gitlab_todos` only when the todo URL clearly targets a PR / MR, such as a
    GitHub `/pull/` URL or GitLab `/-/merge_requests/` URL.
- `issue` item mode includes:
  - `github_search_issues`;
  - `gitlab_issues`;
  - `gitlab_todos` only when the todo URL clearly targets an issue, such as a
    GitHub `/issues/` URL or GitLab `/-/issues/` URL.
- If a `gitlab_todos` target cannot be classified as PR / MR or issue, show it
  only in `all` mode.
- Pressing Enter opens the item's URL. Modifier actions may copy URL or copy a
  compact markdown reference, but mutation actions are out of scope.

## Scope

- Add workflow manifest, README, Script Filter, action script, tests, and local
  troubleshooting doc for `forge-inbox`.
- Resolve `forge-cli` through:
  1. `FORGE_CLI_BIN` when configured;
  2. `PATH` lookup for `forge-cli`.
- Omit `rust_binary` from `workflows/forge-inbox/workflow.toml` in v1. The
  workflow consumes an external `forge-cli` runtime instead of packaging one
  from this repository.
- Render Alfred rows from `forge-cli inbox list --format json`.
- Support provider mode overrides through query tokens and workflow env
  defaults.
- Support item mode overrides through query tokens and workflow env defaults.
- Support local text filtering after mode tokens by title, repo, number, author,
  provider, reason, and source.
- Render provider warnings from partial success as non-actionable rows without
  hiding successful provider results.
- Render clear non-actionable rows for missing `forge-cli`, missing GitLab host,
  invalid JSON, all-provider failure, or empty inbox results.
- Add fixture-backed smoke tests that stub `FORGE_CLI_BIN`.

## Non-Scope

- Do not implement provider queries with direct `gh`, `glab`, or REST calls in
  Alfred scripts.
- Do not add a new CLI contract such as `forge-cli inbox --item-type` in this
  workflow slice.
- Do not mutate PRs, MRs, issues, todos, reviewers, assignments, labels, or
  comments.
- Do not mark GitLab todos done.
- Do not build an Alfred JSON mode into `forge-cli`.
- Do not add persistent cross-provider cache in v1 unless a later plan proves
  live query latency is unacceptable.
- Do not hardcode local absolute paths, user-specific binary paths, tokens, or
  private hosts in tracked scripts.

## Query Model

The workflow accepts leading mode tokens, followed by optional free-text row
filter terms:

```text
fi [provider-mode] [item-mode] [text-filter]
```

Provider mode tokens:

- `all`, `both`, `mixed`: GitHub + GitLab.
- `gh`, `github`: GitHub only.
- `glab`, `gitlab`: GitLab only.

Item mode tokens:

- `all`, `work`: PR / MR + issue + GitLab todo.
- `pr`, `prs`, `mr`, `mrs`: PR / MR only.
- `issue`, `issues`: issue only.

Parsing rules:

- Tokens are order-insensitive while they are recognized mode tokens.
- Unrecognized remaining text becomes the row filter.
- If a mode is omitted, use workflow env defaults.
- Ambiguous `all` applies to the first unset mode, with provider first. For
  example, `fi all issue` means all providers + issue mode.

Example queries:

```text
fi
fi gh pr
fi glab issue
fi all all nils-cli
fi pr review
fi issue gamania
```

## CLI Invocation Model

The Script Filter builds `forge-cli` argv from the parsed provider mode:

```text
forge-cli --format json inbox list --limit <limit>
forge-cli --provider github --format json inbox list --limit <limit>
forge-cli --provider gitlab --format json inbox list --gitlab-host <host> --limit <limit>
```

For mixed mode with a configured GitLab host:

```text
forge-cli --format json inbox list --gitlab-host <host> --limit <limit>
```

For mixed mode without a configured GitLab host:

```text
forge-cli --provider github --format json inbox list --limit <limit>
```

GitLab-only mode without a configured GitLab host must not run `forge-cli`;
render `Set FORGE_INBOX_GITLAB_HOST` instead.

The workflow may add repeatable `--kind <reason>` only for a future
reason-filter feature. It must not use `--kind` for PR / issue selection.

## Workflow Configuration

Proposed `workflow.toml` env keys:

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `FORGE_CLI_BIN` | No | empty | Optional absolute path override for `forge-cli`. |
| `FORGE_INBOX_PROVIDER_MODE` | No | `all` | Default provider mode: `all`, `gh`, or `glab`. |
| `FORGE_INBOX_ITEM_MODE` | No | `all` | Default item mode: `all`, `pr`, or `issue`. |
| `FORGE_INBOX_GITLAB_HOST` | For GitLab modes | empty | GitLab host passed to `forge-cli inbox --gitlab-host`; empty mixed mode degrades to GitHub-only with a warning. |
| `FORGE_INBOX_LIMIT` | No | `30` | Per-provider, per-query-family CLI limit. |
| `FORGE_INBOX_OPEN_ACTION` | No | `open` | Reserved action behavior knob; v1 opens URLs. |

## Row Rendering

Each actionable item row:

- `title`: `<repo>#<number> <title>`
- `subtitle`: `<Provider> <Type> | <reasons> | updated <updated_at> | <author>`
- `arg`: compact JSON action token containing `url`, `provider`, `repo`,
  `number`, `title`, and `source`.
- `valid`: `true` only when a URL is present.

Recommended type labels:

- GitHub `github_search_prs`: `GitHub PR`
- GitHub `github_search_issues`: `GitHub Issue`
- GitLab `gitlab_merge_requests`: `GitLab MR`
- GitLab `gitlab_issues`: `GitLab Issue`
- GitLab `gitlab_todos`: `GitLab Todo`

Non-actionable rows:

- Missing binary: `forge-cli binary not found`.
- Missing GitLab host: `Set FORGE_INBOX_GITLAB_HOST`.
- Provider warning: `GitLab query failed; GitHub results are shown`.
- Empty result: `No inbox items`.
- Invalid JSON or failed CLI envelope: `forge-cli inbox failed`.

Warning parsing contract:

- Read `data.providers[]` first. Any selected provider with `ok=false` should
  render a provider warning row from `provider`, `host`, and `error.message`.
- Also tolerate top-level `warnings[]` as either strings or structured objects.
  Use them as supplemental warning text, not as the only source of provider
  status.

## Implementation Boundaries

- `nils-cli` / `forge-cli` owns provider query construction, GitHub / GitLab
  auth state, GitLab host propagation, JSON normalization, dedupe, bounded
  limits, ranking, and partial-failure semantics.
- `nils-alfredworkflow` owns mode parsing, Script Filter row rendering,
  item-type filtering, local text filtering, modifier action tokens, workflow
  docs, smoke fixtures, and packaging.
- The workflow must treat `forge-cli` JSON as an external contract. It should
  parse defensively and show clear fallback rows on schema or runtime errors.
- The workflow should not duplicate `forge-cli` ranking logic in v1. Row order
  should preserve CLI order after filtering unless a later plan defines a local
  UI sort.

## Requirements

- `fi` with default config renders mixed provider + all item rows when
  `FORGE_INBOX_GITLAB_HOST` is configured.
- `fi` with default config and no `FORGE_INBOX_GITLAB_HOST` renders GitHub-only
  results plus a GitLab-host configuration warning row.
- `fi gh pr` invokes GitHub-only CLI mode and shows only PR rows.
- `fi gh issue` invokes GitHub-only CLI mode and shows only issue rows.
- `fi glab pr` invokes GitLab-only CLI mode with `--gitlab-host` and shows only
  MR rows plus classifiable MR todos.
- `fi glab issue` invokes GitLab-only CLI mode with `--gitlab-host` and shows
  only issue rows plus classifiable issue todos.
- `fi all all` invokes mixed provider mode and shows PR / MR, issue, and todo
  rows when `FORGE_INBOX_GITLAB_HOST` is configured.
- `fi pr <text>` uses the default provider mode and locally filters PR / MR
  rows by free text.
- GitLab-only mode without `FORGE_INBOX_GITLAB_HOST` renders a config row and
  does not call `forge-cli`.
- Partial provider failures are visible as warning rows and do not suppress
  successful item rows.
- Empty successful inbox responses render a stable empty-state row.

## Acceptance Criteria

- Shell smoke tests cover all nine mode combinations:
  - `gh` x `pr`, `issue`, `all`;
  - `glab` x `pr`, `issue`, `all`;
  - `all` x `pr`, `issue`, `all`.
- Smoke tests assert the expected `forge-cli` argv for provider modes.
- Smoke tests assert that PR / issue filtering is based on normalized item
  `source` / URL and does not pass `--kind pr` or `--kind issue`.
- Smoke tests cover GitLab host missing behavior:
  - mixed mode falls back to GitHub-only argv and a config warning row;
  - GitLab-only mode emits a config row and no `forge-cli` invocation.
- Smoke tests cover provider warning parsing from both `data.providers[].error`
  and top-level `warnings[]`.
- Smoke tests cover partial success warnings and empty result rows.
- Action script tests verify Enter opens the URL action token and copy actions
  are newline-safe.
- Manifest checks assert `workflows/forge-inbox/workflow.toml` omits
  `rust_binary` in v1.
- `bash scripts/workflow-lint.sh --id forge-inbox` passes.
- `scripts/workflow-test.sh --id forge-inbox --skip-workspace-tests` passes for
  focused workflow validation.
- Before delivery, `scripts/local-pre-commit.sh` or
  `scripts/local-pre-commit.sh --mode ci` should be run according to release
  scope.

## Validation Plan

- Use fixture JSON envelopes from `forge-cli inbox list --format json`.
- Stub `FORGE_CLI_BIN` in `workflows/forge-inbox/tests/smoke.sh`.
- Add tests for mode parser normalization and row filtering.
- Add tests for malformed CLI JSON and non-zero CLI exits.
- Add tests for `gitlab_todos` URL classification:
  - GitLab `/-/merge_requests/` -> PR / MR mode;
  - GitLab `/-/issues/` -> issue mode;
  - unclassifiable target URL -> all mode only.
- Run repository docs checks after adding the discussion source:
  - `bash scripts/ci/markdownlint-audit.sh --strict`
  - `bash scripts/docs-placement-audit.sh --strict`
  - `git diff --check`

## Risks And Guardrails

- Risk: mapping `pr` / `issue` to `forge-cli --kind` would silently produce
  wrong results because `--kind` means reason, not item type. Guardrail: tests
  must assert no `--kind pr` or `--kind issue` argv appears.
- Risk: mixed mode without a GitLab host can query `gitlab.com` instead of the
  intended company host. Guardrail: require explicit `FORGE_INBOX_GITLAB_HOST`
  before invoking any GitLab-backed `forge-cli inbox` call; otherwise degrade
  mixed mode to GitHub-only plus a configuration warning.
- Risk: GitLab todos do not expose a normalized target type in the current
  contract. Guardrail: classify todos by URL only when obvious; otherwise show
  them in all mode only.
- Risk: live provider calls may be slow for Alfred. Guardrail: keep the default
  limit bounded and defer persistent cache until measured latency justifies it.
- Risk: workflow scripts could drift into provider wrappers. Guardrail: all
  provider calls go through `forge-cli`; Alfred only renders and filters JSON.

## Execution

Recommended plan: docs/plans/forge-cli-inbox-workflow-plan.md
Recommended execution state: docs/plans/forge-cli-inbox-workflow-execution-state.md

- Recommended plan type: standard implementation plan.
- Recommended first slice: scaffold workflow manifest, README, Script Filter,
  action script, and `FORGE_CLI_BIN` resolver.
- Recommended second slice: implement provider / item mode parser, CLI argv
  construction, JSON row rendering, and error rows with smoke fixtures.
- Recommended third slice: add action-token behavior, troubleshooting docs,
  packaging validation, and final workflow gates.

## Retention Intent

This is an execution source artifact for the Alfred workflow implementation.
Keep it while the workflow is planned and delivered. After implementation
closes, either delete this plan bundle as completed coordination material or
promote durable user-facing behavior into `workflows/forge-inbox/README.md` and
`workflows/forge-inbox/TROUBLESHOOTING.md`.

## Deferred Decisions

- Packaging a `forge-cli` binary with the workflow is deferred. v1 relies on
  `FORGE_CLI_BIN` / `PATH` because release packaging for `forge-cli` is owned by
  `nils-cli`.
- Whether to add a persistent cache is deferred until fixture and live smoke
  evidence shows Alfred latency needs it.

## Recommended Next Artifact

Create `docs/plans/forge-cli-inbox-workflow-plan.md` from this source and link
this document under that plan's `Read First` section.
