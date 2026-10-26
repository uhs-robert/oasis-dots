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
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicPtr, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::sync::{Once, OnceLock};
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
    command.stdin(Stdio::null());
    run(command, Some(timeout), OnStop::Kill, Capture::Yes, Leftovers::Killed)
}

/// `run_with_timeout` for a command that reads voxcmd's own stdin (a wake clip voxcmd-wake pipes in, `/dev/stdin`);
/// `None` is no deadline.
pub fn run_with_timeout_on_stdin(command: &mut Command, timeout: Option<Duration>) -> std::io::Result<Outcome> {
    command.stdin(Stdio::inherit());
    let leftovers = if timeout.is_some() {
        Leftovers::Killed
    } else {
        Leftovers::Kept
    };
    run(command, timeout, OnStop::Kill, Capture::Yes, leftovers)
}

/// `run_with_timeout` for an action, which has no deadline of its own (Stop Voice ends it). What it left running after
/// it exited is left alone: an action may start an app, which must outlive it.
pub fn run_to_end(command: &mut Command) -> std::io::Result<Outcome> {
    command.stdin(Stdio::null());
    run(command, None, OnStop::Kill, Capture::Yes, Leftovers::Kept)
}

/// `run_to_end` with both outputs to /dev/null and a deadline, so a child the command leaves behind never holds a
/// pipe this call waits on. It kills the command's whole group. A child it left running when
/// it exited in time is left alone, as `run_to_end` leaves it.
pub fn run_discarding_output_within(command: &mut Command, timeout: Duration) -> std::io::Result<Outcome> {
    command.stdin(Stdio::null());
    run(command, Some(timeout), OnStop::Kill, Capture::No, Leftovers::Kept)
}

/// `run_to_end` for an ask, which a stop signal gives time to take its question down (see `STOP_GRACE`).
pub fn run_ask_to_end(command: &mut Command) -> std::io::Result<Outcome> {
    command.stdin(Stdio::null());
    run(command, None, OnStop::LetCleanUp, Capture::Yes, Leftovers::Kept)
}

/// Starts a long-lived child in a process group of its own and returns at once, its group listed until the returned
/// guard drops: a stop signal TERMs it, as it does an ask. For a watcher's auto-stop detector, whose caller waits on it.
pub fn spawn_letting_clean_up(command: &mut Command) -> std::io::Result<(Child, LiveGroup)> {
    command.process_group(0);
    spawn_listed(command, OnStop::LetCleanUp, None)
}

/// Starts one process of a pipeline and returns at once, its group listed until the returned guard drops: a stop
/// signal kills the group. `leader` is None for the first process, which leads a group of its own, and that process's
/// pid for each later one, which joins its group so that one kill reaches the whole pipeline. The caller spawns every
/// stage before it waits on any: a stage spawned after the group was killed would outlive it.
pub fn spawn_killed_on_stop(command: &mut Command, leader: Option<u32>) -> std::io::Result<(Child, LiveGroup)> {
    command.process_group(leader.map_or(0, |pid| pid.try_into().unwrap_or(0)));
    spawn_listed(command, OnStop::Kill, leader)
}

/// Has the child TERMed when the thread that spawns it ends (`PR_SET_PDEATHSIG`; for a child that must not outlive
/// voxcmd even when voxcmd is SIGKILLed). A parent that died before the call took effect is caught too: the child then
/// never execs. It exits instead of raising TERM, which in the forked child would run voxcmd's own handler, or stay
/// blocked by an inherited mask.
pub fn die_with_parent(command: &mut Command) {
    // SAFETY: getpid has no preconditions.
    let parent = unsafe { libc::getpid() };
    // SAFETY: prctl and getppid are async-signal-safe and touch only the child. Nothing here may allocate: another
    // thread may have held the malloc lock at the fork.
    unsafe {
        command.pre_exec(move || {
            libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
            if parent_is_gone(parent, libc::getppid()) {
                return Err(std::io::Error::from_raw_os_error(libc::ESRCH));
            }
            Ok(())
        });
    }
}

