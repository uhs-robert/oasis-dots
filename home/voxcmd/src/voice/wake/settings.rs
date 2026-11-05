//! the listener's settings: the environment, else Settings > Voice's `voice.env` (read as data by `config::voice_env`)
//!
//! A bad environment value refuses to start (exit 78). A bad file value falls back to the default, because a unit that
//! exits on a hand-edited file would crash-loop. `voice_env_value` already drops a bad file value, so only the
//! environment is checked here.
use super::decider::{DEFAULT_COOLDOWN_SECS, Level};
use crate::config::voice_env::{voice_env_file, voice_env_value};
use std::path::{Path, PathBuf};

const DEFAULT_PAUSE_FOR_MEDIA: bool = false;
const DEFAULT_PAUSE_FOR_MIC: bool = true;

#[derive(Debug, PartialEq)]
pub struct Settings {
    pub threshold: f32,
    pub frames: u32,
    pub pause_for_media: bool,
    pub pause_for_mic: bool,
    pub cooldown_secs: f64,
    pub model_dir: PathBuf,
}

impl Settings {
    /// From the process environment and the saved file.
    pub fn load() -> Result<Self, String> {
        Self::from_lookup(|key| std::env::var(key).ok(), &voice_env_file())
    }

    pub fn from_lookup(environment: impl Fn(&str) -> Option<String>, file: &Path) -> Result<Self, String> {
        let env = |key: &str| environment(key).filter(|value| !value.is_empty());
        let level = match env("VOXCMD_WAKE_SENSITIVITY") {
            Some(name) => {
                Level::parse(&name).ok_or_else(|| format!("VOXCMD_WAKE_SENSITIVITY must be {}", Level::NAMES))?
            }
            None => voice_env_value("VOXCMD_WAKE_SENSITIVITY", None, file)
                .and_then(|name| Level::parse(&name))
                .unwrap_or(Level::Strict),
        };
        let (level_threshold, level_frames) = level.threshold_and_frames();
        let threshold = match env("VOXCMD_WAKE_THRESHOLD") {
            Some(text) => text
                .parse::<f32>()
                .map_err(|_| bad_number("VOXCMD_WAKE_THRESHOLD", &text))?,
            None => level_threshold,
        };
        let frames = match env("VOXCMD_WAKE_FRAMES") {
            Some(text) => text
                .parse::<u32>()
                .map_err(|_| bad_number("VOXCMD_WAKE_FRAMES", &text))?,
            None => level_frames,
        };
        let cooldown_secs = match env("VOXCMD_WAKE_COOLDOWN_SECS") {
            Some(text) => text
                .parse::<f64>()
                .map_err(|_| bad_number("VOXCMD_WAKE_COOLDOWN_SECS", &text))?,
            None => DEFAULT_COOLDOWN_SECS,
        };
        if !(threshold > 0.0 && threshold <= 1.0) || frames < 1 || !(cooldown_secs >= 0.0 && cooldown_secs.is_finite())
        {
            return Err(
                "VOXCMD_WAKE_THRESHOLD must be in (0, 1], _FRAMES at least 1, _COOLDOWN_SECS not negative".into(),
            );
        }
        Ok(Self {
            threshold,
            frames,
            pause_for_media: flag(&env, file, "VOXCMD_WAKE_PAUSE_FOR_MEDIA", DEFAULT_PAUSE_FOR_MEDIA)?,
            pause_for_mic: flag(&env, file, "VOXCMD_WAKE_PAUSE_FOR_MIC", DEFAULT_PAUSE_FOR_MIC)?,
            cooldown_secs,
            model_dir: env("VOXCMD_WAKE_MODEL_DIR")
                .map(PathBuf::from)
                .unwrap_or_else(|| default_model_dir(&env)),
        })
    }
}

fn bad_number(key: &str, text: &str) -> String {
    format!("{key} is not a number: {text:?}")
}

/// 0 or 1 only. An environment value that is neither refuses to start; a file's falls back to the default.
fn flag(env: &dyn Fn(&str) -> Option<String>, file: &Path, key: &str, default: bool) -> Result<bool, String> {
    match env(key) {
        Some(value) if value == "0" || value == "1" => Ok(value == "1"),
        Some(_) => Err(format!("{key} must be 0 or 1")),
        None => Ok(voice_env_value(key, None, file).map_or(default, |value| value == "1")),
    }
}

