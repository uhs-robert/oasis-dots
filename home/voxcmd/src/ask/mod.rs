//! asking the user: the picker, the confirm card and the hints overlay (`voxcmd ask ...`, were the bash `voxcmd-pick`,
//! `-confirm`, `-hints`), the pending-pick handshake a spoken reply answers them through, and the asker a run uses
//!
//! An ask is a process of its own whose command line says what it is (`voxcmd ask pick ...`): `pending-pick.json` names
//! that process, and a reply, Stop Voice or the bar trust the file only while that process still asks (`read_pending`).
//! Each ask has a private directory under `$XDG_RUNTIME_DIR` holding the answer FIFO; whoever answers writes one line
//! to it, and an empty line is a cancel.
pub mod confirm;
pub mod hints;
pub mod pick;
pub mod reply;

use crate::debug::debug;
use crate::exit::CliError;
use crate::paths;
use crate::process;
use serde::{Deserialize, Deserializer, Serialize};
use std::collections::BTreeMap;
use std::ffi::{CString, OsStr, OsString};
use std::io::{Read, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::{FileTypeExt, OpenOptionsExt};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

/// The state of the open ask, which a reply reads. Written by `ask`, read by `reply`, `stop` and the bash voxcmd's
/// `pending_pick`; the field order is the bash helpers', which the suites match on.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PendingPick {
    #[serde(deserialize_with = "number_or_numeric_text")]
    pub pid: u32,
    pub fifo: PathBuf,
    #[serde(default, deserialize_with = "lenient_text")]
    pub label: String,
    /// `confirm` or `hints`; absent for the text picker.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(default)]
    pub choices: Vec<PickChoice>,
    #[serde(default)]
    pub expansions: BTreeMap<String, Expansion>,
    /// The file holding the expansion key the picker shows, empty for the top level (the text picker only).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub view: Option<PathBuf>,
    /// Present (as a file) while one more listen is left after an unclear reply. Hints write "" when not listening.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub listen_again: Option<String>,
    /// The confirm question's verb, which a reply starting with it answers yes.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub verb: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PickChoice {
    #[serde(default, deserialize_with = "lenient_text")]
    pub id: String,
    /// Numbered as shown: "1. Firefox".
    #[serde(default, deserialize_with = "lenient_text")]
    pub label: String,
    /// The expansion Tab opens from this choice.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expand: Option<String>,
    /// `[left, top, width, height]` on screen, for the hints overlay; kept as the asker gave it.
    #[serde(rename = "box", default, skip_serializing_if = "Option::is_none")]
    pub r#box: Option<serde_json::Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Expansion {
    #[serde(default, deserialize_with = "lenient_text")]
    pub title: String,
    #[serde(default)]
    pub choices: Vec<PickChoice>,
}

/// A file someone else wrote: a pid may come as `123` or `"123"`, as the bash `jq -r .pid` read either.
fn number_or_numeric_text<'de, D: Deserializer<'de>>(deserializer: D) -> Result<u32, D::Error> {
    let text = lenient_text(deserializer)?;
    text.parse().map_err(serde::de::Error::custom)
}

/// Text from a scalar of any type, as `jq -r` prints it; null is "".
fn lenient_text<'de, D: Deserializer<'de>>(deserializer: D) -> Result<String, D::Error> {
    Ok(match serde_json::Value::deserialize(deserializer)? {
        serde_json::Value::Null => String::new(),
        serde_json::Value::String(text) => text,
        other => other.to_string(),
    })
}

// ---- the answering side ---------------------------------------------------------------------------------------------

/// The pending pick while its asker still waits on its FIFO. A stale file is left alone: a new ask may be about to
/// replace it.
pub fn read_pending() -> Option<PendingPick> {
    let state: PendingPick = serde_json::from_str(&std::fs::read_to_string(paths::pending_pick()).ok()?).ok()?;
    let is_fifo = std::fs::metadata(&state.fifo).is_ok_and(|meta| meta.file_type().is_fifo());
    (is_fifo && still_asking(state.pid)).then_some(state)
}

