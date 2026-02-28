# Gmail native contract

## Scope

- Repo-owned native scope:
  - `search <query...>`
  - `get <messageId>`
  - `send`
  - `thread <...>`
- Non-goals in this phase:
  - `labels`, `batch`, `drafts`, and settings automation beyond listed commands

## Native semantics

- Primary transport uses generated Gmail client crates.
- `reqwest` fallback is allowed for generated-client gaps.
- `gmail send` uses native MIME composition and attachment type inference.
- Output/error envelopes stay native and repo-standard.

## Validation

- `rg -n "native|generated|fallback|gmail send" docs/reports/google-cli-native-capability-matrix.md`
- `cargo run -p google-cli -- gmail --help`
