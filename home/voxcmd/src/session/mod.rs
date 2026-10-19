//! the voice session file, `session.json` under `session.lock`: reading it, the modes stacked in it, and every change
//! to it (was `session_locked`, `session_state`, `session_update`, `session_set_owner`, `session_create`,
//! `session_enter/push/truncate/leave/end`, `session_end_all`, `session_end_if_mine` and `session_run_ended_hook`)
//!
//! The lock is the bash one's (`flock` on the same file), so either binary may hold it: until voxcmd-port 3.2 the
//! installed bash voxcmd and voxcmd-wake still act on a session the Rust port opened, and the reverse. The file stays a
//! `serde_json::Value`, so fields this port does not know are kept, and it is replaced whole (written beside it, then
//! renamed), so the bar never reads half of it.
//! "Mine" is a pid the caller names: the watcher's own, or the Rust process a bash hook was run from (`bridge.rs`).
pub mod bridge;
pub mod dictation;
pub mod mode;
pub mod turn;

use crate::debug::debug;
use crate::notify::{self, Kind};
use crate::paths;
use crate::route::sequence_run::process_start_time;
use mode::ModeSettings;
use serde_json::{Map, Value, json};
use std::fs::File;
use std::os::fd::AsRawFd;
use std::process::{Command, Stdio};

/// The session lock, held until dropped. Every read that may clear the file and every change to it holds it. Opened
/// close-on-exec, so nothing voxcmd starts while holding it keeps it.
pub struct SessionLock {
    _file: Option<File>,
}

