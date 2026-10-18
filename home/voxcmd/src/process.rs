//! running a command: its own process group, both pipes drained, the whole group killed on timeout or when voxcmd is
//! told to stop
//!
//! The one place that spawns a hook or an action. Either is `bash -c` and may start children of its own; killing only
//! bash would leave them running (and holding the pipes open), so each command leads a process group of its own. A
//! timeout kills the group, and so does SIGINT or SIGTERM to voxcmd (Stop Voice must reach a running action), which also
//! removes the files listed with `RemovedOnSignal`. An ask is the exception: a stop signal TERMs it so it can take its
//! question down, and kills it only if it is still there after `STOP_GRACE`; so is a watcher's auto-stop detector
//! (`spawn_letting_clean_up`). Once a stop signal has begun ending voxcmd, nothing new is spawned.
use std::ffi::CString;
use std::io::Read;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::Path;
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::Once;
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicPtr, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

const POLL: Duration = Duration::from_millis(5);

/// How long, once the command has exited, its pipes get to deliver what is left. A child that outlived it may still
/// hold them open, and its output is cut off there. One deadline covers both pipes.
const DRAIN_GRACE: Duration = Duration::from_millis(200);

/// How long after the group was killed the readers get to hand over their last bytes.
const DRAIN_AFTER_KILL: Duration = Duration::from_millis(100);

/// How long a stop signal lets an ask clean up (its pending pick, its directory, the bar's overlay) before it is
/// killed. It ends sooner once every ask has exited.
const STOP_GRACE: Duration = Duration::from_secs(2);

/// How a command is ended when voxcmd is told to stop.
#[derive(Clone, Copy, PartialEq)]
enum OnStop {
    /// A hook or an action: killed at once.
    Kill,
    /// An ask: TERM, then KILL after `STOP_GRACE`.
    LetCleanUp,
}

#[derive(Debug)]
pub struct Outcome {
    /// None when the deadline passed first.
    pub status: Option<ExitStatus>,
    pub stdout: String,
    pub stderr: String,
    pub timed_out: bool,
}

impl Outcome {
    /// The exit code; None when timed out or killed by a signal.
    pub fn code(&self) -> Option<i32> {
        self.status.and_then(|status| status.code())
    }

    /// A line for a failure that has no exit code to show.
    pub fn how_it_ended(&self) -> String {
        match (self.timed_out, self.status) {
            (true, _) => "timed out".to_string(),
            (_, Some(status)) => match (status.code(), status.signal()) {
                (Some(code), _) => format!("exit {code}"),
                (None, Some(signal)) => format!("killed by signal {signal}"),
                (None, None) => "ended".to_string(),
            },
            (_, None) => "did not end".to_string(),
        }
    }
}

/// Runs the command with no stdin and both outputs captured. After `timeout` the command's process group is killed;
/// so it is when the command has exited, so that children it left behind do not outlive the call.
pub fn run_with_timeout(command: &mut Command, timeout: Duration) -> std::io::Result<Outcome> {
    run(command, Some(timeout), OnStop::Kill)
}

/// `run_with_timeout` for an action, which has no deadline of its own (Stop Voice ends it). What it left running after
/// it exited is left alone: an action may start an app, which must outlive it.
pub fn run_to_end(command: &mut Command) -> std::io::Result<Outcome> {
    run(command, None, OnStop::Kill)
}

/// `run_to_end` for an ask, which a stop signal gives time to take its question down (see `STOP_GRACE`).
pub fn run_ask_to_end(command: &mut Command) -> std::io::Result<Outcome> {
    run(command, None, OnStop::LetCleanUp)
}

/// Starts a long-lived child in a process group of its own and returns at once, its group listed until the returned
/// guard drops: a stop signal TERMs it, as it does an ask. For a watcher's auto-stop detector, whose caller waits on it.
pub fn spawn_letting_clean_up(command: &mut Command) -> std::io::Result<(Child, LiveGroup)> {
    command.process_group(0);
    spawn_listed(command, OnStop::LetCleanUp)
}

