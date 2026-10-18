//! `voxcmd listen [--start-only]`: the voice key. Stops voxtype while it records; from idle, starts a recording into
//! the transcript file and leaves a detached watcher (`internal watch`) to route the transcript, or to reply with it
//! when an ask is waiting (was `listen` and `listen_locked`)
//!
//! While a voice session is open the bash voxcmd listens instead, since it runs the session's turns until
//! voxcmd-port 2.4c. The whole listen holds the session lock, so a voice key pressed during a session turn and that
//! turn's own next listen never both start a recording.
use super::{secs_setting, voxtype_record, voxtype_state};
use crate::ask;
use crate::debug::debug;
use crate::exit::CliError;
use crate::notify::{self, Kind};
use crate::paths;
use crate::session::{self, SessionLock};
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
}

impl Handler {
    pub fn name(self) -> &'static str {
        match self {
            Self::Route => "route",
            Self::Reply => "reply",
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
    let lock = SessionLock::take();
    let state = voxtype_state();
    if state == "idle" && session::state(&lock).is_some() {
        drop(lock);
        return bash_listens(start_only, owner_file);
    }
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
    let handler = if ask::read_pending().is_some() {
        Handler::Reply
    } else {
        Handler::Route
    };
    let _ = std::fs::remove_file(paths::transcript());
    let file_arg = format!("--file={}", paths::transcript().display());
    if !voxtype_record("start", &[&file_arg]) {
        notify::notify(Kind::Error, "voxcmd error", "voxtype record start failed");
        return false;
    }
    let started = start_watcher(handler, owner_file);
    drop(lock);
    started
}

/// `$VOXCMD_RECORDING_OWNER_FILE`, set by an ask for its reply recording's listen and passed on to its watcher.
pub fn inherited_owner_file() -> Option<PathBuf> {
    std::env::var_os("VOXCMD_RECORDING_OWNER_FILE")
        .filter(|file| !file.is_empty())
        .map(PathBuf::from)
}

/// The session's own listen, by the bash voxcmd, which takes the session lock again.
fn bash_listens(start_only: bool, owner_file: Option<&Path>) -> bool {
    let mut command = Command::new(paths::legacy_bin());
    command.arg("listen").stdin(Stdio::null());
    if start_only {
        command.arg("--start-only");
    }
    if let Some(owner_file) = owner_file {
        command.env("VOXCMD_RECORDING_OWNER_FILE", owner_file);
    }
    command.status().is_ok_and(|status| status.success())
}

/// Starts `internal watch` through the `setsid` binary, so the watcher outlives this listen and the terminal or key
/// binding that ran it; the suites log and stub that `setsid` call.
fn start_watcher(handler: Handler, owner_file: Option<&Path>) -> bool {
    let mut command = Command::new("setsid");
    command
        .arg(ask::this_binary())
        .args(["internal", "watch", handler.name(), "-", "0"])
        .arg(autostop_settings(handler))
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
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
            true
        }
        Err(error) => {
            // Nobody would hear this recording, and it would keep the microphone open.
            debug(&format!("listen: cannot start the watcher: {error}"));
            voxtype_record("cancel", &[]);
            notify::notify(Kind::Error, "voxcmd error", "the listener could not start");
            false
        }
    }
}

/// The auto-stop settings (`VAR=value` lines) for the watcher's detector. Computed here and passed as an argument, as
/// the bash listen did, so the detector starts with the recording; not as an environment, which the watcher's turn
/// would pass on to the overlay and pickers it starts. A reply has a lower speech minimum: "yes" is short.
pub fn autostop_settings(handler: Handler) -> String {
    match handler {
        Handler::Route => String::new(),
        Handler::Reply => format!(
            "VOXCMD_AUTOSTOP_MIN_SPEECH_SECS={}",
            secs_setting("VOXCMD_REPLY_MIN_SPEECH_SECS", "0.1")
        ),
    }
}
