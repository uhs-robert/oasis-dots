//! one-recording modes (type mode): how the mode's one recording ended, and what becomes of its text (was
//! `session_ending_action`, `session_record_ending_locked`, `watcher_record_ending`, `dictation_wake_heard`,
//! `dictation_heard_in_locked`, `stop_voice_recording_locked`, `session_cut_ending`, `session_ending_starts`,
//! `session_finish_recording` and `session_leave_recording_mode_locked`)
//!
//! Whoever ends the recording first records how, as the current mode's `.ending` `{action, by}`, under the session
//! lock; the watcher reads it once the transcript is in. `by` is `voice` (the wake word and one of the mode's endings,
//! which voxcmd-wake confirms during the recording), `key` (Stop Voice), or the detector's `cap`, `pause` or `idle`.
//! The voice key stops the recording without an ending, which reads as `{type, voice_key}`. `action` is the ending
//! row's: `discard` cancels the recording, `end_session` ends the session once the text is handled, and any other is
//! handed to the mode's `handle_turn` with the text. An ending followed by "and then" (a chain) is voxcmd-port
//! 2.4d-2's.
//!
//! Nothing here holds the lock while a mode hook runs: typing.sh's `handle_turn` reads the session through the bridge,
//! which takes the lock.
use super::mode::{self, ModeSettings};
use super::turn::{self, NOISE, Outcome, duration_words};
use super::{SessionLock, is_mine, mode_token, text_of};
use crate::debug::debug;
use crate::paths;
use crate::route::pattern::WholeText;
use crate::text::normalize::{Replacements, apply_replacements, normalize};
use crate::text::wake_word::WakeWords;
use crate::voice::{secs_setting, voxtype_record, voxtype_state};
use serde_json::{Value, json};

/// One of a mode's ways to end its recording after the wake word.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Ending {
    pub action: String,
    /// The whole of the words.
    whole: WholeText,
    /// The start of the words, whatever follows: the dictation's own transcriber may hear a word more than the clip's.
    starting: WholeText,
}

impl Ending {
    /// A bash `ending=` row, `<action> <regex>`, split as `read -r action regex` splits it. None when the regex does
    /// not compile, which bash would have matched nothing with either.
    pub fn from_row(row: &str) -> Option<Self> {
        let row = row.trim();
        let (action, body) = row.split_once(char::is_whitespace).unwrap_or((row, ""));
        let body = body.trim_start();
        Some(Self {
            action: action.to_string(),
            whole: WholeText::new(body).ok()?,
            starting: WholeText::new(&format!("(?:{body})(?: .*)?")).ok()?,
        })
    }
}

/// The action of the first ending that is the whole of the normalized words.
pub fn ending_action<'a>(endings: &'a [Ending], words: &str) -> Option<&'a str> {
    endings
        .iter()
        .find(|ending| ending.whole.is_match(words))
        .map(|ending| ending.action.as_str())
}

fn ending_starts(endings: &[Ending], words: &str) -> bool {
    endings.iter().any(|ending| ending.starting.is_match(words))
}

/// jq's truthiness, as `jq -e` tests it.
fn is_set(value: &Value) -> bool {
    !matches!(value, Value::Null | Value::Bool(false))
}

/// Records how the current mode's recording ended, unless an ending is recorded already: the first one wins, and this
/// one then fails.
fn record_ending(lock: &SessionLock, state: &Value, action: &str, by: &str) -> bool {
    if is_set(&state["ending"]) {
        return false;
    }
    super::update(lock, |fields| {
        fields.insert("ending".into(), json!({"action": action, "by": by}));
    });
    true
}

/// `record_ending` from the watcher `me` (its detector's verdict), only while the session is still its own and in the
/// one-recording mode the recording was heard in. False when it did not record it.
pub fn watcher_record_ending(action: &str, by: &str, heard_mode: &str, me: u32) -> bool {
    let lock = SessionLock::take();
    let Some(state) = super::state(&lock).filter(|state| is_mine(state, me)) else {
        return false;
    };
    if state["one_recording"] != Value::Bool(true) || mode_token(&state) != heard_mode {
        return false;
    }
    record_ending(&lock, &state, action, by)
}