/// Whether the pick read earlier is still the one waiting: Stop Voice may have cancelled it since.
pub fn still_pending(earlier: &PendingPick) -> bool {
    read_pending().is_some_and(|now| now.pid == earlier.pid && now.fifo == earlier.fifo)
}

const ASK_KINDS: [&str; 3] = ["pick", "confirm", "hints"];

/// The pid in the file still asks: it is a bash helper (`voxcmd-pick`, `-confirm`, `-hints`, anywhere in its command
/// line, as the bash `pending_pick` matched) or `voxcmd[-rs] ask <kind>`. A pid since reused by another process fails.
fn still_asking(pid: u32) -> bool {
    std::fs::read(format!("/proc/{pid}/cmdline")).is_ok_and(|cmdline| is_asker_command_line(&cmdline))
}

fn is_asker_command_line(cmdline: &[u8]) -> bool {
    let text = String::from_utf8_lossy(cmdline);
    if ASK_KINDS.iter().any(|kind| text.contains(&format!("voxcmd-{kind}"))) {
        return true;
    }
    let args: Vec<&str> = text.split('\0').collect();
    let program = args[0].rsplit('/').next().unwrap_or_default();
    matches!(program, "voxcmd" | "voxcmd-rs")
        && args.get(1) == Some(&"ask")
        && args.get(2).is_some_and(|kind| ASK_KINDS.contains(kind))
}

/// Writes one answer line to an asker's FIFO; empty is a cancel, as Esc is. Gives up after 2 seconds without a reader:
/// the asker may have exited between reading its state and this write.
pub fn write_answer(fifo: &Path, answer: &str) -> bool {
    let deadline = Instant::now() + Duration::from_secs(2);
    let mut fifo_file = loop {
        // Non-blocking, so a FIFO nobody reads fails (ENXIO) instead of blocking the open.
        match std::fs::OpenOptions::new()
            .write(true)
            .custom_flags(libc::O_NONBLOCK)
            .open(fifo)
        {
            Ok(file) => break file,
            Err(error) if error.raw_os_error() == Some(libc::ENXIO) && Instant::now() < deadline => {
                thread::sleep(Duration::from_millis(10));
            }
            Err(_) => return false,
        }
    };
    set_blocking(&fifo_file);
    fifo_file.write_all(format!("{answer}\n").as_bytes()).is_ok()
}

fn set_blocking(file: &std::fs::File) {
    use std::os::fd::AsRawFd;
    let fd = file.as_raw_fd();
    // SAFETY: fcntl on a descriptor the caller owns.
    unsafe {
        let flags = libc::fcntl(fd, libc::F_GETFL);
        if flags >= 0 {
            libc::fcntl(fd, libc::F_SETFL, flags & !libc::O_NONBLOCK);
        }
    }
}

/// For an ask answered by key, click or timeout while its reply recording still runs: the watcher whose pid the owner
/// file holds is told to drop that recording (its discard flag), which it does on its next poll. Only the watcher can
/// tell its recording from a dictation started since: voxtype has no recording ids. A no-op once the watcher is gone.
pub fn cancel_owned_recording(owner_file: &Path) {
    let Ok(text) = std::fs::read_to_string(owner_file) else {
        return;
    };
    let Ok(watcher) = text.trim_end_matches('\n').parse::<libc::pid_t>() else {
        return;
    };
    // SAFETY: signal 0 only checks that the process exists.
    if unsafe { libc::kill(watcher, 0) } != 0 {
        return;
    }
    debug(&format!(
        "answered without voice: discarding watcher {watcher}'s recording"
    ));
    let _ = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(paths::runtime_dir().join(format!("discard.{watcher}")));
}

