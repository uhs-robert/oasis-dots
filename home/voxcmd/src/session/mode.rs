//! a mode's settings and hooks: how its turns are heard (exits, switches, privacy), how long its listens wait, and the
//! integration's `session_rewrite`, `session_alive` and `session_handle_turn` (was `load_mode_settings`,
//! `session_mode_alive` and the `session_rewrite` and `session_handle_turn` calls of `session_turn`)
//!
//! A bash integration's settings may read the environment (type mode's `VOXCMD_TYPE_*`), so they are read live, by
//! `_legacy-hook mode-settings`, at every session event that needs them, never from the cached legacy dump. A TOML
//! integration's `[mode]` is read the same way, from the file itself, so a change to it applies to the next event and
//! session.json carries nothing of it. Its hooks are shell strings run as `hooks.rs` runs every hook.
//!
//! A TOML `alive` runs under the session lock, as bash's did, so a slow one holds up every session call: it gets
//! `[mode] timeout_secs` (3 s by default) and counts as alive when it times out or cannot run.
use super::{SessionLock, bridge};
use crate::config::intents::Intents;
use crate::config::schema::{self, Integration};
use crate::debug::debug;
use crate::hooks::{HookEnv, ShellHooks};
use crate::paths;
use crate::process;
use crate::route::pattern;
use regex::Regex;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

const HOOK_TIMEOUT: Duration = Duration::from_secs(3);

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
    /// A TOML mode's declared `rewrite`; a bash mode's, or a TOML `rewrite_hook`, is a hook.
    pub rewriting: Option<Rewriting>,
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
            rewriting: None,
            miss_actions: Vec::new(),
        }
    }
}

impl ModeSettings {
    /// The settings of the mode whose integration file this is.
    pub fn of(file: &str) -> Self {
        if let Some((integration, config_dir)) = toml_integration(file) {
            return Self::from_toml(&integration, &config_dir);
        }
        if !is_legacy_file(file) {
            return Self::default();
        }
        let output = legacy_hook("mode-settings", file).output();
        match output {
            Ok(output) if output.status.success() => Self::parse(&String::from_utf8_lossy(&output.stdout)),
            _ => Self::default(),
        }
    }

