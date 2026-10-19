//! `voxcmd ask` and `voxcmd reply`: parity with what the bash `voxcmd-pick`, `-confirm`, `-hints` and the bash reply did
//! for the same questions and answers (golden files made by tests/fixtures/gen-ask-goldens.sh), and the handshake
//! through the answer FIFO. The bar is the same two stub scripts on both sides (tests/fixtures/ask), which copy what
//! they were shown and answer as the bar would.
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

fn fixtures_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures")
}

fn unescape(field: &str) -> String {
    let mut out = String::new();
    let mut chars = field.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('n') => out.push('\n'),
            Some('t') => out.push('\t'),
            Some('r') => out.push('\r'),
            Some(other) => out.push(other),
            None => out.push('\\'),
        }
    }
    out
}

fn rows(file: &str, fields: usize) -> Vec<Vec<String>> {
    std::fs::read_to_string(fixtures_dir().join(file))
        .unwrap()
        .lines()
        .map(|line| {
            let row: Vec<String> = line.split('\t').map(unescape).collect();
            assert_eq!(row.len(), fields, "{file}: {line}");
            row
        })
        .collect()
}

/// A command with none of the caller's voxcmd settings, so the goldens' environment is the only one.
fn voxcmd() -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_voxcmd"));
    for (key, _) in std::env::vars_os() {
        if key.to_string_lossy().starts_with("VOXCMD_") || key.to_string_lossy().starts_with("GOLDEN_") {
            command.env_remove(key);
        }
    }
    command.env("HOME", "/nonexistent").env("LC_ALL", "C");
    command
}

/// Exit status, stdout and stderr, with a bound so that a hang fails the test instead of stalling it.
fn finish(mut child: Child) -> (i32, String, String) {
    let deadline = Instant::now() + Duration::from_secs(30);
    while child.try_wait().unwrap().is_none() {
        assert!(Instant::now() < deadline, "voxcmd did not finish");
        std::thread::sleep(Duration::from_millis(10));
    }
    let output = child.wait_with_output().unwrap();
    (
        output.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&output.stdout)
            .trim_end_matches('\n')
            .to_string(),
        String::from_utf8_lossy(&output.stderr)
            .trim_end_matches('\n')
            .to_string(),
    )
}

