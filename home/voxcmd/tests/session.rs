//! The session file as the Rust port writes it, and the bridge the bash integrations reach it through: `internal
//! session` against a runtime dir of its own (stubs for voxtype, setsid, the toasts, auto-stop and the bash voxcmd),
//! and the bash voxcmd's `_legacy-hook` shims and mode arms run for real on a fake integration.
use serde_json::Value;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Output, Stdio};
use std::time::{Duration, Instant};

mod common;
use common::gone_within;

struct Setup {
    root: tempfile::TempDir,
}

impl Setup {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        for dir in [
            "config/integrations.d",
            "runtime/voxtype",
            "runtime/voxcmd",
            "bin",
            "legacy",
            "work",
        ] {
            std::fs::create_dir_all(root.path().join(dir)).unwrap();
        }
        let setup = Self { root };
        let calls = setup.path().join("calls");
        let state = setup.path().join("runtime/voxtype/state");
        setup.script(
            "bin/voxtype",
            &format!(
                "echo \"voxtype $*\" >> '{}'\ncase \"$2\" in start) echo recording > '{1}' ;; stop | cancel) echo idle > '{1}' ;; esac",
                calls.display(),
                state.display()
            ),
        );
        // The watcher a listen starts stands in as a process that lives, so the session it is handed stays open.
        setup.script(
            "bin/setsid",
            &format!(
                "echo \"setsid $*\" >> '{}'\necho $$ >> '{}'\nexec sleep 30",
                calls.display(),
                setup.path().join("work/watchers").display()
            ),
        );
        setup.script(
            "bin/notify-send",
            &format!("echo \"notify-send $*\" >> '{}'", calls.display()),
        );
        setup.script(
            "legacy/voxcmd",
            &format!("echo \"bash voxcmd $*\" >> '{}'", calls.display()),
        );
        setup.script("legacy/voxcmd-autostop", "exit 0");
        std::fs::write(&state, "idle\n").unwrap();
        setup
    }

    fn path(&self) -> &Path {
        self.root.path()
    }

    fn runtime(&self) -> PathBuf {
        self.path().join("runtime/voxcmd")
    }

    /// An executable that is ready to exec (see tests/voice.rs: a fork on another thread may hold its write fd).
    fn script(&self, name: &str, body: &str) -> PathBuf {
        let path = self.path().join(name);
        let temp = path.with_extension("tmp");
        std::fs::write(
            &temp,
            format!("#!/bin/sh\n[ -z \"$VOXCMD_TEST_PROBE\" ] || exit 0\n{body}\n"),
        )
        .unwrap();
        std::fs::set_permissions(&temp, std::fs::Permissions::from_mode(0o755)).unwrap();
        std::fs::rename(&temp, &path).unwrap();
        for _ in 0..500 {
            match Command::new(&path).env("VOXCMD_TEST_PROBE", "1").status() {
                Err(error) if error.kind() == std::io::ErrorKind::ExecutableFileBusy => {
                    std::thread::sleep(Duration::from_millis(10));
                }
                _ => break,
            }
        }
        path
    }

    fn command(&self, args: &[&str]) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_voxcmd"));
        command
            .args(args)
            .env_clear()
            .env("PATH", format!("{}/bin:/usr/bin:/bin", self.path().display()))
            .env("HOME", "/nonexistent")
            .env("LC_ALL", "C")
            .env("WORK", self.path().join("work"))
            .env("VOXCMD_CONFIG_DIR", self.path().join("config"))
            .env("VOXCMD_LEGACY_BIN", self.path().join("legacy/voxcmd"))
            .env("XDG_RUNTIME_DIR", self.path().join("runtime"))
            .env("VOXCMD_DEBUG", "1")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        command
    }

    /// `internal session <args>` for the process `me`, as a bash hook run from it calls it.
    fn session(&self, me: u32, args: &[&str]) -> Output {
        self.command(&[&["internal", "session"][..], args].concat())
            .env("VOXCMD_LEGACY_PID", me.to_string())
            .output()
            .unwrap()
    }

    fn state(&self) -> Option<Value> {
        let text = std::fs::read_to_string(self.runtime().join("session.json")).ok()?;
        Some(serde_json::from_str(&text).unwrap())
    }

    fn calls(&self) -> String {
        std::fs::read_to_string(self.path().join("calls")).unwrap_or_default()
    }

    fn debug_log(&self) -> String {
        std::fs::read_to_string(self.runtime().join("debug.log")).unwrap_or_default()
    }

    /// Kills what the listens left running (the stand-in watchers).
    fn end_watchers(&self) {
        let pids = std::fs::read_to_string(self.path().join("work/watchers")).unwrap_or_default();
        for pid in pids.lines().filter_map(|pid| pid.parse::<i32>().ok()) {
            // SAFETY: kill only sends a signal, to a stand-in this test started.
            unsafe { libc::kill(pid, libc::SIGKILL) };
        }
    }
}

