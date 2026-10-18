//! a mode's settings and hooks: how its turns are heard (exits, switches, privacy), how long its listens wait, and the
//! integration's `session_rewrite`, `session_alive` and `session_handle_turn` (was `load_mode_settings`,
//! `session_mode_alive` and the `session_rewrite` and `session_handle_turn` calls of `session_turn`)
//!
//! A bash integration's settings may read the environment (type mode's `VOXCMD_TYPE_*`), so they are read live, by
//! `_legacy-hook mode-settings`, at every session event that needs them, never from the cached legacy dump. A TOML
//! mode is voxcmd-port 2.4c2; until then any other file has the defaults.
use super::{SessionLock, bridge};
use crate::paths;
use std::path::Path;
use std::process::{Command, Stdio};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModeSettings {
    /// "done", "im done" and "thats all", and the mode's own exit phrases, leave it without the wake word.
    pub default_exits: bool,
    /// A bare "exit", "stop", "cancel" or "quit" ends the whole session (off where they are content: button labels).
    pub bare_exits: bool,
    /// A turn that is exactly another mode's entry or exit switches to it.
    pub allows_switches: bool,
    pub exit_hint: String,
    /// An ERE alternation, the mode's own ways out.
    pub exit_phrases: String,
    /// What is said is dictation: no text in the logs, and a wake word command that is no mode command is not routed.
    pub private: bool,
    /// Bounded by its own limits, not the session's turn and time caps.
    pub open_ended: bool,
    /// Hears one recording (type mode), which the bash voxcmd handles until voxcmd-port 2.4d.
    pub one_recording: bool,
    pub wake_listens: bool,
    /// The auto-stop settings of the mode's listens; empty takes the session's.
    pub listen_silence_secs: String,
    pub listen_max_secs: String,
    pub listen_no_speech_secs: String,
    /// The mode takes its turns' words itself (`session_handle_turn`).
    pub has_handler: bool,
    pub has_rewrite: bool,
    pub has_alive: bool,
    /// Actions that ran but found nothing to act on, so the turn missed.
    pub miss_actions: Vec<String>,
}

impl Default for ModeSettings {
    fn default() -> Self {
        Self {
            default_exits: true,
            bare_exits: true,
            allows_switches: false,
            exit_hint: String::new(),
            exit_phrases: String::new(),
            private: false,
            open_ended: false,
            one_recording: false,
            wake_listens: false,
            listen_silence_secs: String::new(),
            listen_max_secs: String::new(),
            listen_no_speech_secs: String::new(),
            has_handler: false,
            has_rewrite: false,
            has_alive: false,
            miss_actions: Vec::new(),
        }
    }
}

impl ModeSettings {
    /// The settings of the mode whose integration file this is.
    pub fn of(file: &str) -> Self {
        if !is_legacy_file(file) {
            return Self::default();
        }
        let output = legacy_hook("mode-settings", file).output();
        match output {
            Ok(output) if output.status.success() => Self::parse(&String::from_utf8_lossy(&output.stdout)),
            _ => Self::default(),
        }
    }

    /// `print_mode_settings` output: `key=value` lines. Its `ending` rows are 2.4d's.
    fn parse(output: &str) -> Self {
        let mut settings = Self::default();
        for (key, value) in output.lines().filter_map(|line| line.split_once('=')) {
            let on = value == "1";
            match key {
                "default_exits" => settings.default_exits = on,
                "bare_exits" => settings.bare_exits = on,
                "allows_switches" => settings.allows_switches = on,
                "exit_hint" => settings.exit_hint = value.to_string(),
                "exit_phrases" => settings.exit_phrases = value.to_string(),
                "private" => settings.private = on,
                "open_ended" => settings.open_ended = on,
                "one_recording" => settings.one_recording = on,
                "wake_listens" => settings.wake_listens = on,
                "listen_silence_secs" => settings.listen_silence_secs = value.to_string(),
                "listen_max_secs" => settings.listen_max_secs = value.to_string(),
                "listen_no_speech_secs" => settings.listen_no_speech_secs = value.to_string(),
                "has_handler" => settings.has_handler = on,
                "has_rewrite" => settings.has_rewrite = on,
                "has_alive" => settings.has_alive = on,
                "miss_action" if !value.is_empty() => settings.miss_actions.push(value.to_string()),
                _ => {}
            }
        }
        settings
    }

