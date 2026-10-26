//! `voxcmd run` end to end: the binary against a config of its own, with stubs for the toasts, the questions and the
//! bar. Each case is a process, so the environment it sets (runtime dir, pacing) reaches no other test.
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const INTEGRATION: &str = r#"
name = "Tools"
verbs = [
  { action = "ok",      match = 'do ok' },
  { action = "fail",    match = 'do fail' },
  { action = "silent",  match = 'do silent' },
  { action = "nothing", match = 'do nothing' },
  { action = "env",     match = 'do env {target}' },
  { action = "risky",   match = 'do risky' },
  { action = "pick",    match = 'do pick' },
  { action = "wait",    match = 'do wait' },
  { action = "gate",    match = 'do gate' },
  { action = "hang",    match = 'do hang' },
  { action = "after",   match = 'do after' },
  { action = "lag",     match = 'do lag' },
  { action = "hold",    match = 'do hold' },
]

[actions]
ok = "echo done; echo line two"
fail = "echo first >&2; echo boom >&2; exit 3"
silent = { run = "echo hidden", silent = true }
nothing = ""
env = 'echo "$VOXCMD_ACTION|$VOXCMD_PHRASE|$VOXCMD_ARG_TARGET|$VOXCMD_CONFIRMED"'
risky = "echo risky ran:$VOXCMD_CONFIRMED"
pick = { run = 'echo picked $VOXCMD_ID', candidates = "printf 'a\\tAlpha\\nb\\tBeta\\n'" }
wait = { run = "touch $WORK/started", wait_hook = "test -f $WORK/ready" }
gate = { run = "true", wait_hook = "test -f $WORK/never", timeout_secs = 5 }
hang = "true"
after = "echo after ran >> $WORK/after"
lag = { run = "true", wait_hook = "sleep 3", timeout_secs = 5 }
hold = 'sleep 30 & echo $! > "$WORK/held"; wait'
"#;

mod common;
use common::gone_within;

struct Setup {
    root: tempfile::TempDir,
}

impl Setup {
    fn new(integration: &str) -> Self {
        let root = tempfile::tempdir().unwrap();
        for dir in ["config/integrations", "runtime", "state", "bin", "xdg"] {
            std::fs::create_dir_all(root.path().join(dir)).unwrap();
        }
        std::fs::write(root.path().join("config/integrations/tools.toml"), integration).unwrap();
        let setup = Self { root };
        setup.script(
            "notify-send",
            &format!(
                "printf '%s\\037' \"$@\" >> '{0}/toasts'; printf '\\036' >> '{0}/toasts'",
                setup.path().display()
            ),
        );
        setup
    }

    fn path(&self) -> &Path {
        self.root.path()
    }

    /// An executable that is ready to exec (see `settle_exec`).
    fn script(&self, name: &str, body: &str) -> PathBuf {
        let temp = self.path().join("bin").join(format!(".{name}.tmp"));
        std::fs::write(
            &temp,
            format!("#!/bin/sh\n[ -z \"$VOXCMD_TEST_PROBE\" ] || exit 0\n{body}\n"),
        )
        .unwrap();
        std::fs::set_permissions(&temp, std::fs::Permissions::from_mode(0o755)).unwrap();
        let path = self.path().join("bin").join(name);
        std::fs::rename(&temp, &path).unwrap();
        settle_exec(&path);
        path
    }

    /// The binary with these arguments, in this setup's environment.
    fn command(&self, args: &[&str], envs: &[(&str, String)]) -> Command {
        let work = self.path().join("work");
        std::fs::create_dir_all(&work).unwrap();
        let mut command = Command::new(env!("CARGO_BIN_EXE_voxcmd"));
        command
            .args(args)
            .env_clear()
            .env("PATH", format!("{}/bin:/usr/bin:/bin", self.path().display()))
            .env("HOME", "/nonexistent")
            .env("LC_ALL", "C")
            .env("WORK", &work)
            .env("VOXCMD_CONFIG_DIR", self.path().join("config"))
            .env("XDG_RUNTIME_DIR", self.path().join("runtime"))
            .env("XDG_STATE_HOME", self.path().join("state"))
            .env("XDG_CONFIG_HOME", self.path().join("xdg"))
            .env("VOXCMD_STEP_TIMEOUT_SECS", "1")
            .env("VOXCMD_APP_SETTLE_SECS", "0")
            .env("VOXCMD_TIME_SCALE", "0.1");
        for (name, value) in envs {
            command.env(name, value);
        }
        command
    }

