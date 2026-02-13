# nils-alfred-core

Core Alfred Script Filter payload models shared by workflow crates.

## Public API Summary

- `Feedback`: top-level Script Filter payload (`items`) with `to_json()` serialization helper.
- `Item`: Script Filter item model with builder-style setters for optional fields.
- `ItemModifier`: modifier payload (`mods`) model with builder-style setters.
- `ItemIcon`: icon payload model (`path`, optional `type`).

## Documentation

- `docs/README.md`

## Validation

- `cargo check -p nils-alfred-core`
- `cargo test -p nils-alfred-core`