/// Has the child TERMed when the thread that spawns it ends (`PR_SET_PDEATHSIG`; for a child that must not outlive
/// voxcmd even when voxcmd is SIGKILLed). A parent that died before the call took effect is caught too: the child then
/// never execs. It exits instead of raising TERM, which in the forked child would run voxcmd's own handler, or stay
/// blocked by an inherited mask.
pub fn die_with_parent(command: &mut Command) {
    // SAFETY: getpid has no preconditions.
    let parent = unsafe { libc::getpid() };
    // SAFETY: prctl and getppid are async-signal-safe and touch only the child.
    unsafe {
        command.pre_exec(move || {
            libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
            if parent_is_gone(parent, libc::getppid()) {
                return Err(std::io::Error::other("the parent is gone"));
            }
            Ok(())
        });
    }
}

/// A child whose parent died is reparented, so its parent pid is no longer the one it was forked from.
fn parent_is_gone(forked_from: libc::pid_t, parent_now: libc::pid_t) -> bool {
    forked_from != parent_now
}

fn run(command: &mut Command, timeout: Option<Duration>, on_stop: OnStop) -> std::io::Result<Outcome> {
    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .process_group(0);
    let (mut child, _live) = spawn_listed(command, on_stop)?;
    let stdout = Drain::start(child.stdout.take());
    let stderr = Drain::start(child.stderr.take());
    let deadline = timeout.map(|timeout| Instant::now() + timeout);
    let (status, timed_out) = loop {
        match child.try_wait() {
            Ok(Some(status)) => break (Some(status), false),
            Ok(None) => {}
            Err(error) => {
                kill_and_reap(&mut child);
                return Err(error);
            }
        }
        if deadline.is_some_and(|deadline| Instant::now() >= deadline) {
            kill_and_reap(&mut child);
            break (None, true);
        }
        thread::sleep(POLL);
    };
    if !timed_out {
        let grace_ends = Instant::now() + DRAIN_GRACE;
        wait_until(grace_ends, || stdout.finished() && stderr.finished());
        if timeout.is_some() {
            // The command is reaped, but a child of its group may live on; the group id stays taken while it does.
            kill_group(child.id());
        }
    }
    wait_until(Instant::now() + DRAIN_AFTER_KILL, || {
        stdout.finished() && stderr.finished()
    });
    Ok(Outcome {
        status,
        stdout: stdout.text(),
        stderr: stderr.text(),
        timed_out,
    })
}

fn kill_and_reap(child: &mut Child) {
    kill_group(child.id());
    // Reaped so no zombie is left; the group is gone, so this does not wait long.
    let _ = child.wait();
}

fn wait_until(deadline: Instant, done: impl Fn() -> bool) {
    while !done() && Instant::now() < deadline {
        thread::sleep(Duration::from_millis(2));
    }
}

/// One pipe read on a thread of its own, so that a full pipe never blocks the command. The bytes are kept as they
/// arrive: a pipe held open by a leftover child must not cost the output already read.
struct Drain {
    bytes: Arc<Mutex<Vec<u8>>>,
    reached_end: Arc<AtomicBool>,
}

impl Drain {
    fn start(pipe: Option<impl Read + Send + 'static>) -> Self {
        let drain = Self {
            bytes: Arc::default(),
            reached_end: Arc::default(),
        };
        let (bytes, reached_end) = (Arc::clone(&drain.bytes), Arc::clone(&drain.reached_end));
        thread::spawn(move || {
            if let Some(mut pipe) = pipe {
                let mut chunk = [0u8; 4096];
                while let Ok(count) = pipe.read(&mut chunk) {
                    if count == 0 {
                        break;
                    }
                    bytes
                        .lock()
                        .expect("reader holds the lock briefly")
                        .extend_from_slice(&chunk[..count]);
                }
            }
            reached_end.store(true, Ordering::Release);
        });
        drain
    }

    fn finished(&self) -> bool {
        self.reached_end.load(Ordering::Acquire)
    }

    fn text(&self) -> String {
        String::from_utf8_lossy(&self.bytes.lock().expect("reader holds the lock briefly")).into_owned()
    }
}

