//! A TOML integration's `[mode]` end to end (voxcmd-port 2.4c2): `enter_mode`/`leave_mode` actions, a turn heard in the
//! mode (`internal watch session_turn` on a transcript), its rewrite, `alive` and `ended` hooks, exits and misses. The
//! binary runs against a runtime dir of its own with stubs for voxtype, setsid and the toasts; the bash voxcmd is
//! never involved.
use serde_json::{Value, json};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const TOOLS: &str = r#"
name = "{name}"
verbs = [
  { action = "open", match = '{stem} mode' },
  { action = "close", match = 'stop {stem}' },
  { action = "ok", match = 'do ok' },
  { action = "keep_it", match = 'keep it' },
  { action = "plain", match = 'ok' },
  { action = "nothing", match = 'do nothing' },
]

[actions.open]
enter_mode = true
mode_switch = true
run = 'echo "opened {stem}" >> "$WORK/ran"'

[actions.close]
leave_mode = "done"
mode_switch = true

[actions.ok]
run = 'echo "ok:$VOXCMD_PHRASE" >> "$WORK/ran"'
silent = true

[actions.keep_it]
run = 'echo "kept:$VOXCMD_PHRASE" >> "$WORK/ran"'
silent = true

[actions.plain]
run = 'echo "plain:$VOXCMD_PHRASE" >> "$WORK/ran"'
silent = true

[actions.nothing]
run = "true"
silent = true
miss = true

[mode]
label = "{name} mode"
exit_object = '(the )?{stem}'
exit_phrases = 'finish {mode_object}'
exit_hint = "say finish {stem}"
"#;

struct Rig {
    root: tempfile::TempDir,
}

impl Rig {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        for dir in [
            "config/integrations",
            "runtime/voxtype",
            "runtime/voxcmd",
            "bin",
            "legacy",
            "work",
        ] {
            std::fs::create_dir_all(root.path().join(dir)).unwrap();
        }
        let rig = Self { root };
        let calls = rig.path().join("calls");
        let state = rig.path().join("runtime/voxtype/state");
        rig.script(
            "bin/voxtype",
            &format!(
                "echo \"voxtype $*\" >> '{}'\ncase \"$2\" in start) echo recording > '{1}' ;; stop | cancel) echo idle > '{1}' ;; esac",
                calls.display(),
                state.display()
            ),
        );
        // The watcher a listen starts stands in as a process that lives, so the session it is handed stays open.
        rig.script(
            "bin/setsid",
            &format!(
                "echo $$ >> '{}'\nexec sleep 30",
                rig.path().join("work/watchers").display()
            ),
        );
        rig.script(
            "bin/notify-send",
            &format!("echo \"notify-send $*\" >> '{}'", calls.display()),
        );
        rig.script("legacy/voxcmd", "exit 0");
        rig.script("legacy/voxcmd-autostop", "exit 0");
        std::fs::write(&state, "idle\n").unwrap();
        rig
    }

    fn path(&self) -> &Path {
        self.root.path()
    }

    fn work(&self, name: &str) -> PathBuf {
        self.path().join("work").join(name)
    }

    fn read_work(&self, name: &str) -> String {
        std::fs::read_to_string(self.work(name)).unwrap_or_default()
    }

    /// An executable that is ready to exec (see tests/voice.rs: a fork on another thread may hold its write fd).
    fn script(&self, name: &str, body: &str) {
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
    }

    /// `integrations/<stem>.toml`: the shared verbs and actions, then the `[mode]` table's extra lines. `stem` is also
    /// the first word of the phrases that open and leave it ("demo mode", "stop demo").
    fn integration(&self, stem: &str, mode_extra: &str) -> String {
        let name = format!("{}{}", stem[..1].to_uppercase(), &stem[1..]);
        let text = TOOLS.replace("{name}", &name).replace("{stem}", stem) + mode_extra;
        let file = self.path().join(format!("config/integrations/{stem}.toml"));
        std::fs::write(&file, text).unwrap();
        file.display().to_string()
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
            .env("XDG_STATE_HOME", self.path().join("state"))
            .env("VOXCMD_DEBUG", "1")
            .env("VOXCMD_TIME_SCALE", "0.1")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        command
    }

    fn run(&self, phrase: &str) {
        assert!(self.command(&["run", phrase]).status().unwrap().success(), "{phrase}");
    }

    /// The session file as it is, without clearing one whose owner has gone.
    fn session(&self) -> Option<Value> {
        let text = std::fs::read_to_string(self.path().join("runtime/voxcmd/session.json")).ok()?;
        Some(serde_json::from_str(&text).unwrap())
    }

    fn calls(&self) -> String {
        std::fs::read_to_string(self.path().join("calls")).unwrap_or_default()
    }

    fn debug_log(&self) -> String {
        std::fs::read_to_string(self.path().join("runtime/voxcmd/debug.log")).unwrap_or_default()
    }

    /// A session of one mode `stem` whose turn's watcher hears `transcript`; returns once the turn is over.
    /// `fields` adds to the session file (an unclear count, say).
    fn hear(&self, stem: &str, fields: Value, transcript: &str) {
        let seen = self.debug_log().matches("watch: voxtype recording").count();
        std::fs::write(self.path().join("runtime/voxtype/state"), "recording\n").unwrap();
        let token = format!("1:{stem}:1");
        let mut watcher = self
            .command(&["internal", "watch", "session_turn", &token, "0", ""])
            .spawn()
            .unwrap();
        assert!(
            wait_for(|| self.debug_log().matches("watch: voxtype recording").count() > seen),
            "the watcher never saw the recording"
        );
        let mut session = json!({"kind": stem, "integration": format!("{}/config/integrations/{stem}.toml", self.path().display()),
            "label": "x", "exit_hint": "x", "started": now(), "owner": watcher.id(), "owner_start": start_time_of(watcher.id()),
            "unclear": 0, "turns": 0, "mode_started": now(), "last_heard": now(), "frame_id": "1", "active_secs": 0,
            "resumes": 0, "open_ended": false, "one_recording": false, "wake_listens": false, "stack": []});
        session
            .as_object_mut()
            .unwrap()
            .extend(fields.as_object().unwrap().clone());
        std::fs::write(self.path().join("runtime/voxcmd/session.json"), session.to_string()).unwrap();
        std::fs::write(
            self.path().join("runtime/voxcmd/transcript.txt"),
            format!("{transcript}\n"),
        )
        .unwrap();
        std::fs::write(self.path().join("runtime/voxtype/state"), "idle\n").unwrap();
        assert!(watcher.wait().unwrap().success(), "{}", self.debug_log());
    }
}

