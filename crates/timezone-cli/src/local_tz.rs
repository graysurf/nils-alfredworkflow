use std::{
    env, fs,
    path::Path,
    process::{Command, Stdio},
};

use chrono_tz::Tz;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LocalTimezoneSource {
    Override,
    TzEnv,
    IanaLookup,
    PlatformCommand,
    LocaltimeSymlink,
    UtcFallback,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalTimezone {
    pub id: String,
    pub tz: Tz,
    pub source: LocalTimezoneSource,
    pub trace: Vec<String>,
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct ProbeValues {
    pub override_tz: Option<String>,
    pub tz_env: Option<String>,
    pub iana_lookup: Option<String>,
    pub platform_lookup: Option<String>,
    pub localtime_lookup: Option<String>,
}

pub fn detect_local_timezone() -> LocalTimezone {
    detect_local_timezone_with(ProbeValues {
        override_tz: env::var("MULTI_TZ_LOCAL_OVERRIDE").ok(),
        tz_env: env::var("TZ").ok(),
        iana_lookup: iana_time_zone::get_timezone().ok(),
        platform_lookup: detect_platform_timezone(),
        localtime_lookup: detect_localtime_timezone(),
    })
}

pub fn detect_local_timezone_with(values: ProbeValues) -> LocalTimezone {
    let mut trace = Vec::new();

    let candidates = [
        (LocalTimezoneSource::Override, values.override_tz),
        (LocalTimezoneSource::TzEnv, values.tz_env),
        (LocalTimezoneSource::IanaLookup, values.iana_lookup),
        (LocalTimezoneSource::PlatformCommand, values.platform_lookup),
        (
            LocalTimezoneSource::LocaltimeSymlink,
            values.localtime_lookup,
        ),
        (LocalTimezoneSource::UtcFallback, Some("UTC".to_string())),
    ];

    for (source, candidate) in candidates {
        let Some(raw) = candidate else {
            trace.push(format!("{source:?}: missing"));
            continue;
        };

        let Some(normalized) = normalize_timezone_candidate(&raw) else {
            trace.push(format!("{source:?}: empty/unsupported '{raw}'"));
            continue;
        };

        match normalized.parse::<Tz>() {
            Ok(tz) => {
                trace.push(format!("{source:?}: selected '{normalized}'"));
                return LocalTimezone {
                    id: normalized,
                    tz,
                    source,
                    trace,
                };
            }
            Err(_) => {
                trace.push(format!("{source:?}: invalid '{normalized}'"));
            }
        }
    }

    LocalTimezone {
        id: "UTC".to_string(),
        tz: chrono_tz::UTC,
        source: LocalTimezoneSource::UtcFallback,
        trace,
    }
}

fn normalize_timezone_candidate(value: &str) -> Option<String> {
    let mut normalized = value.trim();
    if normalized.is_empty() {
        return None;
    }

    if let Some((prefix, rest)) = normalized.split_once(':')
        && prefix.trim().eq_ignore_ascii_case("Time Zone")
    {
        normalized = rest.trim();
    }

    if let Some(stripped) = normalized.strip_prefix(':') {
        normalized = stripped.trim();
    }

    normalized = extract_zoneinfo_suffix(normalized).unwrap_or(normalized);

    if normalized.is_empty() {
        None
    } else {
        Some(normalized.to_string())
    }
}

fn extract_zoneinfo_suffix(value: &str) -> Option<&str> {
    let marker = "zoneinfo/";
    value
        .find(marker)
        .map(|index| &value[index + marker.len()..])
        .map(str::trim)
        .filter(|suffix| !suffix.is_empty())
}

fn detect_platform_timezone() -> Option<String> {
    if cfg!(target_os = "macos") {
        return run_command("/usr/sbin/systemsetup", &["-gettimezone"]);
    }

    if cfg!(target_os = "linux") {
        return run_command("timedatectl", &["show", "-p", "Timezone", "--value"]);
    }

    None
}

fn run_command(program: &str, args: &[&str]) -> Option<String> {
    let output = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if text.is_empty() { None } else { Some(text) }
}

fn detect_localtime_timezone() -> Option<String> {
    let link = fs::read_link(Path::new("/etc/localtime")).ok()?;
    let path = link.to_string_lossy();
    extract_zoneinfo_suffix(&path).map(ToString::to_string)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn local_tz_fallback_chain_order() {
        let override_selected = detect_local_timezone_with(ProbeValues {
            override_tz: Some("Asia/Taipei".to_string()),
            tz_env: Some("America/New_York".to_string()),
            iana_lookup: Some("Europe/London".to_string()),
            platform_lookup: Some("Asia/Tokyo".to_string()),
            localtime_lookup: Some("UTC".to_string()),
        });
        assert_eq!(override_selected.id, "Asia/Taipei");
        assert_eq!(override_selected.source, LocalTimezoneSource::Override);

        let tz_env_selected = detect_local_timezone_with(ProbeValues {
            override_tz: Some("Invalid/Timezone".to_string()),
            tz_env: Some("America/New_York".to_string()),
            iana_lookup: Some("Europe/London".to_string()),
            platform_lookup: Some("Asia/Tokyo".to_string()),
            localtime_lookup: Some("UTC".to_string()),
        });
        assert_eq!(tz_env_selected.id, "America/New_York");
        assert_eq!(tz_env_selected.source, LocalTimezoneSource::TzEnv);

        let iana_selected = detect_local_timezone_with(ProbeValues {
            override_tz: Some("Invalid/Timezone".to_string()),
            tz_env: Some("Invalid/Timezone".to_string()),
            iana_lookup: Some("Europe/London".to_string()),
            platform_lookup: Some("Asia/Tokyo".to_string()),
            localtime_lookup: Some("UTC".to_string()),
        });
        assert_eq!(iana_selected.id, "Europe/London");
        assert_eq!(iana_selected.source, LocalTimezoneSource::IanaLookup);

        let platform_selected = detect_local_timezone_with(ProbeValues {
            override_tz: Some("Invalid/Timezone".to_string()),
            tz_env: Some("Invalid/Timezone".to_string()),
            iana_lookup: Some("Invalid/Timezone".to_string()),
            platform_lookup: Some("Time Zone: Asia/Tokyo".to_string()),
            localtime_lookup: Some("UTC".to_string()),
        });
        assert_eq!(platform_selected.id, "Asia/Tokyo");
        assert_eq!(
            platform_selected.source,
            LocalTimezoneSource::PlatformCommand
        );

        let localtime_selected = detect_local_timezone_with(ProbeValues {
            override_tz: Some("Invalid/Timezone".to_string()),
            tz_env: Some("Invalid/Timezone".to_string()),
            iana_lookup: Some("Invalid/Timezone".to_string()),
            platform_lookup: Some("Invalid/Timezone".to_string()),
            localtime_lookup: Some("/usr/share/zoneinfo/Europe/Berlin".to_string()),
        });
        assert_eq!(localtime_selected.id, "Europe/Berlin");
        assert_eq!(
            localtime_selected.source,
            LocalTimezoneSource::LocaltimeSymlink
        );
    }

    #[test]
    fn local_tz_terminal_utc_when_all_probes_fail() {
        let detected = detect_local_timezone_with(ProbeValues {
            override_tz: Some("Invalid/Timezone".to_string()),
            tz_env: Some("Invalid/Timezone".to_string()),
            iana_lookup: Some("Invalid/Timezone".to_string()),
            platform_lookup: Some("Invalid/Timezone".to_string()),
            localtime_lookup: Some("/not/a/zone".to_string()),
        });

        assert_eq!(detected.id, "UTC");
        assert_eq!(detected.source, LocalTimezoneSource::UtcFallback);
    }

    #[test]
    fn normalize_timezone_candidate_handles_systemsetup_output_and_zoneinfo_path() {
        assert_eq!(
            normalize_timezone_candidate("Time Zone: America/Los_Angeles"),
            Some("America/Los_Angeles".to_string())
        );
        assert_eq!(
            normalize_timezone_candidate("/usr/share/zoneinfo/Asia/Taipei"),
            Some("Asia/Taipei".to_string())
        );
        assert_eq!(
            normalize_timezone_candidate(":/usr/share/zoneinfo/Europe/London"),
            Some("Europe/London".to_string())
        );
    }
}
