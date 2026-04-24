// Consolidated integration test target.
// Each former `tests/*.rs` is declared as a submodule here so the crate
// links one integration test binary instead of many. This keeps the
// dev-loop link phase O(crates) instead of O(test-files).

#[path = "integration/cli_contract.rs"]
mod cli_contract;
#[path = "integration/codex_readme_fixtures.rs"]
mod codex_readme_fixtures;
#[path = "integration/image_assets.rs"]
mod image_assets;
#[path = "integration/table_downgrade.rs"]
mod table_downgrade;
