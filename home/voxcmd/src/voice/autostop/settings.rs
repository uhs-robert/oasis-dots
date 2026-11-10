//! auto-stop's settings: `autostop.conf`, then `VOXCMD_AUTOSTOP_*` over it (the voxcmd README's "Auto-stop")
use crate::paths;
use std::collections::BTreeMap;

/// Every setting and its default, in the order of the README. An unknown name in the file is an error.
const DEFAULTS: [(&str, &str); 13] = [
    ("enabled", "true"),
    ("silence_secs", "1.0"),
    ("min_speech_secs", "0.25"),
    ("no_speech_secs", "6"),
    ("threshold_db", "auto"),
    ("margin_db", "12"),
    // 0 is no limit. Type mode sets it just under voxtype's max_duration_secs, so its own cut is never the one that ends it.
    ("max_secs", "0"),
    // A file the auto threshold is written to, as the quiet room sets it, for a later detector that starts mid-speech and
    // cannot measure the room itself (voxcmd's chain after a type-mode ending). Set by voxcmd, not for autostop.conf.
    ("threshold_file", ""),
    // Type mode's endings (pause checks): the recording "<frame_id>:<owner>:<owner_start>" whose pauses are checked, set
    // by voxcmd, and the voxcmd that checks them. Unset, no pause is checked.
    ("pause_check_recording", ""),
    ("pause_check_voxcmd", ""),
    ("pause_check_secs", "0.6"),
    ("pause_check_clip_secs", "3"),
    // How long a pause verdict waits for the checks still running or waiting, so an ending said just before the pause,
    // a cancel above all, decides how the recording ends; bounded, so a hung check never keeps the recording open.
    ("pause_check_wait_secs", "8"),
];

pub struct Settings(BTreeMap<String, String>);

impl Settings {
    /// `name = value` lines from the file (`#` starts a comment), then the environment's overrides.
    pub fn load() -> Result<Self, String> {
        Self::from_sources(
            std::fs::read_to_string(paths::config_dir().join("autostop.conf"))
                .ok()
                .as_deref(),
            |name| std::env::var(name).ok(),
        )
    }

    fn from_sources(file: Option<&str>, env: impl Fn(&str) -> Option<String>) -> Result<Self, String> {
        let mut values: BTreeMap<String, String> = DEFAULTS
            .iter()
            .map(|(name, value)| ((*name).to_string(), (*value).to_string()))
            .collect();
        for line in file.unwrap_or_default().lines() {
            let line = line.split('#').next().unwrap_or_default().trim();
            if let Some((name, value)) = line.split_once('=') {
                values.insert(name.trim().to_string(), value.trim().to_string());
            }
        }
        for (name, _) in DEFAULTS.iter() {
            let env_name = if *name == "enabled" {
                "VOXCMD_AUTOSTOP".to_string()
            } else {
                format!("VOXCMD_AUTOSTOP_{}", name.to_uppercase())
            };
            if let Some(value) = env(&env_name).filter(|value| !value.is_empty()) {
                values.insert((*name).to_string(), value);
            }
        }
        let unknown: Vec<&str> = values
            .keys()
            .map(String::as_str)
            .filter(|name| !DEFAULTS.iter().any(|(known, _)| known == name))
            .collect();
        if !unknown.is_empty() {
            return Err(format!("unknown setting: {}", unknown.join(", ")));
        }
        Ok(Self(values))
    }

    #[cfg(test)]
    pub fn from_test_env(vars: Vec<(String, String)>) -> Self {
        Self::from_sources(None, |name| {
            vars.iter().find(|(key, _)| key == name).map(|(_, value)| value.clone())
        })
        .expect("known settings")
    }

    pub fn text(&self, name: &str) -> &str {
        &self.0[name]
    }

    /// A number setting; a bad one is a settings error, as Python's `float()` was.
    pub fn number(&self, name: &str) -> Result<f64, String> {
        let text = self.text(name);
        text.trim()
            .parse::<f64>()
            .map_err(|_| format!("could not convert string to float: '{text}'"))
    }

    pub fn is_enabled(&self) -> bool {
        !["0", "false", "no", "off"].contains(&self.text("enabled").to_lowercase().as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn load(file: Option<&str>, env: &[(&str, &str)]) -> Result<Settings, String> {
        Settings::from_sources(file, |name| {
            env.iter()
                .find(|(key, _)| *key == name)
                .map(|(_, value)| (*value).to_string())
        })
    }

    #[test]
    fn the_file_overrides_the_defaults_and_the_environment_the_file() {
        let settings = load(
            Some("silence_secs = 2 # a longer pause\n\n# comment\nno_speech_secs=9\n"),
            &[
                ("VOXCMD_AUTOSTOP_NO_SPEECH_SECS", "4"),
                ("VOXCMD_AUTOSTOP_MAX_SECS", ""),
            ],
        )
        .unwrap();
        assert_eq!(settings.text("silence_secs"), "2");
        assert_eq!(settings.text("no_speech_secs"), "4");
        assert_eq!(settings.text("max_secs"), "0", "an empty variable is unset");
    }

    #[test]
    fn the_enabled_switch_has_the_short_variable_name_and_reads_off_words() {
        for off in ["0", "false", "No", "OFF"] {
            assert!(!load(None, &[("VOXCMD_AUTOSTOP", off)]).unwrap().is_enabled(), "{off}");
        }
        assert!(load(None, &[("VOXCMD_AUTOSTOP", "yes")]).unwrap().is_enabled());
    }

    #[test]
    fn an_unknown_name_in_the_file_is_an_error_naming_it() {
        assert_eq!(
            load(Some("bogus = 1\nalso = 2"), &[]).err().unwrap(),
            "unknown setting: also, bogus"
        );
    }

    #[test]
    fn a_bad_number_says_so() {
        let settings = load(None, &[("VOXCMD_AUTOSTOP_SILENCE_SECS", "soon")]).unwrap();
        assert!(settings.number("silence_secs").unwrap_err().contains("'soon'"));
    }
}
