# Codex CLI - Alfred Workflow

Run core `nils-codex-cli@0.3.2` operations from Alfred.

## Screenshot

![Codex CLI workflow screenshot](./screenshot.png)

## Configuration

- Variable: `CODEX_CLI_BIN`; Required: No; Default: empty; Description: Optional absolute path override for `codex-cli`.
- Variable: `CODEX_SAVE_CONFIRM`; Required: No; Default: `1`; Description: Require confirmation for `save` without `--yes` (`0` disables).

## Keywords

- Keyword: `cx`; Behavior: Command palette for auth/save/diag actions.
- Keyword: `cxda`; Behavior: Alias of `cx diag all-json ...` (all-accounts JSON view).
