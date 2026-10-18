//! a voice session's turns: opening the session, hearing a turn in the mode on top, counting it, and listening again
//! (was `session_begin`, `session_turn`, `session_continue`, `session_count_turn`, `session_listen`,
//! `session_silence`, `session_heard_nothing`, the exit words and `session_classify_wake_command`)
//!
//! A turn's watcher owns the session while it hears and acts; its next listen hands the session to the next watcher.
//! A voice key pressed meanwhile takes the session over, and the turn then leaves it alone ("another listen took
//! over"). A one-recording mode's turn (type mode) is the bash voxcmd's until voxcmd-port 2.4d: `listen` starts the
//! bash watcher for it.
use super::mode::{self, ModeSettings};
use super::{Opened, SessionLock, is_mine, mode_token, now_secs, text_of};
use crate::actions::{Spoken, StepOutcome};
use crate::debug::debug;
use crate::notify::{self, Kind};
use crate::paths;
use crate::route::runner::Runner;
use crate::route::sequence;
use crate::text::normalize::{Replacements, apply_replacements, normalize};
use crate::text::wake_word::{WAKE_WORD, WakeWords};
use crate::voice::{listen, secs_setting, settle};
use regex::Regex;
use serde_json::json;
use std::sync::LazyLock;

/// Only phrases nobody would click: "cancel", "exit", "stop" and "never mind" are button labels, so they are targets.
/// The open mode adds its own as its exit phrases.
static EXIT_WORDS: LazyLock<Regex> = LazyLock::new(|| Regex::new("^(done|im done|thats all)$").expect("fixed pattern"));
/// Bare words that end the whole session and everything it opened, unless the mode opts out (they are its content).
static BARE_EXIT_WORDS: LazyLock<Regex> =
    LazyLock::new(|| Regex::new("^(exit|stop|cancel|quit)$").expect("fixed pattern"));
/// After the wake word, "stop" ends the whole session as the Stop Voice key does.
static STOP_WORDS: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new("^(stop|stop listening|stop everything|end session|end the session)$").expect("fixed pattern")
});
/// Whisper's stock output for silence and noise, normalized (before replacements): a turn that heard only one of these
/// heard nothing. voxtype-daemon puts "Voice commands start with <wake word>." in Whisper's prompt, which Whisper can
/// echo on silence.
static NOISE: LazyLock<Regex> = LazyLock::new(|| {
    let echo = regex::escape(&normalize(&format!("Voice commands start with {WAKE_WORD}")));
    Regex::new(&format!(
        "^(|you|bye|the end|thank you|thank you for watching|thanks for watching|blank audio|{echo})$"
    ))
    .expect("fixed pattern")
});
/// Unusable turns in a row that end the session.
const UNCLEAR_CAP: i64 = 3;

/// What a turn came to, for the caps.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    /// It did something: the unclear count starts again.
    Ran,
    /// It did nothing: one more unclear turn.
    Missed,
    /// It heard nothing: neither.
    Unheard,
}

/// Whether the replaced text is a way out of the mode: the exit words, or its own phrases.
fn is_exit(text: &str, mode: &ModeSettings) -> bool {
    EXIT_WORDS.is_match(text) || mode.exit_phrases.as_ref().is_some_and(|phrases| phrases.is_match(text))
}

/// Whether the replaced text is a bare word that ends the whole session.
fn is_bare_exit(text: &str, mode: &ModeSettings) -> bool {
    mode.default_exits && mode.bare_exits && BARE_EXIT_WORDS.is_match(text)
}

/// What a turn's words ask of the session, before anything runs. `T` is a mode switch's option.
#[derive(Debug, PartialEq, Eq)]
pub enum Heard<T> {
    /// The transcriber's guess at noise.
    Noise,
    /// The wake word and nothing after it.
    WakeAlone,
    /// The wake word, then a way out of the mode.
    WakeExit,
    /// The wake word, then "stop": the whole session ends.
    WakeStop,
    /// The wake word, then exactly one mode's entry or exit.
    WakeSwitch(T),
    /// The wake word, then words that are no mode command, as the text routed.
    WakeCommand(String),
    BareExit,
    Exit,
    /// Exactly one mode's entry or exit, in a mode that allows switches.
    Switch(T),
    /// Words for the mode.
    Words,
}

