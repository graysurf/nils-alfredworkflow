# CI Deletion Matrix (Sprint 1 / S1T3)

This matrix records stale CI workflow blocks removed in Sprint 1 tasks S1T3+S1T4 and the canonical path that now owns the behavior.

| Removed workflow block | Previous location | Removal rationale | Canonical replacement |
| --- | --- | --- | --- |
| Inline apt install (`sudo apt-get install -y git jq ripgrep shellcheck shfmt zip unzip`) | `.github/workflows/ci.yml` (`validate` job) | Duplicated workflow-level setup and drift-prone package list. | Runner defaults + canonical shared bootstrap via `scripts/ci/ci-bootstrap.sh` |
| Inline codex-cli install (`source scripts/lib/codex_cli_version.sh` + `cargo install ...`) | `.github/workflows/ci.yml` (`Package smoke` step) | Legacy compatibility branch duplicated runtime install at workflow level. | Canonical shared bootstrap: `scripts/ci/ci-bootstrap.sh --context ci --install-codex-cli` |
| Inline codex-cli install (`source scripts/lib/codex_cli_version.sh` + `cargo install ...`) | `.github/workflows/release.yml` (`Install codex-cli for packaging` step) | Same stale install branch as CI, maintained in multiple workflows. | Canonical shared bootstrap: `scripts/ci/ci-bootstrap.sh --context release --install-codex-cli` |
| Direct gate calls (`scripts/workflow-lint.sh`, `scripts/workflow-test.sh`, `scripts/workflow-pack.sh`, `scripts/publish-crates.sh`) | CI/release/publish workflow YAML | Bypasses shared gate routing introduced by Sprint 1 extraction. | Canonical shared gate dispatcher: `scripts/ci/ci-run-gates.sh <gate>` |

## Drift Guard

- `scripts/ci/ci-workflow-audit.sh --check` is the canonical drift guard for:
  - required shared entrypoints (`ci-bootstrap.sh` + `ci-run-gates.sh`) per workflow
  - forbidden stale inline setup/install blocks
  - forbidden direct workflow-level bypasses of shared gate routing
- `scripts/workflow-lint.sh` now invokes `bash scripts/ci/ci-workflow-audit.sh --check` so CI drift is blocked by default.

## Verification Commands

```bash
! rg -n "sudo apt-get install -y git jq ripgrep shellcheck shfmt zip unzip" .github/workflows/*.yml
! rg -n "cargo install \"\\$\\{CODEX_CLI_CRATE\\}\" --version \"\\$\\{CODEX_CLI_VERSION\\}\" --locked" .github/workflows/*.yml
bash scripts/ci/ci-workflow-audit.sh --check
```
