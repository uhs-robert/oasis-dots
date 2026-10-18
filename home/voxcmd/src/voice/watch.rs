//! `voxcmd internal watch <handler> <mode token> <private> <detector settings>`: the watcher a listen leaves behind. It
//! runs the auto-stop detector, follows voxtype's state until the recording is over, then routes the transcript or
//! answers the waiting ask with it (was `watch_recording`, `autostop_recording` and `release_recording_ownership`)
//!
//! A watcher ends however it ends without leaving its discard flag, its detector's threshold file, its claim on an
//! ask's recording owner file or the detector itself behind: on return by `Cleanup`, on SIGINT or SIGTERM by the stop
//! handler in `process.rs` (which TERMs the detector's group and removes the listed files), and when it is SIGKILLed
//! the detector still dies with it (`die_with_parent`); only the two files are then left, as the bash EXIT trap left
//! them. A session turn's watcher (`session_turn`) is the bash voxcmd's until voxcmd-port 2.4c.
use super::listen::{Handler, inherited_owner_file};
use super::{time_scaled, voxtype_record, voxtype_state, voxtype_write_mark};
use crate::ask;
use crate::cli::ReplyArgs;
use crate::debug::debug;
use crate::exit::CliError;
use crate::paths;
use crate::process::{self, LiveGroup, RemovedOnSignal};
use crate::route;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

/// Polls 0.2 s apart; recording plus transcription can outlast voxtype's `max_duration_secs`, and 3000 polls (10
/// minutes) cover both.
const POLL_SECS: f64 = 0.2;
const MAX_POLLS: u32 = 3000;
/// How long a recording that never shows as started is waited for.
const START_GRACE_POLLS: u32 = 50;
/// voxtype may write the transcript a moment after it reports idle.
const TRANSCRIPT_GRACE_POLLS: u32 = 10;

/// voxcmd-autostop's `VERDICT_*` exit codes; any other exit leaves the recording alone.
const VERDICT_SILENCE: i32 = 0;
const VERDICT_NO_SPEECH: i32 = 3;
const VERDICT_MAX_LENGTH: i32 = 5;

/// `internal watch` (alias `_watch`), positional as the bash entry point took them: the handler (`route`, `reply`;
/// `session_turn` goes to the bash voxcmd), the session mode the recording is heard in, 1 when that mode is private
/// (only lengths are logged, nothing goes to the no-match log), and the detector's `VAR=value` lines.
pub fn run(args: &[String]) -> Result<(), CliError> {
    let handler = match args.first().map(String::as_str) {
        Some("route") => Handler::Route,
        Some("reply") => Handler::Reply,
        Some("session_turn") => {
            let error = Command::new(paths::legacy_bin()).arg("_watch").args(args).exec();
            return Err(CliError::failed(
                "internal watch",
                format!("cannot run the bash watcher: {error}"),
            ));
        }
        _ => {
            return Err(CliError::usage(
                "internal watch",
                "usage: route|reply|session_turn [mode token] [private 0|1] [detector settings]",
            ));
        }
    };
    let heard_private = args.get(2).is_some_and(|private| private == "1");
    let detector_settings = args.get(3).map_or("", String::as_str);
    // Held until the handler is done: Stop Voice flags this watcher's discard flag to keep what the handler opens
    // from listening.
    let mut cleanup = Cleanup::new();
    let Some(transcript) = watch_recording(&mut cleanup, detector_settings) else {
        return Ok(());
    };
    if heard_private {
        debug(&format!(
            "watch: a transcript of {} characters goes to {}",
            transcript.chars().count(),
            handler.name()
        ));
    } else {
        debug(&format!(
            "watch: transcript \"{transcript}\" goes to {}",
            handler.name()
        ));
    }
    let exit_code = match handler {
        Handler::Route => route::runner::run_spoken(&transcript, heard_private),
        Handler::Reply => i32::from(
            ask::reply::run(ReplyArgs {
                dry_run: false,
                phrase: vec![transcript],
            })
            .is_err(),
        ),
    };
    drop(cleanup);
    if exit_code == 0 {
        Ok(())
    } else {
        Err(CliError::quiet("internal watch"))
    }
}

