# Auth native contract

## Scope

- Repo-owned native scope:
  - `credentials <...>`
  - `add <email>`
  - `list`
  - `status`
  - `remove <email>`
  - `alias <...>`
  - `manage`
- Non-goals in this phase:
  - browser account-manager UI rebuild
  - non-scoped Google domains

## Native semantics

- `auth add` supports `loopback`, `manual`, and `remote` OAuth modes.
- Native state tracking must eliminate wrapper-era state mismatch issues.
- Account resolution order is: explicit `--account` -> alias -> configured default account -> single stored account ->
  deterministic error.
- `auth status` without `--account` must never emit an empty account payload.
- `auth manage` is terminal-native only and does not open an external account manager page.

## Validation

- `rg -n "native|default account|auth status|auth manage|loopback|manual|remote" docs/specs/google-cli-native-contract.md`
- `cargo run -p google-cli -- auth --help`
