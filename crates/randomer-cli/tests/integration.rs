// Consolidated integration test target.
// Each former `tests/*.rs` is declared as a submodule here so the crate
// links one integration test binary instead of many. This keeps the
// dev-loop link phase O(crates) instead of O(test-files).

// Tests stay terse with `unwrap()` / `expect()`; production paths run
// under `#![deny(clippy::unwrap_used, clippy::expect_used)]`.
#![allow(clippy::unwrap_used, clippy::expect_used)]

#[path = "integration/cli_contract.rs"]
mod cli_contract;