fn wait_for(done: impl Fn() -> bool) -> bool {
    let deadline = Instant::now() + Duration::from_secs(10);
    while !done() {
        if Instant::now() >= deadline {
            return false;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    true
}

fn start_time_of(pid: u32) -> String {
    let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).unwrap();
    stat.rsplit_once(") ")
        .unwrap()
        .1
        .split(' ')
        .nth(19)
        .unwrap()
        .to_string()
}

fn owned_session(setup: &Setup, owner: &Child, fields: Value) {
    let mut session = serde_json::json!({"kind": "rapid", "integration": "/i/rapid.sh", "label": "Rapid mode",
        "exit_hint": "say done to stop", "started": 100, "owner": owner.id(), "owner_start": start_time_of(owner.id()),
        "unclear": 0, "turns": 2, "mode_started": 100, "last_heard": 100, "frame_id": "1", "active_secs": 0,
        "resumes": 0, "open_ended": false, "one_recording": false, "wake_listens": false, "stack": []});
    session
        .as_object_mut()
        .unwrap()
        .extend(fields.as_object().unwrap().clone());
    std::fs::write(setup.runtime().join("session.json"), session.to_string()).unwrap();
}

fn number(value: &Value) -> i64 {
    value.as_i64().unwrap_or_else(|| panic!("not a number: {value}"))
}

// ---- the session file -----------------------------------------------------------------------------------------------

#[test]
fn begin_opens_a_session_whose_first_listen_owns_it() {
    let setup = Setup::new();
    let opener = Command::new("sleep").arg("30").spawn().unwrap();
    let output = setup.session(opener.id(), &["begin", "rapid", "/i/rapid.sh", "Rapid mode"]);
    assert!(output.status.success());
    let state = setup.state().expect("a session is open");
    for (field, expected) in [
        ("kind", "rapid"),
        ("integration", "/i/rapid.sh"),
        ("label", "Rapid mode"),
        ("exit_hint", "say done to stop"),
    ] {
        assert_eq!(state[field], expected, "{field}");
    }
    // The shapes the bar and the wake listener read: owner a number, owner_start a string, the flags real booleans.
    let watcher = u32::try_from(number(&state["owner"])).unwrap();
    assert_ne!(watcher, opener.id());
    assert_eq!(state["owner_start"], start_time_of(watcher));
    for flag in ["open_ended", "one_recording", "wake_listens"] {
        assert_eq!(state[flag], false, "{flag}");
    }
    assert_eq!(state["stack"], serde_json::json!([]));
    assert!(state.get("owner_handover").is_none());
    assert_eq!(number(&state["started"]), number(&state["mode_started"]));
    let token = format!("1:rapid:{}", state["frame_id"].as_str().unwrap());
    assert!(
        wait_for(|| {
            setup.calls().contains(&format!(
            "internal watch session_turn {token} 0 VOXCMD_AUTOSTOP_NO_SPEECH_SECS=10\nVOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0.4\nVOXCMD_AUTOSTOP_SILENCE_SECS=1.5\n"
        ))
        }),
        "{}",
        setup.calls()
    );
    assert!(setup.debug_log().contains("session: rapid begins"));
    setup.end_watchers();
    let mut opener = opener;
    let _ = opener.kill();
    let _ = opener.wait();
}

#[test]
fn a_mode_opened_in_a_turn_stacks_and_one_open_underneath_is_returned_to() {
    let setup = Setup::new();
    let mut owner = Command::new("sleep").arg("30").spawn().unwrap();
    owned_session(&setup, &owner, serde_json::json!({"custom": "kept"}));
    assert!(
        setup
            .session(owner.id(), &["begin", "click", "/i/click.sh", "Click mode"])
            .status
            .success()
    );
    let state = setup.state().unwrap();
    assert_eq!(state["kind"], "click");
    assert_eq!(state["exit_hint"], "say done to stop (back to Rapid mode)");
    assert_eq!(state["stack"][0]["kind"], "rapid");
    assert_eq!(state["stack"][0]["label"], "Rapid mode");
    assert_eq!(number(&state["turns"]), 2);
    assert_eq!(number(&state["owner"]), i64::from(owner.id()));
    let click_frame = state["frame_id"].as_str().unwrap().to_string();
    // The mode that is open already changes nothing.
    assert!(
        setup
            .session(owner.id(), &["begin", "click", "/i/click.sh", "Click mode"])
            .status
            .success()
    );
    assert_eq!(setup.state().unwrap()["stack"].as_array().unwrap().len(), 1);
    assert!(
        setup
            .session(owner.id(), &["begin", "rapid", "/i/rapid.sh", "Rapid mode"])
            .status
            .success()
    );
    let state = setup.state().unwrap();
    assert_eq!((state["kind"].as_str(), number(&state["resumes"])), (Some("rapid"), 1));
    assert_eq!(state["stack"], serde_json::json!([]));
    assert!(setup.debug_log().contains("session: back to rapid"));
    assert!(setup.debug_log().contains("session: left click"));
    assert!(wait_for(|| setup.calls().contains(&format!(
        "bash voxcmd _legacy-hook ended /i/click.sh  {click_frame} 1"
    ))));
    // A plain update keeps a field this port does not know; a whole new frame, as bash's jq built it, does not.
    assert!(state.get("custom").is_none());
    let _ = owner.kill();
    let _ = owner.wait();
}

#[test]
fn begin_from_outside_the_session_leaves_it_alone() {
    let setup = Setup::new();
    let mut owner = Command::new("sleep").arg("30").spawn().unwrap();
    owned_session(&setup, &owner, serde_json::json!({}));
    let before = std::fs::read_to_string(setup.runtime().join("session.json")).unwrap();
    assert!(
        setup
            .session(1, &["begin", "click", "/i/click.sh", "Click mode"])
            .status
            .success()
    );
    assert_eq!(
        std::fs::read_to_string(setup.runtime().join("session.json")).unwrap(),
        before
    );
    assert!(
        setup
            .calls()
            .contains("voxcmd: Click mode A voice session is already open")
    );
    let _ = owner.kill();
    let _ = owner.wait();
}

#[test]
fn leave_state_and_end_reach_the_session_from_any_process() {
    let setup = Setup::new();
    let mut owner = Command::new("sleep").arg("30").spawn().unwrap();
    owned_session(
        &setup,
        &owner,
        serde_json::json!({"kind": "click", "label": "Click mode", "frame_id": "2",
            "stack": [{"kind": "rapid", "integration": "/i/rapid.sh", "label": "Rapid mode", "frame_id": "1"}]}),
    );
    let printed = setup.session(1, &["state"]);
    assert!(printed.status.success());
    let printed: Value = serde_json::from_slice(&printed.stdout).unwrap();
    assert_eq!(printed["kind"], "click");
    assert!(!setup.session(1, &["leave", "type", "done"]).status.success());
    assert!(setup.session(1, &["end", "done"]).status.success());
    assert_eq!(setup.state().unwrap()["kind"], "rapid");
    assert!(setup.calls().contains("voxcmd: Click mode ended done"));
    assert!(setup.session(1, &["end-all", "stopped"]).status.success());
    assert!(setup.state().is_none());
    assert!(setup.calls().contains("voxcmd: Rapid mode ended stopped"));
    // The owner, which is not the caller, is told to drop its recording.
    assert!(setup.runtime().join(format!("discard.{}", owner.id())).exists());
    assert!(!setup.session(1, &["state"]).status.success());
    let _ = owner.kill();
    let _ = owner.wait();
}

#[test]
fn a_hook_run_under_the_session_lock_reads_the_session_without_it_and_changes_nothing() {
    use std::os::fd::AsRawFd;
    let setup = Setup::new();
    let mut owner = Command::new("sleep").arg("30").spawn().unwrap();
    owned_session(&setup, &owner, serde_json::json!({}));
    let lock = std::fs::File::create(setup.runtime().join("session.lock")).unwrap();
    // SAFETY: flock on a descriptor this test owns, released when it closes.
    unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX) };
    let under_lock = |args: &[&str]| {
        setup
            .command(&[&["internal", "session"][..], args].concat())
            .env("VOXCMD_LEGACY_PID", "1")
            .env("VOXCMD_SESSION_LOCK_HELD", "1")
            .output()
            .unwrap()
    };
    let printed = under_lock(&["state"]);
    assert!(printed.status.success());
    assert_eq!(
        serde_json::from_slice::<Value>(&printed.stdout).unwrap()["kind"],
        "rapid"
    );
    assert!(!under_lock(&["end-all", "stopped"]).status.success());
    assert!(setup.state().is_some());
    assert!(
        setup
            .debug_log()
            .contains("internal session: end-all refused, called from a hook run under the session lock")
    );
    drop(lock);
    let _ = owner.kill();
    let _ = owner.wait();
}

