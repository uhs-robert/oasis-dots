//! Reads the strips with tesseract, all at once, and ends the lot as soon as one fails.
//!
//! A strip that fails must fail the whole run: its missing words would read as "not on screen", or leave one of two
//! matches to be clicked without asking. Ending the others is a race with strips still being spawned, forked and
//! reaped, so the rules are:
//! - every process of every strip is spawned before any wait, so no stage is spawned after the kill ;
//! - each strip is a process group, killed whole, so a tesseract forked a moment before the kill dies too;
//! - the groups are remembered from the spawn rather than looked up when one fails;
//! - a strip that finished well leaves the set before anything is killed, since its pid may lead an unrelated group by
//!   then; the failed strip stays, as a process it forked may still run.
use super::capture::{Tools, command_of};
use super::strips::{self, Cut};
use crate::process::{self, LiveGroup};
use std::fs::File;
use std::path::Path;
use std::process::{Child, ExitStatus, Stdio};
use std::thread;
use std::time::{Duration, Instant};

const POLL: Duration = Duration::from_millis(5);
/// How long the killed strips get to exit before they are killed for certain.
const REAP_GRACE: Duration = Duration::from_secs(1);

/// The process groups of the strips that have not finished well.
pub struct LiveStrips {
    groups: Vec<libc::pid_t>,
}

impl LiveStrips {
    pub fn new(groups: Vec<libc::pid_t>) -> Self {
        Self { groups }
    }

    pub fn finished_well(&mut self, group: libc::pid_t) {
        self.groups.retain(|live| *live != group);
    }