/// `voxcmd internal cancel-owned-recording <owner file>`.
pub fn run_cancel_owned_recording(args: &[String]) -> Result<(), CliError> {
    let owner_file = args
        .first()
        .ok_or_else(|| CliError::usage("internal cancel-owned-recording", "usage: <recording owner file>"))?;
    cancel_owned_recording(Path::new(owner_file));
    Ok(())
}

/// Starts a reply's recording as `voxcmd listen --start-only` does: only from idle, never stopping a recording someone
/// else started. With an owner file, the watcher keeps its pid there while voxtype records or transcribes, so the ask
/// can cancel only its own recording.
pub fn listen_start_only(owner_file: Option<&Path>) -> bool {
    crate::voice::listen::start_only(owner_file)
}

// ---- the asking side ------------------------------------------------------------------------------------------------

/// INT, TERM or HUP arrived. The ask then cleans up and exits 1.
#[derive(Debug)]
pub struct Stopped;

/// INT, TERM and HUP while asking only mark the ask stopped, so it cleans up before it exits, as the bash helpers'
/// traps did: the mark is noticed between steps, never in the middle of one (a call to the bar runs to its end first).
/// A handler, not a blocked mask: children would inherit the mask, but exec resets a handler to the default.
pub struct StopSignals;

static STOP_RECEIVED: AtomicBool = AtomicBool::new(false);

extern "C" fn mark_stopped(_signal: libc::c_int) {
    STOP_RECEIVED.store(true, Ordering::SeqCst);
}

impl StopSignals {
    /// Also unblocks the three, which a parent's blocked mask would otherwise keep from ever arriving; one already
    /// pending is then marked at once.
    pub fn hold() -> Self {
        // SAFETY: a zeroed sigset filled by sigemptyset and sigaddset.
        let mut stop_set: libc::sigset_t = unsafe { std::mem::zeroed() };
        for signal in [libc::SIGINT, libc::SIGTERM, libc::SIGHUP] {
            // SAFETY: the handler only stores to an atomic; SA_RESTART resumes the call it interrupted.
            unsafe {
                let mut action: libc::sigaction = std::mem::zeroed();
                action.sa_sigaction = mark_stopped as extern "C" fn(libc::c_int) as libc::sighandler_t;
                action.sa_flags = libc::SA_RESTART;
                libc::sigemptyset(&mut action.sa_mask);
                libc::sigaction(signal, &action, std::ptr::null_mut());
                libc::sigaddset(&mut stop_set, signal);
            }
        }
        // SAFETY: changes only this thread's mask, the one the ask runs on.
        unsafe { libc::pthread_sigmask(libc::SIG_UNBLOCK, &stop_set, std::ptr::null_mut()) };
        Self
    }

    pub fn check(&self) -> Result<(), Stopped> {
        if STOP_RECEIVED.load(Ordering::SeqCst) {
            Err(Stopped)
        } else {
            Ok(())
        }
    }
}

/// An ask's private directory, `$XDG_RUNTIME_DIR/voxcmd-<kind>.XXXXXX` (a suite matches the prefix), holding the
/// answer FIFO `result` and the recording owner file. Cleaned up when dropped.
pub struct Asking {
    pub dir: PathBuf,
    pub fifo: PathBuf,
    owner_file: PathBuf,
    cleaned: bool,
}