impl SessionLock {
    pub fn take() -> Self {
        let _ = std::fs::create_dir_all(paths::runtime_dir());
        let file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(paths::session_lock());
        // A runtime dir that cannot hold the lock cannot hold a session either: reads then find none.
        let Ok(file) = file else {
            return Self { _file: None };
        };
        // SAFETY: flock on a descriptor this lock owns; it is released when the file closes.
        unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX) };
        if crate::process::last_act_runs_elsewhere() {
            // A stop signal's last act ends the session next; it takes the lock once this lets it go.
            drop(file);
            crate::process::wait_for_last_act();
        }
        Self { _file: Some(file) }
    }

    /// The lock a hook's caller holds while the hook runs (`bridge::lock_held_by_caller`): taking it again here would
    /// wait for the caller, which waits for the hook.
    pub fn held_by_caller() -> Self {
        Self { _file: None }
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

/// `state` under a lock of its own, released on return.
pub fn read_state() -> Option<Value> {
    state(&SessionLock::take())
}

/// A field as `jq -r` prints it: "" for null or absent.
pub fn text_of(value: &Value) -> String {
    match value {
        Value::Null => String::new(),
        Value::String(text) => text.clone(),
        other => other.to_string(),
    }
}

/// Whether this process (`me`) owns the session: it hears the next turn.
pub fn is_mine(state: &Value, me: u32) -> bool {
    text_of(&state["owner"]) == me.to_string()
}

/// A one-recording mode (type mode) whose recording's watcher still owns the session: that watcher still has the
/// recording's transcript to hand over.
pub fn recording_owner_holds(state: &Value) -> bool {
    state["one_recording"] == Value::Bool(true) && text_of(&state["recording_owner"]) == text_of(&state["owner"])
}

/// What a recording is heard in, `<modes open>:<kind on top>:<its frame_id>`: a transcript that arrives under another
/// is not for the mode the session is in by then.
pub fn mode_token(state: &Value) -> String {
    let depth = state["stack"].as_array().map_or(0, Vec::len) + 1;
    format!("{depth}:{}:{}", text_of(&state["kind"]), text_of(&state["frame_id"]))
}

fn now_secs() -> i64 {
    jiff::Timestamp::now().as_second()
}

/// A number field, or `default` where jq's `// default` would take it (absent or null).
fn number_or(value: &Value, default: i64) -> i64 {
    value
        .as_i64()
        .or_else(|| value.as_f64().map(|float| float as i64))
        .unwrap_or(default)
}

/// Replaces the file whole, as one compact line.
fn write(state: &Value) {
    let file = paths::session_file();
    let temporary = file.with_extension(format!("json.{}", std::process::id()));
    if std::fs::write(&temporary, state.to_string()).is_ok() {
        let _ = std::fs::rename(&temporary, &file);
    }
}

/// Edits the open session in place; under the lock, so it never recreates one that ended meanwhile.
pub fn update(_lock: &SessionLock, edit: impl FnOnce(&mut Map<String, Value>)) {
    let Ok(text) = std::fs::read_to_string(paths::session_file()) else {
        return;
    };
    match serde_json::from_str::<Value>(&text) {
        Ok(Value::Object(mut fields)) => {
            edit(&mut fields);
            write(&Value::Object(fields));
        }
        _ => debug("session: could not update the state"),
    }
}

/// The watcher with this pid hears the next turn. A one-recording mode's `recording_owner` is the watcher of its one
/// recording, which still has its transcript to hand over for as long as it owns the session in that mode.
pub fn set_owner(lock: &SessionLock, pid: u32) {
    update(lock, |fields| {
        fields.insert("owner".into(), json!(pid));
        fields.insert("owner_start".into(), json!(process_start_time(pid).unwrap_or_default()));
        fields.remove("owner_handover");
        if fields.get("one_recording") == Some(&Value::Bool(true)) {
            fields.insert("recording_owner".into(), json!(pid));
        }
    });
}

/// `<epoch secs>-<random>`: names a mode for as long as it is open.
fn new_frame_id() -> String {
    let nanos = jiff::Timestamp::now().as_nanosecond();
    let random = (nanos as u64 ^ u64::from(std::process::id()).rotate_left(32)) % 1_000_000_000;
    format!("{}-{random}", now_secs())
}

/// The fields of a mode that are its own, as the current mode holds them beside `stack` (bash `def frame`); one it
/// lacks is null.
const FRAME_FIELDS: [&str; 12] = [
    "kind",
    "integration",
    "label",
    "exit_hint",
    "unclear",
    "mode_started",
    "open_ended",
    "one_recording",
    "wake_listens",
    "frame_id",
    "active_secs",
    "resumes",
];

fn current_frame(state: &Value) -> Map<String, Value> {
    FRAME_FIELDS
        .iter()
        .map(|field| (field.to_string(), state[field].clone()))
        .collect()
}

/// The modes of a session, bottom first: those under the current one (`stack`), then the current one.
fn frames(state: &Value) -> Vec<Value> {
    let mut frames = state["stack"].as_array().cloned().unwrap_or_default();
    frames.push(Value::Object(current_frame(state)));
    frames
}

/// The position (bottom first) of the topmost mode of that kind.
fn frame_index(state: &Value, kind: &str) -> Option<usize> {
    frames(state).iter().rposition(|frame| text_of(&frame["kind"]) == kind)
}

/// `.label // "Voice session"`: false counts as absent too.
fn label_of(frame: &Value) -> String {
    match &frame["label"] {
        Value::Null | Value::Bool(false) => "Voice session".to_string(),
        label => text_of(label),
    }
}

/// The true-or-false fields a mode's frame takes from its settings.
fn insert_flags(fields: &mut Map<String, Value>, mode: &ModeSettings) {
    fields.insert("open_ended".into(), json!(mode.open_ended));
    fields.insert("one_recording".into(), json!(mode.one_recording));
    fields.insert("wake_listens".into(), json!(mode.wake_listens));
}

/// Opens a session in the mode, owned by `me`; fails when one is open already.
pub fn create(lock: &SessionLock, kind: &str, file: &str, label: &str, me: u32) -> bool {
    if state(lock).is_some() {
        return false;
    }
    let mode = ModeSettings::of(file);
    let now = now_secs();
    let mut fields = Map::new();
    for (key, value) in [
        ("kind", json!(kind)),
        ("integration", json!(file)),
        ("label", json!(label)),
        ("exit_hint", json!(mode.exit_hint_or_default())),
        ("started", json!(now)),
        ("owner", json!(me)),
        ("owner_start", json!(process_start_time(me).unwrap_or_default())),
        ("unclear", json!(0)),
        ("turns", json!(0)),
        ("mode_started", json!(now)),
        ("last_heard", json!(now)),
        ("frame_id", json!(new_frame_id())),
        ("active_secs", json!(0)),
        ("resumes", json!(0)),
    ] {
        fields.insert(key.into(), value);
    }
    insert_flags(&mut fields, &mode);
    fields.insert("stack".into(), json!([]));
    write(&Value::Object(fields));
    true
}

/// What opening a mode did, so that a caller whose action then fails closes only a mode it opened.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Opened {
    /// A new session in the mode, which nothing listens for yet.
    Session,
    /// The mode, over the current one.
    Pushed,
    /// Back to the mode, which was open underneath; the modes over it ended.
    WentBack,
    /// It was the current mode already.
    AlreadyOn,
    /// It could not open (another process's session, no auto-stop); a toast said why.
    Refused,
}

