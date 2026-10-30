//! `listen`, `internal watch`, `stop`, `session end` and `internal settle` end to end: the binary against a runtime dir
//! of its own, with stubs for voxtype, setsid, the toasts, the auto-stop detector and the stand-in voxcmd (which logs what
//! it was asked to do). voxtype's state is a file the test writes, as voxtype would.
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Output, Stdio};
use std::time::{Duration, Instant};

mod common;
mod executable;
use common::gone_within;

const INTEGRATION: &str = r#"
name = "Tools"
verbs = [{ action = "ok", match = 'do ok' }]

[actions]
ok = { run = "echo ran >> $WORK/ran", silent = true }
"#;

struct Voice {
    root: tempfile::TempDir,
}

impl Voice {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        for dir in [
            "config/integrations",
            "runtime/voxtype",
            "runtime/voxcmd",
            "state",
            "bin",
            "stand-in",
            "xdg",
            "work",
        ] {
            std::fs::create_dir_all(root.path().join(dir)).unwrap();
        }
        std::fs::write(root.path().join("config/integrations/tools.toml"), INTEGRATION).unwrap();
        let voice = Self { root };
        let calls = voice.path().join("calls");
        let state = voice.path().join("runtime/voxtype/state");
        voice.script(
            "bin/voxtype",
            &format!(
                "echo \"voxtype $*\" >> '{}'\ncase \"$2\" in start) echo recording > '{1}' ;; stop | cancel) echo idle > '{1}' ;; esac",
                calls.display(),
                state.display()
            ),
        );
        voice.script(
            "bin/setsid",
            &format!(
                "echo \"setsid owner=${{VOXCMD_RECORDING_OWNER_FILE-}} $*\" >> '{}'",
                calls.display()
            ),
        );
        voice.script(
            "bin/notify-send",
            &format!("echo \"notify-send $*\" >> '{}'", calls.display()),
        );
        voice.script(
            "stand-in/voxcmd",
            &format!("echo \"stand-in voxcmd $*\" >> '{}'", calls.display()),
        );
        voice
    }

    fn path(&self) -> &Path {
        self.root.path()
    }

    fn runtime(&self) -> PathBuf {
        self.path().join("runtime/voxcmd")
    }

    fn work(&self, name: &str) -> PathBuf {
        self.path().join("work").join(name)
    }

    fn script(&self, name: &str, body: &str) -> PathBuf {
        let path = self.path().join(name);
        executable::write_executable(&path, &format!("#!/bin/sh\n{body}\n"));
        path
    }

    /// The auto-stop detector the watcher starts: writes its pid and the threshold file, then runs `body`.
    fn detector(&self, body: &str) {
        self.script(
            "stand-in/voxcmd-autostop",
            &format!(
                ": > \"$VOXCMD_AUTOSTOP_THRESHOLD_FILE\"\necho $$ > '{}'\n{body}",
                self.work("detector").display()
            ),
        );
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
            .env("XDG_STATE_HOME", self.path().join("state"))
            .env("XDG_CONFIG_HOME", self.path().join("xdg"))
            .env("VOXCMD_DEBUG", "1")
            .env("VOXCMD_TIME_SCALE", "0.1")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        command
    }

    fn output(&self, args: &[&str]) -> Output {
        self.command(args).output().expect("the binary runs")
    }

    fn set_state(&self, state: &str) {
        std::fs::write(self.path().join("runtime/voxtype/state"), format!("{state}\n")).unwrap();
    }

    fn calls(&self) -> String {
        std::fs::read_to_string(self.path().join("calls")).unwrap_or_default()
    }

    fn debug_log(&self) -> String {
        std::fs::read_to_string(self.runtime().join("debug.log")).unwrap_or_default()
    }

    /// A watcher of a recording voxtype has started, once it has seen it (and, with a detector, the detector runs).
    fn watcher(&self, args: &[&str], envs: &[(&str, &Path)], with_detector: bool) -> Child {
        self.set_state("recording");
        let mut command = self.command(&[&["internal", "watch"][..], args].concat());
        for (name, value) in envs {
            command.env(name, value);
        }
        let watcher = command.spawn().unwrap();
        assert!(
            wait_for(|| self.debug_log().contains("watch: voxtype recording")),
            "the watcher never saw the recording"
        );
        if with_detector {
            assert!(wait_for(|| self.detector_pid().is_some()), "no detector");
        }
        watcher
    }

    fn detector_pid(&self) -> Option<i32> {
        std::fs::read_to_string(self.work("detector")).ok()?.trim().parse().ok()
    }

    fn leftovers(&self, pid: u32) -> Vec<PathBuf> {
        [format!("discard.{pid}"), format!("threshold.{pid}")]
            .iter()
            .map(|name| self.runtime().join(name))
            .filter(|path| path.exists())
            .collect()
    }
}

