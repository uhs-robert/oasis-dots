//! The session file as the Rust port writes it, against a runtime dir of its own (stubs for voxtype, setsid, the toasts
//! and auto-stop).
use serde_json::Value;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
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
            "stand-in",
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
        setup.script("stand-in/voxcmd-autostop", "exit 0");
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
            .env("VOXCMD_STAND_IN_BIN", self.path().join("stand-in/voxcmd"))
            .env("XDG_RUNTIME_DIR", self.path().join("runtime"))
            .env("VOXCMD_DEBUG", "1")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        command
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
