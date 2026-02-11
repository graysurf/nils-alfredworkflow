use std::fs;
use std::path::PathBuf;

use workflow_readme_cli::downgrade_markdown_tables;

#[test]
fn codex_fixture_removes_table_separators_and_keeps_screenshot_reference() {
    let source_path = PathBuf::from("tests/fixtures/codex-cli-readme.md");
    let expected_path = PathBuf::from("tests/fixtures/expected/codex-cli-readme-alfred.md");

    let source = fs::read_to_string(source_path).expect("read source fixture");
    let expected = fs::read_to_string(expected_path).expect("read expected fixture");
    let converted = downgrade_markdown_tables(&source);

    assert!(!converted.contains("|---|"));
    assert!(converted.contains("![Codex CLI workflow screenshot](./screenshot.png)"));
    assert_eq!(converted, expected);
}