/// The wake word, confirmed by voxcmd-wake in a clip cut while a `wake_listens` mode recorded: `after_wake` is the
/// normalized words after its first wake word. When the words after the clip's last wake word are one of the mode's
/// endings, records it and ends the recording: stopped, so the watcher gets the transcript, or cancelled for discard.
/// Any other words leave the recording running.
///
/// Under the lock, only while voxtype records, and only for the recording the trigger was heard in (`heard_in`,
/// `<frame_id>:<owner>:<owner_start>`, which voxcmd-wake read from session.json then: the owner is the watcher of that
/// one recording). So a confirmation that outlasted its recording never ends the next one, and a mode left, a session
/// ended or an ending recorded since the trigger is never ended twice.
pub fn wake_heard(after_wake: &str, heard_in: &str, wake: &WakeWords) {
    let lock = SessionLock::take();
    let Some(state) = heard_in_locked(&lock, heard_in) else {
        return;
    };
    // The clip holds dictation before the trigger too, which may say the wake word: the ending follows the last one.
    let words = wake.after_last(after_wake);
    let mode = ModeSettings::of(&text_of(&state["integration"]));
    let Some(action) = ending_action(&mode.endings, &words) else {
        debug("dictation: the wake word, not an ending");
        return;
    };
    if !record_ending(&lock, &state, action, "voice") {
        return;
    }
    debug(&format!("dictation: ended by voice ({action})"));
    if action == "discard" {
        if let Ok(owner) = text_of(&state["owner"]).parse::<u32>() {
            touch(&paths::discard_flag(owner));
        }
        voxtype_record("cancel", &[]);
    } else {
        voxtype_record("stop", &[]);
    }
}

fn touch(path: &std::path::Path) {
    let _ = std::fs::OpenOptions::new().create(true).append(true).open(path);
}

/// The session, when its mode is a `wake_listens` one, voxtype records, and the recording is the one named.
fn heard_in_locked(lock: &SessionLock, heard_in: &str) -> Option<Value> {
    let state = super::state(lock)?;
    if state["wake_listens"] != Value::Bool(true) || voxtype_state() != "recording" {
        return None;
    }
    let recording = format!(
        "{}:{}:{}",
        text_of(&state["frame_id"]),
        text_of(&state["owner"]),
        text_of(&state["owner_start"])
    );
    if recording != heard_in {
        debug("dictation: the wake word was heard in an earlier recording, not acted on");
        return None;
    }
    Some(state)
}

/// Stop Voice in a one-recording mode whose recording's watcher still owns the session: the recording, if voxtype still
/// records it, stops, and is handled as any ending that keeps it would be; the watcher then ends the session. The
/// watcher's ownership decides, not voxtype's state: once voxtype is idle the watcher may still be reading the
/// transcript, which must not be dropped. An ending already recorded keeps its action, so a cancel stays a cancel and
/// this fails, for Stop Voice to end the session as usual; so it does with no such recording (also before the mode's
/// recording has started, while the turn that opened the mode still owns the session).
pub fn stop_recording_locked(lock: &SessionLock) -> bool {
    let Some(state) = super::state(lock).filter(super::recording_owner_holds) else {
        return false;
    };
    if !record_ending(lock, &state, "type", "key") {
        if text_of(&state["ending"]["action"]) == "discard" {
            return false;
        }
        super::update(lock, |fields| {
            if let Some(Value::Object(ending)) = fields.get_mut("ending") {
                ending.insert("by".into(), json!("key"));
            }
        });
    }
    debug(&format!(
        "stop: the {} recording is handled, then the session ends",
        text_of(&state["kind"])
    ));
    if voxtype_state() == "recording" {
        voxtype_record("stop", &[]);
    }
    true
}