fn end(child: &mut Child) {
    let _ = child.kill();
    let _ = child.wait();
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

fn signal(child: &Child, signal: libc::c_int) {
    // SAFETY: kill only sends a signal.
    unsafe { libc::kill(i32::try_from(child.id()).unwrap(), signal) };
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

/// A process whose command line names a bash asker, as the pending pick's pid must.
fn asker(voice: &Voice) -> Child {
    let program = voice.path().join("bin/voxcmd-hints");
    std::fs::copy("/bin/sleep", &program).unwrap();
    // A fork on another test thread may hold the copy's write fd for a moment.
    for _ in 0..500 {
        match Command::new(&program).arg("30").spawn() {
            Err(error) if error.kind() == std::io::ErrorKind::ExecutableFileBusy => {
                std::thread::sleep(Duration::from_millis(10));
            }
            spawned => return spawned.unwrap(),
        }
    }
    panic!("the asker never started")
}

fn pending_pick(voice: &Voice, asker: &Child) -> PathBuf {
    let fifo = voice.work("fifo");
    let path = std::ffi::CString::new(fifo.to_str().unwrap()).unwrap();
    // SAFETY: mkfifo on a NUL-terminated path.
    assert_eq!(unsafe { libc::mkfifo(path.as_ptr(), 0o600) }, 0);
    let pending = serde_json::json!({"pid": asker.id(), "fifo": fifo, "label": "Which one?", "kind": "hints",
        "choices": [{"id": "a", "label": "1. A"}], "expansions": {}});
    std::fs::write(voice.runtime().join("pending-pick.json"), pending.to_string()).unwrap();
    fifo
}

/// A process named `qs` publishing its open picker, as the bar does, and the `qs-ipc` its answers go through.
fn bar_picker(voice: &Voice) -> Child {
    let program = voice.path().join("bin/qs");
    std::fs::copy("/bin/sleep", &program).unwrap();
    let bar = (0..500)
        .find_map(|_| match Command::new(&program).arg("30").spawn() {
            Err(error) if error.kind() == std::io::ErrorKind::ExecutableFileBusy => {
                std::thread::sleep(Duration::from_millis(10));
                None
            }
            spawned => Some(spawned.unwrap()),
        })
        .expect("the bar never started");
    assert!(wait_for(|| {
        std::fs::read_to_string(format!("/proc/{}/comm", bar.id())).is_ok_and(|comm| comm == "qs\n")
    }));
    std::fs::create_dir_all(voice.path().join("xdg/hypr/scripts")).unwrap();
    voice.script(
        "xdg/hypr/scripts/qs-ipc",
        &format!(
            "echo \"qs-ipc $*\" >> '{}'; echo ok",
            voice.path().join("calls").display()
        ),
    );
    let pending = serde_json::json!({"pid": bar.id(), "owner": "bar", "token": "k1", "label": "Session",
        "choices": [{"id": "Work", "label": "Work"}], "expansions": {}, "view_key": ""});
    std::fs::write(voice.runtime().join("pending-pick.json"), pending.to_string()).unwrap();
    bar
}

#[test]
fn the_voice_key_answers_a_picker_the_bar_published() {
    let voice = Voice::new();
    voice.set_state("idle");
    let mut bar = bar_picker(&voice);
    let bar_pid = bar.id();
    assert!(voice.output(&["listen"]).status.success());
    end(&mut bar);
    assert!(wait_for(|| voice.calls().contains("setsid")));
    assert!(
        voice.calls().contains(" internal watch reply - 0 "),
        "{}",
        voice.calls()
    );
    assert!(
        voice.calls().contains(
            r#" {"pid":%PID%,"owner":"bar","fifo":null,"token":"k1"}"#.replace("%PID%", &bar_pid.to_string()).as_str()
        ),
        "{}",
        voice.calls()
    );
}

/// A reply watcher of the bar's pick `k1`, its transcript already heard, with voxtype still recording.
fn pinned_reply_watcher(voice: &Voice, bar: &Child) -> Child {
    std::fs::write(voice.runtime().join("transcript.txt"), "work\n").unwrap();
    let pin = serde_json::json!({"pid": bar.id(), "owner": "bar", "fifo": null, "token": "k1"}).to_string();
    voice.watcher(&["reply", "-", "0", "", &pin], &[], false)
}

#[test]
fn a_reply_answers_the_picker_it_was_recorded_for() {
    let voice = Voice::new();
    let mut bar = bar_picker(&voice);
    let mut watcher = pinned_reply_watcher(&voice, &bar);
    voice.set_state("idle");
    assert!(watcher.wait().unwrap().success());
    end(&mut bar);
    assert!(
        voice.calls().contains("qs-ipc call picker answer k1 Work\n"),
        "{}",
        voice.calls()
    );
}

#[test]
fn a_reply_does_not_answer_a_picker_opened_while_it_was_transcribed() {
    let voice = Voice::new();
    let mut bar = bar_picker(&voice);
    let mut other_asker = asker(&voice);
    let mut watcher = pinned_reply_watcher(&voice, &bar);
    // The bar reopened its picker (new token), then an ask (other pid and FIFO) took the file.
    let reopened = serde_json::json!({"pid": bar.id(), "owner": "bar", "token": "k2", "label": "Session",
        "choices": [{"id": "Work", "label": "Work"}], "expansions": {}, "view_key": ""});
    std::fs::write(voice.runtime().join("pending-pick.json"), reopened.to_string()).unwrap();
    voice.set_state("idle");
    assert!(!watcher.wait().unwrap().success());
    assert!(!voice.calls().contains("picker answer"), "{}", voice.calls());

    let mut watcher = pinned_reply_watcher(&voice, &bar);
    let fifo = pending_pick(&voice, &other_asker);
    voice.set_state("idle");
    assert!(!watcher.wait().unwrap().success());
    assert!(!voice.calls().contains("picker answer"), "{}", voice.calls());
    // Nothing was written to the other ask's FIFO: a reader finds it empty.
    let reader = std::fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NONBLOCK)
        .open(&fifo)
        .unwrap();
    let mut written = String::new();
    let _ = std::io::Read::read_to_string(&mut { reader }, &mut written);
    assert_eq!(written, "");
    end(&mut bar);
    end(&mut other_asker);
}

#[test]
fn stop_cancels_the_bars_picker_only_while_a_reply_recording_is_attached() {
    let voice = Voice::new();
    voice.set_state("idle");
    let mut bar = bar_picker(&voice);
    // Opened by key: nothing records an answer for it, so it is the user's to close.
    assert!(voice.output(&["stop"]).status.success());
    assert!(!voice.calls().contains("picker cancel"), "{}", voice.calls());
    // The voice key: a reply watcher waits on the recording.
    voice.detector("exec sleep 30");
    let mut watcher = voice.watcher(&["reply", "-", "0", ""], &[], true);
    assert!(voice.output(&["stop"]).status.success());
    assert!(watcher.wait().unwrap().success());
    end(&mut bar);
    let calls = voice.calls();
    assert_eq!(calls.matches("qs-ipc call picker cancel k1\n").count(), 1, "{calls}");
    assert!(calls.contains("voxtype record cancel"), "{calls}");
}

#[test]
fn stop_leaves_a_picker_the_bar_reopened_while_a_reply_was_recorded_for_the_old_one() {
    let voice = Voice::new();
    voice.set_state("idle");
    let mut bar = bar_picker(&voice);
    voice.detector("exec sleep 30");
    let pin = serde_json::json!({"pid": bar.id(), "owner": "bar", "fifo": null, "token": "k1"}).to_string();
    let mut watcher = voice.watcher(&["reply", "-", "0", "", &pin], &[], true);
    let reopened = serde_json::json!({"pid": bar.id(), "owner": "bar", "token": "k2", "label": "Session",
        "choices": [{"id": "Work", "label": "Work"}], "expansions": {}, "view_key": ""});
    std::fs::write(voice.runtime().join("pending-pick.json"), reopened.to_string()).unwrap();
    assert!(voice.output(&["stop"]).status.success());
    assert!(watcher.wait().unwrap().success());
    end(&mut bar);
    assert!(!voice.calls().contains("picker cancel"), "{}", voice.calls());
}

#[test]
fn a_reply_with_an_unreadable_pin_answers_nothing() {
    let voice = Voice::new();
    let mut bar = bar_picker(&voice);
    std::fs::write(voice.runtime().join("transcript.txt"), "work\n").unwrap();
    let mut watcher = voice.watcher(&["reply", "-", "0", "", "garbage"], &[], false);
    voice.set_state("idle");
    assert!(!watcher.wait().unwrap().success());
    end(&mut bar);
    assert!(!voice.calls().contains("picker answer"), "{}", voice.calls());
}

// ---- listen_for_pick --------------------------------------------------------------------------------------------

const PICKER_INTEGRATION: &str = r#"
name = "Pickers"
verbs = [
  { action = "opens", match = 'open it' },
  { action = "opens_nothing", match = 'open nothing' },
  { action = "unflagged", match = 'open plain' },
]

[actions]
opens = { run = 'sleep 0.05; cp "$WORK/next-pick.json" "$WORK/../runtime/voxcmd/pending-pick.json"', silent = true, listen_for_pick = true }
opens_nothing = { run = "true", silent = true, listen_for_pick = true }
unflagged = { run = 'cp "$WORK/next-pick.json" "$WORK/../runtime/voxcmd/pending-pick.json"', silent = true }
"#;

/// A bar with pick `k1` open, and `k2` ready for the action to publish.
fn voice_with_bar_picks() -> (Voice, Child) {
    let voice = Voice::new();
    std::fs::write(
        voice.path().join("config/integrations/pickers.toml"),
        PICKER_INTEGRATION,
    )
    .unwrap();
    let bar = bar_picker(&voice);
    let next = serde_json::json!({"pid": bar.id(), "owner": "bar", "token": "k2", "label": "Session",
        "choices": [{"id": "Work", "label": "Work"}], "expansions": {}, "view_key": ""});
    std::fs::write(voice.work("next-pick.json"), next.to_string()).unwrap();
    (voice, bar)
}

/// Routes `said` as a watcher does for a spoken command, and waits for it to finish.
fn route_by_voice(voice: &Voice, said: &str) {
    std::fs::write(voice.runtime().join("transcript.txt"), format!("{said}\n")).unwrap();
    let mut watcher = voice.watcher(&["route", "-", "0", ""], &[], false);
    voice.set_state("idle");
    assert!(watcher.wait().unwrap().success());
}

#[test]
fn a_spoken_command_that_opens_a_bar_picker_listens_for_its_reply() {
    let (voice, mut bar) = voice_with_bar_picks();
    let bar_pid = bar.id();
    route_by_voice(&voice, "open it");
    end(&mut bar);
    assert!(wait_for(|| voice.calls().contains("setsid")), "{}", voice.calls());
    assert!(
        voice.calls().contains(" internal watch reply - 0 "),
        "{}",
        voice.calls()
    );
    let pin = r#" {"pid":%PID%,"owner":"bar","fifo":null,"token":"k2"}"#.replace("%PID%", &bar_pid.to_string());
    assert!(voice.calls().contains(&pin), "{}", voice.calls());
}

#[test]
fn no_reply_listens_without_a_new_bar_picker_or_the_flag() {
    for said in ["open nothing", "open plain"] {
        let (voice, mut bar) = voice_with_bar_picks();
        route_by_voice(&voice, said);
        end(&mut bar);
        assert!(!voice.calls().contains("setsid"), "{said}: {}", voice.calls());
    }
}

#[test]
fn a_typed_run_does_not_wait_for_a_picker() {
    let (voice, mut bar) = voice_with_bar_picks();
    assert!(voice.output(&["run", "open it"]).status.success());
    end(&mut bar);
    assert!(!voice.calls().contains("setsid"), "{}", voice.calls());
}

#[test]
fn a_flagged_action_heard_in_a_session_turn_leaves_the_microphone_to_the_session() {
    let (voice, mut bar) = voice_with_bar_picks();
    // The mode is the pickers file itself, so the turn routes "open it" to the flagged action.
    let file = voice.path().join("config/integrations/pickers.toml");
    voice.set_state("recording");
    let mut watcher = voice
        .command(&["internal", "watch", "session_turn", "1:pickers:1", "0", ""])
        .spawn()
        .unwrap();
    assert!(wait_for(|| voice.debug_log().contains("watch: voxtype recording")));
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let session = serde_json::json!({"kind": "pickers", "label": "Pickers", "exit_hint": "x", "frame_id": "1",
        "integration": file, "owner": watcher.id(), "owner_start": start_time_of(watcher.id()), "unclear": 0,
        "turns": 0, "stack": [], "started": now, "mode_started": now, "last_heard": now});
    std::fs::write(voice.runtime().join("session.json"), session.to_string()).unwrap();
    std::fs::write(voice.runtime().join("transcript.txt"), "open it\n").unwrap();
    voice.set_state("idle");
    assert!(watcher.wait().unwrap().success(), "{}", voice.debug_log());
    end(&mut bar);
    // The action ran and its picker opened, so what follows is not vacuous.
    let pending = std::fs::read_to_string(voice.runtime().join("pending-pick.json")).unwrap();
    assert!(pending.contains("k2"), "{pending}");
    // The session carries on: its own next listen is a session turn, owned by a live watcher. A reply recording
    // started first, or a next listen read as a reply to the picker, would end it.
    let state: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(voice.runtime().join("session.json")).unwrap_or_default())
            .unwrap_or_else(|_| panic!("the session ended: {}", voice.debug_log()));
    let owner = state["owner"].as_u64().unwrap();
    assert_ne!(owner, u64::from(watcher.id()));
    // The stub setsid logs after the watcher has exited, so wait for the call before checking the rest.
    assert!(
        wait_for(|| voice.calls().contains("internal watch session_turn 1:pickers:1 0 ")),
        "{}",
        voice.calls()
    );
    assert!(!voice.calls().contains("internal watch reply"), "{}", voice.calls());
}

