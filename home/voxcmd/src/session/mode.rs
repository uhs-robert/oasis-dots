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
//!
//! Which kind a mode is goes by its file's extension alone. A `.toml` mode that stops loading mid-session (a live edit
//! half done, the file moved away) is never handed to the bash loader, which would source it as shell: its settings
//! stay those of the last version that loaded, and its hooks are skipped until it loads again.
use super::{SessionLock, bridge};
use crate::config::intents::Intents;
use crate::config::schema::{self, Integration};
use crate::debug::debug;
use crate::hooks::{self, HookEnv, ShellHooks};
use crate::paths;
use crate::process;
use crate::route::pattern::{self, ModePatterns, WholeText};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModeSettings {
    /// "done", "im done" and "thats all", and the mode's own exit phrases, leave it without the wake word.
    pub default_exits: bool,
    /// A bare "exit", "stop", "cancel" or "quit" ends the whole session (off where they are content: button labels).
    pub bare_exits: bool,
    /// A turn that is exactly another mode's entry or exit switches to it.
    pub allows_switches: bool,
    pub exit_hint: String,
    /// The mode's own ways out.
    pub exit_phrases: Option<WholeText>,
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
            exit_phrases: None,
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
        if is_toml_file(file) {
            // No version of it ever loaded: nothing better than the defaults is known.
            return load_toml_mode(file).map_or_else(Self::default, |mode| Self::from_toml(&mode));
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

    fn from_toml(loaded: &TomlMode) -> Self {
        let integration = &loaded.integration;
        let Some(mode) = &integration.mode else {
            return Self::default();
        };
        let patterns = loaded.patterns.clone();
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
                "exit_phrases" if !value.is_empty() => {
                    settings.exit_phrases = WholeText::new(value)
                        .inspect_err(|error| debug(&format!("session: exit_phrases: {error}")))
                        .ok();
                }
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

/// A declared `rewrite` (TOML): what a turn's words become.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rewriting {
    drop: Option<WholeText>,
    keep: Option<WholeText>,
    prefix: String,
}

impl Rewriting {
    /// The text to route, empty when nothing is: `drop` first, then `keep` (as spoken), else the prefix and the text.
    fn apply(&self, text: &str) -> String {
        let whole = |pattern: &Option<WholeText>| pattern.as_ref().is_some_and(|pattern| pattern.is_match(text));
        if whole(&self.drop) {
            String::new()
        } else if whole(&self.keep) {
            text.to_string()
        } else {
            format!("{}{text}", self.prefix)
        }
    }
}

/// A TOML mode as one session event reads it: the file as it is now, or the last version of it that loaded when it no
/// longer does (`current` false), whose hooks are then not run.
struct TomlMode {
    integration: Integration,
    config_dir: PathBuf,
    patterns: ModePatterns,
    current: bool,
}

fn is_toml_file(file: &str) -> bool {
    Path::new(file).extension().is_some_and(|extension| extension == "toml")
}

/// The mode at `file`, logging why it does not load now. None only when no version of it ever loaded.
fn load_toml_mode(file: &str) -> Option<TomlMode> {
    let path = Path::new(file);
    // `<config dir>/integrations/<stem>.toml`
    let config_dir = path.parent()?.parent()?.to_path_buf();
    let intents = Intents::load(&config_dir);
    let last_good = last_good_copy(path);
    let as_it_is_now = std::fs::read_to_string(path)
        .map_err(|error| format!("{file}: {error}"))
        .and_then(|text| compile_toml_mode(path, &text, &intents).map(|compiled| (text, compiled)));
    let (integration, patterns, current) = match as_it_is_now {
        Ok((text, (integration, patterns))) => {
            let copy_is_stale = std::fs::read_to_string(&last_good).ok().as_deref() != Some(text.as_str());
            if copy_is_stale && let Some(copies) = last_good.parent() {
                // A copy that cannot be written only leaves a later broken edit with the defaults.
                let _ = std::fs::create_dir_all(copies).and_then(|()| std::fs::write(&last_good, &text));
            }
            (integration, patterns, true)
        }
        Err(error) => {
            debug(&format!("session: {error}; its hooks are skipped"));
            let text = std::fs::read_to_string(&last_good).ok()?;
            let (integration, patterns) = compile_toml_mode(path, &text, &intents).ok()?;
            debug(&format!("session: {file}: the last version that loaded stands in"));
            (integration, patterns, false)
        }
    };
    Some(TomlMode {
        integration,
        config_dir,
        patterns,
        current,
    })
}

fn compile_toml_mode(path: &Path, text: &str, intents: &Intents) -> Result<(Integration, ModePatterns), String> {
    let integration = schema::parse_toml(path, text)?;
    let patterns = pattern::compile_mode(&integration, intents)?
        .ok_or_else(|| format!("{}: has no [mode] table", path.display()))?;
    Ok((integration, patterns))
}

/// Where the last version of a TOML mode that loaded is kept, for when it stops loading. In the runtime dir, so it
/// lasts the login, not the session: a session gone before a fix still has it the next time.
fn last_good_copy(path: &Path) -> PathBuf {
    let name = path.to_string_lossy().replace('%', "%25").replace('/', "%2F");
    paths::runtime_dir().join("last-good-modes").join(name)
}

/// A mode hook's command: the integration's library sourced first, the turn's words as `VOXCMD_PHRASE`. With a
/// `heard_mode` it runs with the identity of the Rust process, so a session call in it reaches this session; without
/// one it has none.
fn toml_hook(mode: &TomlMode, shell: &str, phrase: &str, heard_mode: Option<&str>) -> Command {
    let hooks = ShellHooks::for_config_dir(&mode.config_dir);
    let env = HookEnv {
        integration: &mode.integration,
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

fn hook_timeout(mode: &TomlMode) -> Duration {
    mode.integration
        .mode
        .as_ref()
        .and_then(|mode| mode.timeout_secs)
        .map_or(hooks::DEFAULT_TIMEOUT, Duration::from_secs_f64)
}

/// Runs a TOML mode's `ended` hook in the background, after the lock has gone; true when `file` is a TOML mode, so
/// the bash loader never gets it. Like the bash hook it gets no session identity, so a session read in it takes the
/// lock as any reader does.
pub fn run_toml_ended(file: &str, reason: &str, frame_id: &str, continues: bool) -> bool {
    if !is_toml_file(file) {
        return false;
    }
    let Some(mode) = load_toml_mode(file).filter(|mode| mode.current) else {
        return true;
    };
    let Some(shell) = mode
        .integration
        .mode
        .as_ref()
        .and_then(|declared| declared.ended.clone())
    else {
        return true;
    };
    let mut command = toml_hook(&mode, &shell, "", None);
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
    if is_toml_file(file) {
        return load_toml_mode(file)
            .filter(|mode| mode.current)
            .is_none_or(|mode| toml_alive(&mode, heard_mode, lock_held));
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
fn toml_alive(mode: &TomlMode, heard_mode: &str, lock_held: bool) -> bool {
    let Some(shell) = mode
        .integration
        .mode
        .as_ref()
        .and_then(|declared| declared.alive.as_deref())
    else {
        return true;
    };
    let mut command = toml_hook(mode, shell, "", Some(heard_mode));
    if lock_held {
        command.env(bridge::LOCK_HELD_BY_CALLER, "1");
    }
    match process::run_with_timeout(&mut command, hook_timeout(mode)) {
        Ok(outcome) if outcome.timed_out => {
            debug(&format!(
                "session: {}'s alive hook timed out, counted as alive",
                mode.integration.stem
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
    if is_toml_file(file) {
        if let Some(rewriting) = &settings.rewriting {
            return Some(texts.iter().map(|text| rewriting.apply(text)).collect());
        }
        // A hook skipped (the file does not load now) routes nothing rather than words it was meant to change.
        let mode = load_toml_mode(file).filter(|mode| mode.current)?;
        let shell = mode.integration.mode.as_ref()?.rewrite_hook.clone()?;
        return texts
            .iter()
            .map(|text| {
                let mut command = toml_hook(&mode, &shell, text, Some(heard_mode));
                let outcome = process::run_with_timeout(&mut command, hook_timeout(&mode)).ok()?;
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
        let exit_phrases = settings.exit_phrases.as_ref().unwrap();
        assert!(exit_phrases.is_match("done with it") && !exit_phrases.is_match("done with it now"));
        assert_eq!(settings.listen_max_secs, "295");
        assert_eq!(settings.miss_actions, ["no_text"]);
        assert_eq!(settings.exit_hint_or_default(), "say cortana stop");
        // One that is no regex matches nothing, and the mode's other settings still apply.
        let broken = ModeSettings::parse("exit_phrases=done (\nbare_exits=0\n");
        assert!(broken.exit_phrases.is_none() && !broken.bare_exits);
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
            drop: WholeText::new("click").ok(),
            keep: WholeText::new("(left )?click .+").ok(),
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
        let exit_phrases = settings.exit_phrases.as_ref().unwrap();
        assert!(exit_phrases.is_match("im done clicking") && exit_phrases.is_match("done with click mode"));
        let rewriting = settings.rewriting.unwrap();
        assert_eq!(rewriting.apply("click"), "");
        assert_eq!(rewriting.apply("right click settings"), "right click settings");
        assert_eq!(rewriting.apply("sign in"), "click sign in");
    }
}