/// SIGKILL to the group the child leads. Never pid 0 or 1, and never voxcmd's own group: either would take voxcmd (or
/// the session) down with the hook.
fn kill_group(pid: u32) {
    let Ok(group) = libc::pid_t::try_from(pid) else {
        return;
    };
    // SAFETY: getpgrp has no preconditions.
    let own_group = unsafe { libc::getpgrp() };
    if group > 1 && group != own_group {
        // SAFETY: killpg only sends a signal; a group that no longer exists is an ignored ESRCH.
        unsafe { libc::killpg(group, libc::SIGKILL) };
    }
}

// ---- what to undo when voxcmd is told to stop -----------------------------------------------------------------------
//
// Everything here is read by the signal handler, which may not take a lock or allocate: fixed arrays of atomics, and
// paths turned into C strings before they are listed.

const LIVE_SLOTS: usize = 32;
const REMOVED_SLOTS: usize = 8;

/// Process groups of the commands running now, 0 for a free slot; negated for an `OnStop::LetCleanUp` group, so that
/// the handler never reads a group without how to end it.
static LIVE_GROUPS: [AtomicI32; LIVE_SLOTS] = [const { AtomicI32::new(0) }; LIVE_SLOTS];
/// Files to remove on a stop signal, null for a free slot.
static REMOVED_ON_SIGNAL: [AtomicPtr<Removal>; REMOVED_SLOTS] =
    [const { AtomicPtr::new(std::ptr::null_mut()) }; REMOVED_SLOTS];
/// Threads between spawning a command and listing its group. A signal then is held until the last of them has
/// listed its group (`PENDING_SIGNAL`), or the command would outlive voxcmd.
static SPAWNING: AtomicUsize = AtomicUsize::new(0);
static PENDING_SIGNAL: AtomicI32 = AtomicI32::new(0);
/// Set once a stop signal has begun ending voxcmd. A thread the signal did not land on keeps running through the
/// ask's grace, and must not start a command the ending has already passed over.
static STOPPING: AtomicBool = AtomicBool::new(false);
static HANDLERS: Once = Once::new();

/// Spawns the command and lists its group, with no moment between the two at which a stop signal leaves it running.
/// Fails once voxcmd is stopping.
fn spawn_listed(command: &mut Command, on_stop: OnStop) -> std::io::Result<(Child, LiveGroup)> {
    HANDLERS.call_once(install_handlers);
    // SeqCst throughout, paired with the handler's: it either sees this thread spawning, or this thread sees its signal.
    SPAWNING.fetch_add(1, Ordering::SeqCst);
    if STOPPING.load(Ordering::SeqCst) {
        SPAWNING.fetch_sub(1, Ordering::SeqCst);
        return Err(std::io::Error::other("voxcmd is stopping"));
    }
    let spawned = command.spawn();
    let live = spawned
        .as_ref()
        .ok()
        .map(|child| LiveGroup::register(child.id(), on_stop));
    if SPAWNING.fetch_sub(1, Ordering::SeqCst) == 1 {
        let signal = PENDING_SIGNAL.load(Ordering::SeqCst);
        if signal != 0 {
            end_on_signal(signal);
        }
    }
    Ok((spawned?, live.unwrap_or(LiveGroup(None))))
}

/// A running command's group, listed until dropped.
pub struct LiveGroup(Option<usize>);

impl LiveGroup {
    fn register(pid: u32, on_stop: OnStop) -> Self {
        let Ok(group) = libc::pid_t::try_from(pid) else {
            return Self(None);
        };
        let group = if on_stop == OnStop::LetCleanUp { -group } else { group };
        let slot = LIVE_GROUPS.iter().position(|slot| {
            slot.compare_exchange(0, group, Ordering::AcqRel, Ordering::Acquire)
                .is_ok()
        });
        Self(slot)
    }
}

impl Drop for LiveGroup {
    fn drop(&mut self) {
        if let Some(slot) = self.0 {
            LIVE_GROUPS[slot].store(0, Ordering::Release);
        }
    }
}

