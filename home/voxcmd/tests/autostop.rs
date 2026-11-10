//! `voxcmd internal autostop`: the detector on synthetic audio, type mode's pause checks, and the lifecycle with the
//! watcher (process group, signals, detached checks, the threshold file the chain's stopper reads)
//!
//! The audio is generated here, nothing recorded: `noise:<secs>:<dBFS>` is a steady hiss (a fan) and `voice:<secs>:<dBFS>`
//! a syllable-paced tone over the last noise. Verdicts are exit codes, as the watcher reads them.
mod autostop_audio;
use autostop_audio::pcm;
use std::io::Write;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

struct Rig {
    dir: tempfile::TempDir,
}

impl Rig {
    fn new() -> Self {
        let rig = Self {
            dir: tempfile::tempdir().unwrap(),
        };
        std::fs::create_dir_all(rig.path("run/voxcmd")).unwrap();
        std::fs::create_dir_all(rig.path("run/voxtype")).unwrap();
        std::fs::create_dir_all(rig.path("config")).unwrap();
        std::fs::write(rig.trace_path(), "").unwrap();
        rig
    }

    fn path(&self, name: &str) -> PathBuf {
        self.dir.path().join(name)
    }

    fn trace_path(&self) -> PathBuf {
        self.path("run/voxcmd/debug.log")
    }

    fn trace(&self) -> Vec<String> {
        std::fs::read_to_string(self.trace_path())
            .unwrap()
            .lines()
            .map(|line| line.split_once("] ").unwrap().1.to_string())
            .collect()
    }

    fn trace_has(&self, text: &str) -> bool {
        self.trace().iter().any(|line| line.contains(text))
    }

    fn script(&self, name: &str, body: &str) -> PathBuf {
        let path = self.path(name);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, format!("#!/bin/sh\n{body}\n")).unwrap();
        std::fs::set_permissions(&path, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
        path
    }

    fn command(&self, args: &[&str], env: &[(&str, &str)]) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_voxcmd"));
        for (key, _) in std::env::vars() {
            if key.starts_with("VOXCMD_") {
                command.env_remove(key);
            }
        }
        command
            .args(["internal", "autostop"])
            .args(args)
            .env("XDG_RUNTIME_DIR", self.path("run"))
            .env("VOXCMD_CONFIG_DIR", self.path("config"))
            .envs(env.iter().copied());
        command
    }

    /// Runs the detector on a file of audio: its exit code.
    fn detect(&self, audio: &[u8], env: &[(&str, &str)]) -> i32 {
        std::fs::write(self.trace_path(), "").unwrap();
        let file = self.path("audio.s16");
        std::fs::write(&file, audio).unwrap();
        self.command(&["--pcm", file.to_str().unwrap()], env)
            .output()
            .unwrap()
            .status
            .code()
            .unwrap()
    }

    /// Runs the detector on what a feeder writes into its stdin, a piece at a time.
    fn feed(&self, args: &[&str], env: &[(&str, &str)]) -> Feeder {
        std::fs::write(self.trace_path(), "").unwrap();
        let mut command = self.command(args, env);
        command
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        Feeder {
            child: command.spawn().unwrap(),
        }
    }
}

struct Feeder {
    child: Child,
}

impl Feeder {
    fn write(&mut self, audio: &[u8]) {
        self.child.stdin.as_mut().unwrap().write_all(audio).unwrap();
    }

    /// Closes the feed, which ends the audio, and returns the exit code.
    fn finish(mut self) -> i32 {
        drop(self.child.stdin.take());
        wait_for_exit(&mut self.child, Duration::from_secs(20)).code().unwrap()
    }
}

