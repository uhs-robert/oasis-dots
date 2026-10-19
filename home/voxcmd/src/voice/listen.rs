//! `voxcmd listen [--start-only]`: the voice key. Stops voxtype while it records; from idle, starts a recording into
//! the transcript file and leaves a detached watcher (`internal watch`) to route the transcript, to reply with it when
//! an ask is waiting, or to hear it as the open session's next turn (was `listen` and `listen_locked`)
//!
//! The whole listen holds the session lock, so a voice key pressed during a session turn and that turn's own next
//! listen never both start a recording. A voice key during a session takes it over: its watcher hears the next turn.
use super::{secs_setting, voxtype_record, voxtype_state};
use crate::ask;
use crate::debug::debug;
use crate::exit::CliError;
use crate::notify::{self, Kind};
use crate::paths;
use crate::session::mode::ModeSettings;
use crate::session::{self, SessionLock, bridge, text_of};
use serde_json::Value;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// What the watcher does with the transcript.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Handler {
    /// Route it as a command.
    Route,
    /// Answer the waiting ask with it.
    Reply,
    /// Hear it as the open session's next turn.
    SessionTurn,
}

impl Handler {
    pub fn name(self) -> &'static str {
        match self {
            Self::Route => "route",
            Self::Reply => "reply",
            Self::SessionTurn => "session_turn",
        }
    }
}

/// `voxcmd listen [--start-only]`. Exit 1 when no recording could be started or stopped (with `--start-only`, also
/// when voxtype was not idle).
pub fn run(start_only: bool) -> Result<(), CliError> {
    if listen(start_only, None) {
        Ok(())
    } else {
        Err(CliError::quiet("listen"))
    }
}

/// `listen --start-only` for an ask's reply recording, in this process: only from idle, never stopping a recording
/// someone else started (a confirm card's recording must not end one the user is making). With an owner file, the
/// watcher keeps its pid there while it owns the recording; without one, the watcher inherits this process's
/// `VOXCMD_RECORDING_OWNER_FILE`, as the bash listen's global did.
pub fn start_only(owner_file: Option<&Path>) -> bool {
    listen(true, owner_file)
}

fn listen(start_only: bool, owner_file: Option<&Path>) -> bool {
    listen_locked(&SessionLock::take(), start_only, owner_file, std::process::id())
}

/// The session's watcher to be, as the listen chose it.
struct SessionListen {
    /// What the recording is heard in (`session::mode_token`).
    token: String,
    mode: ModeSettings,
}

/// `listen` under a session lock the caller holds; `me` is the process the listen is for, which a session's own listen
/// hands the session from.
pub fn listen_locked(lock: &SessionLock, start_only: bool, owner_file: Option<&Path>, me: u32) -> bool {
    let state = voxtype_state();
    let for_reply = owner_file.is_some() || inherited_owner_file().is_some();
    debug(&format!(
        "listen: voxtype {state}{}{}",
        if for_reply { ", for a reply" } else { "" },
        if start_only { ", start only" } else { "" }
    ));
    if start_only && state != "idle" {
        return false;
    }
    match state.as_str() {
        "recording" => return voxtype_record("stop", &[]),
        // The transcript is already on its way to its owner.
        "transcribing" => return true,
        "idle" => {}
        _ => {
            notify::notify(Kind::Error, "voxcmd", &format!("voxtype is not ready ({state})"));
            return false;
        }
    }
    let _ = std::fs::create_dir_all(paths::runtime_dir());
    let mut session_listen = None;
    let handler = match session::state(lock) {
        Some(session) => {
            if recording_transcript_pending(&session, me) {
                // A new recording would take the transcript file and the session from the watcher still to type it.
                debug("listen: a one-recording mode's watcher still has its transcript to hand over, not listening");
                let label = text_of(&session["label"]);
                notify::notify(Kind::Info, &format!("voxcmd: {label}"), "Still typing what was said");
                return false;
            }
            let mode = ModeSettings::of(&text_of(&session["integration"]));
            // A mode that takes the words itself or keeps them private (type mode) never has its dictation read as a
            // reply to an ask, which would log the words and could answer a card with them.
            if ask::read_pending().is_some() && !mode.private && !mode.has_handler {
                Handler::Reply
            } else {
                session_listen = Some(SessionListen {
                    token: session::mode_token(&session),
                    mode,
                });
                Handler::SessionTurn
            }
        }
        None if ask::read_pending().is_some() => Handler::Reply,
        None => Handler::Route,
    };
    let _ = std::fs::remove_file(paths::transcript());
    // From the recording's start until its watcher is the owner, session.json still names the watcher before it, so
    // voxcmd-wake would name that one as the recording a trigger was heard in; owner_handover tells it to wait.
    if session_listen.is_some() {
        session::update(lock, |fields| {
            fields.insert("owner_handover".into(), Value::Bool(true));
        });
    }
    let file_arg = format!("--file={}", paths::transcript().display());
    if !voxtype_record("start", &[&file_arg]) {
        notify::notify(Kind::Error, "voxcmd error", "voxtype record start failed");
        return false;
    }
    let Some(watcher) = start_watcher(handler, session_listen.as_ref(), owner_file) else {
        return false;
    };
    if session_listen.is_some() {
        session::set_owner(lock, watcher);
    }
    true
}

