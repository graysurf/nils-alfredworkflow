use anyhow::{Context, Result};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

pub fn render_template(template: &str, vars: &BTreeMap<String, String>) -> String {
    vars.iter().fold(template.to_owned(), |acc, (key, value)| {
        let token = format!("{{{{{key}}}}}");
        acc.replace(&token, value)
    })
}

pub fn render_template_file(
    template_path: impl AsRef<Path>,
    output_path: impl AsRef<Path>,
    vars: &BTreeMap<String, String>,
) -> Result<()> {
    let template_path = template_path.as_ref();
    let output_path = output_path.as_ref();

    let template = fs::read_to_string(template_path)
        .with_context(|| format!("failed to read template: {}", template_path.display()))?;
    let rendered = render_template(&template, vars);

    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create output parent: {}", parent.display()))?;
    }

    fs::write(output_path, rendered)
        .with_context(|| format!("failed to write output file: {}", output_path.display()))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn replaces_known_tokens() {
        let mut vars = BTreeMap::new();
        vars.insert("name".to_string(), "Open Project".to_string());

        let rendered = render_template("<name>{{name}}</name>", &vars);
        assert_eq!(rendered, "<name>Open Project</name>");
    }
}