impl Drop for Rig {
    fn drop(&mut self) {
        let pids = std::fs::read_to_string(self.work("watchers")).unwrap_or_default();
        for pid in pids.lines().filter_map(|pid| pid.parse::<i32>().ok()) {
            // SAFETY: kill only sends a signal, to a stand-in this test started.
            unsafe { libc::kill(pid, libc::SIGKILL) };
        }
    }
}

fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64
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

const REWRITE: &str = "rewrite = { drop = 'skip', keep = 'keep it', prefix = 'do ' }\n";

// ---- enter_mode and leave_mode --------------------------------------------------------------------------------------

#[test]
fn enter_mode_opens_the_mode_before_run_and_a_second_one_stacks_over_it() {
    let rig = Rig::new();
    rig.integration(
        "demo",
        "allows_switches = true\nprivate = true\nopen_ended = true\nwake_listens = true\n",
    );
    rig.integration("other", "");
    rig.run("demo mode");
    let state = rig.session().expect("the mode opened a session");
    assert_eq!(
        (state["kind"].as_str(), state["label"].as_str()),
        (Some("demo"), Some("Demo mode"))
    );
    assert_eq!(state["exit_hint"], "say finish demo");
    for flag in ["open_ended", "wake_listens"] {
        assert_eq!(state[flag], true, "{flag}");
    }
    assert_eq!(state["one_recording"], false);
    assert_eq!(rig.read_work("ran"), "opened demo\n");
    // Heard in the mode, another mode's entry stacks over it; leaving that one returns to the first.
    rig.hear("demo", json!({}), "other mode");
    let state = rig.session().unwrap();
    assert_eq!(state["kind"], "other");
    assert_eq!(state["stack"][0]["kind"], "demo");
    rig.run("stop other");
    assert_eq!(rig.session().unwrap()["kind"], "demo");
    assert!(rig.debug_log().contains("session: left other"));
}