/// Leaves a detached child (a watcher, a chain's stopper) hearing SIGINT, SIGTERM and SIGHUP whatever the caller does
/// with them: an ask holding its stop signals, or a caller that ignores them, must not leave the child deaf to Stop
/// Voice's TERM, and exec keeps a blocked mask and an ignored signal.
pub fn hear_stop_signals(command: &mut Command) {
    // SAFETY: sigprocmask and signal are async-signal-safe and touch only the child.
    unsafe {
        command.pre_exec(|| {
            let mut stop_set: libc::sigset_t = std::mem::zeroed();
            libc::sigemptyset(&mut stop_set);
            for signal in [libc::SIGINT, libc::SIGTERM, libc::SIGHUP] {
                libc::signal(signal, libc::SIG_DFL);
                libc::sigaddset(&mut stop_set, signal);
            }
            libc::sigprocmask(libc::SIG_UNBLOCK, &stop_set, std::ptr::null_mut());
            Ok(())
        });
    }
}

/// A child whose parent died is reparented, so its parent pid is no longer the one it was forked from.
fn parent_is_gone(forked_from: libc::pid_t, parent_now: libc::pid_t) -> bool {
    forked_from != parent_now
}

#[derive(Clone, Copy)]
enum Capture {
    Yes,
    No,
}

/// What becomes of what the command left running in its group once it has exited by itself.
#[derive(Clone, Copy, PartialEq)]
enum Leftovers {
    Killed,
    Kept,
}