// ---- the watcher ------------------------------------------------------------------------------------------------

#[test]
fn a_watcher_routes_what_was_said_and_leaves_nothing_behind() {
    let voice = Voice::new();
    std::fs::write(voice.runtime().join("transcript.txt"), "do ok\n").unwrap();
    let mut watcher = voice.watcher(&["route", "-", "0", ""], &[], false);
    voice.set_state("idle");
    assert!(watcher.wait().unwrap().success());
    assert_eq!(std::fs::read_to_string(voice.work("ran")).unwrap(), "ran\n");
    assert!(voice.debug_log().contains("watch: transcript \"do ok\" goes to route"));
    assert!(!voice.runtime().join("transcript.txt").exists());
    assert_eq!(voice.leftovers(watcher.id()), Vec::<PathBuf>::new());
}

#[test]
fn what_a_private_mode_heard_stays_out_of_the_logs() {
    let voice = Voice::new();
    let misses = voice.path().join("state/voxcmd/no-match.log");
    std::fs::write(voice.runtime().join("transcript.txt"), "secret words").unwrap();
    let mut watcher = voice.watcher(&["route", "-", "1", ""], &[], false);
    voice.set_state("idle");
    watcher.wait().unwrap();
    assert!(
        voice
            .debug_log()
            .contains("a transcript of 12 characters goes to route")
    );
    assert!(!voice.debug_log().contains("secret"));
    assert!(!std::fs::read_to_string(&misses).unwrap_or_default().contains("secret"));
    // Heard in an ordinary mode, the same miss is logged.
    std::fs::write(voice.runtime().join("transcript.txt"), "public words").unwrap();
    let mut watcher = voice.watcher(&["route", "-", "0", ""], &[], false);
    voice.set_state("idle");
    watcher.wait().unwrap();
    assert!(std::fs::read_to_string(&misses).unwrap().contains("\tpublic words"));
}