impl Opened {
    /// This call opened the mode, so it is this call's to close again.
    pub fn is_new(self) -> bool {
        matches!(self, Self::Session | Self::Pushed)
    }
}

/// From a turn of the session `me` owns: opens the mode on top of the current one, or returns to it when it is open
/// underneath, and does nothing when it is the current one.
pub fn enter(lock: &SessionLock, kind: &str, file: &str, label: &str, me: u32) -> Opened {
    let Some(state) = state(lock).filter(|state| is_mine(state, me)) else {
        return Opened::Refused;
    };
    let count = frames(&state).len();
    match frame_index(&state, kind) {
        None => {
            push(lock, &state, kind, file, label);
            Opened::Pushed
        }
        Some(index) if index + 1 < count => {
            debug(&format!("session: back to {kind}"));
            if let Some(popped) = truncate(lock, index + 1, "", me) {
                popped.announce();
            }
            Opened::WentBack
        }
        Some(_) => Opened::AlreadyOn,
    }
}

/// Opens a mode over the current one; the unclear count starts again. An open-ended mode underneath has its time so
/// far credited to the session's start now, since it is not counted against the session's cap; it is not counted
/// twice when it is the current mode again (`truncate` restarts its clock).
fn push(_lock: &SessionLock, state: &Value, kind: &str, file: &str, label: &str) {
    let mode = ModeSettings::of(file);
    debug(&format!("session: {kind} opens over the current mode"));
    let now = now_secs();
    let mut under = current_frame(state);
    let under_started = number_or(&under["mode_started"], now);
    let active = number_or(&under["active_secs"], 0) + now - under_started;
    let open_ended_credit = if under["open_ended"] == Value::Bool(true) {
        now - under_started
    } else {
        0
    };
    let hint = format!("{} (back to {})", mode.exit_hint_or_default(), text_of(&under["label"]));
    under.insert("active_secs".into(), json!(active));
    let mut stack = state["stack"].as_array().cloned().unwrap_or_default();
    stack.push(Value::Object(under));
    let mut fields = Map::new();
    for (key, value) in [
        ("kind", json!(kind)),
        ("integration", json!(file)),
        ("label", json!(label)),
        ("exit_hint", json!(hint)),
        ("unclear", json!(0)),
        ("mode_started", json!(now)),
        ("last_heard", json!(now)),
        ("frame_id", json!(new_frame_id())),
        ("active_secs", json!(0)),
        ("resumes", json!(0)),
    ] {
        fields.insert(key.into(), value);
    }
    insert_flags(&mut fields, &mode);
    for key in ["owner", "owner_start", "turns"] {
        fields.insert(key.into(), state[key].clone());
    }
    fields.insert("stack".into(), Value::Array(stack));
    fields.insert(
        "started".into(),
        json!(number_or(&state["started"], 0) + open_ended_credit),
    );
    write(&Value::Object(fields));
}