impl Asking {
    pub fn create(kind: &str) -> Result<Self, CliError> {
        let failed = |what: &str| {
            CliError::failed(
                &format!("ask {kind}"),
                format!("{what}: {}", std::io::Error::last_os_error()),
            )
        };
        let template = paths::user_runtime_dir().join(format!("voxcmd-{kind}.XXXXXX"));
        let mut template = CString::new(template.into_os_string().into_vec())
            .map_err(|_| failed("bad runtime dir"))?
            .into_bytes_with_nul();
        // SAFETY: mkdtemp rewrites the X's of the NUL-terminated buffer it is given.
        if unsafe { libc::mkdtemp(template.as_mut_ptr().cast()) }.is_null() {
            return Err(failed("cannot make the ask's directory"));
        }
        template.pop();
        let dir = PathBuf::from(OsString::from_vec(template));
        let asking = Self {
            fifo: dir.join("result"),
            owner_file: dir.join("recording-owner"),
            dir,
            cleaned: false,
        };
        let fifo = CString::new(asking.fifo.as_os_str().as_bytes()).map_err(|_| failed("bad runtime dir"))?;
        // SAFETY: mkfifo on a NUL-terminated path.
        if unsafe { libc::mkfifo(fifo.as_ptr(), 0o600) } != 0 {
            return Err(failed("cannot make the answer FIFO"));
        }
        Ok(asking)
    }

    /// Replaces `pending-pick.json` in one step, before the question shows, so a reply recording started now or by
    /// the voice key goes to this ask.
    pub fn publish(&self, pending: &PendingPick) -> Result<(), CliError> {
        let failed = |error: std::io::Error| CliError::failed("ask", format!("cannot write the pending pick: {error}"));
        let staged = self.dir.join("pending-pick.json");
        let json = serde_json::to_string(pending).expect("the pending pick serializes");
        std::fs::write(&staged, json + "\n").map_err(failed)?;
        std::fs::create_dir_all(paths::runtime_dir()).map_err(failed)?;
        std::fs::rename(&staged, paths::pending_pick()).map_err(failed)
    }

    /// `--listen`: starts the reply recording before the question shows, so the microphone is live when it appears (an
    /// answer said the moment it shows is otherwise half lost), and waits up to 2 seconds for voxtype to report it.
    /// None when voxtype was busy, else how long it waited, in milliseconds.
    pub fn start_reply_recording(&self, signals: &StopSignals) -> Result<Option<u32>, Stopped> {
        let started = listen_start_only(Some(&self.owner_file));
        signals.check()?;
        if !started {
            return Ok(None);
        }
        let mut polls = 0;
        while polls < 40 && !self.reply_recording_live() {
            thread::sleep(Duration::from_millis(50));
            signals.check()?;
            polls += 1;
        }
        Ok(Some(polls * 50))
    }

    fn reply_recording_live(&self) -> bool {
        let recording = std::fs::read_to_string(paths::voxtype_state())
            .is_ok_and(|state| state.trim_end_matches('\n') == "recording");
        recording && std::fs::metadata(&self.owner_file).is_ok_and(|meta| meta.len() > 0)
    }

    /// The first line written to the FIFO (not EOF: rofi keeps it open while a voice reply arrives through it), or ""
    /// once `timeout` passes (read as `timeout(1)` reads it: "0.2", "5m"; 0 is none) or every writer closed it. Read
    /// by `timeout <t> head -n 1`, as the bash helpers read it, so a suite still finds the reader it waits for.
    pub fn read_answer(&self, timeout: &str, signals: &StopSignals) -> Result<String, Stopped> {
        let mut command = Command::new("timeout");
        command
            .arg(timeout)
            .args(["head", "-n", "1"])
            .arg(&self.fifo)
            .stdin(Stdio::null())
            .stdout(Stdio::piped());
        // `timeout` moves to a process group of its own, which a stop signal to the ask's group misses. It is TERMed
        // when the ask dies, even when the ask is killed outright, and passes that on to `head`.
        process::die_with_parent(&mut command);
        let Ok(mut reader) = command.spawn() else {
            return Ok(String::new());
        };
        let mut stdout = reader.stdout.take().expect("piped");
        let collected = thread::spawn(move || {
            let mut answer = String::new();
            let _ = stdout.read_to_string(&mut answer);
            answer
        });
        wait_or_terminate(&mut reader, signals)?;
        let answer = collected.join().unwrap_or_default();
        Ok(answer.trim_end_matches('\n').to_string())
    }

