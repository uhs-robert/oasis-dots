//! `voxcmd stop`, Stop Voice: the one key for any voice activity that will not end by itself (was `stop_voice`)
//!
//! The session goes first, so its watcher cannot open the microphone again: ending it flags the watcher's recording as
//! discarded, whatever the watcher is doing. Then every running sequence is flagged, the waiting ask is cancelled, and
//! whatever voxtype still records or transcribes is cancelled. A one-recording mode's recording (type mode's
//! dictation) is the exception: it is stopped and typed, and its watcher ends the session
//! (`session::dictation::stop_recording_locked`).
use super::{voxtype_record, voxtype_state};
use crate::ask;
use crate::debug::debug;
use crate::exit::CliError;
use crate::paths;
use crate::route::sequence_run::process_start_time;
use crate::session::{self, SessionLock, dictation, text_of};

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
        ask::write_answer(&pending.fifo, "");
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
