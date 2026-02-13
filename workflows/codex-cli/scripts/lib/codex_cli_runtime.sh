#!/usr/bin/env bash
# Shared pinned codex-cli runtime metadata for this workflow.

if [[ -z "${CODEX_CLI_PINNED_VERSION:-}" ]]; then
  CODEX_CLI_PINNED_VERSION="0.3.7"
fi

if [[ -z "${CODEX_CLI_PINNED_CRATE:-}" ]]; then
  CODEX_CLI_PINNED_CRATE="nils-codex-cli"
fi

codex_cli_runtime_install_hint() {
  printf '%s %s' "${CODEX_CLI_PINNED_CRATE}" "${CODEX_CLI_PINNED_VERSION}"
}