/// A one-recording mode's recording is over (voxtype is idle when this is asked) and its watcher, some process other
/// than `me`, still owns the session: the transcript it wrote is not handled yet. Its own listen, after a turn heard
/// in another mode, may go on.
fn recording_transcript_pending(state: &Value, me: u32) -> bool {
    session::recording_owner_holds(state) && !session::is_mine(state, me)
}

/// `$VOXCMD_RECORDING_OWNER_FILE`, set by an ask for its reply recording's listen and passed on to its watcher.
pub fn inherited_owner_file() -> Option<PathBuf> {
    std::env::var_os("VOXCMD_RECORDING_OWNER_FILE")
        .filter(|file| !file.is_empty())
        .map(PathBuf::from)
}

/// Starts the watcher through the `setsid` binary, so it outlives this listen and the terminal or key binding that ran
/// it; the suites log and stub that `setsid` call. The session lock is close-on-exec, so the watcher never holds it.
/// Its pid, none when it could not start.
fn start_watcher(handler: Handler, session_listen: Option<&SessionListen>, owner_file: Option<&Path>) -> Option<u32> {
    let mut command = Command::new("setsid");
    command.arg(ask::this_binary()).args(["internal", "watch"]);
    let (token, private) = session_listen.map_or(("-", false), |listen| (listen.token.as_str(), listen.mode.private));
    command
        .args([handler.name(), token, if private { "1" } else { "0" }])
        .arg(autostop_settings(handler, session_listen.map(|listen| &listen.mode)))
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    bridge::clear_hook_env(&mut command);
    if let Some(owner_file) = owner_file {
        command.env("VOXCMD_RECORDING_OWNER_FILE", owner_file);
    }
    // An ask holding its stop signals, or a caller that ignores them, must not leave the watcher deaf to Stop Voice's
    // TERM: exec keeps a blocked mask and an ignored signal.
    // SAFETY: sigprocmask and signal are async-signal-safe and touch only the child.
    unsafe {
        command.pre_exec(|| {
            let mut stop_set: libc::sigset_t = std::mem::zeroed();
            libc::sigemptyset(&mut stop_set);
            for signal in [libc::SIGINT, libc::SIGTERM, libc::SIGHUP] {
                libc::signal(signal, libc::SIG_DFL);
                libc::sigaddset(&mut stop_set, signal);
            }
            libc::sigprocmask(libc::SIG_UNBLOCK, &stop_set, std::ptr::null_mut());
            Ok(())
        });
    }
    match command.spawn() {
        Ok(watcher) => {
            debug(&format!(
                "listen: recording started, watcher {} will {}",
                watcher.id(),
                handler.name()
            ));
            Some(watcher.id())
        }
        Err(error) => {
            // Nobody would hear this recording, and it would keep the microphone open.
            debug(&format!("listen: cannot start the watcher: {error}"));
            voxtype_record("cancel", &[]);
            notify::notify(Kind::Error, "voxcmd error", "the listener could not start");
            None
        }
    }
}

/// The auto-stop settings (`VAR=value` lines) for the watcher's detector. Computed here and passed as an argument, as
/// the bash listen did, so the detector starts with the recording; not as an environment, which the watcher's turn
/// would pass on to the overlay and pickers it starts. A reply has a lower speech minimum: "yes" is short. A session
/// listens unprompted, mostly to the room, so it wants more speech and a longer pause than a command, and the mode may
/// set its own (type mode's, which also cuts a long speech at its max).
pub fn autostop_settings(handler: Handler, mode: Option<&ModeSettings>) -> String {
    let or_session = |own: Option<&String>, name: &str, default: &str| match own {
        Some(own) if !own.is_empty() => own.clone(),
        _ => secs_setting(name, default),
    };
    match handler {
        Handler::Route => String::new(),
        Handler::Reply => format!(
            "VOXCMD_AUTOSTOP_MIN_SPEECH_SECS={}",
            secs_setting("VOXCMD_REPLY_MIN_SPEECH_SECS", "0.1")
        ),
        Handler::SessionTurn => {
            let mut settings = format!(
                "VOXCMD_AUTOSTOP_NO_SPEECH_SECS={}\nVOXCMD_AUTOSTOP_MIN_SPEECH_SECS={}\nVOXCMD_AUTOSTOP_SILENCE_SECS={}",
                or_session(
                    mode.map(|mode| &mode.listen_no_speech_secs),
                    "VOXCMD_SESSION_NO_SPEECH_SECS",
                    "10"
                ),
                secs_setting("VOXCMD_SESSION_MIN_SPEECH_SECS", "0.4"),
                or_session(
                    mode.map(|mode| &mode.listen_silence_secs),
                    "VOXCMD_SESSION_SILENCE_SECS",
                    "1.5"
                ),
            );
            if let Some(max) = mode.map(|mode| &mode.listen_max_secs).filter(|max| !max.is_empty()) {
                settings.push_str(&format!("\nVOXCMD_AUTOSTOP_MAX_SECS={max}"));
            }
            settings
        }
    }
}
