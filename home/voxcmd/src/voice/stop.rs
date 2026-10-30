//! `voxcmd stop`, Stop Voice: the one key for any voice activity that will not end by itself (was `stop_voice`)
//!
//! The session goes first, so its watcher cannot open the microphone again: ending it flags the watcher's recording as
//! discarded, whatever the watcher is doing. Then every running sequence is flagged, the waiting ask is cancelled, and
//! whatever voxtype still records or transcribes is cancelled. A one-recording mode's recording (type mode's
//! dictation) is the exception: it is stopped and typed, and its watcher ends the session
//! (`session::dictation::stop_recording_locked`). A picker the bar published is cancelled only while a reply recording
//! is attached to it: one opened by key is the user's, not voice activity.
use super::{voxtype_record, voxtype_state};
use crate::ask;
use crate::debug::debug;
use crate::exit::CliError;
use crate::paths;
use crate::route::sequence_run::process_start_time;
use crate::session::{self, SessionLock, dictation, text_of};
use std::os::unix::ffi::OsStrExt;

pub fn run() -> Result<(), CliError> {
    if dictation::stop_recording_locked(&SessionLock::take()) {
        return Ok(());
    }
    session::end_all("stopped", std::process::id());
    // Before the ask is cancelled, so the sequence it was asking for reads that answer as Stop Voice's.
    for pid in running_sequence_pids() {
        let _ = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(paths::discard_flag(pid));
    }
    if let Some(pending) = ask::read_pending() {
        match (pending.owner, &pending.fifo) {
            (ask::Owner::Ask, Some(fifo)) => {
                ask::write_answer(fifo, "");
            }
            (ask::Owner::Bar, _) if reply_watcher_running_for(&pending) => {
                let token = pending.token.clone().unwrap_or_default();
                debug("stop: cancelling the bar's picker, which a reply recording was answering");
                ask::qs_ipc_call(&["picker".as_ref(), "cancel".as_ref(), token.as_ref()]);
            }
            _ => {}
        }
    }
    // Under the lock a listen holds while it starts a recording, so a voice key pressed just before this is either
    // cancelled here or starts after it, never between the look and the cancel.
    let _lock = SessionLock::take();
    let state = voxtype_state();
    if state == "recording" || state == "transcribing" {
        debug(&format!("stop: cancelling the {state} voxtype"));
        voxtype_record("cancel", &[]);
    }
    Ok(())
}

/// A listen's watcher that will hand its transcript to `reply` is running for this user's voxcmd and answers `pending`:
/// the pending pick has a reply recording attached. A watcher pinned to an earlier pick (the bar reopened its picker)
/// is not attached to this one, since its reply is refused. The watcher outlives the recording while it hands the
/// answer over, which also counts.
/// Matched by `XDG_RUNTIME_DIR` too, so a sandbox or a parallel suite's watcher is not taken for this one's.
fn reply_watcher_running_for(pending: &ask::PendingPick) -> bool {
    let Ok(entries) = std::fs::read_dir("/proc") else {
        return false;
    };
    let runtime_dir = paths::user_runtime_dir();
    entries.flatten().any(|entry| {
        let proc_dir = entry.path();
        std::fs::read(proc_dir.join("cmdline")).is_ok_and(|cmdline| is_reply_watcher_for(&cmdline, pending))
            && std::fs::read(proc_dir.join("environ")).is_ok_and(|environ| runtime_dir_of(&environ) == runtime_dir)
    })
}

/// `<voxcmd> internal watch reply <token> <private> <settings> [pin]`, as `listen` starts it, unpinned or pinned to
/// `pending`.
fn is_reply_watcher_for(cmdline: &[u8], pending: &ask::PendingPick) -> bool {
    let mut args = cmdline.split(|&byte| byte == 0);
    let program = args.next().unwrap_or_default();
    let name = program.rsplit(|&byte| byte == b'/').next().unwrap_or_default();
    let is_reply = name.starts_with(b"voxcmd") && args.by_ref().take(3).eq([&b"internal"[..], b"watch", b"reply"]);
    // After the handler: token, private flag, detector settings, then the pin.
    is_reply
        && args.nth(3).filter(|pin| !pin.is_empty()).is_none_or(|pin| {
            std::str::from_utf8(pin)
                .ok()
                .and_then(ask::PickId::parse)
                .is_some_and(|pin| pin.matches(pending))
        })
}

/// The `XDG_RUNTIME_DIR` a process started with, `/tmp` when unset or empty, as `paths::user_runtime_dir` reads it.
fn runtime_dir_of(environ: &[u8]) -> std::path::PathBuf {
    let value = environ
        .split(|&byte| byte == 0)
        .find_map(|entry| entry.strip_prefix(b"XDG_RUNTIME_DIR="))
        .filter(|value| !value.is_empty());
    value.map_or_else(
        || "/tmp".into(),
        |value| std::path::PathBuf::from(std::ffi::OsStr::from_bytes(value)),
    )
}

/// The pid of each sequence running now. A record whose process is gone, or is another one under a reused pid (its
/// start time differs), is stale and removed.
fn running_sequence_pids() -> Vec<u32> {
    let Ok(entries) = std::fs::read_dir(paths::sequence_dir()) else {
        return Vec::new();
    };
    let mut running = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().is_none_or(|extension| extension != "json") {
            continue;
        }
        let record: serde_json::Value = std::fs::read_to_string(&path)
            .ok()
            .and_then(|text| serde_json::from_str(&text).ok())
            .unwrap_or_default();
        let pid = text_of(&record["pid"]).parse::<u32>().ok();
        let start = text_of(&record["start"]);
        match pid {
            Some(pid) if process_start_time(pid).is_some_and(|now| now == start) => running.push(pid),
            _ => {
                let _ = std::fs::remove_file(&path);
            }
        }
    }
    running
}
