//! One-recording modes end to end (type mode's dictation): the Rust watcher, `internal wake-confirm` and Stop Voice
//! against a runtime dir of their own, with a fake one-recording integration run by this checkout's bash voxcmd (copied
//! beside stubs for the detector), and stubs for voxtype, setsid and the toasts. Each test drives one of the paths
//! where the bash port went wrong before: the lock, endings landing at once, stale clips, stop signals, the
//! detached watcher, the two binaries handing a recording over, voxcmd-wake as the caller, timeouts and privacy.
use serde_json::Value;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Output, Stdio};
use std::time::{Duration, Instant};

mod common;
use common::gone_within;

/// Type mode as far as voxcmd sees it: one recording, heard through by the wake listener, ended by these rows. Its
/// handler writes what it was handed, and blocks while `$WORK/turn-gate` exists.
const DICTATE: &str = r#"
name="Dictate"
verbs=("dictate_mode dictate mode")
declare -A actions=([dictate_mode]='session_begin dictate "$file" "Dictate mode"')
session_default_exits=0
session_private=1
session_open_ended=1
session_one_recording=1
session_wake_listens=1
session_endings=(
  "type        stop|stop typing"
  "send        send|send it"
  "discard     cancel"
  "end_session stop listening"
)
session_listen_no_speech_secs=10
session_listen_silence_secs=10
session_listen_max_secs=295
session_handle_turn() {
  echo $$ > "$WORK/turn-pid"
  if [ -e "$WORK/turn-gate" ]; then
    : > "$WORK/turn-entered"
    until [ -e "$WORK/turn-release" ]; do sleep 0.02; done
  fi
  printf '%s|%s|%s|%s\n' "$1" "${2-}" "$(discard_flag_of $$)" "$(session_state | jq -r .ending.by)" >> "$WORK/handled"
}
"#;

const TOKEN: &str = "1:dictate:f1";

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
        std::fs::write(root.path().join("config/integrations.d/dictate.sh"), DICTATE).unwrap();
        let setup = Self { root };
        let calls = setup.path().join("calls");
        let state = setup.path().join("runtime/voxtype/state");
        let transcript = setup.path().join("runtime/voxcmd/transcript.txt");
        let work = setup.path().join("work");
        // voxtype: `record stop` writes $WORK/speech as the transcript; `-q ... transcribe <file>` prints the progress
        // lines, then a blank line and $TRANSCRIBE_TEXT (none when unset: no speech), or acts out TRANSCRIBE=fail|hang.
        setup.script(
            "bin/voxtype",
            &format!(
                r#"if [ "$1" = -q ]; then
  for clip; do :; done
  echo "voxtype transcribe $clip riff=$(head -c 4 "$clip")" >> '{calls}'
  echo "voxtype flags $*" >> '{calls}'
  case "${{TRANSCRIBE-}}" in
  fail) exit 1 ;;
  hang) sleep 30 & echo $! > '{work}/hang-child'; echo $$ > '{work}/hang'; exec sleep 30 ;;
  esac
  printf 'Loading audio file: "%s"\n' "$clip"
  [ -z "${{TRANSCRIBE_TEXT-}}" ] || printf '\n%s\n' "$TRANSCRIBE_TEXT"
  exit 0
