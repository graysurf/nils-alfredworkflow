# nils-alfred-plist docs

Crate-local documentation index for `nils-alfred-plist`.

## Intended Readers

- Maintainers generating workflow `info.plist` files from checked-in templates.
- Contributors updating template token rendering or file output behavior.

## Canonical Documents

- `../README.md`: crate purpose, public API summary, and validation commands.

## Why no `workflow-contract.md`

`nils-alfred-plist` is a library-only crate — it has no binary, no clap subcommand surface, and no JSON
service envelope of its own. There is no per-CLI contract to freeze; the public API documented in
[`../README.md`](../README.md) is the canonical surface and is exercised through `cargo test -p
nils-alfred-plist`. A dedicated `workflow-contract.md` would only restate the README without adding
information.