#[test]
fn stop_mid_recording_cancels_it_and_the_watcher_cleans_up() {
    let voice = Voice::new();
    voice.detector("exec sleep 30");
    let owner_file = voice.work("recording-owner");
    let mut watcher = voice.watcher(
        &["route", "-", "0", ""],
        &[("VOXCMD_RECORDING_OWNER_FILE", &owner_file)],
        true,
    );
    let detector = voice.detector_pid().unwrap();
    assert_eq!(
        std::fs::read_to_string(&owner_file).unwrap(),
        format!("{}\n", watcher.id())
    );
    assert!(voice.output(&["stop"]).status.success());
    assert!(watcher.wait().unwrap().success());
    assert!(voice.debug_log().contains("stop: cancelling the recording voxtype"));
    assert!(voice.calls().contains("voxtype record cancel"));
    assert!(voice.debug_log().contains("watch: no transcript"));
    assert!(
        gone_within(detector, Duration::from_secs(3)),
        "the detector outlived the watcher"
    );
    assert!(!owner_file.exists());
    assert_eq!(voice.leftovers(watcher.id()), Vec::<PathBuf>::new());
}

#[test]
fn a_stop_signal_mid_recording_still_cleans_up() {
    // SIGHUP as well: logind sends it at logout.
    for stop_signal in [libc::SIGTERM, libc::SIGINT, libc::SIGHUP] {
        let voice = Voice::new();
        voice.detector("exec sleep 30");
        let owner_file = voice.work("recording-owner");
        let mut watcher = voice.watcher(
            &["route", "-", "0", ""],
            &[("VOXCMD_RECORDING_OWNER_FILE", &owner_file)],
            true,
        );
        let detector = voice.detector_pid().unwrap();
        signal(&watcher, stop_signal);
        watcher.wait().unwrap();
        assert!(gone_within(detector, Duration::from_secs(3)), "signal {stop_signal}");
        assert!(!owner_file.exists(), "signal {stop_signal}");
        assert_eq!(
            voice.leftovers(watcher.id()),
            Vec::<PathBuf>::new(),
            "signal {stop_signal}"
        );
    }
}