    /// Removes the pending pick if it is still this ask's (a newer one may have replaced it), drops the reply recording
    /// when nobody answered by voice, and removes the directory. Runs once.
    pub fn clean_up(&mut self) {
        if std::mem::replace(&mut self.cleaned, true) {
            return;
        }
        let ours = std::fs::read_to_string(paths::pending_pick())
            .ok()
            .and_then(|text| serde_json::from_str::<serde_json::Value>(&text).ok())
            .is_some_and(|state| state["pid"].as_u64() == Some(u64::from(std::process::id())));
        if ours {
            let _ = std::fs::remove_file(paths::pending_pick());
        }
        if self.owner_file.exists() {
            cancel_owned_recording(&self.owner_file);
        }
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

impl Drop for Asking {
    fn drop(&mut self) {
        self.clean_up();
    }
}

/// An ask's timeout setting as `timeout(1)` reads it, with empty counting as unset as `${VAR:-default}` does.
pub fn timeout_setting(name: &str, default: &str) -> String {
    std::env::var(name)
        .ok()
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| default.to_string())
}

/// Waits for a child, sending it TERM and returning `Stopped` when a held signal arrives first. TERM rather than KILL:
/// `timeout` passes it on to the `head` blocked opening the FIFO, which would otherwise outlive it.
pub fn wait_or_terminate(child: &mut Child, signals: &StopSignals) -> Result<std::process::ExitStatus, Stopped> {
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return Ok(status),
            Ok(None) => {}
            Err(_) => return Err(Stopped),
        }
        if signals.check().is_err() {
            if let Ok(pid) = libc::pid_t::try_from(child.id()) {
                // SAFETY: kill only sends a signal.
                unsafe { libc::kill(pid, libc::SIGTERM) };
            }
            let _ = child.wait();
            return Err(Stopped);
        }
        thread::sleep(Duration::from_millis(10));
    }
}

/// Ends a picker still running and what it started (rofi under `sh -c`), as `pkill -P <pid>; kill <pid>` did.
pub fn terminate_with_children(picker: &Child) {
    let _ = Command::new("pkill")
        .args(["-P", &picker.id().to_string()])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    if let Ok(pid) = libc::pid_t::try_from(picker.id()) {
        // SAFETY: kill only sends a signal.
        unsafe { libc::kill(pid, libc::SIGTERM) };
    }
}

/// `[ -x <path> ]`.
pub fn is_executable(path: &Path) -> bool {
    // SAFETY: access on a NUL-terminated path.
    CString::new(path.as_os_str().as_bytes()).is_ok_and(|path| unsafe { libc::access(path.as_ptr(), libc::X_OK) } == 0)
}

/// What `qs-ipc call <args>` printed, without trailing newlines; "" when it could not start. Unbounded, as the bash
/// helpers' calls were.
pub fn qs_ipc_call(args: &[&OsStr]) -> String {
    let output = Command::new(paths::qs_ipc())
        .arg("call")
        .args(args)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output();
    output.map_or_else(
        |_| String::new(),
        |output| {
            String::from_utf8_lossy(&output.stdout)
                .trim_end_matches('\n')
                .to_string()
        },
    )
}

/// One word quoted for `sh -c`: the rofi fallbacks are command strings that the bar's `qs-picker` runs.
pub fn shell_quote(word: &OsStr) -> String {
    format!("'{}'", word.to_string_lossy().replace('\'', r"'\''"))
}

// ---- asking from a run ----------------------------------------------------------------------------------------------

/// Who shows the choices.
pub enum PickWith<'a> {
    /// The text picker.
    Picker,
    /// An integration's own picker (click's numbered boxes), by the command the integration names.
    Command(&'a str),
}

pub trait Asker: Sync {
    /// Whether the user said yes. `verb` is the question's first word, which a spoken answer starting with it confirms.
    /// `listen` records the answer by voice too.
    fn confirm(&self, question: &str, verb: &str, listen: bool) -> bool;
    /// The index of the choice picked, none when the picker was cancelled. `choices` is the JSON `[{id, label}]`.
    fn pick(&self, with: &PickWith, label: &str, choices: &str, listen: bool) -> Option<usize>;
}