    fn run_with(&self, phrase: &str, envs: &[(&str, String)]) -> Output {
        self.command(&["run", phrase], envs).output().expect("the binary runs")
    }

    fn run(&self, phrase: &str) -> Output {
        self.run_with(phrase, &[])
    }

    /// Every toast sent so far as its arguments.
    fn toasts(&self) -> Vec<Vec<String>> {
        let text = std::fs::read_to_string(self.path().join("toasts")).unwrap_or_default();
        text.split('\x1e')
            .filter(|toast| !toast.is_empty())
            .map(|toast| toast.split_terminator('\x1f').map(str::to_string).collect())
            .collect()
    }

    /// Waits for the toasts a detached waiter sends (the no-match toast), up to two seconds.
    fn toasts_settled(&self, count: usize) -> Vec<Vec<String>> {
        for _ in 0..200 {
            if self.toasts().len() >= count {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        self.toasts()
    }

    /// The summary and body of each toast.
    fn texts(&self) -> Vec<(String, String)> {
        self.toasts()
            .into_iter()
            .map(|args| (args[args.len() - 2].clone(), args[args.len() - 1].clone()))
            .collect()
    }

    fn ask_stub(&self, body: &str) -> (&'static str, String) {
        ("VOXCMD_ASK_CMD", self.script("ask", body).display().to_string())
    }
}

/// Runs the script once in probe mode until it execs. Renaming does not help (the inode is the same), but a fork on
/// another test thread that held the write fd lets go of it at its exec, so after this no later exec is ETXTBSY.
fn settle_exec(path: &Path) {
    for _ in 0..500 {
        match Command::new(path).env("VOXCMD_TEST_PROBE", "1").status() {
            Err(error) if error.kind() == std::io::ErrorKind::ExecutableFileBusy => {
                std::thread::sleep(std::time::Duration::from_millis(10));
            }
            _ => return,
        }
    }
}

fn code(output: &Output) -> Option<i32> {
    output.status.code()
}

fn pair(summary: &str, body: &str) -> (String, String) {
    (summary.to_string(), body.to_string())
}

#[test]
fn a_successful_action_toasts_its_label_and_last_output_line() {
    let setup = Setup::new(INTEGRATION);
    let output = setup.run("do ok");
    assert_eq!(code(&output), Some(0));
    assert_eq!(setup.texts(), [pair("voxcmd", "Tools: ok: line two")]);
    // An info toast is transient.
    assert!(setup.toasts()[0].contains(&"--transient".to_string()));
}

#[test]
fn a_silent_action_sends_no_toast() {
    let setup = Setup::new(INTEGRATION);
    assert_eq!(code(&setup.run("do silent")), Some(0));
    assert!(setup.texts().is_empty());
}

#[test]
fn a_failing_action_reports_the_tail_of_its_output_and_exits_one() {
    let setup = Setup::new(INTEGRATION);
    let output = setup.run("do fail");
    assert_eq!(code(&output), Some(1));
    assert_eq!(setup.texts(), [pair("voxcmd failed", "Tools: fail: first\nboom")]);
    assert!(!setup.toasts()[0].contains(&"--transient".to_string()));
}

#[test]
fn an_action_without_a_command_is_an_error_toast() {
    let setup = Setup::new(INTEGRATION);
    assert_eq!(code(&setup.run("do nothing")), Some(1));
    assert_eq!(setup.texts(), [pair("voxcmd error", "Tools: nothing has no command")]);
}

#[test]
fn the_action_sees_the_step_in_its_environment() {
    let setup = Setup::new(INTEGRATION);
    assert_eq!(code(&setup.run("do env Tea Cup")), Some(0));
    let (_, body) = &setup.texts()[0];
    assert!(body.ends_with(": env|do env tea cup|tea cup|0"), "{body}");
}

#[test]
fn a_phrase_nothing_matches_logs_a_miss_and_toasts_once() {
    let setup = Setup::new(INTEGRATION);
    assert_eq!(code(&setup.run("zzz unknown")), Some(1));
    let toasts = setup.toasts_settled(1);
    assert_eq!(toasts.len(), 1, "{toasts:?}");
    assert_eq!(toasts[0][toasts[0].len() - 2], "voxcmd: no match");
    let log = std::fs::read_to_string(setup.path().join("state/voxcmd/no-match.log")).unwrap();
    // The bash `date -Is` shape, then the phrase: `2026-10-17T12:00:00+02:00<TAB>zzz unknown`.
    let (date, phrase) = log.strip_suffix('\n').unwrap().split_once('\t').unwrap();
    assert_eq!(phrase, "zzz unknown");
    let shape: String = date
        .chars()
        .map(|char| if char.is_ascii_digit() { '9' } else { char })
        .collect();
    assert!(
        ["9999-99-99T99:99:99+99:99", "9999-99-99T99:99:99-99:99"].contains(&shape.as_str()),
        "{log}"
    );
}

#[test]
fn a_miss_forced_to_a_private_integration_is_toasted_but_not_logged() {
    let setup = Setup::new(
        "name = \"Secret\"\nprivate_labels = true\nforce_prefixes = [\"secret\"]\n\
         verbs = [{ action = \"x\", match = 'do x' }]\n[actions]\nx = \"true\"\n",
    );
    assert_eq!(code(&setup.run("secret zzz")), Some(1));
    let toasts = setup.toasts_settled(1);
    assert_eq!(toasts.len(), 1, "{toasts:?}");
    assert!(!setup.path().join("state/voxcmd/no-match.log").exists());
}

#[test]
fn only_the_wake_word_asks_for_a_command_and_is_not_a_failure() {
    let setup = Setup::new(INTEGRATION);
    assert_eq!(code(&setup.run("Cortana")), Some(0));
    assert_eq!(setup.texts(), [pair("voxcmd", "Say a command after \"cortana\"")]);
}

#[test]
fn a_confirm_integration_runs_only_after_a_yes() {
    let confirming = format!("confirm = true\n{INTEGRATION}");
    let setup = Setup::new(&confirming);
    let (name, value) = setup.ask_stub("echo \"$@\" >> \"$WORK/asked\"; exit 1");
    assert_eq!(code(&setup.run_with("do risky", &[(name, value)])), Some(0));
    let asked = std::fs::read_to_string(setup.path().join("work/asked")).unwrap();
    assert_eq!(
        asked,
        "confirm --verb risky Risky?\n"
            .replace("Risky?", "Tools: risky?")
            .replace("Tools: risky?", "Risky?")
    );
    // The user declined: nothing ran and nothing was reported.
    assert!(setup.texts().is_empty());

    let (name, value) = setup.ask_stub("exit 0");
    assert_eq!(code(&setup.run_with("do risky", &[(name, value)])), Some(0));
    assert_eq!(setup.texts(), [pair("voxcmd", "Tools: risky: risky ran:1")]);
}

#[test]
fn several_candidates_ask_which_and_run_the_one_picked() {
    let setup = Setup::new(INTEGRATION);
    let (name, value) = setup.ask_stub("echo \"$@\" > \"$WORK/asked\"; echo 1");
    assert_eq!(code(&setup.run_with("do pick", &[(name, value)])), Some(0));
    let asked = std::fs::read_to_string(setup.path().join("work/asked")).unwrap();
    assert!(asked.starts_with("pick Which command? [{"), "{asked}");
    assert!(asked.contains("\"label\":\"Tools: pick Alpha\""), "{asked}");
    assert_eq!(setup.texts(), [pair("voxcmd", "Tools: pick Beta: picked b")]);
}

#[test]
fn a_closed_picker_runs_nothing_and_is_not_a_failure() {
    let setup = Setup::new(INTEGRATION);
    let (name, value) = setup.ask_stub("exit 1");
    assert_eq!(code(&setup.run_with("do pick", &[(name, value)])), Some(0));
    assert!(setup.texts().is_empty());
}

#[test]
fn a_sequence_runs_its_steps_in_order_and_toasts_each() {
    let setup = Setup::new(INTEGRATION);
    assert_eq!(code(&setup.run("do ok and then do silent and then do after")), Some(0));
    let after = std::fs::read_to_string(setup.path().join("work/after")).unwrap();
    assert_eq!(after, "after ran\n");
    assert_eq!(setup.texts().len(), 2);
}

#[test]
fn a_failing_step_stops_the_sequence_with_one_report() {
    let setup = Setup::new(INTEGRATION);
    assert_eq!(code(&setup.run("do ok and then do fail and then do after")), Some(0));
    assert!(!setup.path().join("work/after").exists());
    let texts = setup.texts();
    assert_eq!(
        texts.last().unwrap(),
        &pair(
            "voxcmd: stopped at step 2 of 3",
            "Tools: fail: first\nboom\n1 more step not run"
        )
    );
}

#[test]
fn a_sequence_whose_first_step_fails_exits_one() {
    let setup = Setup::new(INTEGRATION);
    assert_eq!(code(&setup.run("do fail and then do after")), Some(1));
}

#[test]
fn a_step_nothing_matches_stops_the_sequence_naming_it() {
    let setup = Setup::new(INTEGRATION);
    assert_eq!(code(&setup.run("do silent and then do zzz and then do after")), Some(0));
    setup.toasts_settled(1);
    assert_eq!(
        setup.texts(),
        [pair(
            "voxcmd: stopped at step 2 of 3",
            "no match for \"do zzz\"\n1 more step not run"
        )]
    );
}

#[test]
fn a_wait_hook_holds_the_next_step_until_it_succeeds() {
    let setup = Setup::new(INTEGRATION);
    let work = setup.path().join("work");
    std::fs::create_dir_all(&work).unwrap();
    // The condition holds only after the step has started, so the order is the wait's doing.
    let ready = work.join("ready");
    let releaser = std::thread::spawn({
        let (started, ready) = (work.join("started"), ready.clone());
        move || {
            while !started.exists() {
                std::thread::sleep(std::time::Duration::from_millis(5));
            }
            std::thread::sleep(std::time::Duration::from_millis(150));
            std::fs::write(ready, "").unwrap();
        }
    });
    let output = setup.run_with(
        "do wait and then do after",
        &[("VOXCMD_STEP_TIMEOUT_SECS", "10".to_string())],
    );
    releaser.join().unwrap();
    assert_eq!(code(&output), Some(0));
    assert!(work.join("after").exists());
}

#[test]
fn a_wait_that_never_holds_times_out_and_names_the_step() {
    let setup = Setup::new(INTEGRATION);
    assert_eq!(code(&setup.run("do gate and then do after")), Some(0));
    assert!(!setup.path().join("work/after").exists());
    assert_eq!(
        setup.texts(),
        [
            pair("voxcmd", "Tools: gate"),
            pair(
                "voxcmd: stopped at step 1 of 2",
                "Tools: gate: timed out after 1s\n1 more step not run"
            ),
        ]
    );
}

#[test]
fn the_discard_flag_stops_a_sequence_without_a_toast() {
    let setup = Setup::new(INTEGRATION);
    let runtime = setup.path().join("runtime/voxcmd");
    let watcher = std::thread::spawn({
        let started = setup.path().join("work/started");
        move || {
            while !started.exists() {
                std::thread::sleep(std::time::Duration::from_millis(5));
            }
            // The record Stop Voice reads names the sequence's pid.
            let sequences = runtime.join("sequences");
            let record = loop {
                if let Some(entry) = std::fs::read_dir(&sequences).ok().and_then(|mut dir| dir.next()) {
                    break entry.unwrap().path();
                }
                std::thread::sleep(std::time::Duration::from_millis(5));
            };
            let pid = record.file_stem().unwrap().to_string_lossy().into_owned();
            std::fs::write(runtime.join(format!("discard.{pid}")), "").unwrap();
        }
    });
    let output = setup.run_with(
        "do wait and then do after",
        &[("VOXCMD_STEP_TIMEOUT_SECS", "20".to_string())],
    );
    watcher.join().unwrap();
    assert_eq!(code(&output), Some(0));
    assert!(!setup.path().join("work/after").exists());
    assert_eq!(setup.texts(), [pair("voxcmd", "Tools: wait")]);
    // The flag and the sequence's record are gone with it.
    assert_eq!(
        std::fs::read_dir(setup.path().join("runtime/voxcmd"))
            .unwrap()
            .flatten()
            .filter(|entry| {
                let name = entry.file_name().to_string_lossy().into_owned();
                name.starts_with("discard.")
            })
            .count(),
        0
    );
}

const SLOW_ROUTE: &str = r#"
name = "Slow route"
verbs = [
  { action = "slow",  match = 'do slow' },
  { action = "after", match = 'do after' },
]

[actions]
slow = { run = 'echo slow ran >> "$WORK/after"', candidates = 'touch "$WORK/routing"; sleep 1; printf "a\tA\n"' }
after = "echo after ran >> $WORK/after"
"#;

#[test]
fn a_discard_flag_that_appears_while_a_step_is_routing_keeps_its_action_from_running() {
    let setup = Setup::new(SLOW_ROUTE);
    let runtime = setup.path().join("runtime/voxcmd");
    let watcher = std::thread::spawn({
        let routing = setup.path().join("work/routing");
        move || {
            while !routing.exists() {
                std::thread::sleep(std::time::Duration::from_millis(5));
            }
            let record = std::fs::read_dir(runtime.join("sequences"))
                .unwrap()
                .next()
                .unwrap()
                .unwrap();
            let pid = record.path().file_stem().unwrap().to_string_lossy().into_owned();
            std::fs::write(runtime.join(format!("discard.{pid}")), "").unwrap();
        }
    });
    let output = setup.run_with(
        "do slow and then do after",
        &[("VOXCMD_STEP_TIMEOUT_SECS", "20".to_string())],
    );
    watcher.join().unwrap();
    assert_eq!(code(&output), Some(1));
    assert!(!setup.path().join("work/after").exists());
    assert!(setup.texts().is_empty(), "{:?}", setup.texts());
}

#[test]
fn a_library_warning_on_stderr_is_not_part_of_a_toml_action_s_toast() {
    let setup = Setup::new(INTEGRATION);
    std::fs::write(
        setup.path().join("config/integrations/tools.sh"),
        "echo 'library warning' >&2\n",
    )
    .unwrap();
    assert_eq!(code(&setup.run("do hang")), Some(0));
    assert_eq!(setup.texts(), [pair("voxcmd", "Tools: hang")]);
    // An action's own stderr still reads as its output.
    setup.run("do ok");
    assert_eq!(setup.texts().last().unwrap(), &pair("voxcmd", "Tools: ok: line two"));
}

#[test]
fn a_record_left_by_a_dead_sequence_does_not_stop_a_new_one() {
    let setup = Setup::new(INTEGRATION);
    let runtime = setup.path().join("runtime/voxcmd");
    std::fs::create_dir_all(runtime.join("sequences")).unwrap();
    std::fs::write(
        runtime.join("sequences/999999.json"),
        "{\"pid\":999999,\"start\":\"1\"}",
    )
    .unwrap();
    std::fs::write(runtime.join("discard.999999"), "").unwrap();
    assert_eq!(code(&setup.run("do ok and then do after")), Some(0));
    assert!(setup.path().join("work/after").exists());
}

#[test]
fn a_wait_past_the_step_timeout_is_cut_off_there_and_times_out() {
    let setup = Setup::new(INTEGRATION);
    let started = std::time::Instant::now();
    // The hook would succeed after 3 s, and may run for 5, but the step has 1.
    assert_eq!(code(&setup.run("do lag and then do after")), Some(0));
    assert!(
        started.elapsed() < std::time::Duration::from_millis(2500),
        "{:?}",
        started.elapsed()
    );
    assert!(!setup.path().join("work/after").exists());
    assert_eq!(
        setup.texts().last().unwrap(),
        &pair(
            "voxcmd: stopped at step 1 of 2",
            "Tools: lag: timed out after 1s\n1 more step not run"
        )
    );
}

// ---- the built-in waits, against a stub Hyprland and bar ----

const WAITS: &str = r#"
name = "Waits"
verbs = [
  { action = "focus",  match = 'check focus' },
  { action = "is_id",  match = 'check named' },
  { action = "gone",   match = 'check gone' },
  { action = "popup",  match = 'check popup' },
  { action = "after",  match = 'do after' },
]

[actions]
focus = { run = '[ -z "$HOLDS" ] || echo 0xb > "$WORK/active"', wait = "active_window_changed" }
is_id = { run = '[ -z "$HOLDS" ] || echo 0xb > "$WORK/active"', candidates = "printf '0xb\\tB\\n'", wait = "active_window_is_id" }
gone = { run = '[ -z "$HOLDS" ] || echo "[]" > "$WORK/clients"', candidates = "printf '0xb\\tB\\n'", wait = "window_gone" }
popup = { run = '[ -z "$HOLDS" ] || echo "open calendar" > "$WORK/popup"', wait = "popup_open:calendar" }
after = "echo after ran >> $WORK/after"
"#;

/// Hyprland focuses 0xa with 0xb open, and no popup is open, until an action writes otherwise.
fn waits_setup() -> Setup {
    let setup = Setup::new(WAITS);
    setup.script(
        "hyprctl",
        "case \"$1\" in\n\
           activewindow) printf '{\"address\":\"%s\"}' \"$(cat \"$WORK/active\" 2>/dev/null || echo 0xa)\" ;;\n\
           clients) cat \"$WORK/clients\" 2>/dev/null || echo '[{\"address\":\"0xb\"}]' ;;\n\
         esac",
    );
    let qs_ipc = setup.script(
        "qs-ipc",
        "if [ \"$2\" = popup ]; then cat \"$WORK/popup\" 2>/dev/null || echo closed; else echo closed; fi",
    );
    let scripts = setup.path().join("xdg/hypr/scripts");
    std::fs::create_dir_all(&scripts).unwrap();
    std::os::unix::fs::symlink(qs_ipc, scripts.join("qs-ipc")).unwrap();
    setup
}

#[test]
fn each_built_in_wait_holds_the_next_step_until_its_condition_does() {
    for phrase in ["check focus", "check named", "check gone", "check popup"] {
        for holds in [true, false] {
            let setup = waits_setup();
            let envs: Vec<(&str, String)> = if holds {
                vec![("HOLDS", "1".to_string())]
            } else {
                Vec::new()
            };
            assert_eq!(
                code(&setup.run_with(&format!("{phrase} and then do after"), &envs)),
                Some(0)
            );
            assert_eq!(
                setup.path().join("work/after").exists(),
                holds,
                "{phrase} with the condition {}: {:?}",
                if holds { "met" } else { "unmet" },
                setup.texts()
            );
            if !holds {
                assert!(
                    setup.texts().last().unwrap().1.contains("timed out after 1s"),
                    "{phrase}: {:?}",
                    setup.texts()
                );
            }
        }
    }
}

const SLOW_PROBE: &str = r#"
name = "Slow"
verbs = [
  { action = "hang",  match = 'check hang' },
  { action = "after", match = 'do after' },
]

[actions]
hang = { run = 'touch "$WORK/slow"', wait = "active_window_changed" }
after = "echo after ran >> $WORK/after"
"#;

#[test]
fn a_built_in_wait_probe_is_cut_off_at_the_step_deadline() {
    let setup = Setup::new(SLOW_PROBE);
    // Answers at once until the action has run, then hangs well past the 1 s step.
    setup.script(
        "hyprctl",
        "if [ -e \"$WORK/slow\" ]; then sleep 5; fi; printf '{\"address\":\"0xa\"}'",
    );
    let started = std::time::Instant::now();
    assert_eq!(code(&setup.run("check hang and then do after")), Some(0));
    // The probe may use only the second the step has left, not its own two.
    assert!(
        started.elapsed() < std::time::Duration::from_millis(1800),
        "{:?}",
        started.elapsed()
    );
    assert!(
        setup.texts().last().unwrap().1.contains("timed out after 1s"),
        "{:?}",
        setup.texts()
    );
}

// ---- a stop signal ----

/// Starts `voxcmd run <phrase>`, waits until its `hold` action has started its child, and sends voxcmd the signal.
/// Returns how voxcmd ended and the child's pid.
fn signal_while_holding(setup: &Setup, phrase: &str, signal: &str, before: impl FnOnce(u32)) -> (Output, i32) {
    let voxcmd = setup
        .command(&["run", phrase], &[("VOXCMD_STEP_TIMEOUT_SECS", "20".to_string())])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    let held = setup.path().join("work/held");
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
    let child = loop {
        if let Some(pid) = std::fs::read_to_string(&held)
            .ok()
            .and_then(|text| text.trim().parse().ok())
        {
            break pid;
        }
        assert!(std::time::Instant::now() < deadline, "the action never started");
        std::thread::sleep(std::time::Duration::from_millis(10));
    };
    before(voxcmd.id());
    let sent = Command::new("kill")
        .args([&format!("-{signal}"), &voxcmd.id().to_string()])
        .status()
        .unwrap();
    assert!(sent.success());
    (voxcmd.wait_with_output().unwrap(), child)
}

#[test]
fn a_stop_signal_ends_the_running_action_with_its_children() {
    use std::os::unix::process::ExitStatusExt;
    let setup = Setup::new(INTEGRATION);
    let (output, child) = signal_while_holding(&setup, "do hold", "INT", |_| {});
    assert_eq!(output.status.signal(), Some(libc_signal("INT")));
    assert!(
        gone_within(child, std::time::Duration::from_secs(2)),
        "child {child} outlived voxcmd"
    );
}

#[test]
fn a_stop_signal_mid_sequence_removes_its_record_and_discard_flag() {
    use std::os::unix::process::ExitStatusExt;
    let setup = Setup::new(INTEGRATION);
    let runtime = setup.path().join("runtime/voxcmd");
    let (output, child) = signal_while_holding(&setup, "do hold and then do after", "TERM", |pid| {
        assert!(runtime.join(format!("sequences/{pid}.json")).exists());
        // Stop Voice flags the sequence first.
        std::fs::write(runtime.join(format!("discard.{pid}")), "").unwrap();
    });
    assert_eq!(output.status.signal(), Some(libc_signal("TERM")));
    assert!(gone_within(child, std::time::Duration::from_secs(2)));
    assert!(!setup.path().join("work/after").exists());
    let left: Vec<_> = std::fs::read_dir(&runtime)
        .unwrap()
        .chain(std::fs::read_dir(runtime.join("sequences")).unwrap())
        .flatten()
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .filter(|name| name.starts_with("discard.") || name.ends_with(".json"))
        .collect();
    assert!(left.is_empty(), "{left:?}");
}

/// The bar's stubs from tests/ask.rs (tests/fixtures/ask) in this setup, holding every question open; what they were
/// asked is copied into `work/dumps`.
fn bar_holding_questions(setup: &Setup) -> Vec<(&'static str, String)> {
    let scripts = setup.path().join("xdg/hypr/scripts");
    let dumps = setup.path().join("work/dumps");
    std::fs::create_dir_all(&scripts).unwrap();
    std::fs::create_dir_all(&dumps).unwrap();
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/ask");
    for name in ["qs-ipc", "qs-picker"] {
        std::os::unix::fs::symlink(fixtures.join(name), scripts.join(name)).unwrap();
    }
    vec![
        ("GOLDEN_HOLD", "1".to_string()),
        ("GOLDEN_DUMPS", dumps.display().to_string()),
    ]
}

/// The pid of the `timeout ... head -n 1 <fifo>` an ask in this setup reads its answer with.
fn answer_reader(setup: &Setup) -> Option<i32> {
    let runtime = setup.path().join("runtime").display().to_string();
    std::fs::read_dir("/proc").ok()?.flatten().find_map(|entry| {
        let pid: i32 = entry.file_name().to_str()?.parse().ok()?;
        let cmdline = std::fs::read(entry.path().join("cmdline")).ok()?;
        let cmdline = String::from_utf8_lossy(&cmdline);
        (cmdline.starts_with("timeout\0") && cmdline.contains(&runtime)).then_some(pid)
    })
}

/// `voxcmd run <phrase>` TERMed while its ask waits for an answer: voxcmd ends as TERM says, and the ask has cleaned
/// up after itself. Returns what the bar was asked.
fn term_run_while_asking(setup: &Setup, phrase: &str, envs: &[(&str, String)]) -> String {
    use std::os::unix::process::ExitStatusExt;
    let voxcmd = setup
        .command(&["run", phrase], envs)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
    let reader = loop {
        if let Some(pid) = answer_reader(setup) {
            break pid;
        }
        assert!(std::time::Instant::now() < deadline, "the ask never waited");
        std::thread::sleep(std::time::Duration::from_millis(10));
    };
    let pending = setup.path().join("runtime/voxcmd/pending-pick.json");
    assert!(pending.exists());
    // SAFETY: kill only sends a signal.
    unsafe { libc::kill(voxcmd.id() as i32, libc::SIGTERM) };
    let output = voxcmd.wait_with_output().unwrap();
    assert_eq!(output.status.signal(), Some(libc_signal("TERM")));
    assert!(!pending.exists(), "the pending pick stayed");
    let ask_dirs: Vec<_> = std::fs::read_dir(setup.path().join("runtime"))
        .unwrap()
        .flatten()
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .filter(|name| name.starts_with("voxcmd-"))
        .collect();
    assert!(ask_dirs.is_empty(), "{ask_dirs:?}");
    assert!(
        gone_within(reader, std::time::Duration::from_secs(2)),
        "the answer reader {reader} outlived the ask"
    );
    let dumps = setup.path().join("work/dumps");
    let mut calls: Vec<_> = std::fs::read_dir(&dumps)
        .unwrap()
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|extension| extension == "call"))
        .collect();
    calls.sort();
    calls
        .iter()
        .map(|path| std::fs::read_to_string(path).unwrap())
        .collect()
}