fn wait_for_exit(child: &mut Child, limit: Duration) -> std::process::ExitStatus {
    let deadline = Instant::now() + limit;
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            return status;
        }
        assert!(Instant::now() < deadline, "the detector did not exit");
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn wait_until(what: &str, mut done: impl FnMut() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(20);
    while !done() {
        assert!(Instant::now() < deadline, "timed out waiting for {what}");
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn wait_for_path(path: &Path) {
    wait_until(&format!("{}", path.display()), || path.exists());
}

fn process_is_gone(pid: i32) -> bool {
    // A zombie (state Z) is gone for this purpose: its parent has yet to reap it.
    std::fs::read_to_string(format!("/proc/{pid}/stat"))
        .map_or(true, |stat| stat.rsplit(") ").next().unwrap_or("").starts_with('Z'))
}

// ---- the detector on synthetic audio ----

const SESSION: [(&str, &str); 3] = [
    ("VOXCMD_AUTOSTOP_MIN_SPEECH_SECS", "0.4"),
    ("VOXCMD_AUTOSTOP_SILENCE_SECS", "1.5"),
    ("VOXCMD_AUTOSTOP_NO_SPEECH_SECS", "5"),
];
const REPLY: [(&str, &str); 1] = [("VOXCMD_AUTOSTOP_MIN_SPEECH_SECS", "0.1")];

#[test]
fn a_steady_fan_after_a_quiet_start_is_not_speech_then_a_pause() {
    let rig = Rig::new();
    let audio = pcm(&["noise:0.3:-75", "noise:7.7:-42"]);
    assert_eq!(rig.detect(&audio, &[]), 3);
    assert!(rig.trace_has("of speech is 0.00s against the room now"));
    assert!(rig.trace_has("verdict no speech"));
    assert_eq!(rig.detect(&audio, &SESSION), 3, "and in a session");
    assert_eq!(rig.detect(&audio, &REPLY), 3, "and for a reply");
}

#[test]
fn a_word_over_the_fan_still_stops_it_and_the_trace_says_what_it_heard() {
    let rig = Rig::new();
    let audio = pcm(&["noise:0.3:-75", "noise:2.7:-42", "voice:0.9:-18", "noise:4:-42"]);
    assert_eq!(rig.detect(&audio, &[]), 0);
    let trace = rig.trace().join("\n");
    for expected in [
        r"calibrated: room -7\d\.\d dBFS, threshold -45\.0 dBFS",
        r"speech run [\d.]+s \+[\d.]+s: mean -[\d.]+ peak -[\d.]+ threshold -[\d.]+ dBFS",
        r"verdict speech then quiet at [\d.]+s: room -4[\d.]+, threshold -3[\d.]+ dBFS, speech [\d.]+s",
    ] {
        assert!(
            regex::Regex::new(expected).unwrap().is_match(&trace),
            "{expected} in\n{trace}"
        );
    }
    assert_eq!(rig.detect(&audio, &SESSION), 0, "a session stops on it too");
}

#[test]
fn two_knocks_stop_a_command_but_a_session_only_takes_them_as_a_short_word_at_its_deadline() {
    let rig = Rig::new();
    let audio = pcm(&[
        "noise:1:-55",
        "voice:0.15:-25",
        "noise:0.35:-55",
        "voice:0.15:-25",
        "noise:5:-55",
    ]);
    assert_eq!(rig.detect(&audio, &[]), 0);
    assert!(rig.trace_has("verdict speech then quiet at 1.") || rig.trace_has("verdict speech then quiet at 2."));
    assert_eq!(rig.detect(&audio, &SESSION), 0);
    assert!(rig.trace_has("a short word, stopping"));
    assert!(rig.trace_has("verdict speech then quiet at 5."));
}

#[test]
fn a_short_word_is_transcribed_at_the_no_speech_deadline_not_cancelled() {
    let rig = Rig::new();
    let audio = pcm(&["noise:2:-48", "voice:0.15:-28", "noise:6:-48"]);
    assert_eq!(rig.detect(&audio, &[]), 0);
    assert!(rig.trace_has("a short word, stopping"));
    assert!(rig.trace_has("verdict speech then quiet at 6."));
    assert_eq!(
        rig.detect(&audio, &REPLY),
        0,
        "a reply's lower minimum stops on the pause after it"
    );
    assert!(rig.trace_has("verdict speech then quiet at 3."));
}

#[test]
fn speech_under_way_at_the_deadline_still_waits_for_its_pause() {
    let rig = Rig::new();
    let audio = pcm(&["noise:5.8:-48", "voice:0.5:-28", "noise:3:-48"]);
    assert_eq!(rig.detect(&audio, &[]), 0);
    assert!(rig.trace_has("verdict speech then quiet at 7."));
}

#[test]
fn max_secs_cuts_a_long_speech_with_its_own_verdict_and_without_it_the_speech_runs_to_its_pause() {
    let rig = Rig::new();
    let audio = pcm(&["noise:0.3:-60", "voice:9:-18", "noise:3:-60"]);
    assert_eq!(rig.detect(&audio, &[("VOXCMD_AUTOSTOP_MAX_SECS", "4")]), 5);
    assert!(rig.trace_has("recording with speech in it, cutting here"));
    assert!(rig.trace_has("verdict length limit at 4."));
    assert_eq!(rig.detect(&audio, &[]), 0);
    assert!(rig.trace_has("verdict speech then quiet at 1"));
}

#[test]
fn a_quiet_room_is_no_speech() {
    let rig = Rig::new();
    assert_eq!(rig.detect(&pcm(&["noise:6:-60"]), &[]), 3);
    assert_eq!(rig.detect(&pcm(&["noise:6:-60"]), &REPLY), 3);
}

#[test]
fn the_published_threshold_follows_a_room_that_was_quieter_at_the_start_and_speech_does_not_raise_it() {
    let rig = Rig::new();
    let file = rig.path("threshold-out");
    let env = [("VOXCMD_AUTOSTOP_THRESHOLD_FILE", file.to_str().unwrap())];
    rig.detect(&pcm(&["noise:0.3:-75", "noise:7.7:-42"]), &env);
    let followed: f64 = std::fs::read_to_string(&file).unwrap().trim().parse().unwrap();
    assert!(followed > -40.0, "{followed}");
    std::fs::remove_file(&file).unwrap();
    rig.detect(&pcm(&["noise:3:-55", "voice:4:-18", "noise:3:-55"]), &env);
    let held: f64 = std::fs::read_to_string(&file).unwrap().trim().parse().unwrap();
    assert!(held < -40.0, "{held}");
}

#[test]
fn without_the_debug_log_there_is_no_trace() {
    let rig = Rig::new();
    std::fs::remove_file(rig.trace_path()).unwrap();
    let file = rig.path("audio.s16");
    std::fs::write(&file, pcm(&["noise:6:-60"])).unwrap();
    rig.command(&["--pcm", file.to_str().unwrap()], &[]).output().unwrap();
    assert!(!rig.trace_path().exists());
}

#[test]
fn check_says_whether_it_can_listen_and_why_not() {
    let rig = Rig::new();
    let with_pw = rig.script("pw-bin/pw-record", "");
    let pw_dir = with_pw.parent().unwrap().to_str().unwrap().to_string();
    let empty_dir = rig.path("no-pw-bin");
    std::fs::create_dir_all(&empty_dir).unwrap();
    let check = |path: &str, env: &[(&str, &str)]| {
        let output = rig.command(&["--check"], env).env("PATH", path).output().unwrap();
        (
            output.status.code().unwrap(),
            String::from_utf8_lossy(&output.stdout).to_string(),
        )
    };
    assert_eq!(check(&pw_dir, &[]).0, 0);
    let (code, said) = check(&pw_dir, &[("VOXCMD_AUTOSTOP", "false")]);
    assert_eq!(code, 1);
    assert!(said.contains("turned off"), "{said}");
    let (code, said) = check(empty_dir.to_str().unwrap(), &[]);
    assert_eq!(code, 1);
    assert!(said.contains("pw-record is not installed"), "{said}");
    std::fs::write(rig.path("config/autostop.conf"), "bogus = 1\n").unwrap();
    assert!(check(&pw_dir, &[]).1.contains("unknown setting: bogus"));
}

#[test]
fn turned_off_or_without_pw_record_a_listen_exits_with_the_protocol_codes() {
    let rig = Rig::new();
    let off = rig.command(&[], &[("VOXCMD_AUTOSTOP", "off")]).output().unwrap();
    assert_eq!(off.status.code(), Some(4));
    let none = rig.path("no-pw-bin");
    std::fs::create_dir_all(&none).unwrap();
    let missing = rig.command(&[], &[]).env("PATH", &none).output().unwrap();
    assert_eq!(missing.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&missing.stderr).contains("pw-record is not installed"));
}

#[test]
fn the_recording_ending_elsewhere_is_nothing_to_do() {
    let rig = Rig::new();
    let state = rig.path("state");
    std::fs::write(&state, "recording\n").unwrap();
    let mut feeder = rig.feed(&["--pcm", "-", "--state-file", state.to_str().unwrap()], &[]);
    feeder.write(&pcm(&["noise:1:-55"]));
    wait_until("the first frames", || rig.trace_has("calibrated"));
    std::fs::write(&state, "idle\n").unwrap();
    assert_eq!(feeder.finish(), 4);
}

// ---- type mode's pause checks ----

struct Checks<'a> {
    rig: &'a Rig,
    runs: PathBuf,
    gate: PathBuf,
}

