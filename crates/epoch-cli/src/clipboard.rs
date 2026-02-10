use std::process::Command;

pub fn read_clipboard_text() -> Option<String> {
    #[cfg(target_os = "macos")]
    {
        run_capture("pbpaste", &[])
    }

    #[cfg(target_os = "linux")]
    {
        run_capture("wl-paste", &["--no-newline"])
            .or_else(|| run_capture("xclip", &["-o", "-selection", "clipboard"]))
            .or_else(|| run_capture("xsel", &["--clipboard", "--output"]))
    }

    #[cfg(target_os = "windows")]
    {
        run_capture(
            "powershell",
            &["-NoProfile", "-Command", "Get-Clipboard -Raw"],
        )
    }

    #[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
    {
        None
    }
}

fn run_capture(program: &str, args: &[&str]) -> Option<String> {
    let output = Command::new(program).args(args).output().ok()?;
    if !output.status.success() {
        return None;
    }

    let text = String::from_utf8(output.stdout).ok()?;
    normalize(text)
}

fn normalize(text: String) -> Option<String> {
    let trimmed = text.trim().to_string();
    if trimmed.is_empty() {
        return None;
    }

    Some(trimmed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_trims_and_rejects_empty_values() {
        assert_eq!(
            normalize("  hello world\n".to_string()),
            Some("hello world".to_string())
        );
        assert_eq!(normalize("  \n\t ".to_string()), None);
    }
}
