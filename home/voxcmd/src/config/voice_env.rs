//! voice.env reader (was voice-env.sh); `util voice-env`
//!
//! The file is read as data, never sourced: only lines of the shape KEY=NUMBER count (VOXCMD_WAKE_SENSITIVITY takes
//! one of its level names instead), so a stray line cannot run anything.
use crate::exit::CliError;
use std::path::{Path, PathBuf};

pub fn voice_env_file() -> PathBuf {
    if let Some(path) = std::env::var_os("VOXCMD_VOICE_ENV_FILE").filter(|path| !path.is_empty()) {
        return PathBuf::from(path);
    }
    let state_home = match std::env::var_os("XDG_STATE_HOME").filter(|dir| !dir.is_empty()) {
        Some(dir) => PathBuf::from(dir),
        None => PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state"),
    };
    state_home.join("voxcmd/voice.env")
}

/// The environment's value for `key`, else the file's last valid line for it. Environment values are not checked: they
/// are the user's explicit choice. None when neither has one, so the caller's default applies.
pub fn voice_env_value(key: &str, environment: Option<String>, file: &Path) -> Option<String> {
    if let Some(value) = environment.filter(|value| !value.is_empty()) {
        return Some(value);
    }
    let content = std::fs::read_to_string(file).ok()?;
    let prefix = format!("{key}=");
    let value = content
        .split('\n')
        .filter_map(|line| line.strip_prefix(prefix.as_str()))
        .rfind(|value| well_formed(key, value))?;
    acceptable(key, value).then(|| value.to_string())
}

/// The value's shape: a level name for the wake sensitivity, else digits with an optional fraction.
fn well_formed(key: &str, value: &str) -> bool {
    if key == "VOXCMD_WAKE_SENSITIVITY" {
        return !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_lowercase());
    }
    let (whole, fraction) = value
        .split_once('.')
        .map_or((value, None), |(whole, fraction)| (whole, Some(fraction)));
    let digits = |text: &str| !text.is_empty() && text.bytes().all(|byte| byte.is_ascii_digit());
    digits(whole) && fraction.is_none_or(digits)
}

/// The same limits Settings > Voice enforces, so a hand-edited value out of range falls back to the default.
fn acceptable(key: &str, value: &str) -> bool {
    match key {
        "VOXCMD_DUCK_MEDIA_VOLUME" => value.parse::<u64>().is_ok_and(|percent| percent <= 100),
        "VOXCMD_WAKE_SENSITIVITY" => matches!(value, "strict" | "balanced" | "relaxed"),
        "VOXCMD_WAKE_PAUSE_FOR_MEDIA" | "VOXCMD_WAKE_PAUSE_FOR_MIC" => matches!(value, "0" | "1"),
        _ => true,
    }
}

/// `voxcmd util voice-env <KEY>`: prints the value; exit 1 when unset.
pub fn run(key: &str) -> Result<String, CliError> {
    let environment = std::env::var(key).ok();
    voice_env_value(key, environment, &voice_env_file())
        .ok_or_else(|| CliError::failed("util voice-env", format!("{key} is not set")))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lookup(key: &str, environment: Option<&str>, file_content: &str) -> Option<String> {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("voice.env");
        std::fs::write(&file, file_content).unwrap();
        voice_env_value(key, environment.map(str::to_string), &file)
    }

    #[test]
    fn the_environment_wins_unchecked() {
        assert_eq!(
            lookup("VOXCMD_DUCK_MEDIA_VOLUME", Some("500"), "VOXCMD_DUCK_MEDIA_VOLUME=20\n").as_deref(),
            Some("500")
        );
    }

    #[test]
    fn the_last_valid_line_wins() {
        let content = "VOXCMD_DUCK_MEDIA_VOLUME=20\nVOXCMD_DUCK_MEDIA_VOLUME=abc\nVOXCMD_DUCK_MEDIA_VOLUME=35\n";
        assert_eq!(lookup("VOXCMD_DUCK_MEDIA_VOLUME", None, content).as_deref(), Some("35"));
    }

    #[test]
    fn out_of_range_values_fall_back_to_the_default() {
        assert_eq!(
            lookup("VOXCMD_DUCK_MEDIA_VOLUME", None, "VOXCMD_DUCK_MEDIA_VOLUME=101\n"),
            None
        );
        assert_eq!(
            lookup("VOXCMD_WAKE_PAUSE_FOR_MIC", None, "VOXCMD_WAKE_PAUSE_FOR_MIC=2\n"),
            None
        );
        assert_eq!(
            lookup("VOXCMD_WAKE_SENSITIVITY", None, "VOXCMD_WAKE_SENSITIVITY=loud\n"),
            None
        );
        assert_eq!(
            lookup("VOXCMD_WAKE_SENSITIVITY", None, "VOXCMD_WAKE_SENSITIVITY=strict\n").as_deref(),
            Some("strict")
        );
    }

    #[test]
    fn a_missing_file_is_unset() {
        assert_eq!(
            voice_env_value("VOXCMD_X", None, Path::new("/nonexistent/voice.env")),
            None
        );
    }
}