impl<'a> Checks<'a> {
    /// A stand-in voxcmd that keeps each clip and its arguments, numbered in the order they ran. Its first run waits
    /// for the gate when PAUSE_GATE is set, and each run ends the recording in the state file PAUSE_CANCELS names, as
    /// a check hearing "cortana cancel" does.
    fn new(rig: &'a Rig) -> Self {
        let runs = rig.path("pause-runs");
        std::fs::create_dir_all(&runs).unwrap();
        rig.script(
            "pause-voxcmd",
            r#"run=$(($(find "$PAUSE_RUNS" -name '*.args' | wc -l) + 1))
[ "$run" = 1 ] || [ -e "$PAUSE_RUNS/$((run - 1)).done" ] || : >"$PAUSE_RUNS/overlapped"
cat >"$PAUSE_RUNS/$run.wav"
printf '%s|%s|%s\n' "$*" "${VOXCMD_AUTOSTOP_PAUSE_CHECK_RECORDING-}" "${VOXCMD_AUTOSTOP_THRESHOLD_FILE-}" >"$PAUSE_RUNS/$run.args"
if [ "$run" = 1 ] && [ -n "${PAUSE_GATE-}" ]; then until [ -e "$PAUSE_GATE" ]; do sleep 0.02; done; fi
[ -z "${PAUSE_CANCELS-}" ] || echo idle >"$PAUSE_CANCELS"
: >"$PAUSE_RUNS/$run.done""#,
        );
        Self {
            rig,
            gate: rig.path("pause-gate"),
            runs,
        }
    }