/// Classifies normalized words heard in the mode. `mode_options` gives the mode switches the text names; only one
/// that names exactly one switches.
pub fn classify<T>(
    normalized: &str,
    mode: &ModeSettings,
    wake: &WakeWords,
    replacements: &Replacements,
    mode_options: impl FnOnce(&str) -> Vec<T>,
) -> Heard<T> {
    let only = |mut options: Vec<T>| (options.len() == 1).then(|| options.remove(0));
    if NOISE.is_match(normalized) {
        return Heard::Noise;
    }
    if let Some(rest) = wake.split_leading(normalized) {
        let command = apply_replacements(&rest, replacements);
        return if command.is_empty() {
            Heard::WakeAlone
        } else if is_exit(&command, mode) {
            Heard::WakeExit
        } else if STOP_WORDS.is_match(&command) {
            Heard::WakeStop
        } else {
            match only(mode_options(&command)) {
                Some(option) => Heard::WakeSwitch(option),
                None => Heard::WakeCommand(command),
            }
        };
    }
    let text = apply_replacements(normalized, replacements);
    if is_bare_exit(&text, mode) {
        return Heard::BareExit;
    }
    if mode.default_exits && is_exit(&text, mode) {
        return Heard::Exit;
    }
    if mode.allows_switches
        && let Some(option) = only(mode_options(&text))
    {
        return Heard::Switch(option);
    }
    Heard::Words
}

/// Opens a mode and, when no session is open, the session, which listens for its first turn at once (a bash mode's
/// `session_begin`, called once its screen is up).
pub fn begin(kind: &str, file: &str, label: &str, me: u32) {
    if open(kind, file, label, me) == Opened::Session {
        listen_for_turn(me);
    }
}

/// Opens a mode and, when no session is open, the session; a new session's first listen is the caller's, once what
/// the mode drives is up (its `alive` would end it before). From a turn of the session `me` owns it enters the mode
/// (the turn's own listen follows); from anything else (a terminal, a key) an open session is left as it is and the
/// mode refused. Auto-stop's silence timeout is the only way an idle mode ends, so without it there is none.
pub fn open(kind: &str, file: &str, label: &str, me: u32) -> Opened {
    {
        let lock = SessionLock::take();
        if let Some(state) = super::state(&lock) {
            if is_mine(&state, me) {
                return super::enter(&lock, kind, file, label, me);
            }
            return refuse_occupied(label);
        }
    }
    if let Some(why) = autostop_unavailable() {
        notify::notify(Kind::Info, &format!("voxcmd: {label} needs auto-stop"), &why);
        return Opened::Refused;
    }
    // Another process may have opened a session while auto-stop was probed.
    if !super::create(&SessionLock::take(), kind, file, label, me) {
        return refuse_occupied(label);
    }
    debug(&format!("session: {kind} begins"));
    Opened::Session
}

fn refuse_occupied(label: &str) -> Opened {
    notify::notify(
        Kind::Info,
        &format!("voxcmd: {label}"),
        "A voice session is already open",
    );
    Opened::Refused
}

/// Why auto-stop cannot end a session's listens (`voxcmd-autostop --check`), none when it can.
fn autostop_unavailable() -> Option<String> {
    let autostop = paths::autostop();
    if !crate::ask::is_executable(&autostop) {
        return Some("voxcmd-autostop is missing".to_string());
    }
    let output = std::process::Command::new(autostop).arg("--check").output();
    match output {
        Ok(output) if output.status.success() => None,
        Ok(output) => {
            let said = format!(
                "{}{}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
            Some(said.trim_end_matches('\n').to_string())
        }
        Err(error) => Some(error.to_string()),
    }
}

/// How a session's next listen went.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Listen {
    Started,
    /// Another listen (a voice key's) owns the session, so there is a listener and nothing to start.
    TookOver,
    /// The session had ended, or the microphone could not be opened (which ends it).
    Failed,
}