/// Each caller sets stdin: only `run_with_timeout_on_stdin` lets a command read voxcmd's own.
fn run(
    command: &mut Command,
    timeout: Option<Duration>,
    on_stop: OnStop,
    capture: Capture,
    leftovers: Leftovers,
) -> std::io::Result<Outcome> {
    let output_stdio = match capture {
        Capture::Yes => Stdio::piped,
        Capture::No => Stdio::null,
    };
    command.stdout(output_stdio()).stderr(output_stdio()).process_group(0);
    let (mut child, _live) = spawn_listed(command, on_stop, None)?;
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
        if leftovers == Leftovers::Killed {
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
/// Fails once voxcmd is stopping. `group_leader` is the pid of the group the command joins, None when it leads one.
fn spawn_listed(
    command: &mut Command,
    on_stop: OnStop,
    group_leader: Option<u32>,
) -> std::io::Result<(Child, LiveGroup)> {
    HANDLERS.call_once(install_handlers);
    // SeqCst throughout, paired with the handler's: it either sees this thread spawning, or this thread sees its signal.
    SPAWNING.fetch_add(1, Ordering::SeqCst);
    if STOPPING.load(Ordering::SeqCst) {
        SPAWNING.fetch_sub(1, Ordering::SeqCst);
        return Err(std::io::Error::other(RefusedWhileStopping));
    }
    let spawned = command.spawn();
    let live = spawned
        .as_ref()
        .ok()
        .map(|child| LiveGroup::register(group_leader.unwrap_or_else(|| child.id()), on_stop));
    if SPAWNING.fetch_sub(1, Ordering::SeqCst) == 1 {
        let signal = PENDING_SIGNAL.load(Ordering::SeqCst);
        if signal != 0 {
            end_on_signal(signal);
        }
    }
    Ok((spawned?, live.unwrap_or(LiveGroup(None))))
}

/// Why `spawn_listed` refused: the stop under way ends what voxcmd was doing, so this is no failure to report.
#[derive(Debug)]
struct RefusedWhileStopping;

impl std::fmt::Display for RefusedWhileStopping {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("voxcmd is stopping")
    }
}

impl std::error::Error for RefusedWhileStopping {}

/// Whether a spawn failed only because voxcmd is stopping.
pub fn refused_while_stopping(error: &std::io::Error) -> bool {
    error.get_ref().is_some_and(|inner| inner.is::<RefusedWhileStopping>())
}

/// Whether any process is still in the group. While one is, even a zombie, the kernel keeps the group's id from being
/// handed out again, so signalling it cannot reach someone else's processes.
pub fn group_has_members(group: libc::pid_t) -> bool {
    // SAFETY: signal 0 only checks that the group exists; EPERM means it does, with a member voxcmd may not signal.
    group > 1
        && (unsafe { libc::killpg(group, 0) } == 0
            || std::io::Error::last_os_error().raw_os_error() == Some(libc::EPERM))
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
    /// Set for a directory: the files inside it are unlinked, then it is removed. A signal handler cannot walk a
    /// directory, so the files are listed up front.
    inside: Option<Vec<CString>>,
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

    /// A directory removed with the files named in it, which are the only ones it may hold (no walk in the handler).
    pub fn directory(path: &Path, file_names: &[String]) -> Self {
        let inside = file_names
            .iter()
            .map(|name| CString::new(path.join(name).as_os_str().as_bytes()))
            .collect::<Result<Vec<_>, _>>();
        match inside {
            Ok(inside) => Self::listed_with(path, None, Some(inside)),
            Err(_) => Self(None),
        }
    }

    fn listed(path: &Path, if_holding: Option<&str>) -> Self {
        Self::listed_with(path, if_holding, None)
    }

    fn listed_with(path: &Path, if_holding: Option<&str>, inside: Option<Vec<CString>>) -> Self {
        HANDLERS.call_once(install_handlers);
        let Ok(path) = CString::new(path.as_os_str().as_bytes()) else {
            return Self(None);
        };
        let Ok(if_holding) = if_holding.map(CString::new).transpose() else {
            return Self(None);
        };
        // Never freed: the handler may be reading it on another thread as it is unlisted. A few per process.
        let removal = Box::into_raw(Box::new(Removal {
            path,
            if_holding,
            inside,
        }));
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
        handle_as_stop(signal);
    }
}

/// The stop signals held back on this thread until dropped: one that arrives meanwhile is delivered then. For the
/// steps that set up how a stop ends voxcmd (the handlers, `run_on_stop`), so no signal finds them half done. Only
/// while this is voxcmd's one thread: another one would take the signal instead. Threads started meanwhile keep the
/// signals held for good, so the handler never runs on them.
pub struct StopSignalsHeld(libc::sigset_t);

impl StopSignalsHeld {
    pub fn new() -> Self {
        // SAFETY: sigset_t is plain data, filled by sigemptyset and pthread_sigmask before it is read.
        unsafe {
            let mut held: libc::sigset_t = std::mem::zeroed();
            libc::sigemptyset(&raw mut held);
            for signal in [libc::SIGINT, libc::SIGTERM, libc::SIGHUP] {
                libc::sigaddset(&raw mut held, signal);
            }
            let mut before: libc::sigset_t = std::mem::zeroed();
            libc::pthread_sigmask(libc::SIG_BLOCK, &raw const held, &raw mut before);
            Self(before)
        }
    }
}

impl Drop for StopSignalsHeld {
    fn drop(&mut self) {
        // SAFETY: restores the mask `new` saved.
        unsafe { libc::pthread_sigmask(libc::SIG_SETMASK, &raw const self.0, std::ptr::null_mut()) };
    }
}

/// SIGHUP ends voxcmd as SIGTERM does. Only for a watcher, which logind HUPs at logout and which must still take its
/// files and detector down then, as the bash EXIT trap did; a CLI run whose terminal closes keeps the default.
pub fn stop_on_hangup_too() {
    HANDLERS.call_once(install_handlers);
    handle_as_stop(libc::SIGHUP);
}

fn handle_as_stop(signal: libc::c_int) {
    // SAFETY: the handler only uses atomics and async-signal-safe calls (killpg, waitpid, nanosleep, open, read, close,
    // unlink, write, signal, raise).
    unsafe {
        libc::signal(
            signal,
            on_stop_signal as extern "C" fn(libc::c_int) as libc::sighandler_t,
        )
    };
}

extern "C" fn on_stop_signal(signal: libc::c_int) {
    PENDING_SIGNAL.store(signal, Ordering::SeqCst);
    // A thread mid-spawn ends voxcmd itself once its group is listed.
    if SPAWNING.load(Ordering::SeqCst) == 0 {
        end_on_signal(signal);
    }
}

/// The write end of the pipe that wakes the thread running the stop's last act (`run_on_stop`), -1 while there is
/// none. The handler only writes the signal's number to it: the act takes the session lock, reads JSON and starts
/// processes, none of which a handler may do.
static LAST_ACT_WAKE: AtomicI32 = AtomicI32::new(-1);
static LAST_ACT_THREAD: OnceLock<thread::ThreadId> = OnceLock::new();

/// How long the last act may take before voxcmd ends anyway: it waits for the session lock, which a hung holder could
/// keep.
const LAST_ACT_LIMIT: Duration = Duration::from_secs(5);

/// Has a stop signal run `act` as voxcmd's last act, after it has ended its groups and removed its files: on a thread
/// of its own, which then ends voxcmd as the signal would have. Once per process, under `StopSignalsHeld`: a signal
/// before the act is listed would end voxcmd without it.
pub fn run_on_stop(act: impl FnOnce() + Send + 'static) {
    HANDLERS.call_once(install_handlers);
    let mut fds = [0; 2];
    // SAFETY: pipe2 fills the two descriptors given.
    if unsafe { libc::pipe2(fds.as_mut_ptr(), libc::O_CLOEXEC) } != 0 {
        return;
    }
    let [wake_read, wake_write] = fds;
    let spawned = thread::Builder::new().name("last act".into()).spawn(move || {
        let signal = wait_for_wake(wake_read);
        // The bound on the act, on a thread of its own since the act may block.
        thread::spawn(move || {
            thread::sleep(LAST_ACT_LIMIT);
            end_as(signal);
        });
        act();
        end_as(signal);
    });
    let Ok(last_act_thread) = spawned else {
        return;
    };
    let _ = LAST_ACT_THREAD.set(last_act_thread.thread().id());
    LAST_ACT_WAKE.store(wake_write, Ordering::SeqCst);
}

fn wait_for_wake(wake_read: libc::c_int) -> libc::c_int {
    let mut signal = 0u8;
    loop {
        // SAFETY: a one-byte read into a byte on this stack.
        let read = unsafe { libc::read(wake_read, (&raw mut signal).cast(), 1) };
        if read == 1 {
            return libc::c_int::from(signal);
        }
        if read == 0 || std::io::Error::last_os_error().raw_os_error() != Some(libc::EINTR) {
            // Nothing can wake it any more, so the handler ends voxcmd itself.
            LAST_ACT_WAKE.store(-1, Ordering::SeqCst);
            loop {
                thread::park();
            }
        }
    }
}

/// Whether a stop's last act is under way on a thread other than this one. A session change made here now would land
/// after the act has ended the session, or before it in the lock's queue, so `SessionLock::take` holds this thread.
pub fn last_act_runs_elsewhere() -> bool {
    STOPPING.load(Ordering::SeqCst)
        && LAST_ACT_WAKE.load(Ordering::SeqCst) >= 0
        && LAST_ACT_THREAD.get() != Some(&thread::current().id())
}

/// Holds this thread until the last act ends voxcmd.
pub fn wait_for_last_act() -> ! {
    loop {
        thread::park();
    }
}

/// Lets the signal do what it would have done, so voxcmd still ends as the signal says. The last act's thread holds the
/// stop signals (`StopSignalsHeld`), so the one raised is let through on this thread first.
fn end_as(signal: libc::c_int) {
    // SAFETY: restoring the default action, unblocking and raising again are async-signal-safe.
    unsafe {
        libc::signal(signal, libc::SIG_DFL);
        let mut raised: libc::sigset_t = std::mem::zeroed();
        libc::sigemptyset(&raw mut raised);
        libc::sigaddset(&raw mut raised, signal);
        libc::pthread_sigmask(libc::SIG_UNBLOCK, &raw const raised, std::ptr::null_mut());
        libc::raise(signal);
    }
}

/// Ends every listed group and removes every listed file, then ends voxcmd as the signal says, after the last act
/// when there is one. Runs in the handler, or on the thread that held the signal. A second signal during
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
            // SAFETY: unlink and rmdir on NUL-terminated paths.
            unsafe {
                if let Some(inside) = &removal.inside {
                    for file in inside {
                        libc::unlink(file.as_ptr());
                    }
                    libc::rmdir(removal.path.as_ptr());
                } else {
                    libc::unlink(removal.path.as_ptr());
                }
            }
        }
    }
    if already_stopping {
        return;
    }
    if asks_terminated {
        kill_asks_after_grace();
    }
    let wake = LAST_ACT_WAKE.load(Ordering::SeqCst);
    if wake >= 0 {
        // Signal numbers fit a byte.
        let byte = signal as u8;
        // SAFETY: write is async-signal-safe; the last act's thread ends voxcmd once it has read this.
        if unsafe { libc::write(wake, (&raw const byte).cast(), 1) } == 1 {
            return;
        }
    }
    end_as(signal);
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
    fn a_command_run_discarding_output_leaves_its_children_no_pipe_to_hold_or_break() {
        let dir = tempfile::tempdir().unwrap();
        let (out_file, err_file) = (dir.path().join("out"), dir.path().join("err"));
        let script = format!(
            "(sleep 0.3; [ /dev/fd/1 -ef /dev/null ] && echo null > '{}'; [ /dev/fd/2 -ef /dev/null ] && echo null > '{}') & \
             echo hi; echo hi >&2",
            out_file.display(),
            err_file.display()
        );
        let started = Instant::now();
        let outcome = run_discarding_output_within(&mut sh(&script), Duration::from_secs(10)).unwrap();
        assert!(
            started.elapsed() < DRAIN_GRACE,
            "waited for the child: {:?}",
            started.elapsed()
        );
        assert_eq!(
            (outcome.code(), outcome.stdout.as_str(), outcome.stderr.as_str()),
            (Some(0), "", "")
        );
        for file in [out_file, err_file] {
            let deadline = Instant::now() + Duration::from_secs(5);
            while std::fs::read_to_string(&file).unwrap_or_default().is_empty() && Instant::now() < deadline {
                thread::sleep(Duration::from_millis(20));
            }
            assert_eq!(std::fs::read_to_string(&file).unwrap().trim(), "null");
        }
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

    #[test]
    fn a_deadline_without_output_kills_the_group_only_when_it_passes() {
        let dir = tempfile::tempdir().unwrap();
        let pid_file = dir.path().join("child.pid");
        // In time: the child it left behind lives on, and the call does not wait for it.
        let script = format!("sleep 3 & echo $! > '{}'; exit 4", pid_file.display());
        let started = Instant::now();
        let outcome = run_discarding_output_within(&mut sh(&script), Duration::from_secs(5)).unwrap();
        assert_eq!((outcome.code(), outcome.timed_out), (Some(4), false));
        assert!(started.elapsed() < Duration::from_secs(1), "{:?}", started.elapsed());
        let child: i32 = std::fs::read_to_string(&pid_file).unwrap().trim().parse().unwrap();
        assert!(
            !gone_within(child, Duration::from_millis(300)),
            "the leftover child {child} was killed"
        );
        // SAFETY: kill only signals the child this test started.
        unsafe { libc::kill(child, libc::SIGKILL) };
        // Past it: the command and what it started are killed.
        std::fs::remove_file(&pid_file).unwrap();
        let script = format!("sleep 30 & echo $! > '{}'; wait", pid_file.display());
        let outcome = run_discarding_output_within(&mut sh(&script), Duration::from_millis(300)).unwrap();
        assert!(outcome.timed_out);
        let child: i32 = std::fs::read_to_string(&pid_file).unwrap().trim().parse().unwrap();
        assert!(
            gone_within(child, Duration::from_secs(2)),
            "child {child} outlived the deadline"
        );
    }

    /// Runs the test at that path again in a process of its own with `VOXCMD_PROCESS_TEST_CHILD` set: a stop signal,
    /// and the stopping it starts, would end or poison every other test in this one.
    pub(crate) fn in_own_process(test: &str) -> Command {
        let mut command = Command::new(std::env::current_exe().unwrap());
        command
            .args(["--exact", test, "--test-threads=1"])
            .env("VOXCMD_PROCESS_TEST_CHILD", "1")
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        command
    }

    pub(crate) fn is_own_process() -> bool {
        std::env::var_os("VOXCMD_PROCESS_TEST_CHILD").is_some()
    }

    #[test]
    fn nothing_is_spawned_once_a_stop_has_begun() {
        if is_own_process() {
            STOPPING.store(true, Ordering::SeqCst);
            let refused = run_with_timeout(&mut sh("true"), Duration::from_secs(1))
                .is_err_and(|error| refused_while_stopping(&error));
            std::process::exit(i32::from(!refused));
        }
        assert!(
            in_own_process("process::tests::nothing_is_spawned_once_a_stop_has_begun")
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
        let status = in_own_process("process::tests::a_second_stop_signal_during_the_grace_does_not_add_one")
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
    fn a_stop_signal_while_the_last_act_is_set_up_waits_for_it() {
        let test = "process::tests::a_stop_signal_while_the_last_act_is_set_up_waits_for_it";
        if is_own_process() {
            let marker = std::env::var_os("VOXCMD_TEST_MARKER").unwrap();
            let held = StopSignalsHeld::new();
            stop_on_hangup_too();
            // To this thread: the test harness's own threads would take one sent to the process. Pending while held.
            // SAFETY: raise only sends a signal.
            unsafe { libc::raise(libc::SIGHUP) };
            run_on_stop(move || std::fs::write(marker, "ran").unwrap());
            drop(held);
            thread::sleep(Duration::from_secs(30));
            std::process::exit(0);
        }
        let dir = tempfile::tempdir().unwrap();
        let marker = dir.path().join("marker");
        let started = Instant::now();
        let status = in_own_process(test)
            .env("VOXCMD_TEST_MARKER", &marker)
            .status()
            .unwrap();
        assert_eq!(status.signal(), Some(libc::SIGHUP), "{status:?}");
        assert!(started.elapsed() < Duration::from_secs(4), "{:?}", started.elapsed());
        assert_eq!(std::fs::read_to_string(&marker).unwrap_or_default(), "ran");
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
    fn only_the_stop_s_own_refusal_counts_as_refused_while_stopping() {
        assert!(refused_while_stopping(&std::io::Error::other(RefusedWhileStopping)));
        assert!(!refused_while_stopping(&std::io::Error::other("voxcmd is stopping")));
        assert!(!refused_while_stopping(&std::io::Error::from_raw_os_error(
            libc::ENOENT
        )));
    }

    #[test]
    fn a_group_has_members_until_its_last_process_is_reaped() {
        let mut leader = sh("sleep 30").process_group(0).spawn().unwrap();
        let group = libc::pid_t::try_from(leader.id()).unwrap();
        assert!(group_has_members(group));
        leader.kill().unwrap();
        leader.wait().unwrap();
        assert!(!group_has_members(group));
    }

    /// Whether a stop signal would now signal the group.
    pub(crate) fn is_listed(group: libc::pid_t) -> bool {
        LIVE_GROUPS
            .iter()
            .any(|slot| slot.load(Ordering::Acquire).abs() == group)
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