    fn env(&self, extra: &[(&str, &str)]) -> Vec<(String, String)> {
        let mut env: Vec<(String, String)> = [
            ("VOXCMD_AUTOSTOP_MIN_SPEECH_SECS", "0.4"),
            ("VOXCMD_AUTOSTOP_SILENCE_SECS", "10"),
            ("VOXCMD_AUTOSTOP_NO_SPEECH_SECS", "10"),
            ("VOXCMD_AUTOSTOP_PAUSE_CHECK_RECORDING", "f1:1:1"),
        ]
        .iter()
        .map(|(key, value)| (key.to_string(), value.to_string()))
        .collect();
        env.push((
            "VOXCMD_AUTOSTOP_PAUSE_CHECK_VOXCMD".into(),
            self.rig.path("pause-voxcmd").to_string_lossy().into(),
        ));
        env.push((
            "VOXCMD_AUTOSTOP_THRESHOLD_FILE".into(),
            self.rig.path("pause-threshold").to_string_lossy().into(),
        ));
        env.push(("PAUSE_RUNS".into(), self.runs.to_string_lossy().into()));
        env.extend(extra.iter().map(|(key, value)| (key.to_string(), value.to_string())));
        env
    }

    fn feed(&self, args: &[&str], extra: &[(&str, &str)]) -> Feeder {
        let env = self.env(extra);
        let borrowed: Vec<(&str, &str)> = env.iter().map(|(key, value)| (key.as_str(), value.as_str())).collect();
        self.rig.feed(args, &borrowed)
    }

    fn made(&self) -> usize {
        std::fs::read_dir(&self.runs)
            .unwrap()
            .filter(|entry| entry.as_ref().unwrap().file_name().to_string_lossy().ends_with(".args"))
            .count()
    }

    fn run_path(&self, name: &str) -> PathBuf {
        self.runs.join(name)
    }

    /// A clip's WAV header fields and its loudest sample.
    fn clip(&self, run: usize) -> (u32, u16, u16, usize, i16) {
        let bytes = std::fs::read(self.run_path(&format!("{run}.wav"))).unwrap();
        let samples = bytes[44..]
            .chunks(2)
            .map(|pair| i16::from_le_bytes([pair[0], pair[1]]).saturating_abs())
            .max()
            .unwrap_or(0);
        (
            u32::from_le_bytes(bytes[24..28].try_into().unwrap()),
            u16::from_le_bytes(bytes[22..24].try_into().unwrap()),
            u16::from_le_bytes(bytes[34..36].try_into().unwrap()),
            (bytes.len() - 44) / 2,
            samples,
        )
    }
}