/// Opens the microphone for the next turn, unless the session ended or another listen took it over.
/// Holding the lock while it starts, a failed start cannot be a listen of ours, so voxtype is busy with something else.
pub fn listen_for_turn(me: u32) -> Listen {
    let lock = SessionLock::take();
    if super::state(&lock).is_none() {
        return Listen::Failed;
    }
    drop_dead_modes(&lock, me);
    let Some(state) = super::state(&lock) else {
        return Listen::Failed;
    };
    if !is_mine(&state, me) {
        debug("session: another listen took over");
        return Listen::TookOver;
    }
    let listening = listen::listen_locked(&lock, true, None, me);
    if !listening {
        super::end_all_locked(&lock, "the microphone could not be opened", me);
    }
    if listening { Listen::Started } else { Listen::Failed }
}

/// Leaves the modes whose screen is gone (the overview closed by key), so a mode never outlives what it drives.
fn drop_dead_modes(lock: &SessionLock, me: u32) {
    while let Some(state) = super::state(lock) {
        if mode::alive_under(lock, &text_of(&state["integration"]))
            || !super::leave(lock, &text_of(&state["kind"]), "its screen closed", me)
        {
            return;
        }
    }
}

/// After a turn: counts it, ends the session when a cap is reached, else waits for the screen to settle and listens
/// again.
pub fn continue_turns(outcome: Outcome, me: u32) {
    if !count_turn(&SessionLock::take(), outcome, me) {
        return;
    }
    if !settle::wait_until_ui_settled() {
        debug(&format!(
            "session: the screen had not settled after {}s",
            secs_setting("VOXCMD_UI_SETTLE_MAX_SECS", "2")
        ));
    }
    listen_for_turn(me);
}

/// Records the turn; false when the session is over or another listen took it over. An open-ended mode counts none:
/// it is bounded by its own limits.
fn count_turn(lock: &SessionLock, outcome: Outcome, me: u32) -> bool {
    let Some(state) = super::state(lock) else {
        return false;
    };
    if !is_mine(&state, me) {
        debug("session: another listen took over");
        return false;
    }
    if state["open_ended"] == json!(true) {
        return true;
    }
    let mut unclear = super::number_or(&state["unclear"], 0);
    match outcome {
        Outcome::Missed => unclear += 1,
        Outcome::Ran => unclear = 0,
        Outcome::Unheard => {}
    }
    let turns = super::number_or(&state["turns"], 0) + 1;
    let max_turns = setting("VOXCMD_SESSION_MAX_TURNS", 40);
    let max_secs = setting("VOXCMD_SESSION_MAX_SECS", 300);
    let why = if unclear >= UNCLEAR_CAP {
        format!("nothing understood {UNCLEAR_CAP} times in a row")
    } else if turns >= max_turns {
        format!("it reached {max_turns} turns")
    } else if now_secs() - super::number_or(&state["started"], 0) >= max_secs {
        format!("it reached its time limit ({})", duration_words(max_secs))
    } else {
        super::update(lock, |fields| {
            fields.insert("unclear".into(), json!(unclear));
            fields.insert("turns".into(), json!(turns));
        });
        return true;
    };
    super::end_all_locked(lock, &why, me);
    false
}

fn setting(name: &str, default: i64) -> i64 {
    secs_setting(name, &default.to_string()).parse().unwrap_or(default)
}

pub fn duration_words(secs: i64) -> String {
    if secs >= 60 && secs % 60 == 0 {
        format!("{} min", secs / 60)
    } else {
        format!("{secs} s")
    }
}

/// A listen that was discarded: no speech, or a recording cancelled. The mode ends, back to the mode under it, which
/// listens on.
pub fn silence(me: u32) {
    let lock = SessionLock::take();
    let Some(state) = super::state(&lock).filter(|state| is_mine(state, me)) else {
        return;
    };
    super::leave(&lock, &text_of(&state["kind"]), "nothing was said", me);
    drop(lock);
    listen_for_turn(me);
}

/// A recording that ended with no transcript: the session listens again.
pub fn heard_nothing(me: u32) {
    continue_turns(Outcome::Unheard, me);
}