#[test]
fn a_stop_signal_lets_the_open_ask_clean_up() {
    let setup = Setup::new(INTEGRATION);
    let envs = bar_holding_questions(&setup);
    // A stopped pick leaves closing the picker to the bar.
    assert_eq!(term_run_while_asking(&setup, "do pick", &envs), "qs-picker choices\n");

    // An integration with numbered boxes asks through `ask hints`, which a stop signal dismisses on the bar.
    let setup = Setup::new(HINTED_INTEGRATION);
    let envs = bar_holding_questions(&setup);
    let calls = term_run_while_asking(&setup, "choose thing", &envs);
    let fifo = regex::Regex::new(r"/voxcmd-hints\.[A-Za-z0-9]{6}/result").unwrap();
    assert_eq!(
        fifo.replace_all(&calls, "/X/result"),
        format!(
            "qs-ipc call clickhints open\nqs-ipc call clickhints dismiss {}/runtime/X/result\n",
            setup.path().display()
        )
    );
}

fn libc_signal(name: &str) -> i32 {
    match name {
        "INT" => 2,
        "TERM" => 15,
        _ => unreachable!(),
    }
}

/// Two options whose ids place a box each (`x,y,button,left,top,width,height`), so the integration's `picker = "hints"`
/// shows numbered boxes.
const HINTED_INTEGRATION: &str = r#"
name = "Hinted"
picker = "hints"
verbs = [{ action = "choose", match = 'choose {target}' }]

[actions.choose]
run = "true"
candidates = "printf '1,1,left,0,0,1,1\\tThing One\\n2,2,left,2,2,1,1\\tThing Two\\n'"
"#;
