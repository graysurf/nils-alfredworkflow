use workflow_readme_cli::downgrade_markdown_tables;

#[test]
fn converts_markdown_table_to_deterministic_bullets() {
    let input = r#"# Example

| Variable | Required | Default |
|---|---|---|
| `CODEX_CLI_BIN` | No | empty |
| `CODEX_SAVE_CONFIRM` | No | `1` |
"#;

    let output = downgrade_markdown_tables(input);

    assert!(
        !output.contains("|---|"),
        "table separator should be removed"
    );
    assert!(output.contains("- Variable: `CODEX_CLI_BIN`; Required: No; Default: empty"));
    assert!(output.contains("- Variable: `CODEX_SAVE_CONFIRM`; Required: No; Default: `1`"));
}
