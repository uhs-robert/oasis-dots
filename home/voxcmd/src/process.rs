//! running a command with a deadline: its own process group, both pipes drained, the whole group killed on timeout
//!
//! The one place that spawns with a timeout. A hook is `bash -c` and may start children of its own; killing only bash
//! would leave them running (and holding the pipes open), so each command leads a process group of its own and a
//! timeout kills the group.
use std::io::Read;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

const POLL: Duration = Duration::from_millis(5);

/// How long, once the command has exited, its pipes get to deliver what is left. A child that outlived it may still
/// hold them open, and its output is cut off there. One deadline covers both pipes.
const DRAIN_GRACE: Duration = Duration::from_millis(200);

/// How long after the group was killed the readers get to hand over their last bytes.
const DRAIN_AFTER_KILL: Duration = Duration::from_millis(100);

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
    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .process_group(0);
    let mut child = command.spawn()?;
    let stdout = Drain::start(child.stdout.take());
    let stderr = Drain::start(child.stderr.take());
    let deadline = Instant::now() + timeout;
    let (status, timed_out) = loop {
        match child.try_wait() {
            Ok(Some(status)) => break (Some(status), false),
            Ok(None) => {}
            Err(error) => {
                kill_and_reap(&mut child);
                return Err(error);
            }
        }
        if Instant::now() >= deadline {
            kill_and_reap(&mut child);
            break (None, true);
        }
        thread::sleep(POLL);
    };
    if !timed_out {
        let grace_ends = Instant::now() + DRAIN_GRACE;
        wait_until(grace_ends, || stdout.finished() && stderr.finished());
        // The command is reaped, but a child of its group may live on; the group id stays taken while it does.
        kill_group(child.id());
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