#[test]
fn leave_mode_with_no_mode_open_does_nothing_and_a_leave_with_one_open_ends_it() {
    let rig = Rig::new();
    rig.integration(
        "demo",
        "ended = 'echo \"$VOXCMD_MODE_END_REASON\" >> \"$WORK/ended\"'\n",
    );
    rig.run("stop demo");
    assert!(rig.session().is_none());
    assert!(!rig.work("ended").exists());
    rig.run("demo mode");
    rig.run("stop demo");
    assert!(rig.session().is_none());
    assert!(wait_for(|| rig.work("ended").exists()));
    assert_eq!(rig.read_work("ended"), "done\n");
}

#[test]
fn a_failing_run_ends_the_mode_it_opened() {
    let rig = Rig::new();
    let file = rig.integration(
        "demo",
        "ended = 'echo \"$VOXCMD_MODE_END_REASON\" >> \"$WORK/ended\"'\n",
    );
    let text = std::fs::read_to_string(&file)
        .unwrap()
        .replace("run = 'echo \"opened demo\" >> \"$WORK/ran\"'", "run = 'exit 1'");
    std::fs::write(&file, text).unwrap();
    assert!(!rig.command(&["run", "demo mode"]).status().unwrap().success());
    assert!(rig.session().is_none());
    assert!(wait_for(|| rig.read_work("ended") == "could not start\n"));
}

// ---- rewrite ----------------------------------------------------------------------------------------------------------

#[test]
fn a_rewrite_drops_keeps_or_prefixes_a_turn_s_words() {
    let rig = Rig::new();
    rig.integration("demo", REWRITE);
    rig.hear("demo", json!({}), "skip");
    assert!(rig.calls().contains("Not understood: \"skip\""), "{}", rig.calls());
    assert_eq!(rig.session().unwrap()["unclear"], 1);
    assert_eq!(rig.read_work("ran"), "");
    rig.hear("demo", json!({}), "keep it");
    rig.hear("demo", json!({}), "ok");
    assert_eq!(rig.read_work("ran"), "kept:keep it\nok:do ok\n");
}

#[test]
fn a_mode_without_a_rewrite_routes_the_words_as_spoken_and_a_rewrite_applies_to_each_step() {
    let rig = Rig::new();
    rig.integration("demo", "");
    rig.hear("demo", json!({}), "ok");
    assert_eq!(rig.read_work("ran"), "plain:ok\n");
    rig.integration("demo", REWRITE);
    rig.hear("demo", json!({}), "ok and then ok");
    assert_eq!(rig.read_work("ran"), "plain:ok\nok:do ok\nok:do ok\n");
}

#[test]
fn a_rewrite_hook_prints_the_words_to_route() {
    let rig = Rig::new();
    rig.integration("demo", "rewrite_hook = 'echo \"do $VOXCMD_PHRASE\"'\n");
    rig.hear("demo", json!({}), "ok");
    assert_eq!(rig.read_work("ran"), "ok:do ok\n");
}

// ---- alive and ended ----------------------------------------------------------------------------------------------

#[test]
fn a_mode_whose_alive_hook_fails_is_left_and_the_words_route_outside_it() {
    let rig = Rig::new();
    rig.integration(
        "demo",
        "alive = 'test ! -e \"$WORK/dead\"'\nended = 'echo \"$VOXCMD_MODE_END_REASON\" >> \"$WORK/ended\"'\n",
    );
    rig.hear("demo", json!({}), "do ok");
    assert_eq!(rig.read_work("ran"), "ok:do ok\n");
    assert!(rig.session().is_some());
    std::fs::write(rig.work("dead"), "").unwrap();
    rig.hear("demo", json!({}), "do ok");
    assert_eq!(rig.read_work("ran"), "ok:do ok\nok:do ok\n");
    assert!(rig.debug_log().contains("session: demo's screen is gone"));
    assert!(wait_for(|| rig.read_work("ended") == "its screen closed\n"));
}