/// A file to remove, and the only text it may then hold (none: whatever it holds).
struct Removal {
    path: CString,
    if_holding: Option<CString>,
}

/// A file removed if a stop signal ends voxcmd while this lives; a signal skips every `Drop`, so the owner's own
/// cleanup would not run. Dropping it only unlists the file.
pub struct RemovedOnSignal(Option<usize>);

impl RemovedOnSignal {
    pub fn new(path: &Path) -> Self {
        Self::listed(path, None)
    }

    /// Removed only while the file still holds `content` (a watcher's pid in an ask's recording owner file, which a
    /// newer watcher may have taken over).
    pub fn if_holding(path: &Path, content: &str) -> Self {
        Self::listed(path, Some(content))
    }

    fn listed(path: &Path, if_holding: Option<&str>) -> Self {
        HANDLERS.call_once(install_handlers);
        let Ok(path) = CString::new(path.as_os_str().as_bytes()) else {
            return Self(None);
        };
        let Ok(if_holding) = if_holding.map(CString::new).transpose() else {
            return Self(None);
        };
        // Never freed: the handler may be reading it on another thread as it is unlisted. A few per process.
        let removal = Box::into_raw(Box::new(Removal { path, if_holding }));
        let slot = REMOVED_ON_SIGNAL.iter().position(|slot| {
            slot.compare_exchange(std::ptr::null_mut(), removal, Ordering::AcqRel, Ordering::Acquire)
                .is_ok()
        });
        Self(slot)
    }
}

impl Drop for RemovedOnSignal {
    fn drop(&mut self) {
        if let Some(slot) = self.0 {
            REMOVED_ON_SIGNAL[slot].store(std::ptr::null_mut(), Ordering::Release);
        }
    }
}

/// Whether the file holds exactly `expected`. Only async-signal-safe calls, for the handler.
fn file_holds(path: &CString, expected: &CString) -> bool {
    let mut held = [0u8; 64];
    // SAFETY: open, read and close on a NUL-terminated path, into a buffer of the length given.
    let length = unsafe {
        let fd = libc::open(path.as_ptr(), libc::O_RDONLY | libc::O_CLOEXEC);
        if fd < 0 {
            return false;
        }
        let length = libc::read(fd, held.as_mut_ptr().cast(), held.len());
        libc::close(fd);
        length
    };
    let Ok(length) = usize::try_from(length) else {
        return false;
    };
    &held[..length] == expected.as_bytes()
}

fn install_handlers() {
    for signal in [libc::SIGINT, libc::SIGTERM] {
        // SAFETY: the handler only uses atomics and async-signal-safe calls (killpg, waitpid, nanosleep, open,
        // read, close, unlink, signal, raise).
        unsafe {
            libc::signal(
                signal,
                on_stop_signal as extern "C" fn(libc::c_int) as libc::sighandler_t,
            )
        };
    }
}

extern "C" fn on_stop_signal(signal: libc::c_int) {
    PENDING_SIGNAL.store(signal, Ordering::SeqCst);
    // A thread mid-spawn ends voxcmd itself once its group is listed.
    if SPAWNING.load(Ordering::SeqCst) == 0 {
        end_on_signal(signal);
    }
}

