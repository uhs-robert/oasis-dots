//! the voice session file, read and ended but never written: `session.json` under `session.lock` (was
//! `session_locked`, `session_state`, `session_end_all` and `session_run_ended_hook`)
//!
//! Until voxcmd-port 2.4c a session is opened and run by the bash voxcmd; the Rust one only reads the file, to hand a
//! listen over to bash while a session is open, and ends it for `stop` and `session end`. The lock is the bash one's
//! (`flock` on the same file), so either binary may hold it.
use crate::debug::debug;
use crate::notify::{self, Kind};
use crate::paths;
use crate::route::sequence_run::process_start_time;
use serde_json::Value;
use std::fs::File;
use std::os::fd::AsRawFd;
use std::process::{Command, Stdio};

/// The session lock, held until dropped. Every read that may clear the file and every change to it holds it. Opened
/// close-on-exec, so nothing voxcmd starts while holding it keeps it.
pub struct SessionLock {
    _file: File,
}

impl SessionLock {
    pub fn take() -> Self {
        let _ = std::fs::create_dir_all(paths::runtime_dir());
        let file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(paths::session_lock());
        match file {
            Ok(file) => {
                // SAFETY: flock on a descriptor this lock owns; it is released when the file closes.
                unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX) };
                Self { _file: file }
            }
            // A runtime dir that cannot hold the lock cannot hold a session either: reads then find none.
            Err(_) => Self {
                _file: File::open("/dev/null").expect("/dev/null opens"),
            },
        }
    }
}

/// The open session's state, or none when no session is open. A session whose owner has died (its pid gone, or reused
/// by a process that started at another time) is cleared on the way.
pub fn state(_lock: &SessionLock) -> Option<Value> {
    let text = std::fs::read_to_string(paths::session_file()).ok()?;
    let state: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
    let owner = text_of(&state["owner"]);
    let owner_start = text_of(&state["owner_start"]);
    let alive = !owner_start.is_empty()
        && owner
            .parse::<u32>()
            .ok()
            .and_then(process_start_time)
            .is_some_and(|start| start == owner_start);
    if alive {
        return Some(state);
    }
    let owner = if owner.is_empty() { "none" } else { owner.as_str() };
    debug(&format!("session: owner {owner} is gone, clearing"));
    let _ = std::fs::remove_file(paths::session_file());
    None
}

/// A field as `jq -r` prints it: "" for null or absent.
pub fn text_of(value: &Value) -> String {
    match value {
        Value::Null => String::new(),
        Value::String(text) => text.clone(),
        other => other.to_string(),
    }
}

/// A one-recording mode (type mode) whose recording's watcher still owns the session: that recording is the bash
/// voxcmd's to stop and hand over (voxcmd-port 2.4d).
pub fn recording_owner_holds(state: &Value) -> bool {
    state["one_recording"] == Value::Bool(true) && text_of(&state["recording_owner"]) == text_of(&state["owner"])
}

/// One mode of the session: the current one is the top-level fields, those under it are `stack`.
struct Frame {
    integration: String,
    label: Option<String>,
    frame_id: String,
}

fn frames(state: &Value) -> Vec<Frame> {
    let frame = |value: &Value| Frame {
        integration: text_of(&value["integration"]),
        // `.label // "Voice session"`: false counts as absent too.
        label: match &value["label"] {
            Value::Null | Value::Bool(false) => None,
            label => Some(text_of(label)),
        },
        frame_id: text_of(&value["frame_id"]),
    };
    let mut frames: Vec<Frame> = state["stack"]
        .as_array()
        .map(|stack| stack.iter().map(frame).collect())
        .unwrap_or_default();
    frames.push(frame(state));
    frames
}

/// Ends the session and every mode in it, saying why: the file goes, the watcher whose recording is still open is told
/// to drop it (its discard flag), a toast names the bottom mode, and each mode's `session_ended` hook runs, newest
/// first. A no-op when no session is open.
pub fn end_all(reason: &str) {
    let lock = SessionLock::take();
    let Some(state) = state(&lock) else {
        return;
    };
    let frames = frames(&state);
    let _ = std::fs::remove_file(paths::session_file());
    let owner = text_of(&state["owner"]);
    if !owner.is_empty() && owner != std::process::id().to_string() {
        let _ = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(paths::runtime_dir().join(format!("discard.{owner}")));
    }
    debug(&format!("session ended: {reason}"));
    // Released before the hooks start: a hook may read the session, which takes the lock.
    drop(lock);
    if !reason.is_empty() {
        let label = frames[0].label.as_deref().unwrap_or("Voice session");
        notify::notify(Kind::Info, &format!("voxcmd: {label} ended"), reason);
    }
    for frame in frames.iter().rev() {
        run_ended_hook(&frame.integration, reason, &frame.frame_id);
    }
}

/// Runs a popped mode's `session_ended` in the background, through the bash voxcmd that loaded its integration. Its
/// pid is logged: the suites wait for the hook by it.
fn run_ended_hook(integration: &str, reason: &str, frame_id: &str) {
    let mut command = Command::new(paths::legacy_bin());
    command
        .args(["_legacy-hook", "ended", integration, reason, frame_id, "0"])
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    match command.spawn() {
        Ok(hook) => debug(&format!("session: ended hook {} runs", hook.id())),
        Err(error) => debug(&format!("session: cannot run the ended hook of {integration}: {error}")),
    }
}

/// `voxcmd session end`.
pub fn run_end() {
    end_all("ended by request");
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn frames_run_from_the_bottom_mode_to_the_current_one() {
        let state = json!({"kind": "click", "integration": "/i/click.sh", "label": "Click mode", "frame_id": "2",
            "stack": [{"kind": "rapid", "integration": "/i/rapid.sh", "label": "Rapid mode", "frame_id": "1"}]});
        let frames = frames(&state);
        let integrations: Vec<_> = frames.iter().map(|frame| frame.integration.as_str()).collect();
        assert_eq!(integrations, ["/i/rapid.sh", "/i/click.sh"]);
        assert_eq!(frames[0].label.as_deref(), Some("Rapid mode"));
        assert_eq!(frames[1].frame_id, "2");
    }

    #[test]
    fn a_frame_without_a_label_or_id_reads_as_jq_prints_it() {
        let frames = frames(&json!({"integration": "/i/x.sh", "label": null}));
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0].label, None);
        assert_eq!(frames[0].frame_id, "");
    }

    #[test]
    fn only_the_recording_owner_of_a_one_recording_mode_holds_its_recording() {
        assert!(recording_owner_holds(
            &json!({"one_recording": true, "owner": 5, "recording_owner": 5})
        ));
        assert!(!recording_owner_holds(
            &json!({"one_recording": true, "owner": 6, "recording_owner": 5})
        ));
        assert!(!recording_owner_holds(&json!({"owner": 5, "recording_owner": 5})));
    }
}