/// Asks through `voxcmd ask <kind>` in a process of its own, whose command line is what makes its pending pick
/// answerable; or through `$VOXCMD_ASK_CMD <kind> ...` when that is set, the seam the suites stub asking through.
pub struct AskWith {
    program: PathBuf,
    leading_args: Vec<OsString>,
}

impl AskWith {
    pub fn from_env() -> Self {
        match std::env::var_os("VOXCMD_ASK_CMD").filter(|cmd| !cmd.is_empty()) {
            Some(ask_cmd) => Self::new(ask_cmd.into(), Vec::new()),
            None => Self::new(this_binary(), vec!["ask".into()]),
        }
    }

    pub fn new(program: PathBuf, leading_args: Vec<OsString>) -> Self {
        Self { program, leading_args }
    }

    /// The command that asks a question of this kind; its arguments follow.
    pub fn command(&self, kind: &str) -> Command {
        let mut command = Command::new(&self.program);
        command.args(&self.leading_args).arg(kind);
        command
    }

    /// Runs an asker to its end, its group listed so that Stop Voice reaches it; stderr is passed on.
    fn run(mut command: Command) -> Option<String> {
        let outcome = match process::run_ask_to_end(&mut command) {
            Ok(outcome) => outcome,
            Err(error) => {
                debug(&format!(
                    "cannot run the asker {}: {error}",
                    command.get_program().to_string_lossy()
                ));
                return None;
            }
        };
        eprint!("{}", outcome.stderr);
        (outcome.code() == Some(0)).then_some(outcome.stdout)
    }
}

/// This binary's path. Once a rebuild has replaced the running binary, Linux names it `<path> (deleted)`; the path
/// then holds the new build, which asks as well.
pub fn this_binary() -> PathBuf {
    std::env::current_exe().map_or_else(|_| "voxcmd".into(), without_deleted_mark)
}

fn without_deleted_mark(exe: PathBuf) -> PathBuf {
    match exe.as_os_str().as_bytes().strip_suffix(b" (deleted)") {
        Some(rebuilt) if !exe.exists() => PathBuf::from(OsStr::from_bytes(rebuilt)),
        _ => exe,
    }
}

/// click.sh's `pick_command=voxcmd-hints` (a path beside the bash voxcmd by now) is this binary's `ask hints`.
fn names_hints(command: &str) -> bool {
    Path::new(command)
        .file_name()
        .is_some_and(|name| name == "voxcmd-hints")
}

impl Asker for AskWith {
    fn confirm(&self, question: &str, verb: &str, listen: bool) -> bool {
        let mut command = self.command("confirm");
        command.args(["--verb", verb]);
        if listen {
            command.arg("--listen");
        }
        command.arg(question);
        Self::run(command).is_some()
    }

    fn pick(&self, with: &PickWith, label: &str, choices: &str, listen: bool) -> Option<usize> {
        let mut command = match with {
            PickWith::Picker => self.command("pick"),
            PickWith::Command(path) if names_hints(path) => self.command("hints"),
            PickWith::Command(path) => Command::new(path),
        };
        if listen {
            command.arg("--listen");
        }
        command.args([label, choices]);
        Self::run(command)?.trim().parse().ok()
    }
}