/// The transcript handler while a session is open. A session that ended while the recording ran hands it to the
/// router, unless a mode that keeps its words private heard it: those are never routed.
pub fn session_turn(runner: &Runner, transcript: &str, heard_mode: &str, heard_private: bool) {
    let me = std::process::id();
    // Stop landed after the watcher's own check: nothing from this turn may run or open the microphone.
    if paths::discard_flag(me).exists() {
        if heard_private {
            debug("session: a turn was discarded, stop was pressed");
        } else {
            debug(&format!("session: turn \"{transcript}\" discarded, stop was pressed"));
        }
        return;
    }
    let Some(state) = super::read_state() else {
        if heard_private {
            debug("session: a turn heard in a private mode outlived its session, discarded");
        } else {
            runner.route(transcript);
        }
        return;
    };
    let file = text_of(&state["integration"]);
    let kind = text_of(&state["kind"]);
    let mode = ModeSettings::of(&file);
    if mode.has_alive && !mode::alive(&file, heard_mode) {
        // What was said was heard for a mode whose screen has closed: it goes where it would without the mode.
        debug(&format!("session: {kind}'s screen is gone"));
        super::leave(&SessionLock::take(), &kind, "its screen closed", me);
        let session_goes_on = super::read_state().is_some();
        runner.route(transcript);
        // A mode underneath goes on, and listens here; with none left, a mode the phrase opened listens itself.
        if session_goes_on {
            continue_turns(Outcome::Unheard, me);
        }
        return;
    }
    let token = mode_token(&state);
    if !heard_mode.is_empty() && heard_mode != token {
        debug(&format!(
            "session: heard in {heard_mode} but the session is in {token}, not routed"
        ));
        notify::notify(Kind::Info, "voxcmd", "The mode changed, say it again");
        continue_turns(Outcome::Unheard, me);
        return;
    }
    if mode.one_recording {
        // Its own watcher is the bash one's (listen starts it); a Rust watcher's turn heard in it is a turn heard
        // before the mode changed.
        debug("session: a one-recording mode's turn reached the Rust watcher, not acted on");
        continue_turns(Outcome::Unheard, me);
        return;
    }
    let outcome = TurnRun {
        runner,
        mode: &mode,
        file: &file,
        kind: &kind,
        transcript,
        heard_mode,
        me,
    }
    .run();
    if let Some(outcome) = outcome {
        continue_turns(outcome, me);
    }
}

/// One turn being run in the mode on top.
struct TurnRun<'a> {
    runner: &'a Runner<'a>,
    mode: &'a ModeSettings,
    file: &'a str,
    kind: &'a str,
    transcript: &'a str,
    heard_mode: &'a str,
    me: u32,
}