#[test]
fn a_voice_key_during_a_session_takes_it_over_and_keeps_its_other_fields() {
    let setup = Setup::new();
    let mut owner = Command::new("sleep").arg("30").spawn().unwrap();
    owned_session(&setup, &owner, serde_json::json!({"custom": "kept"}));
    assert!(setup.command(&["listen"]).status().unwrap().success());
    let state = setup.state().unwrap();
    assert_eq!(state["custom"], "kept");
    assert_ne!(number(&state["owner"]), i64::from(owner.id()));
    assert!(state.get("owner_handover").is_none());
    assert!(wait_for(|| setup
        .calls()
        .contains("internal watch session_turn 1:rapid:1 0 ")));
    let _ = owner.kill();
    let _ = owner.wait();
    setup.end_watchers();
}

#[test]
fn a_session_turn_watcher_ended_by_a_stop_signal_ends_the_session_it_owns() {
    let setup = Setup::new();
    std::fs::write(setup.path().join("runtime/voxtype/state"), "recording\n").unwrap();
    let mut watcher = setup
        .command(&["internal", "watch", "session_turn", "1:rapid:1", "0", ""])
        .spawn()
        .unwrap();
    assert!(wait_for(|| setup.debug_log().contains("watch: voxtype recording")));
    let session = serde_json::json!({"kind": "rapid", "label": "Rapid mode", "integration": "/i/rapid.sh",
        "frame_id": "1", "owner": watcher.id(), "owner_start": start_time_of(watcher.id()), "stack": []});
    std::fs::write(setup.runtime().join("session.json"), session.to_string()).unwrap();
    // SAFETY: kill only sends a signal.
    unsafe { libc::kill(i32::try_from(watcher.id()).unwrap(), libc::SIGTERM) };
    let _ = watcher.wait();
    assert!(setup.state().is_none());
    assert!(
        setup
            .debug_log()
            .contains("session ended: the listener stopped unexpectedly")
    );
    assert!(
        setup
            .calls()
            .contains("voxcmd: Rapid mode ended the listener stopped unexpectedly")
    );
    assert!(gone_within(
        i32::try_from(watcher.id()).unwrap(),
        Duration::from_secs(2)
    ));
}