/// Replaces this process with another asker, as the bash `exec` did: stdout, the exit status and signals are then that
/// process's. Returns only when it could not start.
pub fn exec(mut command: Command) -> CliError {
    let error = command.exec();
    CliError::failed("ask", format!("cannot run the text picker: {error}"))
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    /// An executable file whose exec is known to work (see `settle_exec`); `VOXCMD_TEST_PROBE` makes it exit at once.
    pub(crate) fn script(dir: &std::path::Path, name: &str, body: &str) -> PathBuf {
        let temp = dir.join(format!(".{name}.tmp"));
        std::fs::write(
            &temp,
            format!("#!/bin/sh\n[ -z \"$VOXCMD_TEST_PROBE\" ] || exit 0\n{body}\n"),
        )
        .unwrap();
        std::fs::set_permissions(&temp, std::fs::Permissions::from_mode(0o755)).unwrap();
        let path = dir.join(name);
        std::fs::rename(&temp, &path).unwrap();
        settle_exec(&path);
        path
    }

    /// Runs the script once in probe mode until it execs: renaming does not help (the inode is the same), but a fork on
    /// another test thread that held the write fd lets go of it at its exec, so after this no later exec is ETXTBSY.
    fn settle_exec(path: &std::path::Path) {
        for _ in 0..500 {
            match std::process::Command::new(path).env("VOXCMD_TEST_PROBE", "1").status() {
                Err(error) if error.kind() == std::io::ErrorKind::ExecutableFileBusy => {
                    std::thread::sleep(std::time::Duration::from_millis(10));
                }
                _ => return,
            }
        }
    }

    #[test]
    fn the_seam_command_gets_the_kind_then_the_arguments() {
        let dir = tempfile::tempdir().unwrap();
        let log = dir.path().join("calls");
        let stub = script(
            dir.path(),
            "stub",
            &format!(
                "printf '%s|' \"$@\" >> '{}'; echo >> '{0}'; [ \"$1\" = confirm ] || echo 1",
                log.display()
            ),
        );
        let ask = AskWith::new(stub, Vec::new());
        assert!(ask.confirm("Close it?", "close", false));
        assert!(ask.confirm("Close it?", "close", true));
        assert_eq!(
            ask.pick(&PickWith::Picker, "Which command?", "[{\"id\":\"0\"}]", false),
            Some(1)
        );
        assert_eq!(
            ask.pick(
                &PickWith::Command("/pkg/.local/bin/voxcmd-hints"),
                "Which one?",
                "[]",
                true
            ),
            Some(1)
        );
        assert_eq!(
            std::fs::read_to_string(&log).unwrap(),
            "confirm|--verb|close|Close it?|\nconfirm|--verb|close|--listen|Close it?|\n\
             pick|Which command?|[{\"id\":\"0\"}]|\nhints|--listen|Which one?|[]|\n"
        );
    }

    #[test]
    fn an_integrations_own_pick_command_runs_as_named() {
        let dir = tempfile::tempdir().unwrap();
        let log = dir.path().join("calls");
        let own = script(
            dir.path(),
            "fake-pick",
            &format!("echo \"$*\" > '{}'; echo 2", log.display()),
        );
        let ask = AskWith::new(PathBuf::from("/nonexistent"), Vec::new());
        assert_eq!(
            ask.pick(&PickWith::Command(own.to_str().unwrap()), "Which one?", "[]", false),
            Some(2)
        );
        assert_eq!(std::fs::read_to_string(&log).unwrap(), "Which one? []\n");
    }

    #[test]
    fn a_cancelled_or_unreadable_pick_is_none() {
        let dir = tempfile::tempdir().unwrap();
        let cancel = script(dir.path(), "cancel", "exit 1");
        let junk = script(dir.path(), "junk", "echo banana");
        assert_eq!(
            AskWith::new(cancel, Vec::new()).pick(&PickWith::Picker, "l", "[]", false),
            None
        );
        assert_eq!(
            AskWith::new(junk, Vec::new()).pick(&PickWith::Picker, "l", "[]", false),
            None
        );
    }

    #[test]
    fn a_rebuilt_binary_is_asked_by_its_path() {
        let dir = tempfile::tempdir().unwrap();
        let rebuilt = dir.path().join("voxcmd");
        let deleted = dir.path().join("voxcmd (deleted)");
        assert_eq!(without_deleted_mark(deleted.clone()), rebuilt);
        std::fs::write(&deleted, "").unwrap();
        assert_eq!(without_deleted_mark(deleted.clone()), deleted);
        assert_eq!(without_deleted_mark(rebuilt.clone()), rebuilt);
    }

    #[test]
    fn an_asker_is_a_bash_helper_or_voxcmd_ask() {
        let asking: [&[u8]; 5] = [
            b"/bin/bash\0/home/u/.local/bin/voxcmd-confirm\0--verb\0close\0Close it?\0",
            b"/tmp/x/voxcmd-hints\x0060\0",
            b"/home/u/target/release/voxcmd\0ask\0pick\0Which?\0[]\0",
            b"voxcmd-rs\0ask\0hints\0--listen\0Which?\0[]\0",
            b"/usr/bin/voxcmd\0ask\0confirm\0",
        ];
        let other: [&[u8]; 5] = [
            b"/home/u/target/release/voxcmd\0run\0close firefox\0",
            b"/usr/bin/voxcmd\0ask\0",
            b"/usr/bin/voxcmd\0ask\0other\0",
            b"/usr/bin/myvoxcmd\0ask\0pick\0",
            b"sleep\x0060\0",
        ];
        for cmdline in asking {
            assert!(is_asker_command_line(cmdline), "{}", String::from_utf8_lossy(cmdline));
        }
        for cmdline in other {
            assert!(!is_asker_command_line(cmdline), "{}", String::from_utf8_lossy(cmdline));
        }
    }

    #[test]
    fn a_pending_pick_reads_as_the_bash_helpers_wrote_it() {
        let written = r#"{"pid":"42","fifo":"/r/voxcmd-hints.x/result","label":"Which one?","kind":"hints",
            "choices":[{"id":7,"label":"1. Next","box":[1,2,3,4]}],"expansions":{},"listen_again":""}"#;
        let state: PendingPick = serde_json::from_str(written).unwrap();
        assert_eq!(state.pid, 42);
        assert_eq!(state.choices[0].id, "7");
        assert_eq!(state.choices[0].r#box, Some(serde_json::json!([1, 2, 3, 4])));
        assert_eq!(state.listen_again.as_deref(), Some(""));
        assert!(serde_json::from_str::<PendingPick>(r#"{"pid":"x","fifo":"/f"}"#).is_err());
    }

    #[test]
    fn the_pending_pick_keeps_the_helpers_field_order() {
        let state = PendingPick {
            pid: 1,
            fifo: "/f".into(),
            label: "Which one?".into(),
            kind: Some("hints".into()),
            choices: Vec::new(),
            expansions: BTreeMap::new(),
            view: None,
            listen_again: Some(String::new()),
            verb: None,
        };
        assert_eq!(
            serde_json::to_string(&state).unwrap(),
            r#"{"pid":1,"fifo":"/f","label":"Which one?","kind":"hints","choices":[],"expansions":{},"listen_again":""}"#
        );
    }

    #[test]
    fn an_answer_reaches_a_reader_and_a_fifo_nobody_reads_gives_up() {
        let dir = tempfile::tempdir().unwrap();
        let fifo = dir.path().join("result");
        let path = CString::new(fifo.as_os_str().as_bytes()).unwrap();
        // SAFETY: mkfifo on a NUL-terminated path.
        assert_eq!(unsafe { libc::mkfifo(path.as_ptr(), 0o600) }, 0);
        let reader = {
            let fifo = fifo.clone();
            thread::spawn(move || std::fs::read_to_string(fifo).unwrap())
        };
        assert!(write_answer(&fifo, "2. Next - bottom"));
        assert_eq!(reader.join().unwrap(), "2. Next - bottom\n");
        let started = Instant::now();
        assert!(!write_answer(&fifo, "x"));
        assert!(started.elapsed() >= Duration::from_secs(2));
        assert!(!write_answer(&dir.path().join("gone"), "x"));
    }
}