    fn from_toml(integration: &Integration, config_dir: &Path) -> Self {
        let Some(mode) = &integration.mode else {
            return Self::default();
        };
        let patterns = match pattern::compile_mode(integration, &Intents::load(config_dir)) {
            Ok(patterns) => patterns.unwrap_or_default(),
            Err(error) => {
                debug(&format!("session: {error}"));
                return Self::default();
            }
        };
        let secs = |value: Option<f64>| value.map(|secs| secs.to_string()).unwrap_or_default();
        Self {
            default_exits: mode.default_exits,
            bare_exits: mode.bare_exits,
            allows_switches: mode.allows_switches,
            exit_hint: mode.exit_hint.clone(),
            exit_phrases: patterns.exit_phrases,
            private: mode.private,
            open_ended: mode.open_ended,
            wake_listens: mode.wake_listens,
            listen_silence_secs: secs(mode.listen.silence_secs),
            listen_max_secs: secs(mode.listen.max_secs),
            listen_no_speech_secs: secs(mode.listen.no_speech_secs),
            has_rewrite: mode.rewrite.is_some() || mode.rewrite_hook.is_some(),
            has_alive: mode.alive.is_some(),
            rewriting: mode.rewrite.as_ref().map(|rewrite| Rewriting {
                drop: patterns.drop,
                keep: patterns.keep,
                prefix: rewrite.prefix.clone(),
            }),
            miss_actions: integration
                .actions
                .iter()
                .filter(|(_, action)| action.miss)
                .map(|(id, _)| id.clone())
                .collect(),
            ..Self::default()
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

/// A declared `rewrite` (TOML): what a turn's words become, as compiled regex bodies matched against the whole text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rewriting {
    drop: Option<String>,
    keep: Option<String>,
    prefix: String,
}

impl Rewriting {
    /// The text to route, empty when nothing is: `drop` first, then `keep` (as spoken), else the prefix and the text.
    fn apply(&self, text: &str) -> String {
        let whole = |body: &Option<String>| {
            body.as_ref()
                .and_then(|body| Regex::new(&format!("(?s)^(?:{body})$")).ok())
                .is_some_and(|regex| regex.is_match(text))
        };
        if whole(&self.drop) {
            String::new()
        } else if whole(&self.keep) {
            text.to_string()
        } else {
            format!("{}{text}", self.prefix)
        }
    }
}

/// The TOML integration at `file` that has a `[mode]`, and the config dir it was loaded from.
fn toml_integration(file: &str) -> Option<(Integration, PathBuf)> {
    let path = Path::new(file);
    if !path.extension().is_some_and(|extension| extension == "toml") || !path.is_file() {
        return None;
    }
    let integration = schema::load_toml(path)
        .inspect_err(|error| debug(&format!("session: {error}")))
        .ok()?;
    integration.mode.as_ref()?;
    // `<config dir>/integrations/<stem>.toml`
    Some((integration, path.parent()?.parent()?.to_path_buf()))
}

/// A mode hook's command: the integration's library sourced first, the turn's words as `VOXCMD_PHRASE`. With a
/// `heard_mode` it runs with the identity of the Rust process, so a session call in it reaches this session; without
/// one it has none.
fn toml_hook(
    integration: &Integration,
    config_dir: &Path,
    shell: &str,
    phrase: &str,
    heard_mode: Option<&str>,
) -> Command {
    let hooks = ShellHooks::new(
        config_dir,
        [integration.stem.clone()],
        std::env::var_os("VOXCMD_DRY_RUN").is_some_and(|value| value == "1"),
    );
    let env = HookEnv {
        integration,
        action: "",
        args: &[],
        phrase,
        raw_transcript: phrase,
        id: None,
        label: None,
        confirmed: false,
        active_before: None,
        spoken: true,
    };
    let mut command = hooks.command(shell, &env, false);
    bridge::clear_hook_env(&mut command);
    if let Some(heard_mode) = heard_mode {
        command.envs(bridge::hook_env(heard_mode));
    }
    command
}

fn hook_timeout(integration: &Integration) -> Duration {
    integration
        .mode
        .as_ref()
        .and_then(|mode| mode.timeout_secs)
        .map_or(HOOK_TIMEOUT, Duration::from_secs_f64)
}

/// Runs a TOML mode's `ended` hook in the background, after the lock has gone; true when `file` is a TOML mode (with
/// or without one). Like the bash hook it gets no session identity, so a session read in it takes the lock as any
/// reader does.
pub fn run_toml_ended(file: &str, reason: &str, frame_id: &str, continues: bool) -> bool {
    let Some((integration, config_dir)) = toml_integration(file) else {
        return false;
    };
    let Some(shell) = integration.mode.as_ref().and_then(|mode| mode.ended.clone()) else {
        return true;
    };
    let mut command = toml_hook(&integration, &config_dir, &shell, "", None);
    command
        .env("VOXCMD_MODE_END_REASON", reason)
        .env("VOXCMD_MODE_FRAME_ID", frame_id)
        .env("VOXCMD_MODE_CONTINUES", if continues { "1" } else { "0" })
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    std::os::unix::process::CommandExt::process_group(&mut command, 0);
    match command.spawn() {
        Ok(hook) => debug(&format!("session: ended hook {} runs", hook.id())),
        Err(error) => debug(&format!("session: cannot run the ended hook of {file}: {error}")),
    }
    true
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

/// Whether the mode is still wanted: its `session_alive`, when it has one, says its screen is still up. Run with
/// `bridge::hook_env`, so a session check in the hook names this process as `$$`, not the bash child.
pub fn alive(file: &str, heard_mode: &str) -> bool {
    is_alive(file, heard_mode, false)
}

/// `alive` while the session lock is held, as bash ran it there. The hook's session reads skip the lock and its
/// changes are refused (`bridge::LOCK_HELD_BY_CALLER`), so it cannot wait for this caller.
pub fn alive_under(_lock: &SessionLock, file: &str) -> bool {
    is_alive(file, "", true)
}

fn is_alive(file: &str, heard_mode: &str, lock_held: bool) -> bool {
    if let Some((integration, config_dir)) = toml_integration(file) {
        return toml_alive(&integration, &config_dir, heard_mode, lock_held);
    }
    if !is_legacy_file(file) {
        return true;
    }
    let mut command = legacy_hook("alive", file);
    command.envs(bridge::hook_env(heard_mode));
    if lock_held {
        command.env(bridge::LOCK_HELD_BY_CALLER, "1");
    }
    command
        .stdout(Stdio::null())
        .status()
        // A hook that cannot run says nothing against the mode.
        .map_or(true, |status| status.success())
}

/// A hook that cannot run, or runs out of time, says nothing against the mode.
fn toml_alive(integration: &Integration, config_dir: &Path, heard_mode: &str, lock_held: bool) -> bool {
    let Some(shell) = integration.mode.as_ref().and_then(|mode| mode.alive.as_deref()) else {
        return true;
    };
    let mut command = toml_hook(integration, config_dir, shell, "", Some(heard_mode));
    if lock_held {
        command.env(bridge::LOCK_HELD_BY_CALLER, "1");
    }
    match process::run_with_timeout(&mut command, hook_timeout(integration)) {
        Ok(outcome) if outcome.timed_out => {
            debug(&format!(
                "session: {}'s alive hook timed out, counted as alive",
                integration.stem
            ));
            true
        }
        Ok(outcome) => outcome.code() == Some(0),
        Err(_) => true,
    }
}

/// Each text as the mode makes it: its declared `rewrite`, or its hook (`session_rewrite` for bash, with the same
/// `hook_env` as `alive`). None when a hook failed to give one per text. A bash hook given a single text keeps every
/// line it printed.
pub fn rewrite(settings: &ModeSettings, file: &str, texts: &[String], heard_mode: &str) -> Option<Vec<String>> {
    if let Some((integration, config_dir)) = toml_integration(file) {
        if let Some(rewriting) = &settings.rewriting {
            return Some(texts.iter().map(|text| rewriting.apply(text)).collect());
        }
        let shell = integration.mode.as_ref()?.rewrite_hook.clone()?;
        return texts
            .iter()
            .map(|text| {
                let mut command = toml_hook(&integration, &config_dir, &shell, text, Some(heard_mode));
                let outcome = process::run_with_timeout(&mut command, hook_timeout(&integration)).ok()?;
                (outcome.code() == Some(0)).then(|| outcome.stdout.trim_end_matches('\n').to_string())
            })
            .collect();
    }
    let output = legacy_hook("rewrite", file)
        .args(texts)
        .envs(bridge::hook_env(heard_mode))
        .output()
        .ok()?;
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
        assert!(alive("x", ""));
    }

    #[test]
    fn a_declared_rewrite_drops_then_keeps_then_prefixes_whole_texts() {
        let rewriting = Rewriting {
            drop: Some("click".into()),
            keep: Some("(left )?click .+".into()),
            prefix: "click ".into(),
        };
        assert_eq!(rewriting.apply("click"), "");
        assert_eq!(rewriting.apply("left click ok"), "left click ok");
        assert_eq!(rewriting.apply("sign in"), "click sign in");
        // Anchored: a text that only contains a pattern is prefixed.
        assert_eq!(rewriting.apply("double click"), "click double click");
        let prefix_only = Rewriting {
            drop: None,
            keep: None,
            prefix: "overview ".into(),
        };
        assert_eq!(prefix_only.apply("next"), "overview next");
    }

    #[test]
    fn the_click_conversion_loads_as_mode_settings() {
        let file = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/integrations/click.toml");
        let settings = ModeSettings::of(file);
        assert!(!settings.bare_exits && settings.allows_switches && settings.default_exits && settings.has_rewrite);
        assert_eq!(settings.miss_actions, ["no_text"]);
        assert_eq!(settings.exit_hint, "say done to stop");
        assert!(
            settings
                .exit_phrases
                .starts_with("done clicking|im done clicking|done with (?:")
        );
        let rewriting = settings.rewriting.unwrap();
        assert_eq!(rewriting.apply("click"), "");
        assert_eq!(rewriting.apply("right click settings"), "right click settings");
        assert_eq!(rewriting.apply("sign in"), "click sign in");
    }
}