    /// Signals every group still in the set, best effort: a group that is gone already is no error.
    pub fn end_the_rest(&self, mut kill: impl FnMut(libc::pid_t)) {
        for group in &self.groups {
            kill(*group);
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
pub struct OcrFailed;

struct Stage {
    child: Child,
    status: Option<ExitStatus>,
}

struct Strip {
    group: libc::pid_t,
    stages: Vec<Stage>,
    // Listed with the process module so that a stop signal kills the group; unlisted when the strip is dropped.
    _live: Vec<LiveGroup>,
    spawn_failed: bool,
}

enum State {
    Running,
    Done,
    Failed,
}

impl Strip {
    fn poll(&mut self) -> State {
        if self.spawn_failed {
            return State::Failed;
        }
        for stage in &mut self.stages {
            if stage.status.is_none() {
                stage.status = stage.child.try_wait().ok().flatten();
            }
            // Either stage failing fails the strip, as bash's pipefail does.
            if stage.status.is_some_and(|status| !status.success()) {
                return State::Failed;
            }
        }
        if self.stages.iter().all(|stage| stage.status.is_some()) {
            State::Done
        } else {
            State::Running
        }
    }
}

/// Starts the strip's processes: tesseract on the strip's file, or magick negating it into a tesseract that reads the
/// pipe. tesseract's text goes to a file of the work directory and its stderr nowhere.
fn spawn_strip(tools: &Tools, work: &Path, cut: &Cut, invert: bool, many: bool) -> Strip {
    let mut strip = Strip {
        group: 0,
        stages: Vec::new(),
        _live: Vec::new(),
        spawn_failed: false,
    };
    let file = strips::strip_file(work, cut);
    let Ok(text) = File::create(strips::strip_text_file(work, cut)) else {
        strip.spawn_failed = true;
        return strip;
    };
    let mut tesseract = command_of(&tools.tesseract);
    tesseract.stdout(text).stderr(Stdio::null());
    let mut negate = None;
    if invert {
        let mut command = command_of(&tools.magick);
        command.args(strips::negate_args(&file)).stdout(Stdio::piped());
        negate = Some(command);
        tesseract.args(strips::tesseract_args("-"));
    } else {
        tesseract.args(strips::tesseract_args(&file.to_string_lossy()));
    }
    // A single strip may use every core; several run one thread each.
    if many {
        tesseract.env("OMP_THREAD_LIMIT", "1");
    }
    tesseract.stdin(Stdio::null());
    let mut leader = None;
    if let Some(mut negate) = negate {
        if many {
            negate.env("OMP_THREAD_LIMIT", "1");
        }
        match process::spawn_killed_on_stop(&mut negate, None) {
            Ok((mut child, live)) => {
                leader = Some(child.id());
                strip.group = libc::pid_t::try_from(child.id()).unwrap_or(0);
                if let Some(pipe) = child.stdout.take() {
                    tesseract.stdin(Stdio::from(pipe));
                }
                strip.stages.push(Stage { child, status: None });
                strip._live.push(live);
            }
            Err(_) => {
                strip.spawn_failed = true;
                return strip;
            }
        }
    }
    match process::spawn_killed_on_stop(&mut tesseract, leader) {
        Ok((child, live)) => {
            if leader.is_none() {
                strip.group = libc::pid_t::try_from(child.id()).unwrap_or(0);
            }
            strip.stages.push(Stage { child, status: None });
            strip._live.push(live);
        }
        Err(_) => strip.spawn_failed = true,
    }
    strip
}

/// SIGTERM to a strip's group. Never pid 0 or 1, and never voxcmd's own group.
fn term_group(group: libc::pid_t) {
    // SAFETY: getpgrp has no preconditions.
    let own_group = unsafe { libc::getpgrp() };
    if group > 1 && group != own_group {
        // SAFETY: killpg only sends a signal; a group that is gone is an ignored ESRCH.
        unsafe { libc::killpg(group, libc::SIGTERM) };
    }
}

fn kill_group(group: libc::pid_t) {
    if group > 1 {
        // SAFETY: as in `term_group`; the group here was spawned by this module.
        unsafe { libc::killpg(group, libc::SIGKILL) };
    }
}

/// Waits for the stages of the strips that were signalled, so none is left a zombie or running.
fn reap(strips: &mut [Strip]) {
    let deadline = Instant::now() + REAP_GRACE;
    loop {
        let mut running = false;
        for stage in strips.iter_mut().flat_map(|strip| strip.stages.iter_mut()) {
            if stage.status.is_none() {
                stage.status = stage.child.try_wait().ok().flatten();
                running |= stage.status.is_none();
            }
        }
        if !running {
            return;
        }
        if Instant::now() >= deadline {
            break;
        }
        thread::sleep(POLL);
    }
    for strip in strips.iter() {
        kill_group(strip.group);
    }
    for stage in strips.iter_mut().flat_map(|strip| strip.stages.iter_mut()) {
        if stage.status.is_none() {
            let _ = stage.child.wait();
        }
    }
}

/// Reads every strip into its text file in `work`. On the first failure the other strips are signalled and reaped
/// before this returns.
pub fn read_strips(tools: &Tools, work: &Path, cuts: &[Cut], invert: bool) -> Result<(), OcrFailed> {
    let many = cuts.len() > 1;
    let mut running: Vec<Strip> = cuts
        .iter()
        .map(|cut| spawn_strip(tools, work, cut, invert, many))
        .collect();
    let mut live = LiveStrips::new(running.iter().map(|strip| strip.group).collect());
    loop {
        let mut failed = false;
        running.retain_mut(|strip| match strip.poll() {
            State::Done => {
                live.finished_well(strip.group);
                false
            }
            State::Failed => {
                failed = true;
                true
            }
            State::Running => true,
        });
        if failed {
            live.end_the_rest(term_group);
            reap(&mut running);
            return Err(OcrFailed);
        }
        if running.is_empty() {
            return Ok(());
        }
        thread::sleep(POLL);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_strips_that_have_not_finished_well_are_signalled() {
        let mut live = LiveStrips::new(vec![100, 200, 300]);
        live.finished_well(200);
        let mut signalled = Vec::new();
        live.end_the_rest(|group| signalled.push(group));
        assert_eq!(signalled, [100, 300]);
    }

    #[test]
    fn a_failed_strip_stays_in_the_set() {
        let live = LiveStrips::new(vec![100, 200]);
        let mut signalled = Vec::new();
        live.end_the_rest(|group| signalled.push(group));
        assert_eq!(signalled, [100, 200]);
    }
}