    pub fn exit_hint_or_default(&self) -> &str {
        if self.exit_hint.is_empty() {
            "say done to stop"
        } else {
            &self.exit_hint
        }
    }
}

fn is_legacy_file(file: &str) -> bool {
    let path = Path::new(file);
    path.extension().is_some_and(|extension| extension == "sh") && path.is_file()
}

fn legacy_hook(kind: &str, file: &str) -> Command {
    let mut command = Command::new(paths::legacy_bin());
    command
        .args(["_legacy-hook", kind, file])
        .stdin(Stdio::null())
        .stderr(Stdio::null());
    command
}

/// Whether the mode is still wanted: its `session_alive`, when it has one, says its screen is still up.
pub fn alive(file: &str) -> bool {
    is_alive(file, false)
}

/// `alive` while the session lock is held, as bash ran it there. The hook's session reads skip the lock and its
/// changes are refused (`bridge::LOCK_HELD_BY_CALLER`), so it cannot wait for this caller.
pub fn alive_under(_lock: &SessionLock, file: &str) -> bool {
    is_alive(file, true)
}

fn is_alive(file: &str, lock_held: bool) -> bool {
    if !is_legacy_file(file) {
        return true;
    }
    let mut command = legacy_hook("alive", file);
    if lock_held {
        command.env(bridge::LOCK_HELD_BY_CALLER, "1");
    }
    command
        .stdout(Stdio::null())
        .status()
        // A hook that cannot run says nothing against the mode.
        .map_or(true, |status| status.success())
}

/// Each text as the mode's `session_rewrite` makes it; none when the hook failed to give one per text. A single text
/// keeps every line the hook printed.
pub fn rewrite(file: &str, texts: &[String]) -> Option<Vec<String>> {
    let output = legacy_hook("rewrite", file).args(texts).output().ok()?;
    let printed = String::from_utf8_lossy(&output.stdout);
    let printed = printed.trim_end_matches('\n');
    if texts.len() == 1 {
        return Some(vec![printed.to_string()]);
    }
    let lines: Vec<String> = printed.split('\n').map(str::to_string).collect();
    (lines.len() == texts.len()).then_some(lines)
}

/// Hands the turn's words to the mode's `session_handle_turn`, whose session calls go to this process.
pub fn handle_turn(file: &str, transcript: &str, heard_mode: &str) {
    let mut command = legacy_hook("handle-turn", file);
    command
        .arg(transcript)
        .stdout(Stdio::null())
        .envs(bridge::hook_env(heard_mode));
    let _ = command.status();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn settings_read_from_the_bash_print_with_defaults_for_the_rest() {
        let settings = ModeSettings::parse(
            "default_exits=0\nbare_exits=1\nexit_hint=say cortana stop\nexit_phrases=done (clicking|with it)\n\
             private=1\nlisten_max_secs=295\nhas_rewrite=1\nmiss_action=\nmiss_action=no_text\nending=type stop\n",
        );
        assert!(!settings.default_exits && settings.bare_exits && settings.private && settings.has_rewrite);
        assert!(!settings.allows_switches && !settings.has_handler && !settings.has_alive);
        assert_eq!(settings.exit_phrases, "done (clicking|with it)");
        assert_eq!(settings.listen_max_secs, "295");
        assert_eq!(settings.miss_actions, ["no_text"]);
        assert_eq!(settings.exit_hint_or_default(), "say cortana stop");
    }

    #[test]
    fn a_file_that_is_no_bash_integration_has_the_defaults() {
        let settings = ModeSettings::of("/nonexistent/x.sh");
        assert_eq!(settings, ModeSettings::default());
        assert!(settings.default_exits && settings.bare_exits);
        assert_eq!(settings.exit_hint_or_default(), "say done to stop");
        assert!(alive("x"));
    }
}