fi
echo "voxtype $*" >> '{calls}'
case "$2" in
start) echo recording > '{state}' ;;
stop) [ ! -e '{work}/speech' ] || cp '{work}/speech' '{transcript}'; echo idle > '{state}' ;;
cancel) echo idle > '{state}' ;;
esac"#,
                calls = calls.display(),
                work = work.display(),
                state = state.display(),
                transcript = transcript.display(),
            ),
        );
        // setsid logs whether it holds the session lock, which the listen that ran it holds.
        setup.script(
            "bin/setsid",
            &format!(
                "echo \"setsid locks=$(ls -l /proc/$$/fd | grep -c session.lock) $*\" >> '{}'",
                calls.display()
            ),
        );
        setup.script(
            "bin/notify-send",
            &format!("echo \"notify-send $*\" >> '{}'", calls.display()),
        );
        // The detector waits for a verdict in $WORK/verdict, the recording to end, or its TERM.
        setup.script(
            "legacy/voxcmd-autostop",
            &format!(
                ": > \"$VOXCMD_AUTOSTOP_THRESHOLD_FILE\"\necho $$ > '{work}/detector'\n\
                 while [ ! -e '{work}/verdict' ]; do sleep 0.02; done\nexit \"$(cat '{work}/verdict')\"",
                work = work.display()
            ),
        );
        // The copy sources its helpers from ../share/voxcmd, as the installed one does.
        std::fs::create_dir_all(setup.path().join("share")).unwrap();
        std::os::unix::fs::symlink(
            concat!(env!("CARGO_MANIFEST_DIR"), "/.local/share/voxcmd"),
            setup.path().join("share/voxcmd"),
        )
        .unwrap();
        let bash = setup.path().join("legacy/voxcmd");
        std::fs::copy(concat!(env!("CARGO_MANIFEST_DIR"), "/.local/bin/voxcmd"), &bash).unwrap();
        setup.settle_exec(|| setup.bash(&["list"]));
        std::fs::write(&state, "idle\n").unwrap();
        setup
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

    fn integration(&self) -> PathBuf {
        self.path().join("config/integrations.d/dictate.sh")
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
        self.settle_exec(|| {
            let mut probe = Command::new(&path);
            probe.env("VOXCMD_TEST_PROBE", "1");
            probe
        });
        path
    }

    /// Runs `probe` until it execs.
    fn settle_exec(&self, probe: impl Fn() -> Command) {
        for _ in 0..500 {
            match probe().output() {
                Err(error) if error.kind() == std::io::ErrorKind::ExecutableFileBusy => {
                    std::thread::sleep(Duration::from_millis(10));
                }
                _ => break,
            }
        }
    }

    fn env(&self, command: &mut Command) {
        command
            .env_clear()
            .env("PATH", format!("{}/bin:/usr/bin:/bin", self.path().display()))
            .env("HOME", "/nonexistent")
            .env("LC_ALL", "C")
            .env("WORK", self.path().join("work"))
            .env("VOXCMD_CONFIG_DIR", self.path().join("config"))
            .env("VOXCMD_LEGACY_BIN", self.path().join("legacy/voxcmd"))
            .env("XDG_RUNTIME_DIR", self.path().join("runtime"))
            .env("XDG_DATA_HOME", self.path().join("data"))
            .env("VOXCMD_DEBUG", "1")
            .env("VOXCMD_TIME_SCALE", "0.1")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
    }

    fn command(&self, args: &[&str]) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_voxcmd"));
        command.args(args);
        self.env(&mut command);
        command
    }

    fn bash(&self, args: &[&str]) -> Command {
        let mut command = Command::new(self.path().join("legacy/voxcmd"));
        command.args(args);
        self.env(&mut command);
        command
    }

    /// `internal wake-confirm /dev/stdin <recording>` on a clip whose transcription is `heard`.
    fn confirm(&self, heard: &str, recording: &str) -> Output {
        self.confirm_command(heard, recording).output().unwrap()
    }

    fn confirm_command(&self, heard: &str, recording: &str) -> Command {
        let mut command = self.command(&["internal", "wake-confirm", "/dev/stdin", recording]);
        command.env("TRANSCRIBE_TEXT", heard);
        command
    }

    fn set_state(&self, state: &str) {
        std::fs::write(self.path().join("runtime/voxtype/state"), format!("{state}\n")).unwrap();
    }

    fn calls(&self) -> String {
        std::fs::read_to_string(self.path().join("calls")).unwrap_or_default()
    }

    fn record_calls(&self) -> Vec<String> {
        self.calls()
            .lines()
            .filter(|line| line.starts_with("voxtype record"))
            .map(str::to_string)
            .collect()
    }

    fn debug_log(&self) -> String {
        std::fs::read_to_string(self.runtime().join("debug.log")).unwrap_or_default()
    }

    fn handled(&self) -> String {
        std::fs::read_to_string(self.work("handled")).unwrap_or_default()
    }

    fn state(&self) -> Option<Value> {
        let text = std::fs::read_to_string(self.runtime().join("session.json")).ok()?;
        serde_json::from_str(&text).ok()
    }

    /// A dictate session owned by `owner`, its recording's watcher, with `fields` over the defaults.
    fn open_session(&self, owner: u32, fields: Value) -> String {
        let mut session = serde_json::json!({"kind": "dictate", "integration": self.integration(),
            "label": "Dictate mode", "exit_hint": "say cortana stop", "started": 100, "owner": owner,
            "owner_start": start_time_of(owner), "unclear": 0, "turns": 0, "mode_started": 100, "last_heard": 100,
            "frame_id": "f1", "active_secs": 0, "resumes": 0, "open_ended": true, "one_recording": true,
            "wake_listens": true, "recording_owner": owner, "stack": []});
        session
            .as_object_mut()
            .unwrap()
            .extend(fields.as_object().unwrap().clone());
        std::fs::write(self.runtime().join("session.json"), session.to_string()).unwrap();
        format!("f1:{owner}:{}", start_time_of(owner))
    }

    /// The Rust watcher of a dictation now recording, which owns the session; and the recording as voxcmd-wake names
    /// it.
    fn rust_watcher(&self, speech: &str) -> (Child, String) {
        self.watcher(
            self.command(&["internal", "watch", "session_turn", TOKEN, "1", ""]),
            speech,
        )
    }

    fn watcher(&self, mut command: Command, speech: &str) -> (Child, String) {
        std::fs::write(self.work("speech"), speech).unwrap();
        self.set_state("recording");
        let watcher = command.stdout(Stdio::null()).spawn().unwrap();
        assert!(
            wait_for(|| self
                .debug_log()
                .contains(&format!("voxcmd[{}] watch: voxtype recording", watcher.id()))),
            "the watcher never saw the recording"
        );
        let recording = self.open_session(watcher.id(), serde_json::json!({}));
        (watcher, recording)
    }

    fn stand_in(&self) -> Child {
        Command::new("sleep").arg("30").spawn().unwrap()
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

fn exits_within(child: &mut Child, wait: Duration) -> Option<std::process::ExitStatus> {
    let deadline = Instant::now() + wait;
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            return Some(status);
        }
        if Instant::now() >= deadline {
            return None;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn end(child: &mut Child) {
    let _ = child.kill();
    let _ = child.wait();
}

fn signal(pid: u32, signal: libc::c_int) {
    // SAFETY: kill only sends a signal, to a process this test started.
    unsafe { libc::kill(i32::try_from(pid).unwrap(), signal) };
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

// ---- endings ------------------------------------------------------------------------------------------------------

#[test]
fn a_voice_ending_types_the_dictation_without_it_and_logs_only_lengths() {
    let setup = Setup::new();
    let (mut watcher, recording) = setup.rust_watcher("Hello private words. Cortana, send it.");
    let output = setup.confirm("private words. Cortana, send it.", &recording);
    assert_eq!(output.status.code(), Some(0));
    // What follows the clip's first wake word; voxcmd-wake reads only the exit code.
    assert_eq!(stdout(&output), "wake send it\n");
    assert_eq!(
        setup.state().unwrap()["ending"],
        serde_json::json!({"action": "send", "by": "voice"})
    );
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    let discard_flag = setup.runtime().join(format!("discard.{}", watcher.id()));
    assert_eq!(
        setup.handled(),
        format!("Hello private words.|send|{}|voice\n", discard_flag.display())
    );
    assert!(setup.state().is_none(), "the bottom mode left ends the session");
    assert!(
        setup
            .calls()
            .contains("notify-send -a voxcmd --transient voxcmd: Dictate mode ended done\n")
    );
    assert_eq!(setup.record_calls(), ["voxtype record stop"]);
    let log = setup.debug_log();
    assert!(
        log.contains("a transcript of 38 characters goes to session_turn"),
        "{log}"
    );
    assert!(
        log.contains("session: the dictate recording ended (voice, send)"),
        "{log}"
    );
    for said in ["private", "Hello", "send it"] {
        assert!(!log.contains(said), "{said:?} is in the debug log:\n{log}");
        assert!(
            !setup.calls().contains(said) || said == "send it",
            "{said:?} is in a call"
        );
    }
    assert!(!setup.runtime().join("transcript.txt").exists());
}

#[test]
fn a_cancel_drops_the_dictation_and_stop_listening_ends_the_whole_session() {
    let setup = Setup::new();
    let (mut watcher, recording) = setup.rust_watcher("Secret words. Cortana cancel.");
    assert_eq!(setup.confirm("Cortana cancel.", &recording).status.code(), Some(0));
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    // The watcher may see the discard flag before the confirmation's own cancel lands, and cancel too, as in bash.
    let record_calls = setup.record_calls();
    assert!(!record_calls.is_empty() && record_calls.iter().all(|call| call == "voxtype record cancel"));
    assert_eq!(setup.handled(), "");
    assert!(setup.calls().contains("Dictate mode ended cancelled, nothing typed"));

    // Over another mode: "stop listening" types the dictation, then ends both.
    let setup = Setup::new();
    let over_rapid = setup.command(&["internal", "watch", "session_turn", "2:dictate:f1", "1", ""]);
    let (mut watcher, recording) = setup.watcher(over_rapid, "All done. Cortana, stop listening.");
    let stack = serde_json::json!([{"kind": "rapid", "integration": "/i/rapid.sh", "label": "Rapid mode",
        "frame_id": "r1"}]);
    setup.open_session(watcher.id(), serde_json::json!({"stack": stack}));
    assert_eq!(
        setup.confirm("Cortana, stop listening.", &recording).status.code(),
        Some(0)
    );
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert!(setup.handled().starts_with("All done.|end_session|"));
    assert!(setup.calls().contains("voxcmd: Rapid mode ended stopped"));
    assert!(setup.state().is_none());
}

#[test]
fn the_detector_s_verdicts_say_how_the_recording_ended() {
    for (verdict, toast, typed) in [
        ("5", "Dictate mode ended it reached its recording limit (295 s)", true),
        ("0", "Dictate mode ended typed after 10 s of quiet", true),
        ("3", "Dictate mode ended nothing was said for 10 s", false),
    ] {
        let setup = Setup::new();
        let (mut watcher, _) = setup.rust_watcher("A long talk.");
        std::fs::write(setup.work("verdict"), verdict).unwrap();
        assert!(
            exits_within(&mut watcher, Duration::from_secs(10)).is_some(),
            "{verdict}"
        );
        assert!(setup.calls().contains(toast), "{verdict}: {}", setup.calls());
        assert_eq!(setup.handled().starts_with("A long talk.|type|"), typed, "{verdict}");
    }
    // An ending recorded first wins over the verdict.
    let setup = Setup::new();
    let (mut watcher, _) = setup.rust_watcher("Kept.");
    let recorded = serde_json::json!({"ending": {"action": "send", "by": "voice"}});
    setup.open_session(watcher.id(), recorded);
    std::fs::write(setup.work("verdict"), "5").unwrap();
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert!(setup.handled().starts_with("Kept.|send|"), "{}", setup.handled());
    assert!(setup.calls().contains("Dictate mode ended done"));
}

// ---- first ending wins --------------------------------------------------------------------------------------------

#[test]
fn of_endings_confirmed_at_once_exactly_one_is_recorded_and_acted_on() {
    for round in 0..4 {
        let setup = Setup::new();
        let mut owner = setup.stand_in();
        setup.set_state("recording");
        let recording = setup.open_session(owner.id(), serde_json::json!({}));
        let heard = [
            "Cortana stop.",
            "Cortana send it.",
            "Cortana cancel.",
            "Cortana stop listening.",
        ];
        let mut confirms: Vec<Child> = heard
            .iter()
            .map(|heard| setup.confirm_command(heard, &recording).spawn().unwrap())
            .collect();
        for confirm in &mut confirms {
            assert!(confirm.wait().unwrap().success());
        }
        let ending = setup.state().unwrap()["ending"].clone();
        let action = ending["action"].as_str().unwrap().to_string();
        assert_eq!(ending["by"], "voice", "round {round}");
        let expected = if action == "discard" {
            "voxtype record cancel"
        } else {
            "voxtype record stop"
        };
        assert_eq!(setup.record_calls(), [expected], "round {round}: {action}");
        let flag = setup.runtime().join(format!("discard.{}", owner.id()));
        assert_eq!(flag.exists(), action == "discard", "round {round}");
        assert_eq!(setup.debug_log().matches("dictation: ended by voice").count(), 1);
        end(&mut owner);
    }
    // Stop Voice and a confirmation at once: whichever records first, the recording is stopped once and kept.
    for round in 0..4 {
        let setup = Setup::new();
        let mut owner = setup.stand_in();
        setup.set_state("recording");
        let recording = setup.open_session(owner.id(), serde_json::json!({}));
        let mut confirm = setup.confirm_command("Cortana send it.", &recording).spawn().unwrap();
        let mut stop = setup.command(&["stop"]).spawn().unwrap();
        assert!(confirm.wait().unwrap().success() && stop.wait().unwrap().success());
        let ending = setup.state().unwrap()["ending"].clone();
        assert_eq!(ending["by"], "key", "round {round}");
        assert!(
            ending["action"] == "send" || ending["action"] == "type",
            "round {round}: {ending}"
        );
        assert_eq!(setup.record_calls(), ["voxtype record stop"], "round {round}");
        end(&mut owner);
    }
}

#[test]
fn stop_voice_records_a_key_ending_but_keeps_a_recorded_one_s_action() {
    let setup = Setup::new();
    let mut owner = setup.stand_in();
    setup.set_state("recording");
    setup.open_session(owner.id(), serde_json::json!({}));
    assert!(setup.command(&["stop"]).status().unwrap().success());
    assert_eq!(
        setup.state().unwrap()["ending"],
        serde_json::json!({"action": "type", "by": "key"})
    );
    assert_eq!(setup.record_calls(), ["voxtype record stop"]);

    // Ended by voice already, and voxtype is transcribing: only who ended it changes.
    let setup = Setup::new();
    setup.set_state("transcribing");
    let recorded = serde_json::json!({"ending": {"action": "send", "by": "voice"}});
    setup.open_session(owner.id(), recorded);
    assert!(setup.command(&["stop"]).status().unwrap().success());
    assert_eq!(
        setup.state().unwrap()["ending"],
        serde_json::json!({"action": "send", "by": "key"})
    );
    assert!(setup.record_calls().is_empty());

    // A recorded cancel stays a cancel, and Stop Voice ends the session as usual.
    let setup = Setup::new();
    setup.set_state("idle");
    let recorded = serde_json::json!({"ending": {"action": "discard", "by": "voice"}});
    setup.open_session(owner.id(), recorded);
    assert!(setup.command(&["stop"]).status().unwrap().success());
    assert!(setup.state().is_none());
    assert!(setup.runtime().join(format!("discard.{}", owner.id())).exists());

    // Before the mode's recording has a watcher (the turn that opened it still owns the session) too.
    let setup = Setup::new();
    setup.set_state("idle");
    setup.open_session(owner.id(), serde_json::json!({"recording_owner": null}));
    assert!(setup.command(&["stop"]).status().unwrap().success());
    assert!(setup.state().is_none());
    end(&mut owner);
}

// ---- stale clips ----------------------------------------------------------------------------------------------------

#[test]
fn a_clip_cut_during_another_recording_ends_nothing() {
    let setup = Setup::new();
    let mut owner = setup.stand_in();
    setup.set_state("recording");
    let recording = setup.open_session(owner.id(), serde_json::json!({}));
    let start = start_time_of(owner.id());
    for (earlier, why) in [
        // The owner's pid, recycled by another process since.
        (format!("f1:{}:1", owner.id()), "a recycled owner pid"),
        // An earlier mode's frame.
        (format!("f0:{}:{start}", owner.id()), "an earlier frame"),
        (format!("f1:1:{start}"), "another watcher"),
    ] {
        let output = setup.confirm("Cortana stop.", &earlier);
        assert_eq!(output.status.code(), Some(0), "{why}");
        assert!(setup.state().unwrap()["ending"].is_null(), "{why}");
    }
    assert_eq!(setup.debug_log().matches("heard in an earlier recording").count(), 3);
    // Naming no recording ends none either.
    setup
        .command(&["internal", "wake-confirm", "/dev/stdin"])
        .env("TRANSCRIBE_TEXT", "Cortana stop.")
        .status()
        .unwrap();
    assert!(setup.record_calls().is_empty());
    // Nor does one heard once voxtype stopped recording, or in a mode the wake listener does not hear through.
    setup.set_state("transcribing");
    setup.confirm("Cortana stop.", &recording);
    setup.set_state("recording");
    setup.open_session(owner.id(), serde_json::json!({"wake_listens": false}));
    setup.confirm("Cortana stop.", &recording);
    assert!(setup.state().unwrap()["ending"].is_null());
    assert!(setup.record_calls().is_empty());
    // Words that are no ending, after the last wake word, leave it running.
    setup.open_session(owner.id(), serde_json::json!({}));
    setup.confirm("I asked Cortana. Cortana, new paragraph.", &recording);
    assert!(setup.state().unwrap()["ending"].is_null());
    assert!(setup.debug_log().contains("dictation: the wake word, not an ending"));
    end(&mut owner);
}

// ---- the session lock -----------------------------------------------------------------------------------------------

#[test]
fn stop_voice_during_the_hand_over_waits_for_no_hook_and_the_hook_reads_the_session() {
    let setup = Setup::new();
    std::fs::write(setup.work("turn-gate"), "").unwrap();
    let (mut watcher, recording) = setup.rust_watcher("Words.");
    assert!(setup.confirm("Cortana stop.", &recording).status.success());
    assert!(wait_for(|| setup.work("turn-entered").exists()), "the hook never ran");
    // The hook holds no lock, nor does the watcher while it runs: Stop Voice gets the lock at once.
    let started = Instant::now();
    let mut stop = setup.command(&["stop"]).spawn().unwrap();
    assert!(exits_within(&mut stop, Duration::from_secs(5)).is_some_and(|status| status.success()));
    assert!(started.elapsed() < Duration::from_secs(5));
    assert_eq!(setup.state().unwrap()["ending"]["by"], "key");
    std::fs::write(setup.work("turn-release"), "").unwrap();
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    // The hook's session read, through the bridge, took the lock after Stop Voice had let it go.
    assert!(setup.handled().ends_with("|key\n"), "{}", setup.handled());
    assert!(setup.state().is_none());
    assert_eq!(setup.debug_log().matches("session ended: stopped").count(), 1);
}

// ---- stop signals and process groups --------------------------------------------------------------------------------

#[test]
fn a_stop_signal_mid_dictation_ends_the_session_once_and_leaves_nothing_behind() {
    let setup = Setup::new();
    let (watcher, _) = setup.rust_watcher("Words.");
    let mut watcher = watcher;
    assert!(wait_for(|| setup.work("detector").exists()));
    let detector: i32 = std::fs::read_to_string(setup.work("detector"))
        .unwrap()
        .trim()
        .parse()
        .unwrap();
    signal(watcher.id(), libc::SIGTERM);
    assert!(exits_within(&mut watcher, Duration::from_secs(5)).is_some());
    assert!(gone_within(detector, Duration::from_secs(2)));
    assert!(setup.state().is_none());
    let log = setup.debug_log();
    assert_eq!(log.matches("session ended: ").count(), 1, "{log}");
    assert!(log.contains("session ended: the listener stopped unexpectedly"));
    for leftover in ["discard", "threshold"] {
        assert!(!setup.runtime().join(format!("{leftover}.{}", watcher.id())).exists());
    }
}

#[test]
fn a_stop_signal_while_the_text_is_handed_over_ends_the_hook_s_group_and_the_session_once() {
    let setup = Setup::new();
    std::fs::write(setup.work("turn-gate"), "").unwrap();
    let (mut watcher, recording) = setup.rust_watcher("Words.");
    assert!(setup.confirm("Cortana stop.", &recording).status.success());
    assert!(wait_for(|| setup.work("turn-entered").exists()), "the hook never ran");
    let hook: i32 = std::fs::read_to_string(setup.work("turn-pid"))
        .unwrap()
        .trim()
        .parse()
        .unwrap();
    signal(watcher.id(), libc::SIGTERM);
    assert!(exits_within(&mut watcher, Duration::from_secs(5)).is_some());
    assert!(
        gone_within(hook, Duration::from_secs(2)),
        "the hook outlived its watcher"
    );
    assert_eq!(setup.handled(), "");
    assert!(setup.state().is_none());
    assert_eq!(setup.debug_log().matches("session ended: ").count(), 1);
}

// ---- the detached watcher -------------------------------------------------------------------------------------------

#[test]
fn listen_in_a_one_recording_mode_detaches_the_rust_watcher_without_the_session_lock() {
    let setup = Setup::new();
    let mut owner = setup.stand_in();
    setup.open_session(owner.id(), serde_json::json!({"recording_owner": null}));
    assert!(setup.command(&["listen"]).status().unwrap().success());
    end(&mut owner);
    // listen does not wait for what it detached.
    assert!(wait_for(|| setup.calls().contains("setsid ")));
    let calls = setup.calls();
    let setsid_line = calls
        .lines()
        .find(|line| line.starts_with("setsid "))
        .unwrap_or_default();
    assert!(
        setsid_line.starts_with(&format!(
            "setsid locks=0 {} internal watch session_turn {TOKEN} 1 VOXCMD_AUTOSTOP_NO_SPEECH_SECS=10",
            env!("CARGO_BIN_EXE_voxcmd")
        )),
        "{calls}"
    );
    assert!(!calls.contains("_watch"), "{calls}");
}

// ---- the bash and Rust watchers handing over ------------------------------------------------------------------------

#[test]
fn a_recording_the_bash_voxcmd_watches_is_ended_by_the_rust_confirmation() {
    let setup = Setup::new();
    let (mut watcher, recording) = setup.watcher(setup.bash(&["_watch", "session_turn", TOKEN, "1", ""]), "Words.");
    assert_eq!(
        setup.confirm("Cortana, stop typing.", &recording).status.code(),
        Some(0)
    );
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    let log = setup.debug_log();
    assert!(
        log.contains(&format!(
            "voxcmd[{}] session: the dictate recording ended (voice, type)",
            watcher.id()
        )),
        "{log}"
    );
    assert!(setup.handled().starts_with("Words.|type|"), "{}", setup.handled());
    assert!(setup.state().is_none());
}

#[test]
fn a_recording_the_rust_port_watches_is_ended_by_the_bash_confirmation() {
    let setup = Setup::new();
    let (mut watcher, recording) = setup.rust_watcher("Ship it.");
    let output = setup
        .bash(&["_wake-confirm", "/dev/stdin", &recording])
        .env("TRANSCRIBE_TEXT", "Cortana send it.")
        .output()
        .unwrap();
    assert_eq!(stdout(&output), "wake send it\n");
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    let log = setup.debug_log();
    assert!(
        log.contains(&format!(
            "voxcmd[{}] session: the dictate recording ended (voice, send)",
            watcher.id()
        )),
        "{log}"
    );
    assert!(setup.handled().starts_with("Ship it.|send|"), "{}", setup.handled());
}

// ---- voxcmd-wake as the caller --------------------------------------------------------------------------------------

/// `voxcmd _wake-confirm /dev/stdin`, as voxcmd-wake runs it: the top-level alias, the WAV on stdin.
fn wake_confirm(setup: &Setup, envs: &[(&str, &str)], args: &[&str]) -> (Option<i32>, String) {
    let wav = setup.work("trigger.wav");
    let mut clip = b"RIFF".to_vec();
    clip.extend_from_slice(&[0; 40]);
    std::fs::write(&wav, clip).unwrap();
    let mut command = setup.command(&[&["_wake-confirm"][..], args].concat());
    command.stdin(std::fs::File::open(&wav).unwrap());
    for (name, value) in envs {
        command.env(name, value);
    }
    let output = command.output().unwrap();
    (output.status.code(), stdout(&output))
}

#[test]
fn voxcmd_wake_reads_the_verdict_from_the_exit_code() {
    let setup = Setup::new();
    let stdin = ["/dev/stdin"];
    let heard = |text: &str| wake_confirm(&setup, &[("TRANSCRIBE_TEXT", text)], &stdin);
    assert_eq!(heard("Cortana."), (Some(0), "wake\n".into()));
    assert!(setup.calls().contains("voxtype transcribe /dev/stdin riff=RIFF\n"));
    assert_eq!(
        heard("So, Kortana, open Firefox."),
        (Some(0), "wake open firefox\n".into())
    );
    assert_eq!(heard("Cortanas"), (Some(1), "not_wake\n".into()));
    assert_eq!(heard("I was talking to Donna."), (Some(1), "not_wake\n".into()));
    // No blank line: voxtype heard no speech.
    assert_eq!(wake_confirm(&setup, &[], &stdin), (Some(1), "not_wake\n".into()));
    assert_eq!(
        wake_confirm(&setup, &[("TRANSCRIBE", "fail")], &stdin),
        (Some(2), "failed\n".into())
    );
    assert_eq!(wake_confirm(&setup, &[], &[]), (Some(2), "failed\n".into()));
    let log = setup.debug_log();
    for said in ["open", "irefox", "Donna", "talking"] {
        assert!(!log.contains(said), "{said:?} is in the debug log:\n{log}");
    }
    assert!(log.contains("wake confirm: no initial prompt"));
    assert!(log.contains("ggml-base.en.bin is missing"));
    assert!(setup.calls().contains("voxtype flags -q transcribe /dev/stdin\n"));
}

#[test]
fn the_daemon_s_prompt_and_the_downloaded_model_are_passed_on() {
    let setup = Setup::new();
    setup.script("bin/voxtype-prompt", "echo 'stub prompt.'");
    let models = setup.path().join("data/voxtype/models");
    std::fs::create_dir_all(&models).unwrap();
    std::fs::write(models.join("ggml-tiny.en.bin"), "").unwrap();
    let envs = [
        ("TRANSCRIBE_TEXT", "Cortana."),
        ("VOXCMD_WAKE_CONFIRM_MODEL", "tiny.en"),
    ];
    assert_eq!(wake_confirm(&setup, &envs, &["/dev/stdin"]).0, Some(0));
    assert!(
        setup
            .calls()
            .contains("voxtype flags -q --model tiny.en --initial-prompt stub prompt. transcribe /dev/stdin\n"),
        "{}",
        setup.calls()
    );
}

// ---- timeouts -------------------------------------------------------------------------------------------------------

#[test]
fn a_stuck_transcription_fails_in_time_and_leaves_no_voxtype_behind() {
    let setup = Setup::new();
    let started = Instant::now();
    let envs = [("TRANSCRIBE", "hang"), ("VOXCMD_WAKE_CONFIRM_TIMEOUT_SECS", "1")];
    assert_eq!(
        wake_confirm(&setup, &envs, &["/dev/stdin"]),
        (Some(2), "failed\n".into())
    );
    assert!(started.elapsed() < Duration::from_secs(4), "{:?}", started.elapsed());
    for left in ["hang", "hang-child"] {
        let pid: i32 = std::fs::read_to_string(setup.work(left))
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        assert!(
            gone_within(pid, Duration::from_secs(2)),
            "{left} outlived the confirmation"
        );
    }

    // voxcmd-wake kills the confirmation's group when it outlasts its own limit; voxtype, in a group of its own,
    // goes with it.
    let _ = std::fs::remove_file(setup.work("hang"));
    let mut confirm = setup.command(&["_wake-confirm", "/dev/stdin"]);
    confirm.env("TRANSCRIBE", "hang");
    let mut confirm = confirm.spawn().unwrap();
    assert!(wait_for(|| setup.work("hang").exists()));
    let voxtype: i32 = std::fs::read_to_string(setup.work("hang"))
        .unwrap()
        .trim()
        .parse()
        .unwrap();
    end(&mut confirm);
    assert!(
        gone_within(voxtype, Duration::from_secs(2)),
        "voxtype outlived a killed confirmation"
    );
}
