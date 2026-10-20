//! `log misses`, `log errors` and `timer ring` against stub `qs-ipc`, `notify-send` and players, with the bash
//! `voxcmd` and `voxcmd-alarm` beside them as tripwires that must never run.
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::{Command, Output};

fn write_stub(path: &Path, script: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, script).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

struct Sandbox {
    root: tempfile::TempDir,
}

impl Sandbox {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        let sandbox = Self { root };
        let bin = sandbox.root.path().join("bin");
        // The tripwires: the bash siblings these subcommands replaced.
        write_stub(
            &bin.join("voxcmd-alarm"),
            &format!("#!/bin/sh\necho 'BASH-RAN voxcmd-alarm' >> {}\n", sandbox.calls_path()),
        );
        sandbox
    }

    fn calls_path(&self) -> String {
        self.root.path().join("calls.log").display().to_string()
    }

    fn stub(&self, relative: &str, script: &str) {
        write_stub(&self.root.path().join(relative), script);
    }

    /// A `qs-ipc` that logs its call and prints `reply`; `exit_code` is its status.
    fn bar(&self, reply: &str, exit_code: i32) {
        self.stub(
            "config/hypr/scripts/qs-ipc",
            &format!(
                "#!/bin/sh\necho \"qs-ipc $*\" >> {}\ncat <<'REPLY'\n{reply}\nREPLY\necho 'bar noise' >&2\nexit {exit_code}\n",
                self.calls_path()
            ),
        );
    }

    fn voxcmd(&self, args: &[&str], env: &[(&str, &str)]) -> Output {
        let root = self.root.path();
        Command::new(env!("CARGO_BIN_EXE_voxcmd"))
            .args(args)
            .env_clear()
            .env("PATH", format!("{}:/usr/bin:/bin", root.join("bin").display()))
            .env("HOME", root.join("home"))
            .env("XDG_CONFIG_HOME", root.join("config"))
            .env("XDG_STATE_HOME", root.join("state"))
            .env("TZ", "UTC")
            .env("LC_ALL", "C")
            .envs(env.iter().copied())
            .output()
            .unwrap()
    }

    fn calls(&self) -> String {
        std::fs::read_to_string(self.root.path().join("calls.log")).unwrap_or_default()
    }

    fn no_bash_ran(&self) {
        assert!(
            !self.calls().contains("BASH-RAN"),
            "a bash sibling ran:\n{}",
            self.calls()
        );
    }
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

fn write_misses(sandbox: &Sandbox, text: &str) {
    let log = sandbox.root.path().join("state/voxcmd/no-match.log");
    std::fs::create_dir_all(log.parent().unwrap()).unwrap();
    std::fs::write(log, text).unwrap();
}

#[test]
fn misses_prints_the_last_lines_as_logged() {
    let sandbox = Sandbox::new();
    write_misses(
        &sandbox,
        "2026-10-17T12:00:00+00:00\tone\n2026-10-17T12:01:00+00:00\ttwo\n2026-10-17T12:02:00+00:00\tthree\n",
    );
    let last = sandbox.voxcmd(&["log", "misses", "2"], &[]);
    assert!(last.status.success());
    assert_eq!(
        stdout(&last),
        "2026-10-17T12:01:00+00:00\ttwo\n2026-10-17T12:02:00+00:00\tthree\n"
    );
    assert_eq!(stdout(&sandbox.voxcmd(&["log", "misses", "0"], &[])), "");
    assert_eq!(stdout(&sandbox.voxcmd(&["log", "misses"], &[])).lines().count(), 3);
    sandbox.no_bash_ran();
}

#[test]
fn misses_as_json_and_without_a_log() {
    let sandbox = Sandbox::new();
    let none = sandbox.voxcmd(&["log", "misses"], &[]);
    assert!(none.status.success());
    assert_eq!((stdout(&none), stderr(&none)), (String::new(), String::new()));
    assert_eq!(stdout(&sandbox.voxcmd(&["log", "misses", "--json"], &[])), "[]\n");

    write_misses(&sandbox, "2026-10-17T12:00:00+00:00\tlock doors\n");
    assert_eq!(
        stdout(&sandbox.voxcmd(&["log", "misses", "--json"], &[])),
        "[{\"phrase\":\"lock doors\",\"time\":\"2026-10-17T12:00:00+00:00\"}]\n"
    );
}

const HISTORY: &str = r#"[{"time":"2026-10-17T15:47:09.123Z","summary":"Could not open","body":"line one\nline two"},{"time":"2026-10-17T03:05:00Z","summary":"Nothing heard","body":""}]"#;