fn word(first_noise: f64, voice_db: f64) -> Vec<u8> {
    pcm(&[
        &format!("noise:{first_noise}:-55"),
        &format!("voice:1:{voice_db}"),
        "noise:0.7:-55",
    ])
}

#[test]
fn each_pause_after_speech_hands_its_last_three_seconds_to_the_confirmation() {
    let rig = Rig::new();
    let checks = Checks::new(&rig);
    let mut feeder = checks.feed(&["--pcm", "-"], &[]);
    feeder.write(&word(2.0, -18.0));
    wait_for_path(&checks.run_path("1.done"));
    feeder.write(&word(0.1, -24.0));
    wait_for_path(&checks.run_path("2.done"));
    feeder.write(&pcm(&["noise:0.5:-55"]));
    assert_eq!(feeder.finish(), 4, "no verdict of its own yet");
    assert_eq!(checks.made(), 2);
    for run in [1, 2] {
        let (rate, channels, bits, frames, _) = checks.clip(run);
        assert_eq!((rate, channels, bits, frames), (16000, 1, 16, 3 * 16000));
    }
    assert!(rig.trace_has("pause check at 3.6"));
    // Named as a pause, without the recording's own settings in the check's environment.
    assert_eq!(
        std::fs::read_to_string(checks.run_path("1.args")).unwrap(),
        "_wake-confirm /dev/stdin f1:1:1 pause||\n"
    );
}

#[test]
fn one_long_pause_is_one_check_and_quiet_alone_or_no_recording_is_none() {
    let rig = Rig::new();
    let checks = Checks::new(&rig);
    let mut feeder = checks.feed(&["--pcm", "-"], &[]);
    feeder.write(&pcm(&["noise:2:-55", "voice:1:-18", "noise:4:-55"]));
    wait_for_path(&checks.run_path("1.done"));
    feeder.write(&pcm(&["noise:0.5:-55"]));
    feeder.finish();
    assert_eq!(checks.made(), 1);
    let quiet = Checks::new(&rig);
    std::fs::remove_dir_all(&quiet.runs).unwrap();
    std::fs::create_dir_all(&quiet.runs).unwrap();
    let mut feeder = quiet.feed(&["--pcm", "-"], &[]);
    feeder.write(&pcm(&["noise:6:-60"]));
    feeder.finish();
    assert_eq!(quiet.made(), 0, "quiet alone is no check");
    let mut feeder = quiet.feed(&["--pcm", "-"], &[("VOXCMD_AUTOSTOP_PAUSE_CHECK_RECORDING", "")]);
    feeder.write(&word(2.0, -18.0));
    feeder.write(&pcm(&["noise:0.5:-55"]));
    feeder.finish();
    assert_eq!(quiet.made(), 0, "no recording named, no pause checked");
}

#[test]
fn pauses_during_a_check_keep_only_the_newest_clip_run_once_the_check_is_over() {
    let rig = Rig::new();
    let checks = Checks::new(&rig);
    let gate = checks.gate.to_str().unwrap().to_string();
    let mut feeder = checks.feed(&["--pcm", "-"], &[("PAUSE_GATE", &gate)]);
    feeder.write(&word(2.0, -18.0));
    wait_for_path(&checks.run_path("1.args"));
    feeder.write(&word(0.1, -24.0));
    feeder.write(&word(0.1, -12.0));
    wait_until("both pauses to wait", || {
        rig.trace()
            .iter()
            .filter(|line| line.contains("waits for the check running"))
            .count()
            >= 2
    });
    std::fs::write(&checks.gate, "").unwrap();
    wait_for_path(&checks.run_path("1.done"));
    feeder.write(&pcm(&["noise:0.5:-55"]));
    wait_for_path(&checks.run_path("2.done"));
    feeder.finish();
    assert_eq!(checks.made(), 2);
    assert!(!checks.run_path("overlapped").exists());
    assert!(checks.clip(2).4 > 10000 && checks.clip(1).4 < 10000);
}