/// The transcript without the ending spoken at its end: from the last wake word on, when what follows it starts with
/// one of the endings ("...the plan. Cortana, stop." or "Cortana stop typing."). The wake word elsewhere ("I asked
/// Cortana about it") is text.
fn cut_ending(transcript: &str, endings: &[Ending], wake: &WakeWords, replacements: &Replacements) -> String {
    if let Some((before, rest)) = wake.split_trailing(transcript)
        && ending_starts(endings, &apply_replacements(&rest, replacements))
    {
        return before;
    }
    match wake.split_leading(&normalize(transcript)) {
        Some(rest) if ending_starts(endings, &apply_replacements(&rest, replacements)) => String::new(),
        _ => transcript.to_string(),
    }
}

/// The current mode's one recording is over (`discarded` when it was cancelled or heard no speech). Hands its text, cut
/// of the ending, to the mode with the ending's action, then leaves the mode (or ends the session) saying why, and the
/// mode underneath listens on. Nothing is handed over when it was discarded or cancelled, or heard only noise.
pub fn finish_recording(transcript: &str, discarded: bool, heard_mode: &str, replacements: &Replacements, me: u32) {
    let Some(state) = super::read_state().filter(|state| is_mine(state, me)) else {
        return;
    };
    let file = text_of(&state["integration"]);
    let kind = text_of(&state["kind"]);
    let mode = ModeSettings::of(&file);
    let (action, by) = if is_set(&state["ending"]) {
        (text_of(&state["ending"]["action"]), text_of(&state["ending"]["by"]))
    } else {
        ("type".to_string(), "voice_key".to_string())
    };
    debug(&format!("session: the {kind} recording ended ({by}, {action})"));
    let mut text = String::new();
    if action != "discard" && !discarded {
        text = cut_ending(transcript, &mode.endings, &WakeWords::from_env(), replacements);
        if NOISE.is_match(&normalize(&text)) {
            text.clear();
        }
    }
    if !text.is_empty() {
        mode::handle_turn(&file, &text, Some(&action), heard_mode);
    }
    // The mode is left first, so a chain after the ending (2.4d-2) runs as it would after "cortana stop typing", and
    // not at all when Stop Voice ended the session meanwhile.
    leave_recording_mode(&kind, &action, &mode, me);
    turn::continue_turns(Outcome::Ran, me);
}

/// Leaves the one-recording mode saying why, or ends the session. The ending's `by` is read again here, under the lock:
/// Stop Voice may have made it `key` while the text was handled. False when Stop Voice (or anything else) ended the
/// session, left the mode or made the ending a key one.
fn leave_recording_mode(kind: &str, action: &str, mode: &ModeSettings, me: u32) -> bool {
    let lock = SessionLock::take();
    let Some(state) = super::state(&lock).filter(|state| is_mine(state, me)) else {
        return false;
    };
    let by = match text_of(&state["ending"]["by"]) {
        by if by.is_empty() => "voice_key".to_string(),
        by => by,
    };
    let own_or = |own: &str, name: &str, default: &str| {
        if own.is_empty() {
            secs_setting(name, default)
        } else {
            own.to_string()
        }
    };
    let reason = if action == "discard" {
        "cancelled, nothing typed".to_string()
    } else if by == "key" || action == "end_session" {
        super::end_all_locked(&lock, "stopped", me);
        return by != "key";
    } else {
        match by.as_str() {
            "cap" => format!("it reached its recording limit ({})", secs_words(&mode.listen_max_secs)),
            "pause" => format!(
                "typed after {} of quiet",
                secs_words(&own_or(&mode.listen_silence_secs, "VOXCMD_SESSION_SILENCE_SECS", "1.5"))
            ),
            "idle" => format!(
                "nothing was said for {}",
                secs_words(&own_or(
                    &mode.listen_no_speech_secs,
                    "VOXCMD_SESSION_NO_SPEECH_SECS",
                    "10"
                ))
            ),
            _ => "done".to_string(),
        }
    };
    super::leave(&lock, kind, &reason, me) && by != "key"
}