#[test]
fn errors_formats_the_bars_history_in_the_clock_format() {
    let sandbox = Sandbox::new();
    sandbox.bar(HISTORY, 0);
    let twenty_four = sandbox.voxcmd(&["log", "errors", "2"], &[]);
    assert!(twenty_four.status.success(), "{}", stderr(&twenty_four));
    assert_eq!(
        stdout(&twenty_four),
        "2026-10-17 15:47  Could not open: line one line two\n2026-10-17 03:05  Nothing heard: \n"
    );
    assert_eq!(stderr(&twenty_four), "", "the bar's own stderr is silenced");
    assert!(sandbox.calls().contains("qs-ipc call notifications history 2 voxcmd\n"));

    let clock = sandbox.root.path().join("state/quickshell/clock.json");
    std::fs::create_dir_all(clock.parent().unwrap()).unwrap();
    std::fs::write(clock, r#"{"time_format":"12h"}"#).unwrap();
    assert_eq!(
        stdout(&sandbox.voxcmd(&["log", "errors"], &[])),
        "2026-10-17 3:47pm  Could not open: line one line two\n2026-10-17 3:05am  Nothing heard: \n"
    );
    assert!(
        sandbox.calls().contains("history 10 voxcmd\n"),
        "the default count is 10"
    );

    let json = sandbox.voxcmd(&["log", "errors", "--json"], &[]);
    // Exactly the spec's BarError keys, the time as the bar gave it and the body untouched.
    let expected: serde_json::Value = serde_json::json!([
        {"time": "2026-10-17T15:47:09.123Z", "summary": "Could not open", "body": "line one\nline two"},
        {"time": "2026-10-17T03:05:00Z", "summary": "Nothing heard", "body": ""},
    ]);
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&stdout(&json)).unwrap(),
        expected
    );
    sandbox.no_bash_ran();
}

#[test]
fn errors_without_a_bar_exits_1_quietly() {
    let sandbox = Sandbox::new();
    for (reply, exit_code) in [("", 0), ("not json", 0), ("{\"a\":1}", 0), (HISTORY, 1)] {
        sandbox.bar(reply, exit_code);
        let output = sandbox.voxcmd(&["log", "errors"], &[]);
        assert_eq!(output.status.code(), Some(1), "{reply}");
        assert_eq!(stdout(&output), "");
        assert_eq!(stderr(&output), "voxcmd: log errors: bar not running\n", "{reply}");
    }
    // No qs-ipc at all.
    let bare = Sandbox::new();
    let output = bare.voxcmd(&["log", "errors"], &[]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(stderr(&output), "voxcmd: log errors: bar not running\n");
}

/// A notify-send that logs its arguments and, like `--wait`, stays until killed.
const NOTIFY_WAITING: &str = "#!/bin/sh\necho \"notify-send $*\" >> CALLS\nexec sleep 30\n";

fn ring_env<'a>(rings: &'a str, gap: &'a str) -> [(&'a str, &'a str); 2] {
    [("VOXCMD_ALARM_RINGS", rings), ("VOXCMD_ALARM_GAP", gap)]
}

#[test]
fn ring_asks_the_bar_to_play_the_alarm_and_closes_the_notification_at_the_end() {
    let sandbox = Sandbox::new();
    sandbox.stub(
        "bin/notify-send",
        &NOTIFY_WAITING.replace("CALLS", &sandbox.calls_path()),
    );
    sandbox.bar("ok", 0);
    let started = std::time::Instant::now();
    let output = sandbox.voxcmd(&["timer", "ring", "Tea", "Steeped"], &ring_env("3", "0"));
    assert!(output.status.success(), "{}", stderr(&output));
    assert!(
        started.elapsed().as_secs() < 10,
        "the sleeping notify-send was not ended"
    );
    let calls = sandbox.calls();
    assert!(calls.contains("notify-send --wait --urgency=critical --app-name=voxcmd Tea Steeped\n"));
    assert_eq!(calls.matches("qs-ipc call sound play alarm\n").count(), 3);
    assert_eq!(stderr(&output), "");
    sandbox.no_bash_ran();
}

#[test]
fn ring_stops_once_the_notification_is_dismissed() {
    let sandbox = Sandbox::new();
    // --wait returns at once: dismissed before the first gap is over.
    sandbox.stub("bin/notify-send", "#!/bin/sh\nexit 0\n");
    sandbox.bar("ok", 0);
    assert!(
        sandbox
            .voxcmd(&["timer", "ring", "Tea", ""], &ring_env("3", "0.3"))
            .status
            .success()
    );
    assert_eq!(sandbox.calls().matches("qs-ipc call sound play alarm\n").count(), 1);
}

#[test]
fn ring_without_the_bar_plays_the_shipped_file_through_pw_play() {
    let sandbox = Sandbox::new();
    sandbox.stub(
        "bin/notify-send",
        &NOTIFY_WAITING.replace("CALLS", &sandbox.calls_path()),
    );
    sandbox.stub(
        "bin/pw-play",
        &format!("#!/bin/sh\necho \"pw-play $*\" >> {}\n", sandbox.calls_path()),
    );
    // A bar that is there but does not answer "ok".
    sandbox.bar("", 0);
    let alarm = sandbox.root.path().join("config/quickshell/sounds/alarm.ogg");
    std::fs::create_dir_all(alarm.parent().unwrap()).unwrap();
    std::fs::write(&alarm, "").unwrap();
    assert!(
        sandbox
            .voxcmd(&["timer", "ring", "Tea"], &ring_env("2", "0"))
            .status
            .success()
    );
    assert_eq!(
        sandbox
            .calls()
            .matches(&format!("pw-play {}\n", alarm.display()))
            .count(),
        2
    );
    sandbox.no_bash_ran();
}