#[test]
fn checks_change_neither_the_verdict_nor_when_it_comes() {
    let rig = Rig::new();
    let checks = Checks::new(&rig);
    let audio = pcm(&["noise:2:-55", "voice:1:-18", "noise:2:-55"]);
    let verdict_line = |rig: &Rig| {
        rig.trace()
            .into_iter()
            .find(|line| line.starts_with("verdict "))
            .unwrap()
    };
    let mut with = checks.feed(&["--pcm", "-"], &[("VOXCMD_AUTOSTOP_SILENCE_SECS", "1.5")]);
    with.write(&audio);
    let with_code = with.finish();
    let with_verdict = verdict_line(&rig);
    let mut without = checks.feed(
        &["--pcm", "-"],
        &[
            ("VOXCMD_AUTOSTOP_SILENCE_SECS", "1.5"),
            ("VOXCMD_AUTOSTOP_PAUSE_CHECK_RECORDING", ""),
        ],
    );
    without.write(&audio);
    // The pause verdict waits for the check, which the stand-in ends at once.
    assert_eq!((with_code, without.finish()), (0, 0));
    assert_eq!(with_verdict, verdict_line(&rig));
}

#[test]
fn a_pause_verdict_waits_for_the_check_still_running_and_gives_way_when_it_ends_the_recording() {
    let rig = Rig::new();
    let checks = Checks::new(&rig);
    let state = rig.path("pause-state");
    std::fs::write(&state, "recording\n").unwrap();
    let (gate, state_text) = (
        checks.gate.to_str().unwrap().to_string(),
        state.to_str().unwrap().to_string(),
    );
    let mut feeder = checks.feed(
        &["--pcm", "-", "--state-file", &state_text],
        &[
            ("VOXCMD_AUTOSTOP_SILENCE_SECS", "1.5"),
            ("PAUSE_GATE", &gate),
            ("PAUSE_CANCELS", &state_text),
        ],
    );
    feeder.write(&pcm(&["noise:2:-55", "voice:1:-18", "noise:2:-55"]));
    wait_for_path(&checks.run_path("1.args"));
    wait_until("the stop to wait", || {
        rig.trace_has("the stop waits for the pause checks")
    });
    std::fs::write(&checks.gate, "").unwrap();
    assert_eq!(
        feeder.finish(),
        4,
        "the cancel ended the recording, so the pause must not stop it"
    );
    wait_for_path(&checks.run_path("1.done"));
}

#[test]
fn it_stops_once_a_check_that_heard_no_ending_is_over() {
    let rig = Rig::new();
    let checks = Checks::new(&rig);
    let gate = checks.gate.to_str().unwrap().to_string();
    let mut feeder = checks.feed(
        &["--pcm", "-"],
        &[("VOXCMD_AUTOSTOP_SILENCE_SECS", "1.5"), ("PAUSE_GATE", &gate)],
    );
    feeder.write(&pcm(&["noise:2:-55", "voice:1:-18", "noise:2:-55"]));
    wait_until("the stop to wait", || {
        rig.trace_has("the stop waits for the pause checks")
    });
    std::fs::write(&checks.gate, "").unwrap();
    assert_eq!(feeder.finish(), 0);
    wait_for_path(&checks.run_path("1.done"));
}

#[test]
fn a_hung_check_holds_the_pause_verdict_back_only_pause_check_wait_secs() {
    let rig = Rig::new();
    let checks = Checks::new(&rig);
    let gate = checks.gate.to_str().unwrap().to_string();
    let mut feeder = checks.feed(
        &["--pcm", "-"],
        &[
            ("VOXCMD_AUTOSTOP_SILENCE_SECS", "1.5"),
            ("VOXCMD_AUTOSTOP_PAUSE_CHECK_WAIT_SECS", "0.5"),
            ("PAUSE_GATE", &gate),
        ],
    );
    feeder.write(&pcm(&["noise:2:-55", "voice:1:-18", "noise:2:-55"]));
    assert_eq!(feeder.finish(), 0);
    assert!(!checks.run_path("1.done").exists());
    assert!(rig.trace_has("still running after 0.5s, stopping anyway"));
    std::fs::write(&checks.gate, "").unwrap();
    wait_for_path(&checks.run_path("1.done"));
}

// ---- the lifecycle with the watcher ----