/// Ends every listed group and removes every listed file, then lets the signal do what it would have done, so voxcmd
/// still ends as the signal says. Runs in the handler, or on the thread that held the signal. A second signal during
/// the first one's grace (another thread's, or INT on top of TERM) only ends what has been listed since, and leaves
/// the waiting and the exit to the first, so a stop never takes two graces.
fn end_on_signal(signal: libc::c_int) {
    let already_stopping = STOPPING.swap(true, Ordering::SeqCst);
    let mut asks_terminated = false;
    for slot in &LIVE_GROUPS {
        let listed = slot.load(Ordering::Acquire);
        let (group, sent) = if listed < 0 {
            (-listed, libc::SIGTERM)
        } else {
            (listed, libc::SIGKILL)
        };
        // Each listed group leads a command voxcmd started, so it is never voxcmd's own or the session's.
        if group > 1 {
            // SAFETY: killpg only sends a signal.
            unsafe { libc::killpg(group, sent) };
            asks_terminated |= sent == libc::SIGTERM;
        }
    }
    for slot in &REMOVED_ON_SIGNAL {
        // SAFETY: a listed removal is never freed.
        let Some(removal) = (unsafe { slot.load(Ordering::Acquire).as_ref() }) else {
            continue;
        };
        if removal
            .if_holding
            .as_ref()
            .is_none_or(|expected| file_holds(&removal.path, expected))
        {
            // SAFETY: unlink on a NUL-terminated path.
            unsafe { libc::unlink(removal.path.as_ptr()) };
        }
    }
    if already_stopping {
        return;
    }
    if asks_terminated {
        kill_asks_after_grace();
    }
    // SAFETY: restoring the default action and raising again are async-signal-safe.
    unsafe {
        libc::signal(signal, libc::SIG_DFL);
        libc::raise(signal);
    }
}