#[test]
fn an_alive_hook_that_times_out_counts_as_alive() {
    let rig = Rig::new();
    rig.integration("demo", "alive = 'sleep 5'\ntimeout_secs = 0.2\n");
    let started = Instant::now();
    rig.hear("demo", json!({}), "do ok");
    assert_eq!(rig.read_work("ran"), "ok:do ok\n");
    assert!(started.elapsed() < Duration::from_secs(4), "{:?}", started.elapsed());
    assert!(rig.debug_log().contains("alive hook timed out"));
}

#[test]
fn the_ended_hook_runs_once_with_the_reason_frame_and_whether_the_session_goes_on() {
    let rig = Rig::new();
    rig.integration(
        "demo",
        "ended = 'echo \"$VOXCMD_MODE_END_REASON|$VOXCMD_MODE_FRAME_ID|$VOXCMD_MODE_CONTINUES\" >> \"$WORK/ended\"'\n",
    );
    rig.integration("plain", "");
    rig.run("demo mode");
    let frame = rig.session().unwrap()["frame_id"].as_str().unwrap().to_string();
    assert!(rig.command(&["session", "end"]).status().unwrap().success());
    assert!(wait_for(|| rig.work("ended").exists()));
    assert_eq!(rig.read_work("ended"), format!("ended by request|{frame}|0\n"));
    // A mode without the hook runs nothing when it ends.
    rig.run("plain mode");
    rig.run("stop plain");
    std::thread::sleep(Duration::from_millis(300));
    assert_eq!(rig.read_work("ended").lines().count(), 1);
}

// ---- exits and misses -----------------------------------------------------------------------------------------------

#[test]
fn a_mode_s_exit_phrases_expand_its_object_and_bare_exits_follow_the_mode() {
    let rig = Rig::new();
    rig.integration("demo", "bare_exits = false\n");
    rig.hear("demo", json!({}), "stop");
    assert!(rig.session().is_some(), "a bare stop is a target in this mode");
    rig.hear("demo", json!({}), "finish the demo");
    assert!(rig.session().is_none());
    rig.integration("demo", "");
    rig.hear("demo", json!({}), "stop");
    assert!(
        rig.session().is_none(),
        "a bare stop ends the session where bare_exits is on"
    );
    rig.integration("demo", "default_exits = false\n");
    rig.hear("demo", json!({}), "done");
    assert!(
        rig.session().is_some(),
        "done is a word for the mode where default_exits is off"
    );
}

#[test]
fn a_miss_action_counts_toward_the_unclear_cap() {
    let rig = Rig::new();
    rig.integration("demo", "");
    rig.hear("demo", json!({"unclear": 2}), "do ok");
    assert_eq!(rig.session().unwrap()["unclear"], 0);
    rig.hear("demo", json!({"unclear": 1}), "do nothing");
    assert_eq!(rig.session().unwrap()["unclear"], 2);
    rig.hear("demo", json!({"unclear": 2}), "do nothing");
    assert!(rig.session().is_none());
    assert!(
        rig.calls().contains("nothing understood 3 times in a row"),
        "{}",
        rig.calls()
    );
}

// ---- the worked conversion ------------------------------------------------------------------------------------------

#[test]
fn the_click_conversion_runs_as_a_mode() {
    let rig = Rig::new();
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/integrations/click.toml");
    std::fs::copy(fixture, rig.path().join("config/integrations/click.toml")).unwrap();
    assert!(
        rig.command(&["run", "click mode"])
            .env("VOXCMD_DEBUG", "1")
            .status()
            .unwrap()
            .success(),
        "{}",
        rig.debug_log()
    );
    let state = rig.session().expect("click mode opened");
    assert_eq!(
        (state["kind"].as_str(), state["label"].as_str()),
        (Some("click"), Some("Click mode"))
    );
    assert_eq!(state["exit_hint"], "say done to stop");
    // A bare "click" names nothing to click; "stop" stays a target, so only a phrase naming the mode leaves it.
    rig.hear("click", json!({}), "click");
    assert!(rig.calls().contains("Not understood: \"click\""), "{}", rig.calls());
    rig.hear("click", json!({}), "stop");
    assert!(rig.session().is_some());
    rig.hear("click", json!({}), "done clicking");
    assert!(rig.session().is_none());
}