#[test]
fn a_check_still_running_when_the_detector_exits_is_left_to_finish_in_a_session_of_its_own() {
    let rig = Rig::new();
    let checks = Checks::new(&rig);
    let probe = rig.script(
        "probe-voxcmd",
        // What the check inherits: its descriptors (a feed pipe would be a leak that holds the feeder's reader), its
        // session, and whether it outlives the detector.
        r#"ls -l /proc/$$/fd | sed 's/.*-> //' | sort >"$PAUSE_RUNS/fds"
ps -o sid= -p $$ >"$PAUSE_RUNS/sid"
echo $$ >"$PAUSE_RUNS/pid"
cat >/dev/null
until [ -e "$PAUSE_GATE" ]; do sleep 0.02; done
: >"$PAUSE_RUNS/done""#,
    );
    let gate = checks.gate.to_str().unwrap().to_string();
    let probe_path = probe.to_str().unwrap().to_string();
    let mut feeder = checks.feed(
        &["--pcm", "-"],
        &[
            ("VOXCMD_AUTOSTOP_PAUSE_CHECK_VOXCMD", &probe_path),
            ("PAUSE_GATE", &gate),
        ],
    );
    let detector_pid = feeder.child.id();
    feeder.write(&word(2.0, -18.0));
    wait_for_path(&checks.run_path("pid"));
    assert_eq!(feeder.finish(), 4);
    let check_pid: u32 = std::fs::read_to_string(checks.run_path("pid"))
        .unwrap()
        .trim()
        .parse()
        .unwrap();
    assert!(!checks.run_path("done").exists(), "the check outlives the detector");
    assert!(!process_is_gone(check_pid as i32));
    // Its own session leader (sid is its pid) and not the detector's.
    let sid: u32 = std::fs::read_to_string(checks.run_path("sid"))
        .unwrap()
        .trim()
        .parse()
        .unwrap();
    assert_eq!(sid, check_pid);
    assert_ne!(sid, detector_pid);
    let fds = std::fs::read_to_string(checks.run_path("fds")).unwrap();
    assert!(
        !fds.contains("pipe:"),
        "no feed or audio pipe leaks into the check: {fds}"
    );
    std::fs::write(&checks.gate, "").unwrap();
    wait_for_path(&checks.run_path("done"));
}

/// A stand-in `pw-record` that records its pid and then plays no audio, in a directory to put first on PATH.
fn silent_pw_record(rig: &Rig) -> (String, PathBuf) {
    let pid_file = rig.path("pw-pid");
    rig.script(
        "pw-bin/pw-record",
        &format!("echo $$ >'{}'\nexec sleep 300", pid_file.display()),
    );
    let path = format!(
        "{}:{}",
        rig.path("pw-bin").display(),
        std::env::var("PATH").unwrap_or_default()
    );
    (path, pid_file)
}

fn listening(rig: &Rig) -> (Child, i32, PathBuf) {
    let (path, pid_file) = silent_pw_record(rig);
    std::fs::write(rig.path("run/voxtype/state"), "recording\n").unwrap();
    let mut command = rig.command(&[], &[]);
    // As the watcher starts it: a process group of its own, which the watcher kills.
    command
        .env("PATH", path)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0);
    let child = command.spawn().unwrap();
    wait_for_path(&pid_file);
    wait_until("pw-record's pid", || {
        !std::fs::read_to_string(&pid_file).unwrap().is_empty()
    });
    let pw_pid = std::fs::read_to_string(&pid_file).unwrap().trim().parse().unwrap();
    (child, pw_pid, pid_file)
}

#[test]
fn a_stop_signal_exits_4_and_takes_pw_record_with_it() {
    for (signal, name) in [(libc::SIGTERM, "TERM"), (libc::SIGHUP, "HUP"), (libc::SIGINT, "INT")] {
        let rig = Rig::new();
        let (mut child, pw_pid, _) = listening(&rig);
        // SAFETY: signals the detector this test started.
        unsafe { libc::kill(child.id() as i32, signal) };
        let status = wait_for_exit(&mut child, Duration::from_secs(10));
        assert_eq!(status.code(), Some(4), "{name}: {status:?}");
        wait_until("pw-record to end", || process_is_gone(pw_pid));
    }
}