/// A setting in seconds as `duration_words` says it. bash's arithmetic failed on one that is no whole number (the
/// reason then lost its number); it is said as written instead.
fn secs_words(secs: &str) -> String {
    secs.parse::<i64>().map_or_else(|_| format!("{secs} s"), duration_words)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// typing.sh's rows as `_legacy-hook mode-settings` prints them.
    const TYPING_ROWS: &str = "\
type        stop|stop typing|stop recording|done|im done|thats all|((okay|ok|alright|please|now) )*((stop|exit|quit|end|leave|finish|close|turn off|switch off) (the )?(typing|typing mode|type mode|dictation|dictation mode)|(the )?(typing|typing mode|type mode|dictation|dictation mode) off)( (okay|ok|alright|please|now))*|(im )?done typing|done with (the )?(typing|typing mode|type mode|dictation|dictation mode)
send        send|send it|send (the |a )?message|press enter
discard     cancel|never ?mind
end_session stop listening|stop everything|end session|end the session";

    fn typing_endings() -> Vec<Ending> {
        TYPING_ROWS.lines().map(|row| Ending::from_row(row).unwrap()).collect()
    }

    #[test]
    fn the_first_row_whose_regex_is_the_whole_of_the_words_names_the_action() {
        let endings = typing_endings();
        for (words, action) in [
            ("stop", Some("type")),
            ("stop typing", Some("type")),
            ("stop dictation", Some("type")),
            ("okay close the typing mode please", Some("type")),
            ("done", Some("type")),
            ("im done typing", Some("type")),
            ("send", Some("send")),
            ("send the message", Some("send")),
            ("press enter", Some("send")),
            ("cancel", Some("discard")),
            ("nevermind", Some("discard")),
            ("never mind", Some("discard")),
            ("stop listening", Some("end_session")),
            ("end the session", Some("end_session")),
            // Anchored at both ends: more words, or fewer, are no ending.
            ("stop now", None),
            ("please stop", None),
            ("stop and then tap", None),
            ("new paragraph", None),
            ("", None),
        ] {
            assert_eq!(ending_action(&endings, words), action, "{words:?}");
        }
        // The first row wins where two match.
        let both = [
            Ending::from_row("first stop|go").unwrap(),
            Ending::from_row("second stop").unwrap(),
        ];
        assert_eq!(ending_action(&both, "stop"), Some("first"));
    }

    #[test]
    fn a_row_splits_as_bash_read_splits_it() {
        let ending = Ending::from_row("  send   send it  ").unwrap();
        assert_eq!(ending.action, "send");
        assert!(ending.whole.is_match("send it"));
        // A row with no regex matches only nothing; one that does not compile is dropped.
        assert!(Ending::from_row("type").unwrap().whole.is_match(""));
        assert!(Ending::from_row("type stop(").is_none());
    }

    #[test]
    fn the_ending_is_cut_from_the_last_wake_word_and_the_wake_word_elsewhere_is_text() {
        let endings = typing_endings();
        let wake = WakeWords::new("kortana|cortona");
        let none = Replacements::default();
        let cut = |transcript: &str| cut_ending(transcript, &endings, &wake, &none);
        assert_eq!(cut("Hello world. Cortana, stop."), "Hello world.");
        assert_eq!(
            cut("I asked Cortana about it. Cortana, stop."),
            "I asked Cortana about it."
        );
        assert_eq!(cut("I asked Cortana about it."), "I asked Cortana about it.");
        // The transcriber may hear a word more after the ending than the clip did.
        assert_eq!(cut("Ship it. Cortana, send it now."), "Ship it.");
        assert_eq!(cut("Cortana stop typing."), "");
        assert_eq!(cut("Cortana, new paragraph."), "Cortana, new paragraph.");
        assert_eq!(
            cut("Hello. Cortana new paragraph. More."),
            "Hello. Cortana new paragraph. More."
        );
    }

    #[test]
    fn a_setting_that_is_no_whole_number_is_said_as_written() {
        assert_eq!(secs_words("295"), "295 s");
        assert_eq!(secs_words("60"), "1 min");
        assert_eq!(secs_words("1.5"), "1.5 s");
    }
}