#[test]
fn a_discard_flag_an_earlier_watcher_left_under_the_same_pid_is_cleared() {
    let voice = Voice::new();
    std::fs::write(voice.runtime().join("transcript.txt"), "do ok\n").unwrap();
    voice.set_state("recording");
    // exec keeps the pid, so the files are there, under the watcher's own pid, before it starts.
    let mut command = Command::new("sh");
    command.env_clear();
    for (name, value) in voice.command(&[]).get_envs() {
        if let Some(value) = value {
            command.env(name, value);
        }
    }
    let mut watcher = command
        .env("VOXCMD", env!("CARGO_BIN_EXE_voxcmd"))
        .args([
            "-c",
            "touch \"$XDG_RUNTIME_DIR/voxcmd/discard.$$\" \"$XDG_RUNTIME_DIR/voxcmd/threshold.$$\"
             exec \"$VOXCMD\" internal watch route - 0 ''",
        ])
        .stdin(Stdio::null())
        .spawn()
        .unwrap();
    assert!(wait_for(|| voice.debug_log().contains("watch: voxtype recording")));
    voice.set_state("idle");
    assert!(watcher.wait().unwrap().success());
    assert!(
        !voice.debug_log().contains("watch: recording discarded"),
        "{}",
        voice.debug_log()
    );
    assert_eq!(std::fs::read_to_string(voice.work("ran")).unwrap(), "ran\n");
    assert_eq!(voice.leftovers(watcher.id()), Vec::<PathBuf>::new());
}

#[test]
fn a_stopped_watcher_leaves_an_owner_file_a_newer_watcher_took_over() {
    let voice = Voice::new();
    let owner_file = voice.work("recording-owner");
    let mut watcher = voice.watcher(
        &["route", "-", "0", ""],
        &[("VOXCMD_RECORDING_OWNER_FILE", &owner_file)],
        false,
    );
    std::fs::write(&owner_file, "99999\n").unwrap();
    signal(&watcher, libc::SIGTERM);
    watcher.wait().unwrap();
    assert_eq!(std::fs::read_to_string(&owner_file).unwrap(), "99999\n");
}

#[test]
fn a_killed_watcher_takes_its_detector_with_it() {
    let voice = Voice::new();
    voice.detector("exec sleep 30");
    let mut watcher = voice.watcher(&["route", "-", "0", ""], &[], true);
    let detector = voice.detector_pid().unwrap();
    signal(&watcher, libc::SIGKILL);
    watcher.wait().unwrap();
    assert!(gone_within(detector, Duration::from_secs(3)));
}

#[test]
fn the_detector_s_no_speech_verdict_discards_the_recording() {
    let voice = Voice::new();
    voice.detector("sleep 0.2; exit 3");
    std::fs::write(voice.runtime().join("transcript.txt"), "do ok").unwrap();
    let mut watcher = voice.watcher(&["route", "-", "0", ""], &[], true);
    assert!(watcher.wait().unwrap().success());
    let log = voice.debug_log();
    assert!(log.contains("autostop: no speech, cancelling"), "{log}");
    assert!(log.contains("watch: recording discarded"), "{log}");
    assert!(!voice.work("ran").exists());
    assert_eq!(voice.leftovers(watcher.id()), Vec::<PathBuf>::new());
}