impl TurnRun<'_> {
    /// What the turn came to; none when the session is no longer the turn's to go on with.
    fn run(&self) -> Option<Outcome> {
        let normalized = normalize(self.transcript);
        let router = self.runner.router;
        let heard = classify(
            &normalized,
            self.mode,
            router.wake(),
            &router.config().replacements,
            |text| router.mode_options(text),
        );
        if matches!(heard, Heard::Noise) {
            debug("session: the transcriber's guess at noise, listening again");
            return Some(Outcome::Unheard);
        }
        super::update(&SessionLock::take(), |fields| {
            fields.insert("last_heard".into(), json!(now_secs()));
        });
        Some(match heard {
            Heard::Noise => Outcome::Unheard,
            Heard::WakeAlone => {
                notify::notify(Kind::Info, "voxcmd", &format!("Say a command after \"{WAKE_WORD}\""));
                Outcome::Unheard
            }
            Heard::WakeExit => {
                self.leave_mode();
                Outcome::Ran
            }
            Heard::WakeStop => {
                super::end_all("stopped", self.me);
                Outcome::Ran
            }
            Heard::WakeSwitch(option) | Heard::Switch(option) => self.switch(&option),
            Heard::WakeCommand(_) if self.mode.private => {
                // Dictated words are never routed: a stray one could run a command.
                notify::notify(Kind::Info, &format!("voxcmd: {WAKE_WORD}"), "Not a mode command");
                Outcome::Unheard
            }
            Heard::WakeCommand(command) => {
                self.runner.forget_last_run_action();
                let routed = self.runner.route(&command);
                self.ran_or_missed(routed.exit_code == 0)
            }
            Heard::BareExit => {
                super::end_all("done", self.me);
                Outcome::Ran
            }
            Heard::Exit => {
                self.leave_mode();
                Outcome::Ran
            }
            Heard::Words if self.mode.has_handler => {
                // The mode takes the words itself.
                mode::handle_turn(self.file, self.transcript, self.heard_mode);
                Outcome::Ran
            }
            Heard::Words => self.words(),
        })
    }

    fn leave_mode(&self) {
        super::leave(&SessionLock::take(), self.kind, "done", self.me);
    }

    fn switch(&self, option: &crate::route::resolve::RouteOption) -> Outcome {
        self.runner.forget_last_run_action();
        let normalized = normalize(self.transcript);
        let said = Spoken {
            phrase: &normalized,
            raw_transcript: self.transcript,
            active_before: "",
            in_sequence: false,
        };
        if self.runner.run_option(option, &said).outcome == StepOutcome::Ran {
            Outcome::Ran
        } else {
            Outcome::Missed
        }
    }

    /// A turn missed when routing failed, nothing ran (a picker or overlay was cancelled or timed out, though routing
    /// succeeds) or what ran is one of the mode's actions that found nothing to act on.
    fn ran_or_missed(&self, routed: bool) -> Outcome {
        let action = self.runner.last_run_action();
        if !routed || action.is_empty() || self.mode.miss_actions.contains(&action) {
            Outcome::Missed
        } else {
            Outcome::Ran
        }
    }

    /// Words for the mode: rewritten by it when it rewrites, one step or several, where a last step that is a way
    /// out leaves the mode after the steps before it.
    fn words(&self) -> Outcome {
        let router = self.runner.router;
        let replaced = |step: &str| apply_replacements(&normalize(step), &router.config().replacements);
        let mut split = sequence::split_phrase(router, self.transcript);
        let mut leave_after = None;
        if split.steps.len() > 1 && self.mode.default_exits {
            let last = replaced(&split.steps[split.steps.len() - 1]);
            if is_bare_exit(&last, self.mode) {
                leave_after = Some(LeaveAfter::Session);
            } else if is_exit(&last, self.mode) {
                leave_after = Some(LeaveAfter::Mode);
            }
            if leave_after.is_some() {
                split.steps.pop();
            }
        }
        self.runner.forget_last_run_action();
        // As bash's step_outcome, which is "ran" until a step says otherwise.
        let mut step_outcome = StepOutcome::Ran;
        let outcome = if split.steps.len() > 1 {
            match self.rewrite_steps(&split.steps, replaced) {
                None => self.not_understood(),
                Some(steps) => {
                    split.steps = steps;
                    let routed = self.runner.route_steps(&split);
                    step_outcome = routed.outcome;
                    self.ran_or_missed(routed.exit_code == 0)
                }
            }
        } else {
            let text = replaced(&split.steps[0]);
            let rewritten = if self.mode.has_rewrite {
                mode::rewrite(self.mode, self.file, &[text], self.heard_mode)
                    .and_then(|mut rewritten| rewritten.pop())
                    .unwrap_or_default()
            } else {
                text
            };
            if rewritten.is_empty() {
                self.not_understood()
            } else {
                let result = self.runner.route_step(&rewritten);
                step_outcome = result.outcome;
                self.ran_or_missed(result.exit_code == 0)
            }
        };
        if step_outcome == StepOutcome::Ran {
            match leave_after {
                Some(LeaveAfter::Mode) => self.leave_mode(),
                Some(LeaveAfter::Session) => super::end_all("done", self.me),
                None => {}
            }
        }
        outcome
    }

    /// What each step routes as in the mode: rewritten by its `session_rewrite`, or unchanged when it has none. A step
    /// that is exactly a mode switch the mode allows is left as spoken, as a whole turn would be. None when a step
    /// names nothing to route.
    fn rewrite_steps(&self, steps: &[String], replaced: impl Fn(&str) -> String) -> Option<Vec<String>> {
        if !self.mode.has_rewrite {
            return Some(steps.to_vec());
        }
        let texts: Vec<String> = steps.iter().map(|step| replaced(step)).collect();
        let rewritten = mode::rewrite(self.mode, self.file, &texts, self.heard_mode)?;
        let router = self.runner.router;
        let steps: Vec<String> = texts
            .into_iter()
            .zip(rewritten)
            .map(|(text, rewritten)| {
                if self.mode.allows_switches && router.is_mode_action(&text) {
                    text
                } else {
                    rewritten
                }
            })
            .collect();
        steps.iter().all(|step| !step.is_empty()).then_some(steps)
    }

    fn not_understood(&self) -> Outcome {
        notify::notify(
            Kind::Info,
            "voxcmd",
            &format!("Not understood: \"{}\"", self.transcript),
        );
        Outcome::Missed
    }
}