/// Follows the recording to its end and returns its transcript; none when it was discarded or nothing was said.
fn watch_recording(cleanup: &mut Cleanup, detector_settings: &str) -> Option<String> {
    let poll = time_scaled(POLL_SECS);
    cleanup.detector = Detector::start(detector_settings, &cleanup.discard_flag);
    if let Some(owner_file) = &cleanup.owner_file {
        // listen starts a watcher only for a recording it started from idle, so the recording is this one's from the
        // start. The ask may be gone already, its directory with it.
        let _ = std::fs::write(owner_file, format!("{}\n", std::process::id()));
    }
    let mut recording_seen = false;
    let mut last_state = String::new();
    let mut last_mark = None;
    let mut cancel_sent = false;
    for polls in 1..=MAX_POLLS {
        let mark = voxtype_write_mark();
        let state = voxtype_state();
        // voxtype truncates the file before writing the new state.
        if state.is_empty() {
            thread::sleep(poll);
            continue;
        }
        if state != last_state {
            debug(&format!("watch: voxtype {state}"));
        }
        // Ended as surely as by an idle, and the recording now running is someone else's.
        if recording_seen && ended_unseen(&last_state, last_mark, &state, mark) {
            debug("watch: voxtype went idle and started another recording between polls");
            break;
        }
        last_state.clone_from(&state);
        last_mark = mark;
        if state != "idle" {
            recording_seen = true;
            // Transcribing: the microphone is no longer needed.
            if state != "recording" {
                cleanup.stop_detector();
            }
            // Checked against a fresh mark so the cancel never reaches a recording this poll has not seen.
            if !cancel_sent && cleanup.discard_flag.exists() && voxtype_write_mark() == mark {
                debug(&format!("watch: discarded while voxtype is {state}, cancelling"));
                cancel_sent = true;
                voxtype_record("cancel", &[]);
            }
        } else if recording_seen || polls > START_GRACE_POLLS {
            break;
        }
        thread::sleep(poll);
    }
    cleanup.release_recording_ownership();
    cleanup.stop_detector();
    if cleanup.discard_flag.exists() {
        debug("watch: recording discarded");
        return None;
    }
    let transcript_written = || std::fs::metadata(paths::transcript()).is_ok_and(|meta| meta.len() > 0);
    for _ in 0..TRANSCRIPT_GRACE_POLLS {
        if transcript_written() {
            break;
        }
        thread::sleep(poll);
    }
    // Checked again: a key can answer the confirm this reply was for while voxtype finishes writing it.
    if !transcript_written() || cleanup.discard_flag.exists() {
        debug("watch: no transcript");
        return None;
    }
    let transcript = std::fs::read(paths::transcript())
        .map(|bytes| String::from_utf8_lossy(&bytes).trim_end_matches('\n').to_string())
        .unwrap_or_default();
    // Dictation must not outlive its turn on disk; the next listen starts from a fresh file anyway.
    let _ = std::fs::remove_file(paths::transcript());
    Some(transcript)
}

/// A watcher polls, so it can miss voxtype going idle when a dictation starts within one poll. That shows as a new
/// write with the same state, or as recording after transcribing, since voxtype passes through idle for either.
fn ended_unseen(last_state: &str, last_mark: Option<(i64, i64)>, state: &str, mark: Option<(i64, i64)>) -> bool {
    mark != last_mark && (state == last_state || (last_state == "transcribing" && state == "recording"))
}

/// What a watcher leaves behind it to undo, however it ends.
struct Cleanup {
    discard_flag: PathBuf,
    threshold_file: PathBuf,
    /// An ask's recording owner file, which holds this watcher's pid while the recording is its.
    owner_file: Option<PathBuf>,
    detector: Option<Detector>,
    _on_signal: Vec<RemovedOnSignal>,
}

impl Cleanup {
    /// Listed for the stop handler before any of the files exists, so no signal falls between the two.
    fn new() -> Self {
        let pid = std::process::id();
        let discard_flag = paths::discard_flag(pid);
        let threshold_file = paths::threshold_file(pid);
        let owner_file = inherited_owner_file();
        let mut on_signal = vec![
            RemovedOnSignal::new(&discard_flag),
            RemovedOnSignal::new(&threshold_file),
        ];
        if let Some(owner_file) = &owner_file {
            on_signal.push(RemovedOnSignal::if_holding(owner_file, &format!("{pid}\n")));
        }
        Self {
            discard_flag,
            threshold_file,
            owner_file,
            detector: None,
            _on_signal: on_signal,
        }
    }

    fn stop_detector(&mut self) {
        if let Some(detector) = &self.detector {
            detector.stop();
        }
    }

    /// Once voxtype is idle the recording is over, and anything it does next belongs to someone else.
    fn release_recording_ownership(&self) {
        let Some(owner_file) = &self.owner_file else {
            return;
        };
        let holds_this_watcher = std::fs::read_to_string(owner_file)
            .is_ok_and(|held| held.trim_end_matches('\n') == std::process::id().to_string());
        if holds_this_watcher {
            let _ = std::fs::remove_file(owner_file);
        }
    }
}