/// The modes `truncate` popped, whose toast and ended hooks are still to come.
#[must_use]
pub struct Popped {
    label: String,
    reason: String,
    /// Each popped mode's integration and frame_id, newest first.
    hooks: Vec<(String, String)>,
    /// The session goes on in the mode underneath.
    continues: bool,
}

impl Popped {
    /// The toast, named for the lowest mode popped, when there is a reason; then each popped mode's ended hook.
    pub fn announce(self) {
        if !self.reason.is_empty() {
            notify::notify(Kind::Info, &format!("voxcmd: {} ended", self.label), &self.reason);
        }
        for (integration, frame_id) in &self.hooks {
            run_ended_hook(integration, &self.reason, frame_id, self.continues);
        }
    }
}

/// Keeps that many modes from the bottom and pops the rest; keeping none ends the session, and the watcher whose
/// recording is still open (unless that is `me`) is told to drop it. None when no session is open.
pub fn truncate(lock: &SessionLock, keep: usize, reason: &str, me: u32) -> Option<Popped> {
    let state = state(lock)?;
    let all = frames(&state);
    let keep = keep.min(all.len());
    let popped: Vec<&Value> = all[keep..].iter().rev().collect();
    let label = all.get(keep).map_or_else(|| "Voice session".to_string(), label_of);
    if keep == 0 {
        let _ = std::fs::remove_file(paths::session_file());
        let owner = text_of(&state["owner"]);
        if !owner.is_empty() && owner != me.to_string() {
            let _ = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(paths::runtime_dir().join(format!("discard.{owner}")));
        }
        debug(&format!("session ended: {reason}"));
    } else {
        let now = now_secs();
        let top = &all[all.len() - 1];
        let open_ended_credit = if top["open_ended"] == Value::Bool(true) {
            now - number_or(&top["mode_started"], now)
        } else {
            0
        };
        let mut fields = all[keep - 1].as_object().cloned().unwrap_or_default();
        for key in ["owner", "owner_start", "turns"] {
            fields.insert(key.into(), state[key].clone());
        }
        fields.insert("last_heard".into(), json!(now));
        fields.insert(
            "started".into(),
            json!(number_or(&state["started"], 0) + open_ended_credit),
        );
        fields.insert("stack".into(), Value::Array(all[..keep - 1].to_vec()));
        fields.insert("mode_started".into(), json!(now));
        let resumes = number_or(&fields.get("resumes").cloned().unwrap_or_default(), 0) + 1;
        fields.insert("resumes".into(), json!(resumes));
        write(&Value::Object(fields));
        let kinds: Vec<String> = popped.iter().map(|frame| text_of(&frame["kind"])).collect();
        let why = if reason.is_empty() {
            String::new()
        } else {
            format!(" ({reason})")
        };
        debug(&format!("session: left {}{why}", kinds.join(", ")));
    }
    Some(Popped {
        label,
        reason: reason.to_string(),
        hooks: popped
            .iter()
            .map(|frame| (text_of(&frame["integration"]), text_of(&frame["frame_id"])))
            .collect(),
        continues: keep > 0,
    })
}

/// Leaves that mode and every mode opened over it, back to the one underneath; leaving the bottom one ends the
/// session. False when the kind is not open.
pub fn leave(lock: &SessionLock, kind: &str, reason: &str, me: u32) -> bool {
    let Some(index) = state(lock).and_then(|state| frame_index(&state, kind)) else {
        return false;
    };
    match truncate(lock, index, reason, me) {
        Some(popped) => {
            popped.announce();
            true
        }
        None => false,
    }
}