#[test]
fn the_detector_gets_the_listen_s_settings_and_the_threshold_file() {
    let voice = Voice::new();
    voice.detector(&format!(
        "echo \"$VOXCMD_AUTOSTOP_MIN_SPEECH_SECS $VOXCMD_AUTOSTOP_THRESHOLD_FILE\" > '{}'; exec sleep 30",
        voice.work("settings").display()
    ));
    let mut watcher = voice.watcher(&["reply", "-", "0", "VOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0.1"], &[], true);
    voice.set_state("idle");
    watcher.wait().unwrap();
    assert_eq!(
        std::fs::read_to_string(voice.work("settings")).unwrap(),
        format!(
            "0.1 {}\n",
            voice.runtime().join(format!("threshold.{}", watcher.id())).display()
        )
    );
}

// ---- listen -----------------------------------------------------------------------------------------------------

#[test]
fn listen_from_idle_records_and_leaves_a_watcher_to_route() {
    let voice = Voice::new();
    voice.set_state("idle");
    std::fs::write(voice.runtime().join("transcript.txt"), "old").unwrap();
    assert!(voice.output(&["listen"]).status.success());
    let transcript = voice.runtime().join("transcript.txt");
    // The watcher is not waited for, so neither is its setsid's line.
    assert!(wait_for(|| voice.calls().contains("setsid")));
    let calls = voice.calls();
    assert!(calls.contains(&format!("voxtype record start --file={}\n", transcript.display())));
    assert!(
        calls.contains(&format!(
            "setsid owner= {} internal watch route - 0 \n",
            env!("CARGO_BIN_EXE_voxcmd")
        )),
        "{calls}"
    );
    assert!(!transcript.exists());
    assert!(voice.debug_log().contains("listen: voxtype idle\n"));
    assert!(voice.debug_log().contains("listen: recording started, watcher "));
    assert!(voice.debug_log().ends_with(" will route\n"));
}

#[test]
fn listen_with_an_ask_waiting_replies_with_a_shorter_speech_minimum() {
    let voice = Voice::new();
    voice.set_state("idle");
    let mut asking = asker(&voice);
    let pid = asking.id();
    let fifo = pending_pick(&voice, &asking);
    let owner_file = voice.work("owner");
    let output = voice
        .command(&["listen", "--start-only"])
        .env("VOXCMD_RECORDING_OWNER_FILE", &owner_file)
        .output()
        .unwrap();
    end(&mut asking);
    assert!(output.status.success());
    assert!(wait_for(|| voice.calls().contains("setsid")));
    let calls = voice.calls();
    let pin = format!(
        r#"{{"pid":{pid},"owner":"ask","fifo":{},"token":null}}"#,
        serde_json::json!(fifo)
    );
    assert!(
        calls.contains(&format!(
            "setsid owner={} {} internal watch reply - 0 VOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0.1 {}\n",
            owner_file.display(),
            env!("CARGO_BIN_EXE_voxcmd"),
            pin
        )),
        "{calls}"
    );
    assert!(
        voice
            .debug_log()
            .contains("listen: voxtype idle, for a reply, start only")
    );
}

#[test]
fn listen_stops_a_recording_and_leaves_a_transcription_alone() {
    let cases: [(&str, &[&str], bool, &str); 5] = [
        ("recording", &["listen"], true, "voxtype record stop\n"),
        ("transcribing", &["listen"], true, ""),
        // A reply's recording never ends one the user is making.
        ("recording", &["listen", "--start-only"], false, ""),
        ("transcribing", &["listen", "--start-only"], false, ""),
        (
            "booting",
            &["listen"],
            false,
            "notify-send -a voxcmd voxcmd voxtype is not ready (booting)\n",
        ),
    ];
    for (state, args, succeeds, calls) in cases {
        let voice = Voice::new();
        voice.set_state(state);
        assert_eq!(voice.output(args).status.success(), succeeds, "{state} {args:?}");
        assert_eq!(voice.calls(), calls, "{state} {args:?}");
    }
}

#[test]
fn listen_hands_an_open_session_s_next_turn_to_a_session_turn_watcher() {
    let voice = Voice::new();
    voice.set_state("idle");
    let mut owner = Command::new("sleep").arg("30").spawn().unwrap();
    let session = serde_json::json!({"kind": "click", "integration": "/i/click.sh", "label": "Click mode",
        "frame_id": "7", "owner": owner.id(), "owner_start": start_time_of(owner.id())});
    std::fs::write(voice.runtime().join("session.json"), session.to_string()).unwrap();
    assert!(voice.output(&["listen"]).status.success());
    end(&mut owner);
    assert!(
        wait_for(|| voice.calls().contains(&format!(
            "setsid owner= {} internal watch session_turn 1:click:7 0 VOXCMD_AUTOSTOP_NO_SPEECH_SECS=10\n",
            env!("CARGO_BIN_EXE_voxcmd")
        ))),
        "{}",
        voice.calls()
    );
    assert!(!voice.calls().contains("stand-in voxcmd"));
    let state: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(voice.runtime().join("session.json")).unwrap()).unwrap();
    let watcher = voice
        .debug_log()
        .split("recording started, watcher ")
        .nth(1)
        .and_then(|rest| rest.split(' ').next())
        .map(str::to_string)
        .unwrap();
    assert_eq!(state["owner"].to_string(), watcher);
    assert!(state.get("owner_handover").is_none());
}

