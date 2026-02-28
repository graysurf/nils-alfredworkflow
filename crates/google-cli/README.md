# google-cli

Native Rust migration crate for scoped Google `auth`, `gmail`, and `drive` commands.

## Sprint 1 status

- Native dependency stack is pinned in `crates/google-cli/Cargo.toml`.
- Native module tree now exists under `src/auth`, `src/gmail`, `src/drive`, and `src/client`.
- Runtime execution is still wrapper-backed via `src/runtime.rs` while native implementations are delivered in later
  sprints.

## Command scope to preserve

## Auth

| Command | Sprint 1 contract stance |
| --- | --- |
| `auth credentials <...>` | Native-owned config/credential behavior (implementation follows in Sprint 2). |
| `auth add <email> [flags...]` | Native OAuth modes: `loopback`, `manual`, `remote`. |
| `auth list` | Native account inventory behavior. |
| `auth status` | Must resolve default account deterministically or return explicit ambiguity guidance. |
| `auth remove <email>` | Native token + metadata removal behavior. |
| `auth alias <...>` | Native alias metadata behavior. |
| `auth manage [flags...]` | No browser account-manager UI; terminal summary/help behavior only. |

## Gmail

| Command | Sprint 1 contract stance |
| --- | --- |
| `gmail search <query...> [flags...]` | Primary path is generated client; reqwest fallback allowed. |
| `gmail get <messageId> [flags...]` | Primary generated client path. |
| `gmail send [flags...]` | Native MIME path using `mail-builder` and `mime_guess`. |
| `gmail thread <...>` | Primary generated client path with fallback allowance. |

## Drive

| Command | Sprint 1 contract stance |
| --- | --- |
| `drive ls [flags...]` | Primary generated client path with fallback allowance. |
| `drive search <query...> [flags...]` | Primary generated client path with fallback allowance. |
| `drive get <fileId>` | Primary generated client path with fallback allowance. |
| `drive download <fileId> [flags...]` | Primary generated client path with fallback allowance. |
| `drive upload <localPath> [flags...]` | Primary generated client path with fallback allowance. |

## Environment variables

- `GOOGLE_CLI_GOG_BIN`: explicit override for the current wrapper-runtime binary while migration is in progress.

## Output contract

- Envelope stays repository-standard: `schema_version`, `command`, `ok`, and `result`/`error`.
- `--json` expects machine-readable output; `--plain` requests stable text output.

## Validation

- `cargo check -p google-cli --example native_probe`
- `cargo check -p google-cli`
- `cargo run -p google-cli -- auth --help`

## Documentation

- [`docs/README.md`](docs/README.md)
- [`docs/features/auth.md`](docs/features/auth.md)
- [`docs/features/gmail.md`](docs/features/gmail.md)
- [`docs/features/drive.md`](docs/features/drive.md)
- [`../../docs/specs/google-cli-native-contract.md`](../../docs/specs/google-cli-native-contract.md)