/// Waits up to `STOP_GRACE` for every TERMed ask to exit, then kills what is left of their groups: an ask stuck past
/// it, or a child of one. Exited asks are reaped here, as voxcmd is about to end anyway.
fn kill_asks_after_grace() {
    const POLL_NANOS: libc::c_long = 10_000_000;
    let polls = STOP_GRACE.as_nanos() / POLL_NANOS as u128;
    for _ in 0..polls {
        let any_asking = LIVE_GROUPS.iter().any(|slot| {
            let leader = -slot.load(Ordering::Acquire);
            // SAFETY: a non-blocking waitpid on a child of voxcmd; -1 means another thread reaped it already.
            leader > 1 && unsafe { libc::waitpid(leader, std::ptr::null_mut(), libc::WNOHANG) } == 0
        });
        if !any_asking {
            break;
        }
        let pause = libc::timespec {
            tv_sec: 0,
            tv_nsec: POLL_NANOS,
        };
        // SAFETY: nanosleep is async-signal-safe; an early wake only shortens one poll.
        unsafe { libc::nanosleep(&pause, std::ptr::null_mut()) };
    }
    for slot in &LIVE_GROUPS {
        let group = -slot.load(Ordering::Acquire);
        if group > 1 {
            // SAFETY: killpg only sends a signal; a group that is gone is an ignored ESRCH.
            unsafe { libc::killpg(group, libc::SIGKILL) };
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    fn sh(script: &str) -> Command {
        let mut command = Command::new("sh");
        command.args(["-c", script]);
        command
    }

    #[test]
    fn output_and_exit_code_come_back() {
        let outcome = run_with_timeout(&mut sh("echo out; echo err >&2; exit 7"), Duration::from_secs(5)).unwrap();
        assert_eq!(outcome.code(), Some(7));
        assert_eq!(outcome.stdout, "out\n");
        assert_eq!(outcome.stderr, "err\n");
        assert!(!outcome.timed_out);
    }

    #[test]
    fn a_command_past_its_deadline_is_killed_with_its_children() {
        let dir = tempfile::tempdir().unwrap();
        let pid_file = dir.path().join("child.pid");
        let script = format!("sleep 30 & echo $! > '{}'; wait", pid_file.display());
        let started = Instant::now();
        let outcome = run_with_timeout(&mut sh(&script), Duration::from_millis(300)).unwrap();
        assert!(outcome.timed_out);
        assert_eq!(outcome.code(), None);
        assert!(started.elapsed() < Duration::from_secs(5));
        let child: i32 = std::fs::read_to_string(&pid_file).unwrap().trim().parse().unwrap();
        assert!(
            gone_within(child, Duration::from_secs(2)),
            "child {child} outlived the kill"
        );
    }

    #[test]
    fn a_child_holding_the_pipes_costs_neither_time_nor_output() {
        let dir = tempfile::tempdir().unwrap();
        let pid_file = dir.path().join("child.pid");
        let script = format!("sleep 3 & echo $! > '{}'; printf 'a\\tA\\n'", pid_file.display());
        let started = Instant::now();
        let outcome = run_with_timeout(&mut sh(&script), Duration::from_secs(5)).unwrap();
        assert_eq!(outcome.code(), Some(0));
        assert_eq!(outcome.stdout, "a\tA\n");
        assert!(started.elapsed() < Duration::from_secs(1), "{:?}", started.elapsed());
        // The leftover child is killed with the group, not left to hold the pipes.
        let child: i32 = std::fs::read_to_string(&pid_file).unwrap().trim().parse().unwrap();
        assert!(
            gone_within(child, Duration::from_secs(2)),
            "child {child} outlived the call"
        );
    }

    /// Runs the named test again in a process of its own with `VOXCMD_PROCESS_TEST_CHILD` set: a stop signal, and
    /// the stopping it starts, would end or poison every other test in this one.
    fn in_own_process(test: &str) -> Command {
        let mut command = Command::new(std::env::current_exe().unwrap());
        command
            .args(["--exact", &format!("process::tests::{test}"), "--test-threads=1"])
            .env("VOXCMD_PROCESS_TEST_CHILD", "1")
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        command
    }

    fn is_own_process() -> bool {
        std::env::var_os("VOXCMD_PROCESS_TEST_CHILD").is_some()
    }

    #[test]
    fn nothing_is_spawned_once_a_stop_has_begun() {
        if is_own_process() {
            STOPPING.store(true, Ordering::SeqCst);
            let refused = run_with_timeout(&mut sh("true"), Duration::from_secs(1)).is_err();
            std::process::exit(i32::from(!refused));
        }
        assert!(
            in_own_process("nothing_is_spawned_once_a_stop_has_begun")
                .status()
                .unwrap()
                .success()
        );
    }

    #[test]
    fn a_second_stop_signal_during_the_grace_does_not_add_one() {
        if is_own_process() {
            // An ask that ignores TERM, so only the KILL after the grace ends it.
            thread::spawn(|| run_ask_to_end(&mut sh("trap '' TERM; sleep 30")));
            thread::sleep(Duration::from_millis(200));
            // SAFETY: kill only sends a signal, here to this process.
            unsafe { libc::kill(libc::getpid(), libc::SIGTERM) };
            thread::sleep(Duration::from_millis(300));
            // SAFETY: as above.
            unsafe { libc::kill(libc::getpid(), libc::SIGINT) };
            thread::sleep(Duration::from_secs(30));
            std::process::exit(0);
        }
        let started = Instant::now();
        let status = in_own_process("a_second_stop_signal_during_the_grace_does_not_add_one")
            .status()
            .unwrap();
        // One grace (2 s) after the first signal; two would be past 4 s.
        assert!(
            started.elapsed() < Duration::from_millis(3500),
            "{:?}",
            started.elapsed()
        );
        assert_eq!(status.signal(), Some(libc::SIGTERM), "the first signal ends it");
    }

    #[test]
    fn a_child_that_dies_with_its_parent_dies_with_the_thread_that_started_it() {
        let child = thread::spawn(|| {
            let mut command = Command::new("sleep");
            command.arg("30");
            die_with_parent(&mut command);
            command.spawn().unwrap().id()
        })
        .join()
        .unwrap();
        assert!(gone_within(i32::try_from(child).unwrap(), Duration::from_secs(2)));
    }

    #[test]
    fn a_parent_is_gone_once_the_child_has_been_reparented() {
        assert!(!parent_is_gone(100, 100));
        assert!(parent_is_gone(100, 1));
    }

    /// Dead, or a zombie nobody has reaped yet.
    pub(crate) fn gone_within(pid: i32, wait: Duration) -> bool {
        let deadline = Instant::now() + wait;
        loop {
            let state = std::fs::read_to_string(format!("/proc/{pid}/stat"))
                .ok()
                .and_then(|stat| {
                    let after_name = stat.rsplit_once(')')?.1.trim_start().to_string();
                    after_name.chars().next()
                });
            if matches!(state, None | Some('Z')) {
                return true;
            }
            if Instant::now() >= deadline {
                return false;
            }
            thread::sleep(Duration::from_millis(20));
        }
    }
}