#[test]
fn listen_clears_a_session_whose_owner_died_and_routes() {
    let voice = Voice::new();
    voice.set_state("idle");
    let mut owner = Command::new("true").spawn().unwrap();
    owner.wait().unwrap();
    let session = serde_json::json!({"kind": "click", "owner": owner.id(), "owner_start": "1"});
    std::fs::write(voice.runtime().join("session.json"), session.to_string()).unwrap();
    assert!(voice.output(&["listen"]).status.success());
    assert!(!voice.runtime().join("session.json").exists());
    assert!(
        voice
            .debug_log()
            .contains(&format!("session: owner {} is gone, clearing", owner.id()))
    );
    assert!(wait_for(|| voice.calls().contains("internal watch route")));
}

// ---- stop and session end ---------------------------------------------------------------------------------------

/// A mode `stem` whose `ended` hook is `ended`; returns its file, as a session names it.
fn mode_file(voice: &Voice, stem: &str, ended: &str) -> String {
    let file = voice.path().join(format!("config/integrations/{stem}.toml"));
    std::fs::write(
        &file,
        format!("verbs = []\n[mode]\nlabel = \"{stem}\"\nended = '{ended}'\n"),
    )
    .unwrap();
    file.display().to_string()
}

/// A click mode over a rapid mode, whose `ended` hooks log `reason frame continues` to `work/ended`.
fn open_session(voice: &Voice, owner: &Child, extra: serde_json::Value) {
    let log = r#"echo "$VOXCMD_MODE_END_REASON $VOXCMD_MODE_FRAME_ID $VOXCMD_MODE_CONTINUES" >> "$WORK/ended""#;
    open_session_with(voice, owner, extra, log);
}

fn open_session_with(voice: &Voice, owner: &Child, extra: serde_json::Value, ended: &str) {
    let (click, rapid) = (mode_file(voice, "click", ended), mode_file(voice, "rapid", ended));
    let mut session = serde_json::json!({"kind": "click", "integration": click, "label": "Click mode",
        "frame_id": "2", "owner": owner.id(), "owner_start": start_time_of(owner.id()),
        "stack": [{"kind": "rapid", "integration": rapid, "label": "Rapid mode", "frame_id": "1"}]});
    session
        .as_object_mut()
        .unwrap()
        .extend(extra.as_object().unwrap().clone());
    std::fs::write(voice.runtime().join("session.json"), session.to_string()).unwrap();
}

#[test]
fn stop_ends_the_session_the_sequences_the_ask_and_the_recording() {
    let voice = Voice::new();
    voice.set_state("transcribing");
    let mut owner = Command::new("sleep").arg("30").spawn().unwrap();
    open_session(&voice, &owner, serde_json::json!({}));
    let mut sequence = Command::new("sleep").arg("30").spawn().unwrap();
    let sequences = voice.runtime().join("sequences");
    std::fs::create_dir_all(&sequences).unwrap();
    let record = serde_json::json!({"pid": sequence.id(), "start": start_time_of(sequence.id())});
    std::fs::write(sequences.join(format!("{}.json", sequence.id())), record.to_string()).unwrap();
    std::fs::write(sequences.join("999999.json"), r#"{"pid": 999999, "start": "1"}"#).unwrap();
    let mut asking = asker(&voice);
    let fifo = pending_pick(&voice, &asking);
    let answer = std::thread::spawn(move || std::fs::read_to_string(fifo).unwrap());

    assert!(voice.output(&["stop"]).status.success());
    let answer = answer.join().unwrap();
    for child in [&mut owner, &mut sequence, &mut asking] {
        end(child);
    }
    assert_eq!(answer, "\n");
    assert!(!voice.runtime().join("session.json").exists());
    let owner_flag = voice.runtime().join(format!("discard.{}", owner.id()));
    assert!(owner_flag.exists());
    assert!(voice.runtime().join(format!("discard.{}", sequence.id())).exists());
    assert!(!sequences.join("999999.json").exists());
    let calls = voice.calls();
    assert!(
        calls.contains("notify-send -a voxcmd --transient voxcmd: Rapid mode ended stopped\n"),
        "{calls}"
    );
    assert!(calls.contains("voxtype record cancel\n"));
    assert!(wait_for(|| {
        std::fs::read_to_string(voice.work("ended")).is_ok_and(|ended| ended.lines().count() == 2)
    }));
    let mut ended: Vec<_> = std::fs::read_to_string(voice.work("ended"))
        .unwrap()
        .lines()
        .map(str::to_string)
        .collect();
    ended.sort();
    assert_eq!(ended, ["stopped 1 0", "stopped 2 0"]);
    assert_eq!(voice.debug_log().matches("session: ended hook ").count(), 2);
    assert!(voice.debug_log().contains("session ended: stopped"));
}

#[test]
fn stop_stops_a_one_recording_mode_s_recording_for_its_watcher_to_hand_over() {
    let voice = Voice::new();
    voice.set_state("recording");
    let mut owner = Command::new("sleep").arg("30").spawn().unwrap();
    open_session(
        &voice,
        &owner,
        serde_json::json!({"one_recording": true, "recording_owner": owner.id()}),
    );
    assert!(voice.output(&["stop"]).status.success());
    end(&mut owner);
    assert_eq!(voice.calls(), "voxtype record stop\n");
    let session: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(voice.runtime().join("session.json")).unwrap()).unwrap();
    assert_eq!(session["ending"], serde_json::json!({"action": "type", "by": "key"}));
}

