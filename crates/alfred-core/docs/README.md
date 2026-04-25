# nils-alfred-core docs

Crate-local documentation index for `nils-alfred-core`.

## Intended Readers

- Maintainers integrating Alfred Script Filter payload generation in workflow crates.
- Contributors changing payload schema mapping or serialization behavior.

## Canonical Documents

- `../README.md`: crate purpose, public API summary, and validation commands.

## Why no `workflow-contract.md`

`nils-alfred-core` is a library-only crate — it has no binary, no clap subcommand surface, and no JSON
service envelope of its own. There is no per-CLI contract to freeze; the public API documented in
[`../README.md`](../README.md) is the canonical surface and is exercised through `cargo test -p
nils-alfred-core`. A dedicated `workflow-contract.md` would only restate the README without adding
information.
