//! running a command with a deadline: its own process group, both pipes drained, the whole group killed on timeout
//!
//! The one place that spawns with a timeout. A hook is `bash -c` and may start children of its own; killing only bash
//! would leave them running (and holding the pipes open), so each command leads a process group of its own and a
//! timeout kills the group.
use std::io::Read;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::process::{Command, ExitStatus, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

const POLL: Duration = Duration::from_millis(5);

/// How long to wait for the pipes to close after the command exited. A child that outlived it may still hold them.
const DRAIN_GRACE: Duration = Duration::from_millis(200);

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

/// Runs the command with no stdin and both outputs captured. After `timeout` the command's process group is killed.
pub fn run_with_timeout(command: &mut Command, timeout: Duration) -> std::io::Result<Outcome> {
    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .process_group(0);
    let mut child = command.spawn()?;
    let stdout = drain(child.stdout.take());
    let stderr = drain(child.stderr.take());
    let deadline = Instant::now() + timeout;
    let (status, timed_out) = loop {
        if let Some(status) = child.try_wait()? {
            break (Some(status), false);
        }
        if Instant::now() >= deadline {
            kill_group(child.id());
            // Reaped so no zombie is left; the group is gone, so this does not wait long.
            let _ = child.wait();
            break (None, true);
        }
        thread::sleep(POLL);
    };
    Ok(Outcome {
        status,
        stdout: collect(&stdout),
        stderr: collect(&stderr),
        timed_out,
    })
}

/// Reads a pipe to its end on a thread of its own, so that a full pipe never blocks the command.
fn drain(pipe: Option<impl Read + Send + 'static>) -> mpsc::Receiver<Vec<u8>> {
    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || {
        let mut bytes = Vec::new();
        if let Some(mut pipe) = pipe {
            let _ = pipe.read_to_end(&mut bytes);
        }
        let _ = sender.send(bytes);
    });
    receiver
}

fn collect(receiver: &mpsc::Receiver<Vec<u8>>) -> String {
    let bytes = receiver.recv_timeout(DRAIN_GRACE).unwrap_or_default();
    String::from_utf8_lossy(&bytes).into_owned()
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
    fn a_child_holding_the_pipes_does_not_hold_up_a_command_that_exited() {
        let started = Instant::now();
        let outcome = run_with_timeout(&mut sh("sleep 3 >/dev/null 2>&1 & echo done"), Duration::from_secs(5)).unwrap();
        assert_eq!(outcome.code(), Some(0));
        assert_eq!(outcome.stdout, "done\n");
        assert!(started.elapsed() < Duration::from_secs(3));
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