/// Not `~/.local/share/voxcmd`, which stow folds into the repo.
fn default_model_dir(env: &dyn Fn(&str) -> Option<String>) -> PathBuf {
    let data_home = env("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env("HOME").unwrap_or_default()).join(".local/share"));
    data_home.join("voxcmd-wake/models")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn settings(environment: &[(&str, &str)], file_content: &str) -> Result<Settings, String> {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("voice.env");
        std::fs::write(&file, file_content).unwrap();
        let map: HashMap<String, String> = environment
            .iter()
            .map(|(key, value)| (key.to_string(), value.to_string()))
            .collect();
        Settings::from_lookup(|key| map.get(key).cloned(), &file)
    }

    #[test]
    fn the_defaults_are_the_strict_level() {
        let settings = settings(&[("HOME", "/home/x")], "").unwrap();
        assert_eq!((settings.threshold, settings.frames), (0.8, 3));
        assert_eq!(settings.cooldown_secs, 3.0);
        assert!(!settings.pause_for_media && settings.pause_for_mic);
        assert_eq!(
            settings.model_dir,
            PathBuf::from("/home/x/.local/share/voxcmd-wake/models")
        );
    }

    #[test]
    fn each_saved_level_maps_to_its_threshold_and_frames() {
        for (level, threshold) in [("strict", 0.8), ("balanced", 0.7), ("relaxed", 0.6)] {
            let settings = settings(&[], &format!("VOXCMD_WAKE_SENSITIVITY={level}\n")).unwrap();
            assert_eq!((settings.threshold, settings.frames), (threshold, 3), "{level}");
        }
    }

    #[test]
    fn the_environment_level_beats_the_file_and_raw_values_beat_the_level() {
        let file = "VOXCMD_WAKE_SENSITIVITY=relaxed\n";
        assert_eq!(
            settings(&[("VOXCMD_WAKE_SENSITIVITY", "balanced")], file)
                .unwrap()
                .threshold,
            0.7
        );
        let raw = settings(&[("VOXCMD_WAKE_THRESHOLD", "0.9"), ("VOXCMD_WAKE_FRAMES", "5")], file).unwrap();
        assert_eq!((raw.threshold, raw.frames), (0.9, 5));
    }

    #[test]
    fn a_bad_file_value_falls_back_and_a_bad_environment_value_refuses() {
        assert_eq!(settings(&[], "VOXCMD_WAKE_SENSITIVITY=loud\n").unwrap().threshold, 0.8);
        assert!(settings(&[("VOXCMD_WAKE_SENSITIVITY", "loud")], "").is_err());
        assert!(settings(&[], "VOXCMD_WAKE_PAUSE_FOR_MIC=2\n").unwrap().pause_for_mic);
        assert!(settings(&[("VOXCMD_WAKE_PAUSE_FOR_MIC", "2")], "").is_err());
        assert!(settings(&[("VOXCMD_WAKE_PAUSE_FOR_MEDIA", "yes")], "").is_err());
    }

    #[test]
    fn the_file_flips_both_flags_and_the_environment_beats_it() {
        let file = "VOXCMD_WAKE_PAUSE_FOR_MEDIA=1\nVOXCMD_WAKE_PAUSE_FOR_MIC=0\n";
        let from_file = settings(&[], file).unwrap();
        assert!(from_file.pause_for_media && !from_file.pause_for_mic);
        let overridden = settings(&[("VOXCMD_WAKE_PAUSE_FOR_MEDIA", "0")], file).unwrap();
        assert!(!overridden.pause_for_media);
    }

    #[test]
    fn out_of_range_or_unreadable_numbers_refuse() {
        for (key, value) in [
            ("VOXCMD_WAKE_THRESHOLD", "0"),
            ("VOXCMD_WAKE_THRESHOLD", "1.5"),
            ("VOXCMD_WAKE_THRESHOLD", "loud"),
            ("VOXCMD_WAKE_THRESHOLD", "NaN"),
            ("VOXCMD_WAKE_FRAMES", "0"),
            ("VOXCMD_WAKE_FRAMES", "2.5"),
            ("VOXCMD_WAKE_COOLDOWN_SECS", "-1"),
            ("VOXCMD_WAKE_COOLDOWN_SECS", "inf"),
        ] {
            assert!(settings(&[(key, value)], "").is_err(), "{key}={value}");
        }
        assert!(settings(&[("VOXCMD_WAKE_COOLDOWN_SECS", "0")], "").is_ok());
    }

    #[test]
    fn the_model_dir_follows_the_environment() {
        assert_eq!(
            settings(&[("XDG_DATA_HOME", "/data")], "").unwrap().model_dir,
            PathBuf::from("/data/voxcmd-wake/models")
        );
        assert_eq!(
            settings(&[("VOXCMD_WAKE_MODEL_DIR", "/m")], "").unwrap().model_dir,
            PathBuf::from("/m")
        );
    }
}
