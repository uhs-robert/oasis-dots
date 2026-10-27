//! One-recording modes end to end (type mode's dictation): the Rust watcher, `internal wake-confirm` and Stop Voice
//! against a runtime dir of their own, with a fake one-recording integration and stubs for the detector, voxtype, setsid
//! and the toasts. Each test drives one of the paths
//! where the bash port went wrong before: the lock, endings landing at once, stale clips, stop signals, the
//! detached watcher, the two binaries handing a recording over, voxcmd-wake as the caller, timeouts, privacy, and
//! chains with their detached stopper.
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Output, Stdio};
use std::time::{Duration, Instant};

mod common;
mod executable;
use common::gone_within;

/// The commands a chain runs: each writes what it is to `$WORK/handled` too, after the dictation's line. `slow tap`
/// blocks while `$WORK/tap-gate` exists.
const TAP: &str = r#"
name = "Tap"
verbs = [
  { action = "tap_alpha", match = 'tap alpha' },
  { action = "tap_beta", match = 'tap beta' },
  { action = "slow_tap", match = 'slow tap' },
]

[actions]
tap_alpha = 'echo "tap alpha" >> "$WORK/handled"'
tap_beta = 'echo "tap beta" >> "$WORK/handled"'
slow_tap = { run = 'echo $$ > "$WORK/tap-pid"; : > "$WORK/tap-entered"; until [ -e "$WORK/tap-release" ]; do sleep 0.02; done; echo "slow tap" >> "$WORK/handled"', timeout_secs = 60 }
"#;

const TOKEN: &str = "1:dictate:f1";

/// `DICTATE` as a TOML mode (voxcmd-port 2.4d-3), whose `handle_turn` voxcmd runs itself, behind its guards. Its hook
/// writes the same line, from `VOXCMD_TEXT` and `VOXCMD_ENDING` (`-` when unset), and reads the session from this
/// process as typing.sh would; `$WORK/turn-hang` makes it type part of the text and hang, `$WORK/gate-child` makes it
/// start a long-lived child first, and `$WORK/turn-exit` holds its exit code.
const DICTATE_TOML: &str = r#"
name = "Dictate"
verbs = [ { action = "dictate_mode", match = 'dictate mode' } ]

[actions.dictate_mode]
enter_mode = true

[mode]
label = "Dictate mode"
default_exits = false
private = true
open_ended = true
one_recording = true
wake_listens = true
listen = { silence_secs = 10, max_secs = 295, no_speech_secs = 10 }
endings = [
  { action = "type", match = 'stop|stop typing' },
  { action = "send", match = 'send|send it' },
  { action = "discard", match = 'cancel' },
  { action = "end_session", match = 'stop listening' },
]
handle_turn = '''
echo $$ > "$WORK/turn-pid"
if [ -e "$WORK/gate-child" ]; then ( sleep 30 ) & echo $! > "$WORK/gate-child-pid"; fi
if [ -e "$WORK/turn-gate" ]; then
  : > "$WORK/turn-entered"
  until [ -e "$WORK/turn-release" ]; do sleep 0.02; done
fi
if [ -e "$WORK/turn-child" ]; then ( sleep 1; echo late; : > "$WORK/child-survived" ) & fi
if [ -e "$WORK/turn-hang" ]; then
  ( sleep 30; : > "$WORK/hang-child-survived" ) &
  echo $! > "$WORK/hang-child"
  printf 'partial|' >> "$WORK/handled"
  sleep 30
fi
by=$(jq -r .ending.by "$XDG_RUNTIME_DIR/voxcmd/session.json")
printf '%s|%s|%s
' "$VOXCMD_TEXT" "${VOXCMD_ENDING--}" "$by" >> "$WORK/handled"
exit "$(cat "$WORK/turn-exit" 2>/dev/null || echo 0)"
'''
"#;

struct Setup {
    root: tempfile::TempDir,
    integration: PathBuf,
}