impl Drop for Cleanup {
    fn drop(&mut self) {
        self.stop_detector();
        let _ = std::fs::remove_file(&self.discard_flag);
        let _ = std::fs::remove_file(&self.threshold_file);
        self.release_recording_ownership();
    }
}

/// voxcmd-autostop, which ends the recording once it hears speech and then a pause, or cancels it when nothing was
/// said. It exits by itself when the recording ends some other way; `stop` ends it first otherwise.
struct Detector {
    /// Taken by the waiting thread once the detector has exited, so a stop never signals a reused pid.
    child: Arc<Mutex<Option<Child>>>,
    stopped: Arc<AtomicBool>,
    _listed: LiveGroup,
}

impl Detector {
    fn start(settings: &str, discard_flag: &Path) -> Option<Self> {
        let program = paths::autostop();
        if !ask::is_executable(&program) {
            return None;
        }
        let mut command = Command::new(program);
        for (name, value) in settings.lines().filter_map(|line| line.split_once('=')) {
            command.env(name, value);
        }
        // The room's threshold, for the chain detector of an ending that starts mid-speech (voxcmd-port 2.4d).
        command.env(
            "VOXCMD_AUTOSTOP_THRESHOLD_FILE",
            paths::threshold_file(std::process::id()),
        );
        // Spawned on the main thread, which lives as long as the watcher.
        process::die_with_parent(&mut command);
        let (child, listed) = process::spawn_letting_clean_up(&mut command).ok()?;
        let detector = Self {
            child: Arc::new(Mutex::new(Some(child))),
            stopped: Arc::default(),
            _listed: listed,
        };
        let (child, stopped, discard_flag) = (
            Arc::clone(&detector.child),
            Arc::clone(&detector.stopped),
            discard_flag.to_path_buf(),
        );
        thread::spawn(move || {
            let Some(verdict) = wait_for_verdict(&child) else {
                return;
            };
            if !stopped.load(Ordering::SeqCst) {
                act_on_verdict(verdict, &discard_flag);
            }
        });
        Some(detector)
    }

    /// TERMs the detector's group (it leads one) unless it has exited; its verdict is then ignored.
    fn stop(&self) {
        self.stopped.store(true, Ordering::SeqCst);
        let child = self.child.lock().expect("held briefly");
        if let Some(group) = child.as_ref().and_then(|child| libc::pid_t::try_from(child.id()).ok()) {
            // SAFETY: killpg only sends a signal; the group is the detector's own, never voxcmd's.
            unsafe { libc::killpg(group, libc::SIGTERM) };
        }
    }
}

/// The detector's exit code once it has exited, 128 + the signal when a signal ended it, as `wait` reports it.
fn wait_for_verdict(child: &Mutex<Option<Child>>) -> Option<i32> {
    loop {
        {
            let mut held = child.lock().ok()?;
            let status = held.as_mut()?.try_wait().ok()?;
            if let Some(status) = status {
                held.take();
                return status.code().or_else(|| status.signal().map(|signal| 128 + signal));
            }
        }
        thread::sleep(Duration::from_millis(20));
    }
}

fn act_on_verdict(verdict: i32, discard_flag: &Path) {
    // A voice key may have stopped the recording in the meantime.
    if voxtype_state() != "recording" {
        return;
    }
    match verdict {
        VERDICT_SILENCE => {
            debug("autostop: speech then quiet, stopping");
            voxtype_record("stop", &[]);
        }
        VERDICT_MAX_LENGTH => {
            debug("autostop: the recording reached its length limit, stopping");
            voxtype_record("stop", &[]);
        }
        VERDICT_NO_SPEECH => {
            debug("autostop: no speech, cancelling");
            let _ = std::fs::OpenOptions::new().create(true).append(true).open(discard_flag);
            voxtype_record("cancel", &[]);
        }
        other => debug(&format!("autostop: verdict {other}, recording left alone")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const AT_1: Option<(i64, i64)> = Some((1, 0));
    const AT_2: Option<(i64, i64)> = Some((2, 0));

    #[test]
    fn a_recording_that_ended_between_polls_shows_as_a_new_write() {
        assert!(ended_unseen("recording", AT_1, "recording", AT_2));
        assert!(ended_unseen("transcribing", AT_1, "recording", AT_2));
        // Nothing was written since: the same recording.
        assert!(!ended_unseen("recording", AT_1, "recording", AT_1));
        // The ordinary transitions.
        assert!(!ended_unseen("recording", AT_1, "transcribing", AT_2));
        assert!(!ended_unseen("transcribing", AT_1, "idle", AT_2));
    }
}
