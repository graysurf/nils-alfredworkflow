# Drive native contract

## Scope

- Repo-owned native scope:
  - `ls`
  - `search <query...>`
  - `get <fileId>`
  - `download <fileId>`
  - `upload <localPath>`
- Non-goals in this phase:
  - `copy`, `mkdir`, `delete`, `move`, `rename`, permission/comment administration

## Native semantics

- Primary transport uses generated Drive client crates.
- `reqwest` fallback is allowed when generated-client coverage is insufficient.
- `drive upload` and `drive download` stay within repo-owned native output contracts.

## Validation

- `rg -n "native|generated|fallback|drive upload" docs/reports/google-cli-native-capability-matrix.md`
- `cargo run -p google-cli -- drive --help`