impl Setup {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        for dir in [
            "config/integrations",
            "runtime/voxtype",
            "runtime/voxcmd",
            "bin",
            "stand-in",
            "work",
        ] {
            std::fs::create_dir_all(root.path().join(dir)).unwrap();
        }
        std::fs::write(root.path().join("config/integrations/tap.toml"), TAP).unwrap();
        let integration = root.path().join("config/integrations/dictate.toml");
        let setup = Self { root, integration };
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
        // setsid logs whether it holds the session lock, which the listen that ran it holds, then its pid and stdio;
        // it runs what it detaches only with $SETSID_RUN.
        setup.script(
            "bin/setsid",
            &format!(
                r#"echo "setsid locks=$(ls -l /proc/$$/fd | grep -c session.lock) $*" >> '{calls}'
stdio="$(readlink /proc/$$/fd/0),$(readlink /proc/$$/fd/1),$(readlink /proc/$$/fd/2)"
echo "setsid-proc pid=$$ stdio=$stdio" >> '{calls}'
[ -z "${{SETSID_RUN-}}" ] || exec "$@""#,
                calls = calls.display()
            ),
        );
        setup.script(
            "bin/notify-send",
            &format!("echo \"notify-send $*\" >> '{}'", calls.display()),
        );
        // The detector waits for a verdict in $WORK/verdict, the recording to end, or its TERM; it writes the room
        // threshold in $WORK/room when there is one. A chain's detector, which is given no threshold file, logs its
        // settings and waits for $WORK/chain-verdict.
        setup.script(
            "stand-in/voxcmd-autostop",
            &format!(
                r#"if [ -z "${{VOXCMD_AUTOSTOP_THRESHOLD_FILE-}}" ]; then
  echo "chain-detector threshold=${{VOXCMD_AUTOSTOP_THRESHOLD_DB-none}} no_speech=$VOXCMD_AUTOSTOP_NO_SPEECH_SECS min_speech=$VOXCMD_AUTOSTOP_MIN_SPEECH_SECS silence=$VOXCMD_AUTOSTOP_SILENCE_SECS max=$VOXCMD_AUTOSTOP_MAX_SECS" >> '{calls}'
  echo $$ > '{work}/chain-detector'
  # Gives up with the test's directory, as a failed test leaves it.
  while [ ! -e '{work}/chain-verdict' ]; do [ -d '{work}' ] || exit 4; sleep 0.02; done
  exit "$(cat '{work}/chain-verdict')"
fi
if [ -e '{work}/room' ]; then cp '{work}/room' "$VOXCMD_AUTOSTOP_THRESHOLD_FILE"; else : > "$VOXCMD_AUTOSTOP_THRESHOLD_FILE"; fi
echo $$ > '{work}/detector'
while [ ! -e '{work}/verdict' ]; do sleep 0.02; done
exit "$(cat '{work}/verdict')""#,
                calls = calls.display(),
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
        std::fs::write(&state, "idle\n").unwrap();
        setup
    }

    /// Dictate as the TOML mode, `mode_extra` added to its `[mode]` table.
    fn toml(mode_extra: &str) -> Self {
        let setup = Self::new();
        std::fs::write(&setup.integration, format!("{DICTATE_TOML}{mode_extra}\n")).unwrap();
        setup
    }

    /// The bar's `qs-ipc`, which says the click overlay is `overlay` and, the first time it is asked, runs `act`:
    /// whatever lands between the recording's end and its hook.
    fn bar(&self, overlay: &str, act: &str) {
        std::fs::create_dir_all(self.path().join("xdg/hypr/scripts")).unwrap();
        self.script(
            "xdg/hypr/scripts/qs-ipc",
            &format!(
                "echo \"qs-ipc $*\" >> '{calls}'\nif [ ! -e '{acted}' ]; then : > '{acted}'; {act}; fi\n\
                 [ \"$2 $3\" != 'clickhints state' ] || echo {overlay}",
                calls = self.path().join("calls").display(),
                acted = self.work("acted").display(),
            ),
        );
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

    fn env(&self, command: &mut Command) {
        command
            .env_clear()
            .env("PATH", format!("{}/bin:/usr/bin:/bin", self.path().display()))
            .env("HOME", "/nonexistent")
            .env("LC_ALL", "C")
            .env("WORK", self.path().join("work"))
            .env("VOXCMD_CONFIG_DIR", self.path().join("config"))
            .env("VOXCMD_STAND_IN_BIN", self.path().join("stand-in/voxcmd"))
            .env("XDG_RUNTIME_DIR", self.path().join("runtime"))
            .env("XDG_DATA_HOME", self.path().join("data"))
            .env("XDG_CONFIG_HOME", self.path().join("xdg"))
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
        let mut session = serde_json::json!({"kind": "dictate", "integration": self.integration,
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

/// The session lock, held by the test, until the dropped guard lets the processes waiting on it go at once.
struct HeldLock(std::fs::File);

impl HeldLock {
    fn take(setup: &Setup) -> Self {
        let file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(setup.runtime().join("session.lock"))
            .unwrap();
        // SAFETY: flock only locks the open file this test owns.
        assert_eq!(
            unsafe { libc::flock(std::os::fd::AsRawFd::as_raw_fd(&file), libc::LOCK_EX) },
            0
        );
        Self(file)
    }

    /// How many processes wait for the lock, from /proc/locks (a waiter's line has `->` after its number).
    fn waiters(&self) -> usize {
        let inode = std::os::unix::fs::MetadataExt::ino(&self.0.metadata().unwrap());
        std::fs::read_to_string("/proc/locks")
            .unwrap_or_default()
            .lines()
            .filter(|line| line.contains("->") && line.contains(&format!(":{inode} ")))
            .count()
    }

    /// Lets go once `count` processes wait for it.
    fn release_when_waited_on_by(self, count: usize) {
        assert!(
            wait_for(|| self.waiters() >= count),
            "{count} never waited for the lock"
        );
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
    let setup = Setup::toml("");
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
    assert_eq!(setup.handled(), "Hello private words.|send|voice\n");
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
    let setup = Setup::toml("");
    let (mut watcher, recording) = setup.rust_watcher("Secret words. Cortana cancel.");
    assert_eq!(setup.confirm("Cortana cancel.", &recording).status.code(), Some(0));
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    // The watcher may see the discard flag before the confirmation's own cancel lands, and cancel too, as in bash.
    let record_calls = setup.record_calls();
    assert!(!record_calls.is_empty() && record_calls.iter().all(|call| call == "voxtype record cancel"));
    assert_eq!(setup.handled(), "");
    assert!(setup.calls().contains("Dictate mode ended cancelled, nothing typed"));

    // Over another mode: "stop listening" types the dictation, then ends both.
    let setup = Setup::toml("");
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
        let setup = Setup::toml("");
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
    let setup = Setup::toml("");
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
        let setup = Setup::toml("");
        let mut owner = setup.stand_in();
        setup.set_state("recording");
        let recording = setup.open_session(owner.id(), serde_json::json!({}));
        let heard = [
            "Cortana stop.",
            "Cortana send it.",
            "Cortana cancel.",
            "Cortana stop listening.",
        ];
        // Held until all four wait for it, so they race for the lock together.
        let lock = HeldLock::take(&setup);
        let mut confirms: Vec<Child> = heard
            .iter()
            .map(|heard| setup.confirm_command(heard, &recording).spawn().unwrap())
            .collect();
        lock.release_when_waited_on_by(heard.len());
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
        let setup = Setup::toml("");
        let mut owner = setup.stand_in();
        setup.set_state("recording");
        let recording = setup.open_session(owner.id(), serde_json::json!({}));
        let lock = HeldLock::take(&setup);
        let mut confirm = setup.confirm_command("Cortana send it.", &recording).spawn().unwrap();
        let mut stop = setup.command(&["stop"]).spawn().unwrap();
        lock.release_when_waited_on_by(2);
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
    let setup = Setup::toml("");
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
    let setup = Setup::toml("");
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
    let setup = Setup::toml("");
    setup.set_state("idle");
    let recorded = serde_json::json!({"ending": {"action": "discard", "by": "voice"}});
    setup.open_session(owner.id(), recorded);
    assert!(setup.command(&["stop"]).status().unwrap().success());
    assert!(setup.state().is_none());
    assert!(setup.runtime().join(format!("discard.{}", owner.id())).exists());

    // Before the mode's recording has a watcher (the turn that opened it still owns the session) too.
    let setup = Setup::toml("");
    setup.set_state("idle");
    setup.open_session(owner.id(), serde_json::json!({"recording_owner": null}));
    assert!(setup.command(&["stop"]).status().unwrap().success());
    assert!(setup.state().is_none());
    end(&mut owner);
}

// ---- stale clips ----------------------------------------------------------------------------------------------------

#[test]
fn a_clip_cut_during_another_recording_ends_nothing() {
    let setup = Setup::toml("");
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
    // Nor does one heard once voxtype stopped recording, or in a mode that is not one recording.
    setup.set_state("transcribing");
    setup.confirm("Cortana stop.", &recording);
    setup.set_state("recording");
    setup.open_session(owner.id(), serde_json::json!({"one_recording": false}));
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

#[test]
fn a_verdict_the_session_is_not_waiting_for_records_no_ending() {
    // (what the session is by then, why it is refused)
    let other_mode = serde_json::json!({"stack": [{"kind": "rapid", "integration": "/i/rapid.sh", "label": "Rapid mode",
        "frame_id": "r1"}]});
    let not_mine = serde_json::json!({"owner": 1, "recording_owner": 1});
    let not_one_recording = serde_json::json!({"one_recording": false});
    for (fields, why) in [
        (other_mode, "another heard mode"),
        (not_mine, "a session that is not the watcher's"),
        (not_one_recording, "a mode that is not one_recording"),
    ] {
        let setup = Setup::toml("");
        let (mut watcher, _) = setup.rust_watcher("Words.");
        let mut stand_in = setup.stand_in();
        let mut fields = fields;
        if fields.get("owner") == Some(&serde_json::json!(1)) {
            fields["owner"] = stand_in.id().into();
            fields["owner_start"] = start_time_of(stand_in.id()).into();
            fields["recording_owner"] = stand_in.id().into();
        } else {
            fields["owner"] = watcher.id().into();
        }
        setup.open_session(watcher.id(), fields);
        std::fs::write(setup.work("verdict"), "5").unwrap();
        assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some(), "{why}");
        let ending = setup.state().map_or(Value::Null, |state| state["ending"].clone());
        assert_eq!(ending, Value::Null, "{why}");
        assert!(!setup.debug_log().contains("(cap, "), "{why}: {}", setup.debug_log());
        assert!(!setup.calls().contains("reached its recording limit"), "{why}");
        end(&mut stand_in);
    }
}

/// voxtype's `record stop` as a voice key makes it: the transcript is written and the recording over.
fn stop_recording_by_key(setup: &Setup) {
    assert!(
        Command::new(setup.path().join("bin/voxtype"))
            .args(["record", "stop"])
            .status()
            .unwrap()
            .success()
    );
}

#[test]
fn a_recording_stopped_by_the_voice_key_is_typed_and_done() {
    let setup = Setup::toml("");
    let (mut watcher, _) = setup.rust_watcher("Typed by key.");
    stop_recording_by_key(&setup);
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    let log = setup.debug_log();
    assert!(log.contains("the dictate recording ended (voice_key, type)"), "{log}");
    assert!(
        setup.handled().starts_with("Typed by key.|type|"),
        "{}",
        setup.handled()
    );
    assert!(setup.calls().contains("Dictate mode ended done\n"), "{}", setup.calls());
    assert!(setup.state().is_none());
}

#[test]
fn a_one_recording_mode_that_heard_nothing_or_was_discarded_is_over() {
    // The recording ended with no transcript.
    let setup = Setup::toml("");
    let (mut watcher, _) = setup.rust_watcher("");
    stop_recording_by_key(&setup);
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert!(setup.debug_log().contains("watch: no transcript"));
    assert!(
        setup
            .debug_log()
            .contains("the dictate recording ended (voice_key, type)")
    );
    assert_eq!(setup.handled(), "");
    assert!(setup.calls().contains("Dictate mode ended done\n"), "{}", setup.calls());
    assert!(setup.state().is_none());

    // The recording was cancelled (the discard flag, as autostop's no-speech cancel leaves it).
    let setup = Setup::toml("");
    let (mut watcher, _) = setup.rust_watcher("Dropped.");
    std::fs::write(setup.runtime().join(format!("discard.{}", watcher.id())), "").unwrap();
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert!(setup.debug_log().contains("watch: recording discarded"));
    assert!(
        setup
            .debug_log()
            .contains("the dictate recording ended (voice_key, type)")
    );
    assert_eq!(setup.handled(), "");
    assert!(setup.state().is_none());
}

#[test]
fn a_background_child_of_the_hook_neither_holds_the_turn_nor_loses_its_output() {
    let setup = Setup::toml("");
    std::fs::write(setup.work("turn-child"), "").unwrap();
    let (mut watcher, recording) = setup.rust_watcher("Words.");
    assert!(setup.confirm("Cortana stop.", &recording).status.success());
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert!(setup.handled().starts_with("Words.|type|"));
    // The watcher is gone; the child's write to stdout (a pipe voxcmd had closed would kill it) still succeeds.
    assert!(
        wait_for(|| setup.work("child-survived").exists()),
        "the hook's child died of its output"
    );
}

// ---- the session lock -----------------------------------------------------------------------------------------------

#[test]
fn stop_voice_during_the_hand_over_waits_for_no_hook_and_the_hook_reads_the_session() {
    let setup = Setup::toml("");
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
    // The hook read the session after Stop Voice had set the ending.
    assert!(setup.handled().ends_with("|key\n"), "{}", setup.handled());
    assert!(setup.state().is_none());
    assert_eq!(setup.debug_log().matches("session ended: stopped").count(), 1);
}

// ---- stop signals and process groups --------------------------------------------------------------------------------

#[test]
fn a_stop_signal_mid_dictation_ends_the_session_once_and_leaves_nothing_behind() {
    let setup = Setup::toml("");
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
    let setup = Setup::toml("");
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
    let setup = Setup::toml("");
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
    let setup = Setup::toml("");
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
    let setup = Setup::toml("");
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
    let setup = Setup::toml("");
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
    for left in ["hang", "hang-child"] {
        let _ = std::fs::remove_file(setup.work(left));
    }
    let mut confirm = setup.command(&["_wake-confirm", "/dev/stdin"]);
    confirm.env("TRANSCRIBE", "hang");
    let mut confirm = confirm.spawn().unwrap();
    assert!(wait_for(|| setup.work("hang").exists()));
    end(&mut confirm);
    for left in ["hang", "hang-child"] {
        let pid: i32 = std::fs::read_to_string(setup.work(left))
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        assert!(
            gone_within(pid, Duration::from_secs(2)),
            "{left} outlived a killed confirmation"
        );
    }
}

// ---- chains ---------------------------------------------------------------------------------------------------------

/// The pid a stub wrote to `$WORK/<name>`, once it has.
fn pid_in(setup: &Setup, name: &str) -> i32 {
    assert!(wait_for(|| setup.work(name).exists()), "{name} never started");
    std::fs::read_to_string(setup.work(name))
        .unwrap()
        .trim()
        .parse()
        .unwrap()
}

/// A confirmation whose `setsid` really starts the chain's stopper.
fn confirm_running_the_stopper(setup: &Setup, heard: &str, recording: &str) -> Output {
    let output = setup
        .confirm_command(heard, recording)
        .env("SETSID_RUN", "1")
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(0), "{heard}");
    output
}

/// The stopper's settings as a chain's confirmation passes them, with no room threshold.
const CHAIN_SETTINGS: &str = "VOXCMD_AUTOSTOP_NO_SPEECH_SECS=10\nVOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0\n\
                              VOXCMD_AUTOSTOP_SILENCE_SECS=1.5\nVOXCMD_AUTOSTOP_MAX_SECS=10";

#[test]
fn a_chained_ending_records_until_its_pause_then_the_text_is_handled_and_the_chain_runs() {
    let setup = Setup::toml("");
    let (mut watcher, recording) = setup.rust_watcher("Ship it. Cortana send it and then tap beta and then tap alpha.");
    confirm_running_the_stopper(&setup, "Cortana send it and then", &recording);
    assert_eq!(
        setup.state().unwrap()["ending"],
        serde_json::json!({"action": "send", "by": "voice", "chain": true})
    );
    // The stopper's detector, waiting for the pause, wants no speech of its own and has no room threshold to take.
    assert!(wait_for(|| setup.calls().contains(
        "chain-detector threshold=none no_speech=10 min_speech=0 silence=1.5 max=10\n"
    )));
    assert!(setup.record_calls().is_empty(), "the recording ended before its pause");
    assert!(exits_within(&mut watcher, Duration::from_millis(300)).is_none());
    std::fs::write(setup.work("chain-verdict"), "0").unwrap();
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert_eq!(setup.record_calls(), ["voxtype record stop"]);
    // The router splits what follows the ending into its steps, after the dictation was handed over without either.
    assert_eq!(setup.handled(), "Ship it.|send|voice\ntap beta\ntap alpha\n");
    assert!(setup.calls().contains("Dictate mode ended done\n"));
    assert!(setup.state().is_none());
    let log = setup.debug_log();
    assert!(log.contains("dictation: a chain follows the ending, recording until the next pause"));
    assert!(log.contains("dictation: the pause after the chained ending, stopping"));
    // Type mode is private: the chain's words are no more logged than the dictation's.
    for said in ["Ship", "tap beta", "alpha"] {
        assert!(!log.contains(said), "{said:?} is in the debug log:\n{log}");
    }
}

#[test]
fn a_cancel_with_a_chain_stops_the_recording_instead_and_drops_only_the_dictation() {
    let setup = Setup::toml("");
    let (mut watcher, recording) = setup.rust_watcher("Secret words. Cortana cancel and then tap beta.");
    confirm_running_the_stopper(&setup, "Cortana cancel and then tap", &recording);
    assert!(!setup.runtime().join(format!("discard.{}", watcher.id())).exists());
    assert!(setup.record_calls().is_empty());
    pid_in(&setup, "chain-detector");
    std::fs::write(setup.work("chain-verdict"), "0").unwrap();
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert_eq!(setup.record_calls(), ["voxtype record stop"]);
    assert_eq!(setup.handled(), "tap beta\n");
    assert!(setup.calls().contains("Dictate mode ended cancelled, nothing typed"));
}

#[test]
fn of_chained_and_plain_endings_confirmed_at_once_exactly_one_is_recorded_and_acted_on() {
    let heard = [
        "Cortana cancel and then tap beta",
        "Cortana stop.",
        "Cortana send it and then tap alpha",
        "Cortana cancel.",
    ];
    for round in 0..6 {
        let setup = Setup::toml("");
        let mut owner = setup.stand_in();
        setup.set_state("recording");
        let recording = setup.open_session(owner.id(), serde_json::json!({}));
        let lock = HeldLock::take(&setup);
        let mut confirms: Vec<Child> = heard
            .iter()
            .map(|heard| setup.confirm_command(heard, &recording).spawn().unwrap())
            .collect();
        lock.release_when_waited_on_by(heard.len());
        for confirm in &mut confirms {
            assert!(confirm.wait().unwrap().success());
        }
        let ending = setup.state().unwrap()["ending"].clone();
        let chain = ending["chain"] == true;
        // The stopper is not waited for, so its setsid may log a moment later.
        if chain {
            assert!(wait_for(|| setup.calls().contains("setsid-proc ")), "round {round}");
        }
        assert_eq!(
            setup.calls().matches("internal chain-stop").count(),
            usize::from(chain),
            "round {round}: {ending}"
        );
        let expected: &[&str] = match (chain, ending["action"].as_str().unwrap()) {
            // The stopper is detached and stops the recording at its pause, not now.
            (true, _) => &[],
            (false, "discard") => &["voxtype record cancel"],
            (false, _) => &["voxtype record stop"],
        };
        assert_eq!(setup.record_calls(), expected, "round {round}: {ending}");
        let flag = setup.runtime().join(format!("discard.{}", owner.id()));
        assert_eq!(
            flag.exists(),
            !chain && ending["action"] == "discard",
            "round {round}: {ending}"
        );
        assert_eq!(setup.debug_log().matches("dictation: ended by voice").count(), 1);
        end(&mut owner);
    }
}

#[test]
fn the_stopper_stops_only_its_own_recording_still_waiting_for_it_and_only_on_a_stop_verdict() {
    let chained = serde_json::json!({"ending": {"action": "type", "by": "voice", "chain": true}});
    // (verdict, the session over the defaults, voxtype's state, whether the recording is the stopper's, stopped)
    let cases = [
        ("0", chained.clone(), "recording", true, true),
        ("3", chained.clone(), "recording", true, true),
        ("5", chained.clone(), "recording", true, true),
        // A detector error, or the recording over before its pause.
        ("1", chained.clone(), "recording", true, false),
        ("4", chained.clone(), "recording", true, false),
        // Stop Voice made the ending a key one and stopped the recording itself.
        (
            "0",
            serde_json::json!({"ending": {"action": "type", "by": "key", "chain": true}}),
            "recording",
            true,
            false,
        ),
        (
            "0",
            serde_json::json!({"ending": {"action": "type", "by": "voice"}}),
            "recording",
            true,
            false,
        ),
        ("0", chained.clone(), "transcribing", true, false),
        ("0", chained.clone(), "recording", false, false),
    ];
    for (verdict, fields, voxtype, own_recording, stopped) in cases {
        let why = format!("{verdict} {fields} {voxtype} {own_recording}");
        let setup = Setup::toml("");
        let mut owner = setup.stand_in();
        setup.set_state(voxtype);
        let recording = setup.open_session(owner.id(), fields);
        let named = if own_recording {
            recording
        } else {
            format!("f0:{}:{}", owner.id(), start_time_of(owner.id()))
        };
        std::fs::write(setup.work("chain-verdict"), verdict).unwrap();
        let status = setup
            .command(&["_chain-stop", &named, CHAIN_SETTINGS])
            .status()
            .unwrap();
        assert!(status.success(), "{why}");
        let expected: &[&str] = if stopped { &["voxtype record stop"] } else { &[] };
        assert_eq!(setup.record_calls(), expected, "{why}");
        let left_alone = setup.debug_log().contains(&format!(
            "the chain's detector gave verdict {verdict}, recording left alone"
        ));
        assert_eq!(left_alone, verdict == "1" || verdict == "4", "{why}");
        end(&mut owner);
    }
}

#[test]
fn the_stopper_is_detached_hearing_stop_signals_without_the_lock_and_its_detector_dies_with_it() {
    let setup = Setup::toml("");
    let mut owner = setup.stand_in();
    setup.set_state("recording");
    let recording = setup.open_session(owner.id(), serde_json::json!({}));
    // The room threshold the recording's own detector measured.
    std::fs::write(setup.runtime().join(format!("threshold.{}", owner.id())), "-45.0\n").unwrap();
    // A caller that blocks TERM and ignores HUP, as an ask holding its stop signals might.
    let mut confirm = setup.confirm_command("Cortana stop and then tap beta", &recording);
    confirm.env("SETSID_RUN", "1");
    // SAFETY: sigprocmask and signal are async-signal-safe and touch only the child.
    unsafe {
        std::os::unix::process::CommandExt::pre_exec(&mut confirm, || {
            let mut set: libc::sigset_t = std::mem::zeroed();
            libc::sigemptyset(&mut set);
            libc::sigaddset(&mut set, libc::SIGTERM);
            libc::sigprocmask(libc::SIG_BLOCK, &set, std::ptr::null_mut());
            libc::signal(libc::SIGHUP, libc::SIG_IGN);
            Ok(())
        });
    }
    // Waiting for its output also shows the stopper holds none of it.
    let output = confirm.output().unwrap();
    assert_eq!(output.status.code(), Some(0));
    // Not waited for by the confirmation.
    assert!(wait_for(|| setup.calls().contains("setsid-proc ")));
    let calls = setup.calls();
    assert!(
        calls.contains(&format!(
            "setsid locks=0 {} internal chain-stop {recording} VOXCMD_AUTOSTOP_THRESHOLD_DB=-45.0\n",
            env!("CARGO_BIN_EXE_voxcmd")
        )),
        "{calls}"
    );
    let proc_line = calls.lines().find(|line| line.starts_with("setsid-proc ")).unwrap();
    assert!(
        proc_line.ends_with(" stdio=/dev/null,/dev/null,/dev/null"),
        "{proc_line}"
    );
    let stopper: i32 = proc_line
        .split("pid=")
        .nth(1)
        .unwrap()
        .split(' ')
        .next()
        .unwrap()
        .parse()
        .unwrap();
    let detector = pid_in(&setup, "chain-detector");
    // The stopper, exec'd by setsid, hears every stop signal again.
    let status = std::fs::read_to_string(format!("/proc/{stopper}/status")).unwrap();
    let mask = |name: &str| {
        let line = status.lines().find(|line| line.starts_with(name)).unwrap();
        u64::from_str_radix(line[name.len()..].trim(), 16).unwrap()
    };
    let stop_bits = [libc::SIGINT, libc::SIGTERM, libc::SIGHUP]
        .iter()
        .fold(0_u64, |bits, signal| bits | 1 << (signal - 1));
    assert_eq!(mask("SigBlk:") & stop_bits, 0, "{status}");
    assert_eq!(mask("SigIgn:") & stop_bits, 0, "{status}");
    assert!(
        setup
            .calls()
            .contains("chain-detector threshold=-45.0 no_speech=10 min_speech=0 silence=1.5 max=10\n")
    );
    // The stopper waits for its pause holding no session lock.
    let fds = std::fs::read_dir(format!("/proc/{stopper}/fd")).unwrap();
    assert!(
        fds.flatten()
            .filter_map(|fd| std::fs::read_link(fd.path()).ok())
            .all(|target| !target.ends_with("session.lock"))
    );
    let lock = std::fs::File::open(setup.runtime().join("session.lock")).unwrap();
    // SAFETY: flock only locks the open file this test owns.
    let locked = unsafe { libc::flock(std::os::fd::AsRawFd::as_raw_fd(&lock), libc::LOCK_EX | libc::LOCK_NB) };
    assert_eq!(locked, 0, "someone holds the session lock");
    drop(lock);
    signal(u32::try_from(stopper).unwrap(), libc::SIGKILL);
    assert!(
        gone_within(detector, Duration::from_secs(2)),
        "the detector outlived its stopper"
    );
    assert!(setup.record_calls().is_empty());
    end(&mut owner);
}

#[test]
fn stop_voice_while_the_dictation_is_handed_over_ends_the_session_once_and_runs_no_chain() {
    let setup = Setup::toml("");
    std::fs::write(setup.work("turn-gate"), "").unwrap();
    let (mut watcher, recording) = setup.rust_watcher("Typed. Cortana stop and then tap beta.");
    assert!(setup.confirm("Cortana stop and then tap", &recording).status.success());
    // The voice key, which leaves the voice ending as it is.
    stop_recording_by_key(&setup);
    assert!(wait_for(|| setup.work("turn-entered").exists()), "the hook never ran");
    assert!(setup.command(&["stop"]).status().unwrap().success());
    assert_eq!(
        setup.state().unwrap()["ending"],
        serde_json::json!({"action": "type", "by": "key", "chain": true})
    );
    std::fs::write(setup.work("turn-release"), "").unwrap();
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert!(setup.handled().starts_with("Typed.|type|"), "{}", setup.handled());
    assert!(!setup.handled().contains("tap"), "{}", setup.handled());
    assert!(setup.state().is_none());
    assert_eq!(setup.debug_log().matches("session ended: ").count(), 1);
    assert!(setup.debug_log().contains("session ended: stopped"));
}

/// Dictate mode over rapid mode, which goes on once the chain's dictation is handled.
fn over_rapid(setup: &Setup, speech: &str) -> (Child, String) {
    let watcher = setup.command(&["internal", "watch", "session_turn", "2:dictate:f1", "1", ""]);
    let (watcher, _) = setup.watcher(watcher, speech);
    let stack = serde_json::json!([{"kind": "rapid", "integration": "/i/rapid.sh", "label": "Rapid mode",
        "frame_id": "r1"}]);
    let recording = setup.open_session(watcher.id(), serde_json::json!({"stack": stack}));
    (watcher, recording)
}

#[test]
fn a_stop_while_the_chain_runs_ends_the_session_once() {
    // A stop signal to the watcher: its chain's action goes with it.
    let setup = Setup::toml("");
    std::fs::write(setup.work("tap-gate"), "").unwrap();
    let (mut watcher, recording) = over_rapid(&setup, "Words. Cortana stop and then slow tap.");
    assert!(setup.confirm("Cortana stop and then slow", &recording).status.success());
    stop_recording_by_key(&setup);
    assert!(wait_for(|| setup.work("tap-entered").exists()), "the chain never ran");
    assert_eq!(setup.state().unwrap()["kind"], "rapid");
    let action = pid_in(&setup, "tap-pid");
    signal(watcher.id(), libc::SIGTERM);
    assert!(exits_within(&mut watcher, Duration::from_secs(5)).is_some());
    assert!(
        gone_within(action, Duration::from_secs(2)),
        "the chain's action outlived its watcher"
    );
    assert!(setup.state().is_none());
    let log = setup.debug_log();
    assert_eq!(log.matches("session ended: ").count(), 1, "{log}");
    assert!(log.contains("session ended: the listener stopped unexpectedly"));

    // Stop Voice: the session ends at once, and the watcher, once its chain is done, neither ends it again nor listens.
    let setup = Setup::toml("");
    std::fs::write(setup.work("tap-gate"), "").unwrap();
    let (mut watcher, recording) = over_rapid(&setup, "Words. Cortana stop and then slow tap.");
    assert!(setup.confirm("Cortana stop and then slow", &recording).status.success());
    stop_recording_by_key(&setup);
    assert!(wait_for(|| setup.work("tap-entered").exists()), "the chain never ran");
    assert!(setup.command(&["stop"]).status().unwrap().success());
    assert!(setup.state().is_none());
    std::fs::write(setup.work("tap-release"), "").unwrap();
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    let log = setup.debug_log();
    assert_eq!(log.matches("session ended: ").count(), 1, "{log}");
    assert!(log.contains("session ended: stopped"));
    assert_eq!(
        setup
            .record_calls()
            .iter()
            .filter(|call| call.starts_with("voxtype record start"))
            .count(),
        0
    );
}

// ---- a TOML one-recording mode (voxcmd-port 2.4d-3) -----------------------------------------------------------------

/// The toast the guards give, with typing.sh's reason.
fn not_typed(reason: &str) -> String {
    format!("notify-send -a voxcmd --transient voxcmd: not typed {reason}\n")
}

#[test]
fn a_toml_mode_s_hook_gets_the_text_and_ending_in_its_environment_and_logs_only_lengths() {
    let setup = Setup::toml("");
    let (mut watcher, recording) = setup.rust_watcher("Hello \"$(private)\" words. Cortana, send it.");
    assert_eq!(
        setup.confirm("words. Cortana, send it.", &recording).status.code(),
        Some(0)
    );
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert_eq!(setup.handled(), "Hello \"$(private)\" words.|send|voice\n");
    assert!(setup.state().is_none(), "the bottom mode left ends the session");
    assert!(
        setup.calls().contains("voxcmd: Dictate mode ended done\n"),
        "{}",
        setup.calls()
    );
    let log = setup.debug_log();
    assert!(
        log.contains("session: the dictate recording ended (voice, send)"),
        "{log}"
    );
    assert!(!log.contains("handle_turn"), "the hook ran clean:\n{log}");
    for said in ["private", "Hello"] {
        assert!(!log.contains(said), "{said:?} is in the debug log:\n{log}");
    }
}

#[test]
fn a_toml_mode_s_reserved_endings_cancel_and_end_the_session() {
    let setup = Setup::toml("");
    let (mut watcher, recording) = setup.rust_watcher("Secret words. Cortana cancel.");
    assert_eq!(setup.confirm("Cortana cancel.", &recording).status.code(), Some(0));
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert_eq!(setup.handled(), "");
    assert!(setup.calls().contains("Dictate mode ended cancelled, nothing typed"));

    let setup = Setup::toml("");
    let (mut watcher, recording) = setup.rust_watcher("Last words. Cortana, stop listening.");
    assert_eq!(
        setup.confirm("Cortana stop listening.", &recording).status.code(),
        Some(0)
    );
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert!(
        setup.handled().starts_with("Last words.|end_session|"),
        "{}",
        setup.handled()
    );
    assert!(setup.debug_log().contains("session ended: stopped"));
}

#[test]
fn a_toml_hook_s_background_child_neither_holds_the_turn_nor_is_killed() {
    let setup = Setup::toml("");
    std::fs::write(setup.work("turn-child"), "").unwrap();
    let (mut watcher, recording) = setup.rust_watcher("Words.");
    assert!(setup.confirm("Cortana stop.", &recording).status.success());
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert!(setup.handled().starts_with("Words.|type|"), "{}", setup.handled());
    assert!(
        wait_for(|| setup.work("child-survived").exists()),
        "the hook's child was killed or died of its output"
    );
}

#[test]
fn stop_voice_during_a_toml_hand_over_waits_for_no_hook_and_the_hook_reads_the_session() {
    let setup = Setup::toml("");
    std::fs::write(setup.work("turn-gate"), "").unwrap();
    let (mut watcher, recording) = setup.rust_watcher("Words.");
    assert!(setup.confirm("Cortana stop.", &recording).status.success());
    assert!(wait_for(|| setup.work("turn-entered").exists()), "the hook never ran");
    let started = Instant::now();
    let mut stop = setup.command(&["stop"]).spawn().unwrap();
    assert!(exits_within(&mut stop, Duration::from_secs(5)).is_some_and(|status| status.success()));
    assert!(started.elapsed() < Duration::from_secs(5));
    assert_eq!(setup.state().unwrap()["ending"]["by"], "key");
    std::fs::write(setup.work("turn-release"), "").unwrap();
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert!(setup.handled().ends_with("|key\n"), "{}", setup.handled());
    assert!(setup.state().is_none());
    assert_eq!(setup.debug_log().matches("session ended: stopped").count(), 1);
}

#[test]
fn a_stop_signal_during_a_toml_hook_ends_its_group_and_the_session_once() {
    let setup = Setup::toml("");
    std::fs::write(setup.work("turn-gate"), "").unwrap();
    std::fs::write(setup.work("gate-child"), "").unwrap();
    let (mut watcher, recording) = setup.rust_watcher("Words.");
    assert!(setup.confirm("Cortana stop.", &recording).status.success());
    assert!(wait_for(|| setup.work("turn-entered").exists()), "the hook never ran");
    let hook = pid_in(&setup, "turn-pid");
    signal(watcher.id(), libc::SIGTERM);
    assert!(exits_within(&mut watcher, Duration::from_secs(5)).is_some());
    assert!(
        gone_within(hook, Duration::from_secs(2)),
        "the hook outlived its watcher"
    );
    assert!(
        gone_within(pid_in(&setup, "gate-child-pid"), Duration::from_secs(2)),
        "the hook's child outlived its watcher"
    );
    assert_eq!(setup.handled(), "");
    assert!(setup.state().is_none());
    assert_eq!(setup.debug_log().matches("session ended: ").count(), 1);
}

#[test]
fn a_toml_hook_past_its_deadline_is_ended_with_its_group_and_the_turn_goes_on() {
    let setup = Setup::toml("timeout_secs = 0.5");
    std::fs::write(setup.work("turn-hang"), "").unwrap();
    let (mut watcher, recording) = setup.rust_watcher("Words.");
    let started = Instant::now();
    assert!(setup.confirm("Cortana stop.", &recording).status.success());
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert!(started.elapsed() < Duration::from_secs(5), "{:?}", started.elapsed());
    assert!(gone_within(pid_in(&setup, "turn-pid"), Duration::from_secs(2)));
    assert!(gone_within(pid_in(&setup, "hang-child"), Duration::from_secs(2)));
    assert_eq!(setup.handled(), "partial|");
    let log = setup.debug_log();
    assert!(
        log.contains("session: dictate's handle_turn ran past 1.09 s and was ended with what it started; part of the text may have been typed"),
        "{log}"
    );
    // The label, never the words.
    let toast = "notify-send -a voxcmd --transient voxcmd: Dictate mode the turn hook timed out\n";
    assert!(setup.calls().contains(toast), "{}", setup.calls());
    assert!(!setup.calls().contains("Words"), "{}", setup.calls());
    // The mode is left as after any hand-over.
    assert!(
        setup.calls().contains("voxcmd: Dictate mode ended done\n"),
        "{}",
        setup.calls()
    );
    assert_eq!(log.matches("session ended: ").count(), 1, "{log}");
}

/// By design the chain runs: a timeout is a hook that failed, and the turn goes on from there as after any hand-over.
#[test]
fn a_chain_still_runs_after_the_hook_timed_out() {
    let setup = Setup::toml("timeout_secs = 0.5");
    std::fs::write(setup.work("turn-hang"), "").unwrap();
    let (mut watcher, recording) = setup.rust_watcher("Ship it. Cortana send it and then tap beta.");
    confirm_running_the_stopper(&setup, "Cortana send it and then", &recording);
    std::fs::write(setup.work("chain-verdict"), "0").unwrap();
    assert!(exits_within(&mut watcher, Duration::from_secs(15)).is_some());
    assert_eq!(setup.handled(), "partial|tap beta\n", "{}", setup.debug_log());
    assert!(setup.debug_log().contains("handle_turn ran past"));
    assert!(setup.state().is_none());
}

#[test]
fn a_toml_mode_that_no_longer_declares_handle_turn_drops_the_words_and_says_so() {
    let setup = Setup::toml("");
    setup.bar(
        "closed",
        &format!(
            "printf 'name = \"Dictate\"\nverbs = []\n[mode]\nlabel = \"Dictate mode\"\n' > '{}'",
            setup.integration.display()
        ),
    );
    let (mut watcher, recording) = setup.rust_watcher("Words.");
    assert!(setup.confirm("Cortana stop.", &recording).status.success());
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert!(setup.work("acted").exists(), "the bar was never asked");
    assert_eq!(setup.handled(), "");
    let log = setup.debug_log();
    assert!(
        log.contains("session: dictate has no handle_turn now; the turn is not handed over"),
        "{log}"
    );
    assert!(!log.contains("Words"), "{log}");
}

#[test]
fn a_toml_hook_that_fails_is_logged_without_a_toast_and_the_mode_is_left() {
    let setup = Setup::toml("");
    std::fs::write(setup.work("turn-exit"), "3").unwrap();
    let (mut watcher, recording) = setup.rust_watcher("Words.");
    assert!(setup.confirm("Cortana stop.", &recording).status.success());
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert!(setup.handled().starts_with("Words.|type|"));
    assert!(
        setup
            .debug_log()
            .contains("session: dictate's handle_turn failed (exit 3)")
    );
    assert!(!setup.calls().contains("not typed"), "{}", setup.calls());
    assert!(setup.calls().contains("voxcmd: Dictate mode ended done\n"));
}

#[test]
fn a_toml_hook_is_not_run_while_the_click_overlay_is_open() {
    let setup = Setup::toml("");
    setup.bar("open", ":");
    let (mut watcher, recording) = setup.rust_watcher("Words.");
    assert!(setup.confirm("Cortana stop.", &recording).status.success());
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert_eq!(setup.handled(), "");
    assert!(
        setup.calls().contains(&not_typed("the click overlay is open")),
        "{}",
        setup.calls()
    );
    assert!(
        setup
            .debug_log()
            .contains("session: dictate's handle_turn not run: the click overlay is open")
    );
    assert!(setup.calls().contains("voxcmd: Dictate mode ended done\n"));
}

/// What lands while the recording's text is on its way to the hook: Stop Voice's discard flag, a mode switch, or the
/// session's end. Each refuses the hook, which typing.sh's `type_still_wanted` did after its own checks.
#[test]
fn a_toml_hook_is_not_run_once_the_turn_s_session_or_mode_is_gone() {
    let flag_mine = "touch \"$XDG_RUNTIME_DIR/voxcmd/discard.$(cat \"$WORK/watcher-pid\")\"";
    let switch_mode = "f=\"$XDG_RUNTIME_DIR/voxcmd/session.json\"; jq -c '.frame_id = \"f2\"' \"$f\" > \"$f.new\" && mv \"$f.new\" \"$f\"";
    let end_session = "rm \"$XDG_RUNTIME_DIR/voxcmd/session.json\"";
    for act in [flag_mine, switch_mode, end_session] {
        let setup = Setup::toml("");
        setup.bar("closed", act);
        let (mut watcher, recording) = setup.rust_watcher("Words.");
        std::fs::write(setup.work("watcher-pid"), watcher.id().to_string()).unwrap();
        assert!(setup.confirm("Cortana stop.", &recording).status.success());
        assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
        assert!(setup.work("acted").exists(), "{act}: the bar was never asked");
        assert_eq!(setup.handled(), "", "{act}");
        assert!(
            setup.calls().contains(&not_typed("the session ended or was stopped")),
            "{act}: {}",
            setup.calls()
        );
        assert!(!setup.debug_log().contains("Words"), "{act}");
    }
}

/// The file breaks after the turn's integrations loaded, and before its hook runs (where the bar is asked). A file
/// broken earlier fails the whole turn, as any broken integration fails a `voxcmd run`.
#[test]
fn a_toml_mode_that_stops_loading_mid_dictation_hands_the_text_to_its_last_good_hook() {
    let setup = Setup::toml("");
    setup.bar(
        "closed",
        &format!("printf '[mode\\nlabel = ' > '{}'", setup.integration.display()),
    );
    let (mut watcher, recording) = setup.rust_watcher("Words. Cortana stop.");
    assert!(setup.confirm("Cortana stop.", &recording).status.success());
    assert!(exits_within(&mut watcher, Duration::from_secs(10)).is_some());
    assert!(setup.work("acted").exists(), "the bar was never asked");
    assert!(
        setup.handled().starts_with("Words.|type|"),
        "{}\n{}",
        setup.handled(),
        setup.debug_log()
    );
    assert!(setup.debug_log().contains("the last version that loaded stands in"));
    assert!(setup.state().is_none());
}