#[test]
fn the_watchers_group_kill_ends_the_detector_with_4_and_its_pw_record() {
    let rig = Rig::new();
    let (mut child, pw_pid, _) = listening(&rig);
    // The detector leads its group and pw-record is a member, as `watch::Detector` relies on.
    // SAFETY: reads the group ids of processes this test started.
    let (detector_group, pw_group) = unsafe { (libc::getpgid(child.id() as i32), libc::getpgid(pw_pid)) };
    assert_eq!((detector_group, pw_group), (child.id() as i32, child.id() as i32));
    // SAFETY: signals the group this test started.
    unsafe { libc::killpg(child.id() as i32, libc::SIGTERM) };
    let status = wait_for_exit(&mut child, Duration::from_secs(10));
    assert_eq!(status.code(), Some(4), "{status:?}");
    assert!(status.signal().is_none());
    wait_until("pw-record to end", || process_is_gone(pw_pid));
}

#[test]
fn a_detector_killed_outright_still_takes_pw_record_with_it() {
    let rig = Rig::new();
    let (mut child, pw_pid, _) = listening(&rig);
    child.kill().unwrap();
    child.wait().unwrap();
    wait_until("pw-record to follow", || process_is_gone(pw_pid));
}

#[test]
fn a_stop_signal_while_a_pause_verdict_waits_for_a_check_exits_4_at_once() {
    let rig = Rig::new();
    let checks = Checks::new(&rig);
    let gate = checks.gate.to_str().unwrap().to_string();
    let mut feeder = checks.feed(
        &["--pcm", "-"],
        &[("VOXCMD_AUTOSTOP_SILENCE_SECS", "1.5"), ("PAUSE_GATE", &gate)],
    );
    feeder.write(&pcm(&["noise:2:-55", "voice:1:-18", "noise:2:-55"]));
    wait_until("the stop to wait", || {
        rig.trace_has("the stop waits for the pause checks")
    });
    let started = Instant::now();
    // SAFETY: signals the detector this test started.
    unsafe { libc::kill(feeder.child.id() as i32, libc::SIGTERM) };
    assert_eq!(feeder.finish(), 4);
    assert!(
        started.elapsed() < Duration::from_secs(4),
        "it did not wait out pause_check_wait_secs"
    );
    std::fs::write(&checks.gate, "").unwrap();
    wait_for_path(&checks.run_path("1.done"));
}

#[test]
fn the_threshold_file_is_never_seen_half_written_by_the_chains_stopper() {
    let rig = Rig::new();
    let file = rig.path("threshold.123");
    // A room that rises 2 dB every 2.2 s, so each reading moves by more than a dB after the quiet window and is
    // published again and again while the reader below hammers the file, as chain-stop's read of it does.
    let rising: Vec<String> = (0..20).map(|step| format!("noise:2.2:{}", -60 + 2 * step)).collect();
    let rising: Vec<&str> = rising.iter().map(String::as_str).collect();
    let audio = pcm(&rising);
    let stop = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let reader = {
        let (stop, file) = (std::sync::Arc::clone(&stop), file.clone());
        std::thread::spawn(move || {
            let mut seen = std::collections::BTreeSet::new();
            let mut torn = Vec::new();
            while !stop.load(std::sync::atomic::Ordering::SeqCst) {
                if let Ok(text) = std::fs::read_to_string(&file) {
                    match text.strip_suffix('\n').and_then(|number| number.parse::<f64>().ok()) {
                        Some(_) => {
                            seen.insert(text);
                        }
                        None => torn.push(text),
                    }
                }
            }
            (seen, torn)
        })
    };
    // Fed in pieces with a pause between, so the reader gets to see the file between rewrites.
    let env = [
        ("VOXCMD_AUTOSTOP_THRESHOLD_FILE", file.to_str().unwrap()),
        ("VOXCMD_AUTOSTOP_NO_SPEECH_SECS", "100"),
    ];
    let mut feeder = rig.feed(&["--pcm", "-"], &env);
    for piece in audio.chunks(32000) {
        feeder.write(piece);
        std::thread::sleep(Duration::from_millis(4));
    }
    feeder.finish();
    stop.store(true, std::sync::atomic::Ordering::SeqCst);
    let (seen, torn) = reader.join().unwrap();
    assert!(torn.is_empty(), "torn reads: {torn:?}");
    assert!(seen.len() >= 3, "the file was rewritten while read: {seen:?}");
    assert!(!rig.path("threshold.123.new").exists(), "no temporary left behind");
}