/// What the stubs copied, one line per file, with the pid and the private directories made fixed as the generator does.
fn shown(dumps: &Path, runtime: &Path) -> String {
    let mut files: Vec<PathBuf> = std::fs::read_dir(dumps)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .collect();
    files.sort();
    let lines: Vec<String> = files
        .iter()
        .map(|file| {
            let name = file.file_name().unwrap().to_string_lossy();
            let text = std::fs::read_to_string(file).unwrap();
            format!("{name} {}", text.trim_end_matches('\n'))
        })
        .collect();
    let text = lines.join("\n").replace(&runtime.display().to_string(), "RT");
    let text = regex::Regex::new(r"voxcmd-(pick|confirm|hints)\.[A-Za-z0-9]{6}")
        .unwrap()
        .replace_all(&text, "voxcmd-$1.X");
    regex::Regex::new(r#""pid":[0-9]+"#)
        .unwrap()
        .replace_all(&text, r#""pid":0"#)
        .into_owned()
}

/// A runtime dir and a stubbed bar for one ask. Toasts go to a `notify-send` stub that logs them, never the desktop.
struct Bar {
    dir: tempfile::TempDir,
}

impl Bar {
    fn new() -> Self {
        let bar = Self {
            dir: tempfile::tempdir().unwrap(),
        };
        for created in [bar.runtime(), bar.dumps(), bar.scripts(), bar.path().join("bin")] {
            std::fs::create_dir_all(created).unwrap();
        }
        // Linked, not copied: an executable written here could be held open by a fork on another test thread, and
        // its exec would fail (ETXTBSY).
        let stub = |name: &str| fixtures_dir().join("ask").join(name);
        for name in ["qs-ipc", "qs-picker"] {
            std::os::unix::fs::symlink(stub(name), bar.scripts().join(name)).unwrap();
        }
        std::os::unix::fs::symlink(stub("notify-send"), bar.path().join("bin/notify-send")).unwrap();
        bar
    }

    fn path(&self) -> &Path {
        self.dir.path()
    }

    fn runtime(&self) -> PathBuf {
        self.path().join("runtime")
    }

    fn dumps(&self) -> PathBuf {
        self.path().join("dumps")
    }

    fn scripts(&self) -> PathBuf {
        self.path().join("config/hypr/scripts")
    }

    fn pending_pick(&self) -> PathBuf {
        self.runtime().join("voxcmd/pending-pick.json")
    }

    fn command(&self, args: &[&str], env: &[(&str, &str)]) -> Command {
        let mut command = voxcmd();
        let path = format!(
            "{}:{}",
            self.path().join("bin").display(),
            std::env::var("PATH").unwrap_or_default()
        );
        command
            .args(args)
            .envs(env.iter().copied())
            .env("PATH", path)
            .env("XDG_RUNTIME_DIR", self.runtime())
            .env("XDG_CONFIG_HOME", self.path().join("config"))
            .env("GOLDEN_DUMPS", self.dumps())
            .env("GOLDEN_TOASTS", self.path().join("toasts"))
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        command
    }

    fn spawn(&self, args: &[&str], env: &[(&str, &str)]) -> Child {
        self.command(args, env).spawn().unwrap()
    }

    fn calls(&self) -> String {
        shown(&self.dumps(), &self.runtime())
    }

    fn toasts(&self) -> String {
        std::fs::read_to_string(self.path().join("toasts")).unwrap_or_default()
    }

    /// Whatever the ask left beside voxcmd's own runtime dir: its private directory, if it was not removed.
    fn left_behind(&self) -> Vec<std::ffi::OsString> {
        std::fs::read_dir(self.runtime())
            .unwrap()
            .map(|entry| entry.unwrap().file_name())
            .filter(|entry| entry != "voxcmd")
            .collect()
    }
}

fn wait_for(what: &str, done: impl Fn() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(20);
    while !done() {
        assert!(Instant::now() < deadline, "never: {what}");
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn asks_show_and_answer_as_the_bash_helpers_did() {
    for row in rows("ask-goldens.tsv", 7) {
        let [name, kind, env, args, status, stdout, expected_shown] = <[String; 7]>::try_from(row).unwrap();
        let bar = Bar::new();
        let env: serde_json::Map<String, serde_json::Value> = serde_json::from_str(&env).unwrap();
        let env: Vec<(&str, &str)> = env
            .iter()
            .map(|(key, value)| (key.as_str(), value.as_str().unwrap()))
            .collect();
        let args: Vec<String> = serde_json::from_str(&args).unwrap();
        let mut argv = vec!["ask", kind.as_str()];
        argv.extend(args.iter().map(String::as_str));
        let (code, out, err) = finish(bar.spawn(&argv, &env));
        assert_eq!(code.to_string(), status, "{name}: {err}");
        assert_eq!(out, stdout, "{name}");
        assert_eq!(bar.calls(), expected_shown, "{name}");
        assert!(!bar.pending_pick().exists(), "{name}: the pending pick stayed");
        assert!(bar.left_behind().is_empty(), "{name}: left {:?}", bar.left_behind());
    }
}

const TWO: &str = r#"["Firefox", "Slack"]"#;
const BOXES: &str = r#"[{"id":"a","label":"Next - top","box":[100,50,60,20]},{"id":"b","label":"Next - bottom","box":[300,200,70,22]}]"#;

#[test]
fn a_pick_nobody_answers_times_out_closes_the_picker_and_cleans_up() {
    let bar = Bar::new();
    let started = Instant::now();
    let (code, out, _) = finish(bar.spawn(
        &["ask", "pick", "Which?", TWO],
        &[("GOLDEN_HOLD", "1"), ("VOXCMD_PICK_TIMEOUT", "0.3")],
    ));
    assert_eq!((code, out.as_str()), (1, ""));
    assert!(started.elapsed() < Duration::from_secs(10));
    assert!(bar.calls().ends_with("qs-ipc call picker close"), "{}", bar.calls());
    assert!(!bar.pending_pick().exists());
    assert!(bar.left_behind().is_empty());
}

#[test]
fn a_qs_picker_slow_to_exit_after_its_answer_is_still_closed_as_the_bar_picker() {
    let bar = Bar::new();
    let (code, out, err) = finish(bar.spawn(
        &["ask", "pick", "Which?", TWO],
        &[("GOLDEN_ANSWER", "2. Slack"), ("GOLDEN_LINGER", "0.1")],
    ));
    assert_eq!((code, out.as_str()), (0, "Slack"), "{err}");
    assert!(bar.calls().ends_with("qs-ipc call picker close"), "{}", bar.calls());
}

#[test]
fn term_while_waiting_exits_1_dismisses_the_overlay_and_cleans_up() {
    let bar = Bar::new();
    let child = bar.spawn(&["ask", "hints", "Which one?", BOXES], &[("GOLDEN_HOLD", "1")]);
    wait_for("the overlay opens", || bar.calls().contains(".spec "));
    // SAFETY: kill only sends a signal.
    unsafe { libc::kill(child.id() as i32, libc::SIGTERM) };
    let (code, _, _) = finish(child);
    assert_eq!(code, 1);
    assert!(
        bar.calls()
            .ends_with("qs-ipc call clickhints dismiss RT/voxcmd-hints.X/result"),
        "{}",
        bar.calls()
    );
    assert!(!bar.pending_pick().exists());
    assert!(bar.left_behind().is_empty(), "{:?}", bar.left_behind());
}

#[test]
fn a_pending_pick_a_newer_ask_took_over_is_left_alone() {
    let bar = Bar::new();
    let (code, out, _) = finish(bar.spawn(
        &["ask", "pick", "Which?", TWO],
        &[("GOLDEN_REPLACE", "1"), ("GOLDEN_ANSWER", "1. Firefox")],
    ));
    assert_eq!((code, out.as_str()), (0, "Firefox"));
    assert_eq!(
        std::fs::read_to_string(bar.pending_pick()).unwrap(),
        "{\"pid\":1,\"fifo\":\"/newer\"}\n"
    );
}

#[test]
fn a_reply_answers_the_open_pick_and_confirm_through_their_fifos() {
    let bar = Bar::new();
    let pick = bar.spawn(&["ask", "pick", "Which?", TWO], &[("GOLDEN_HOLD", "1")]);
    wait_for("the pick is pending", || bar.pending_pick().exists());
    let (code, _, err) = finish(bar.spawn(&["reply", "the second one"], &[]));
    assert_eq!(code, 0, "{err}");
    assert_eq!(finish(pick).1, "Slack");

    let confirm = bar.spawn(
        &["ask", "confirm", "--verb", "close", "Close it?"],
        &[("GOLDEN_HOLD", "1")],
    );
    wait_for("the card is pending", || bar.pending_pick().exists());
    let (code, out, _) = finish(bar.spawn(&["explain", "--reply", "--json", "close it"], &[]));
    assert_eq!(code, 0);
    let trace: serde_json::Value = serde_json::from_str(&out).unwrap();
    assert_eq!(trace["reply"]["verdict"], "yes");
    assert_eq!(trace["reply"]["kind"], "confirm");
    assert_eq!(finish(bar.spawn(&["reply", "close it"], &[])).0, 0);
    assert_eq!(finish(confirm).0, 0);
    assert!(bar.toasts().is_empty(), "{}", bar.toasts());
}

#[test]
fn an_unclear_reply_leaves_the_question_open_and_says_so() {
    let bar = Bar::new();
    let hints = bar.spawn(&["ask", "hints", "Which one?", BOXES], &[("GOLDEN_HOLD", "1")]);
    wait_for("the overlay opens", || bar.calls().contains(".spec "));
    assert_eq!(finish(bar.spawn(&["reply", "banana"], &[])).0, 1);
    assert_eq!(
        bar.toasts(),
        "-a|voxcmd|--transient|voxcmd: which one?|\"banana\": no choice matches. Say a choice, a number, or cancel.|\n"
    );
    assert_eq!(finish(bar.spawn(&["reply", "the bottom one"], &[])).0, 0);
    assert_eq!(finish(hints).1, "b");
    assert_eq!(finish(bar.spawn(&["reply", "two"], &[])).0, 1);
    assert!(
        bar.toasts()
            .ends_with("-a|voxcmd|--transient|voxcmd|No picker is waiting for a reply|\n"),
        "{}",
        bar.toasts()
    );
}

#[test]
fn the_bash_spelling_of_cancel_owned_recording_flags_the_watcher() {
    let bar = Bar::new();
    let mut watcher = Command::new("sleep").arg("60").spawn().unwrap();
    let owner_file = bar.path().join("recording-owner");
    std::fs::write(&owner_file, format!("{}\n", watcher.id())).unwrap();
    std::fs::create_dir_all(bar.runtime().join("voxcmd")).unwrap();
    let (code, _, _) = finish(bar.spawn(&["_cancel_owned_recording", owner_file.to_str().unwrap()], &[]));
    assert_eq!(code, 0);
    assert!(bar.runtime().join(format!("voxcmd/discard.{}", watcher.id())).exists());
    let _ = watcher.kill();
    let _ = watcher.wait();
    std::fs::write(&owner_file, "999999999\n").unwrap();
    assert_eq!(
        finish(bar.spawn(
            &["internal", "cancel-owned-recording", owner_file.to_str().unwrap()],
            &[]
        ))
        .0,
        0
    );
}

/// A process whose command line names a bash helper, as a pending pick's asker must have. Copying an executable races
/// with forks on other test threads (ETXTBSY until they exec), so the start is retried.
fn waiter(dir: &Path) -> Child {
    let path = dir.join("voxcmd-hints");
    std::fs::copy("/bin/sleep", &path).unwrap();
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        match Command::new(&path).arg("600").spawn() {
            Ok(child) => return child,
            Err(error) if error.kind() == std::io::ErrorKind::ExecutableFileBusy && Instant::now() < deadline => {
                std::thread::sleep(Duration::from_millis(10));
            }
            Err(error) => panic!("{error}"),
        }
    }
}

#[test]
fn replies_match_as_the_bash_reply_did() {
    let dir = tempfile::tempdir().unwrap();
    let mut waiter = waiter(dir.path());
    let runtime = dir.path().join("runtime");
    std::fs::create_dir_all(runtime.join("voxcmd")).unwrap();
    let fifo = runtime.join("result");
    let fifo_path = std::ffi::CString::new(fifo.to_str().unwrap()).unwrap();
    // SAFETY: mkfifo on a NUL-terminated path.
    assert_eq!(unsafe { libc::mkfifo(fifo_path.as_ptr(), 0o600) }, 0);
    let view = runtime.join("view");
    let pending_file = runtime.join("voxcmd/pending-pick.json");
    for row in rows("reply-goldens.tsv", 6) {
        let [name, pending, viewed, reply, status, expected] = <[String; 6]>::try_from(row).unwrap();
        let _ = std::fs::remove_file(&pending_file);
        if pending != "-" {
            let mut state: serde_json::Value = serde_json::from_str(&pending).unwrap();
            state["pid"] = waiter.id().into();
            state["fifo"] = fifo.to_str().unwrap().into();
            if state.get("view").is_some() {
                state["view"] = view.to_str().unwrap().into();
            }
            std::fs::write(&pending_file, state.to_string()).unwrap();
        }
        std::fs::write(&view, &viewed).unwrap();
        let child = voxcmd()
            .args(["reply", "--dry-run", "--", &reply])
            .env("XDG_RUNTIME_DIR", &runtime)
            .env("VOXCMD_CONFIG_DIR", fixtures_dir().join("speech"))
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        let (code, out, err) = finish(child);
        let output = [out, err]
            .into_iter()
            .filter(|text| !text.is_empty())
            .collect::<Vec<_>>()
            .join("\n");
        assert_eq!(
            (code.to_string(), output),
            (status, expected),
            "{name} {viewed:?} {reply:?}"
        );
    }
    let _ = waiter.kill();
    let _ = waiter.wait();
}

/// The command with a TERM already pending when it starts: blocked and raised in the child before its exec, which keeps
/// both, so the ask sees it as soon as it holds its signals.
fn with_term_pending(mut command: Command) -> Command {
    use std::os::unix::process::CommandExt;
    // SAFETY: sigprocmask and raise are async-signal-safe and touch only the child.
    unsafe {
        command.pre_exec(|| {
            let mut term: libc::sigset_t = std::mem::zeroed();
            libc::sigemptyset(&mut term);
            libc::sigaddset(&mut term, libc::SIGTERM);
            libc::sigprocmask(libc::SIG_BLOCK, &term, std::ptr::null_mut());
            libc::raise(libc::SIGTERM);
            Ok(())
        });
    }
    command
}

#[test]
fn a_stop_signal_during_setup_ends_the_ask_before_the_question_shows() {
    let asks: [&[&str]; 3] = [
        &["ask", "pick", "Which?", TWO],
        &["ask", "confirm", "--verb", "close", "Close it?"],
        &["ask", "hints", "Which one?", BOXES],
    ];
    for args in asks {
        let bar = Bar::new();
        let child = with_term_pending(bar.command(args, &[("GOLDEN_HOLD", "1")]))
            .spawn()
            .unwrap();
        let (code, _, err) = finish(child);
        assert_eq!(code, 1, "{args:?}: {err}");
        assert_eq!(bar.calls(), "", "{args:?}: the question showed");
        assert!(!bar.pending_pick().exists(), "{args:?}");
        assert!(bar.left_behind().is_empty(), "{args:?}: left {:?}", bar.left_behind());
    }
}