/// Leaves the current mode.
pub fn end_top(lock: &SessionLock, reason: &str, me: u32) {
    if let Some(state) = state(lock) {
        leave(lock, &text_of(&state["kind"]), reason, me);
    }
}

/// Ends the session and every mode in it, saying why, under a lock the caller holds.
pub fn end_all_locked(lock: &SessionLock, reason: &str, me: u32) {
    if let Some(popped) = truncate(lock, 0, reason, me) {
        popped.announce();
    }
}

/// Ends the session and every mode in it, saying why: the file goes, the watcher whose recording is still open is told
/// to drop it (its discard flag), a toast names the bottom mode, and each mode's `session_ended` hook runs, newest
/// first. A no-op when no session is open.
pub fn end_all(reason: &str, me: u32) {
    let lock = SessionLock::take();
    let popped = truncate(&lock, 0, reason, me);
    // Released first, so a bar that is slow to toast holds up no listen.
    drop(lock);
    if let Some(popped) = popped {
        popped.announce();
    }
}

/// Ends the session `me` owns, as a watcher that dies without handing over leaves it. A session another listen took
/// over is left to that one.
pub fn end_if_mine(reason: &str, me: u32) {
    let lock = SessionLock::take();
    if state(&lock).is_some_and(|state| is_mine(&state, me)) {
        end_all_locked(&lock, reason, me);
    }
}

/// Runs a popped mode's `session_ended` (a TOML mode's `ended`) in the background, a bash one through the bash voxcmd
/// that loaded its integration. Its
/// pid is logged: the suites wait for the hook by it. It gets no `VOXCMD_LEGACY_PID`, so a `session_state` in it takes
/// the lock as any reader does, after the caller has let it go.
fn run_ended_hook(integration: &str, reason: &str, frame_id: &str, continues: bool) {
    if mode::run_toml_ended(integration, reason, frame_id, continues) {
        return;
    }
    let mut command = Command::new(paths::legacy_bin());
    command
        .args(["_legacy-hook", "ended", integration, reason, frame_id])
        .arg(if continues { "1" } else { "0" })
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    bridge::clear_hook_env(&mut command);
    match command.spawn() {
        Ok(hook) => debug(&format!("session: ended hook {} runs", hook.id())),
        Err(error) => debug(&format!("session: cannot run the ended hook of {integration}: {error}")),
    }
}