#[test]
fn stop_with_nothing_open_does_nothing() {
    let voice = Voice::new();
    voice.set_state("idle");
    assert!(voice.output(&["stop"]).status.success());
    assert_eq!(voice.calls(), "");
}

#[test]
fn an_ended_hook_never_gets_the_caller_s_stdin() {
    let voice = Voice::new();
    let mut owner = Command::new("sleep").arg("30").spawn().unwrap();
    open_session_with(
        &voice,
        &owner,
        serde_json::json!({}),
        r#"readlink /proc/$$/fd/0 >> "$WORK/hook-stdin""#,
    );
    let mut ending = voice
        .command(&["session", "end"])
        .stdin(Stdio::piped())
        .spawn()
        .unwrap();
    assert!(ending.wait().unwrap().success());
    end(&mut owner);
    assert!(wait_for(|| {
        std::fs::read_to_string(voice.work("hook-stdin")).is_ok_and(|seen| seen.lines().count() == 2)
    }));
    let seen = std::fs::read_to_string(voice.work("hook-stdin")).unwrap();
    assert!(seen.lines().all(|stdin| stdin == "/dev/null"), "{seen}");
}

#[test]
fn session_end_waits_for_the_session_lock() {
    let voice = Voice::new();
    let mut owner = Command::new("sleep").arg("30").spawn().unwrap();
    open_session(&voice, &owner, serde_json::json!({}));
    let lock = std::fs::File::create(voice.runtime().join("session.lock")).unwrap();
    // SAFETY: flock on a descriptor this test owns.
    assert_eq!(
        unsafe { libc::flock(std::os::fd::AsRawFd::as_raw_fd(&lock), libc::LOCK_EX) },
        0
    );
    let mut ending = voice.command(&["session", "end"]).spawn().unwrap();
    std::thread::sleep(Duration::from_millis(300));
    assert!(
        ending.try_wait().unwrap().is_none(),
        "it ended the session without the lock"
    );
    assert!(voice.runtime().join("session.json").exists());
    drop(lock);
    assert!(ending.wait().unwrap().success());
    end(&mut owner);
    assert!(!voice.runtime().join("session.json").exists());
    assert!(voice.calls().contains("voxcmd: Rapid mode ended ended by request"));
}

#[test]
fn ending_a_session_whose_owner_died_only_clears_it() {
    let voice = Voice::new();
    let mut owner = Command::new("true").spawn().unwrap();
    owner.wait().unwrap();
    std::fs::write(
        voice.runtime().join("session.json"),
        serde_json::json!({"kind": "click", "owner": owner.id(), "owner_start": "1"}).to_string(),
    )
    .unwrap();
    assert!(voice.output(&["session", "end"]).status.success());
    assert!(!voice.runtime().join("session.json").exists());
    assert_eq!(voice.calls(), "");
    assert!(voice.debug_log().contains("is gone, clearing"));
}

// ---- settle -----------------------------------------------------------------------------------------------------

#[test]
fn settle_waits_for_the_overlay_but_not_forever() {
    let voice = Voice::new();
    std::fs::create_dir_all(voice.path().join("xdg/hypr/scripts")).unwrap();
    let no_bar = voice
        .command(&["internal", "settle"])
        .env("VOXCMD_APP_SETTLE_SECS", "0")
        .status();
    assert!(no_bar.unwrap().success(), "no bar to ask counts as settled");
    voice.script(
        "xdg/hypr/scripts/qs-ipc",
        "case \"$2\" in clickhints) echo open ;; *) echo closed ;; esac",
    );
    let started = Instant::now();
    let busy = voice
        .command(&["internal", "settle"])
        .env("VOXCMD_APP_SETTLE_SECS", "0")
        .env("VOXCMD_UI_SETTLE_MAX_SECS", "0.3")
        .status()
        .unwrap();
    assert_eq!(busy.code(), Some(1));
    assert!(started.elapsed() >= Duration::from_millis(300));
}

#[test]
fn settle_with_a_stalled_bar_waits_no_longer_than_its_max() {
    let voice = Voice::new();
    std::fs::create_dir_all(voice.path().join("xdg/hypr/scripts")).unwrap();
    voice.script("xdg/hypr/scripts/qs-ipc", "exec sleep 30");
    for (max_secs, bound) in [("0.5", Duration::from_millis(1200)), ("2", Duration::from_millis(2700))] {
        let started = Instant::now();
        let stalled = voice
            .command(&["internal", "settle"])
            .env("VOXCMD_APP_SETTLE_SECS", "0")
            .env("VOXCMD_UI_SETTLE_MAX_SECS", max_secs)
            .status()
            .unwrap();
        // Each probe alone could take 2 s, so two of them would be past either bound.
        assert!(started.elapsed() < bound, "max {max_secs}: {:?}", started.elapsed());
        assert_eq!(stalled.code(), Some(1), "max {max_secs}");
    }
}