#[derive(Clone, Copy)]
enum LeaveAfter {
    Mode,
    Session,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::route::pattern::WholeText;

    fn heard(said: &str, mode: &ModeSettings, switches: &[&'static str]) -> Heard<&'static str> {
        let wake = WakeWords::new("kortana|cortona");
        let options = |text: &str| switches.iter().copied().filter(|switch| *switch == text).collect();
        classify(&normalize(said), mode, &wake, &Replacements::default(), options)
    }

    #[test]
    fn a_turn_is_classified_by_its_words_and_the_mode() {
        let plain = ModeSettings::default();
        let click = ModeSettings {
            bare_exits: false,
            allows_switches: true,
            exit_phrases: WholeText::new("done clicking|stop clicking").ok(),
            ..ModeSettings::default()
        };
        let typing = ModeSettings {
            default_exits: false,
            private: true,
            ..ModeSettings::default()
        };
        let switches = ["rapid mode", "type mode"];
        use Heard::*;
        for (said, mode, expected) in [
            ("Thank you.", &plain, Noise),
            ("[BLANK_AUDIO]", &plain, Noise),
            ("Voice commands start with Cortana.", &plain, Noise),
            ("Cortana.", &plain, WakeAlone),
            ("cortana done", &plain, WakeExit),
            ("Cortana, stop clicking.", &click, WakeExit),
            ("kortana stop", &plain, WakeStop),
            ("cortana end the session", &typing, WakeStop),
            ("cortana rapid mode", &plain, WakeSwitch("rapid mode")),
            ("cortana tap alpha", &plain, WakeCommand("tap alpha".into())),
            // A wake word command is classified the same in a private mode; running it is what differs.
            ("cortana new paragraph", &typing, WakeCommand("new paragraph".into())),
            // Its exits need the wake word only where the mode turned the plain ones off.
            ("cortana done", &typing, WakeExit),
            ("Stop.", &plain, BareExit),
            ("stop", &click, Words),
            ("exit", &typing, Words),
            ("I'm done.", &plain, Exit),
            ("done clicking", &click, Exit),
            ("done", &typing, Words),
            ("rapid mode", &click, Switch("rapid mode")),
            ("rapid mode", &plain, Words),
            ("tap alpha", &click, Words),
        ] {
            assert_eq!(heard(said, mode, &switches), expected, "{said:?}");
        }
    }

    #[test]
    fn a_text_that_names_two_switches_switches_to_neither() {
        let mode = ModeSettings {
            allows_switches: true,
            ..ModeSettings::default()
        };
        let both = ["rapid mode", "rapid mode"];
        assert_eq!(heard("rapid mode", &mode, &both), Heard::Words);
        assert_eq!(
            heard("cortana rapid mode", &mode, &both),
            Heard::WakeCommand("rapid mode".into())
        );
    }

    #[test]
    fn durations_read_in_minutes_when_whole() {
        assert_eq!(duration_words(300), "5 min");
        assert_eq!(duration_words(295), "295 s");
        assert_eq!(duration_words(30), "30 s");
        assert_eq!(duration_words(0), "0 s");
    }
}