/// `voxcmd session end`.
pub fn run_end() {
    end_all("ended by request", std::process::id());
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::process::tests::{in_own_process, is_own_process};
    use std::io::Write as _;
    use std::os::unix::process::ExitStatusExt;
    use std::time::{Duration, Instant};

    /// A session owned by this process, a stop's last act that ends it, and the order things happened in, in `dir`.
    fn own_a_session_ended_on_stop(dir: &std::path::Path) {
        let me = std::process::id();
        let session = json!({"kind": "rapid", "label": "Rapid mode", "integration": "/i/rapid.sh", "frame_id": "1",
            "owner": me.to_string(), "owner_start": process_start_time(me).unwrap(), "stack": []});
        std::fs::create_dir_all(paths::runtime_dir()).unwrap();
        std::fs::write(paths::session_file(), session.to_string()).unwrap();
        let events = dir.join("events");
        let held = crate::process::StopSignalsHeld::new();
        crate::process::run_on_stop(move || {
            end_if_mine("stopped", me);
            note(&events, "ended");
        });
        drop(held);
    }

    fn note(events: &std::path::Path, event: &str) {
        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(events)
            .unwrap();
        writeln!(file, "{event}").unwrap();
    }

    /// Runs the test in a process of its own against `dir`, and checks it ended by its stop signal, soon, having ended
    /// the session once.
    fn ends_by_its_stop_signal(test: &str, dir: &std::path::Path) -> String {
        let started = Instant::now();
        let status = in_own_process(test)
            .env("XDG_RUNTIME_DIR", dir)
            .env("VOXCMD_DEBUG", "1")
            .env("VOXCMD_DRY_RUN", "1")
            .env("VOXCMD_TEST_DIR", dir)
            .status()
            .unwrap();
        assert_eq!(status.signal(), Some(libc::SIGTERM), "{status:?}");
        assert!(started.elapsed() < Duration::from_secs(4), "{:?}", started.elapsed());
        let log = std::fs::read_to_string(dir.join("voxcmd/debug.log")).unwrap_or_default();
        assert_eq!(log.matches("session ended: stopped").count(), 1, "{log}");
        assert!(!dir.join("voxcmd/session.json").exists());
        std::fs::read_to_string(dir.join("events")).unwrap_or_default()
    }

    fn test_dir() -> std::path::PathBuf {
        std::env::var_os("VOXCMD_TEST_DIR").unwrap().into()
    }

    #[test]
    fn a_stop_signal_while_the_lock_is_held_ends_the_session_once_it_is_let_go() {
        let test = "session::tests::a_stop_signal_while_the_lock_is_held_ends_the_session_once_it_is_let_go";
        if is_own_process() {
            let dir = test_dir();
            own_a_session_ended_on_stop(&dir);
            let lock = SessionLock::take();
            // SAFETY: kill only sends a signal, here to this process.
            unsafe { libc::kill(libc::getpid(), libc::SIGTERM) };
            std::thread::sleep(Duration::from_millis(300));
            note(&dir.join("events"), "released");
            drop(lock);
            std::thread::sleep(Duration::from_secs(30));
            std::process::exit(0);
        }
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(ends_by_its_stop_signal(test, dir.path()), "released\nended\n");
    }

    #[test]
    fn a_stop_signal_while_the_lock_is_taken_and_let_go_ends_the_session_once() {
        let test = "session::tests::a_stop_signal_while_the_lock_is_taken_and_let_go_ends_the_session_once";
        if is_own_process() {
            own_a_session_ended_on_stop(&test_dir());
            std::thread::spawn(|| {
                std::thread::sleep(Duration::from_millis(100));
                // SAFETY: kill only sends a signal, here to this process.
                unsafe { libc::kill(libc::getpid(), libc::SIGTERM) };
            });
            let deadline = Instant::now() + Duration::from_secs(30);
            while Instant::now() < deadline {
                drop(SessionLock::take());
            }
            std::process::exit(0);
        }
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(ends_by_its_stop_signal(test, dir.path()), "ended\n");
    }

    #[test]
    fn frames_run_from_the_bottom_mode_to_the_current_one() {
        let state = json!({"kind": "click", "integration": "/i/click.sh", "label": "Click mode", "frame_id": "2",
            "stack": [{"kind": "rapid", "integration": "/i/rapid.sh", "label": "Rapid mode", "frame_id": "1"}]});
        let frames = frames(&state);
        let integrations: Vec<_> = frames.iter().map(|frame| text_of(&frame["integration"])).collect();
        assert_eq!(integrations, ["/i/rapid.sh", "/i/click.sh"]);
        assert_eq!(label_of(&frames[0]), "Rapid mode");
        assert_eq!(frame_index(&state, "click"), Some(1));
        assert_eq!(frame_index(&state, "type"), None);
        assert_eq!(mode_token(&state), "2:click:2");
    }

    #[test]
    fn a_frame_without_a_label_or_id_reads_as_jq_prints_it() {
        let frames = frames(&json!({"integration": "/i/x.sh", "label": null}));
        assert_eq!(frames.len(), 1);
        assert_eq!(label_of(&frames[0]), "Voice session");
        assert_eq!(text_of(&frames[0]["frame_id"]), "");
        // Every field of a frame is there, null when the mode lacks it, as jq's `{kind, ...}` builds it.
        assert_eq!(frames[0].as_object().unwrap().len(), FRAME_FIELDS.len());
        assert_eq!(mode_token(&json!({"kind": "rapid"})), "1:rapid:");
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
