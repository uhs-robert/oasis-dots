//! `voxcmd internal watch <handler> <mode token> <private> <detector settings>`: the watcher a listen leaves behind. It
//! runs the auto-stop detector, follows voxtype's state until the recording is over, then routes the transcript or
//! answers the waiting ask with it (was `watch_recording`, `autostop_recording` and `release_recording_ownership`)
//!
//! A watcher ends however it ends without leaving its discard flag, its detector's threshold file, its claim on an
//! ask's recording owner file or the detector itself behind: on return by `Cleanup`, on SIGINT, SIGTERM or SIGHUP by
//! the stop handler in `process.rs` (which TERMs the detector's group and removes the listed files), and when it is
//! SIGKILLed the detector still dies with it (`die_with_parent`); only the two files are then left, as the bash EXIT
//! trap left them, and a later watcher that gets the same pid removes them before it starts. A session turn's watcher
//! that ends while it still owns the session ends the session too, on return and on a stop signal alike.
use super::listen::{Handler, PAUSE_CHECK_VOXCMD, inherited_owner_file};
use super::{time_scaled, voxtype_record, voxtype_state, voxtype_write_mark};
use crate::ask;
use crate::cli::ReplyArgs;
use crate::debug::debug;
use crate::exit::CliError;
use crate::paths;
use crate::process::{self, LiveGroup, RemovedOnSignal};
use crate::route;
use crate::session::{self, dictation};
use std::os::unix::process::ExitStatusExt;
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
pub(super) const VERDICT_SILENCE: i32 = 0;
pub(super) const VERDICT_NO_SPEECH: i32 = 3;
pub(super) const VERDICT_MAX_LENGTH: i32 = 5;

/// `internal watch` (alias `_watch`), positional as the bash entry point took them: the handler (`route`, `reply`,
/// `session_turn`), the session mode the recording is heard in (`-` for none), 1 when that mode is private (only
/// lengths are logged, nothing goes to the no-match log), the detector's `VAR=value` lines, and for a reply the
/// encoded `PickId` it answers.
pub fn run(args: &[String]) -> Result<(), CliError> {
    let handler = match args.first().map(String::as_str) {
        Some("route") => Handler::Route,
        Some("reply") => Handler::Reply,
        Some("session_turn") => Handler::SessionTurn,
        _ => {
            return Err(CliError::usage(
                "internal watch",
                "usage: route|reply|session_turn [mode token] [private 0|1] [detector settings] [pick id]",
            ));
        }
    };
    let heard_mode = args.get(1).map_or("", String::as_str);
    let heard_private = args.get(2).is_some_and(|private| private == "1");
    let detector_settings = args.get(3).map_or("", String::as_str);
    // A pin that is there but unreadable refuses the reply; only a missing one leaves it unpinned.
    let pinned = args
        .get(4)
        .map(|text| ask::PickId::parse(text).unwrap_or_else(ask::PickId::unreadable));
    let me = std::process::id();
    let stop_signals_held = process::StopSignalsHeld::new();
    process::stop_on_hangup_too();
    // Held until the handler is done: Stop Voice flags this watcher's discard flag to keep what the handler opens
    // from listening.
    let mut cleanup = Cleanup::new(handler == Handler::SessionTurn);
    drop(stop_signals_held);
    let session_mode = (handler == Handler::SessionTurn).then_some(heard_mode);
    let transcript = match watch_recording(&mut cleanup, detector_settings, session_mode) {
        Heard::Transcript(transcript) => transcript,
        // Autostop's no-speech cancel, or a recording cancelled: the mode is over.
        Heard::Discarded if handler == Handler::SessionTurn => {
            session::turn::silence(me, heard_mode);
            return Ok(());
        }
        Heard::Nothing if handler == Handler::SessionTurn => {
            session::turn::heard_nothing(me, heard_mode);
            return Ok(());
        }
        Heard::Discarded | Heard::Nothing => return Ok(()),
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
    let heard = route::runner::Heard {
        by_voice: true,
        private: heard_private,
        in_session_turn: handler == Handler::SessionTurn,
    };
    let exit_code = match handler {
        Handler::Route => route::runner::run_spoken(&transcript, &heard),
        Handler::Reply => i32::from(
            ask::reply::run_pinned(
                ReplyArgs {
                    dry_run: false,
                    phrase: vec![transcript],
                },
                pinned,
            )
            .is_err(),
        ),
        Handler::SessionTurn => route::runner::with_runner(&heard, |runner| {
            session::turn::session_turn(runner, &transcript, heard_mode, heard_private);
        })
        .map_or(1, |()| 0),
    };
    drop(cleanup);
    if exit_code == 0 {
        Ok(())
    } else {
        Err(CliError::quiet("internal watch"))
    }
}

/// How a recording ended, for its watcher.
enum Heard {
    Transcript(String),
    /// Discarded: auto-stop heard no speech, or Stop Voice or an answer by key cancelled it.
    Discarded,
    /// It ended with no transcript.
    Nothing,
}

/// Follows the recording to its end and returns its transcript, or how it ended without one. A session turn's
/// recording names the mode it is heard in (`session_mode`).
fn watch_recording(cleanup: &mut Cleanup, detector_settings: &str, session_mode: Option<&str>) -> Heard {
    let poll = time_scaled(POLL_SECS);
    cleanup.detector = Detector::start(detector_settings, &cleanup.discard_flag, session_mode);
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
        return Heard::Discarded;
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
        return Heard::Nothing;
    }
    let transcript = std::fs::read(paths::transcript())
        .map(|bytes| String::from_utf8_lossy(&bytes).trim_end_matches('\n').to_string())
        .unwrap_or_default();
    // Dictation must not outlive its turn on disk; the next listen starts from a fresh file anyway.
    let _ = std::fs::remove_file(paths::transcript());
    Heard::Transcript(transcript)
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
    /// A session turn's watcher: the session it still owns when it ends goes with it.
    ends_session: bool,
    _on_signal: Vec<RemovedOnSignal>,
}

impl Cleanup {
    /// Listed for the stop handler before any of the files exists, so no signal falls between the two. Files by this
    /// pid already there are an earlier watcher's that was SIGKILLed with the same pid, and a discard flag of its
    /// would drop what is said now.
    fn new(ends_session: bool) -> Self {
        let pid = std::process::id();
        if ends_session {
            process::run_on_stop(move || session::end_if_mine(UNEXPECTED_END, pid));
        }
        let discard_flag = paths::discard_flag(pid);
        let threshold_file = paths::threshold_file(pid);
        let _ = std::fs::remove_file(&discard_flag);
        let _ = std::fs::remove_file(&threshold_file);
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
            ends_session,
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
        if self.ends_session {
            session::end_if_mine(UNEXPECTED_END, std::process::id());
        }
    }
}

/// Why a session ends with the turn's watcher that still owned it.
const UNEXPECTED_END: &str = "the listener stopped unexpectedly";

/// voxcmd-autostop, which ends the recording once it hears speech and then a pause, or cancels it when nothing was
/// said. It exits by itself when the recording ends some other way; `stop` ends it first otherwise.
struct Detector {
    /// Emptied by the waiting thread once the group has no process left, so neither `stop` nor a stop signal reaches
    /// the group id after it may have been handed out again.
    group: Arc<Mutex<Option<DetectorGroup>>>,
    stopped: Arc<AtomicBool>,
}

/// The detector's process group, which it leads, and its listing for the stop handler, dropped together.
struct DetectorGroup {
    id: libc::pid_t,
    /// None once reaped. The group can outlive it: a child of the detector's (its `pw-record`) may not have exited
    /// yet, and is still the detector's to end.
    leader: Option<Child>,
    _listed: LiveGroup,
}

impl Detector {
    fn start(settings: &str, discard_flag: &Path, session_mode: Option<&str>) -> Option<Self> {
        let program = paths::autostop();
        if !ask::is_executable(&program) {
            return None;
        }
        let mut command = Command::new(program);
        let mut checks_pauses = false;
        for (name, value) in settings.lines().filter_map(|line| line.split_once('=')) {
            command.env(name, value);
            checks_pauses |= name == PAUSE_CHECK_VOXCMD;
        }
        // The room's threshold, for the chain detector of an ending that starts mid-speech (`chain_stop`).
        command.env(
            "VOXCMD_AUTOSTOP_THRESHOLD_FILE",
            paths::threshold_file(std::process::id()),
        );
        // The recording as `dictation::heard_in_locked` names it: this watcher is its owner.
        if checks_pauses && let Some(heard_mode) = session_mode {
            let frame_id = heard_mode.rsplit(':').next().unwrap_or_default();
            let me = std::process::id();
            let start = route::sequence_run::process_start_time(me).unwrap_or_default();
            command.env(
                "VOXCMD_AUTOSTOP_PAUSE_CHECK_RECORDING",
                format!("{frame_id}:{me}:{start}"),
            );
        }
        // Spawned on the main thread, which lives as long as the watcher.
        process::die_with_parent(&mut command);
        Self::spawn(&mut command, discard_flag, session_mode)
    }

    fn spawn(command: &mut Command, discard_flag: &Path, session_mode: Option<&str>) -> Option<Self> {
        let (leader, listed) = process::spawn_letting_clean_up(command).ok()?;
        let detector = Self {
            group: Arc::new(Mutex::new(Some(DetectorGroup {
                id: libc::pid_t::try_from(leader.id()).ok()?,
                leader: Some(leader),
                _listed: listed,
            }))),
            stopped: Arc::default(),
        };
        let (group, stopped, discard_flag, session_mode) = (
            Arc::clone(&detector.group),
            Arc::clone(&detector.stopped),
            discard_flag.to_path_buf(),
            session_mode.map(str::to_string),
        );
        thread::spawn(move || {
            if let Some(verdict) = wait_for_verdict(&group)
                && !stopped.load(Ordering::SeqCst)
            {
                act_on_verdict(verdict, &discard_flag, session_mode.as_deref());
            }
            unlist_once_empty(&group);
        });
        Some(detector)
    }

    /// TERMs the detector's group while any of it runs; its verdict is then ignored.
    fn stop(&self) {
        self.stopped.store(true, Ordering::SeqCst);
        let group = self.group.lock().expect("held briefly");
        if let Some(group) = group.as_ref() {
            // SAFETY: killpg only sends a signal; the group is the detector's own, never voxcmd's.
            unsafe { libc::killpg(group.id, libc::SIGTERM) };
        }
    }
}

const GROUP_POLL: Duration = Duration::from_millis(20);

/// The detector's exit code once it has exited, 128 + the signal when a signal ended it, as `wait` reports it.
fn wait_for_verdict(group: &Mutex<Option<DetectorGroup>>) -> Option<i32> {
    loop {
        {
            let mut held = group.lock().ok()?;
            let held = held.as_mut()?;
            if let Some(status) = held.leader.as_mut()?.try_wait().ok()? {
                held.leader = None;
                return status.code().or_else(|| status.signal().map(|signal| 128 + signal));
            }
        }
        thread::sleep(GROUP_POLL);
    }
}

/// Drops the group, and its listing, once its last process has gone. Checked under the lock `stop` takes, so `stop`
/// signals only a group that still has members. The stop handler takes no lock: it can reach the id for up to one poll
/// after the group emptied, too soon for the kernel to have handed it out again short of a pid wraparound.
fn unlist_once_empty(group: &Mutex<Option<DetectorGroup>>) {
    loop {
        {
            let Ok(mut held) = group.lock() else {
                return;
            };
            let Some(running) = held.as_ref() else {
                return;
            };
            if !process::group_has_members(running.id) {
                *held = None;
                return;
            }
        }
        thread::sleep(GROUP_POLL);
    }
}

fn act_on_verdict(verdict: i32, discard_flag: &Path, session_mode: Option<&str>) {
    // A voice key may have stopped the recording in the meantime.
    if voxtype_state() != "recording" {
        return;
    }
    // In a one-recording mode the verdict is how the recording ended, unless something else ended it first. Recorded
    // before the stop, so the watcher finds it once the transcript is in.
    let ending = match verdict {
        VERDICT_SILENCE => Some("pause"),
        VERDICT_NO_SPEECH => Some("idle"),
        VERDICT_MAX_LENGTH => Some("cap"),
        _ => None,
    };
    if let (Some(heard_mode), Some(by)) = (session_mode, ending) {
        dictation::watcher_record_ending("type", by, heard_mode, std::process::id());
        if voxtype_state() != "recording" {
            return;
        }
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

    /// Whether the detector's group is dropped, and so no longer listed for a stop signal, within 10 s.
    fn unlisted_within_10s(detector: &Detector, group: libc::pid_t) -> bool {
        for _ in 0..500 {
            if detector.group.lock().unwrap().is_none() {
                return !process::tests::is_listed(group);
            }
            thread::sleep(GROUP_POLL);
        }
        false
    }

    fn detector_of(script: &str) -> (Detector, libc::pid_t) {
        let dir = tempfile::tempdir().unwrap();
        let mut command = Command::new("sh");
        command.args(["-c", script]);
        let detector = Detector::spawn(&mut command, &dir.path().join("discard"), None).unwrap();
        let group = detector.group.lock().unwrap().as_ref().unwrap().id;
        (detector, group)
    }

    // A stop signal mid-route, long after the detector exited, must not reach its group id, which may have been
    // handed out again by then.
    #[test]
    fn a_reaped_detector_s_group_is_no_longer_signalled_on_stop() {
        let (detector, group) = detector_of("exit 4");
        assert!(unlisted_within_10s(&detector, group));
    }

    #[test]
    fn a_detector_s_group_stays_listed_while_a_child_of_it_runs() {
        let (detector, group) = detector_of("sleep 1 & exit 4");
        thread::sleep(Duration::from_millis(300));
        assert!(
            detector
                .group
                .lock()
                .unwrap()
                .as_ref()
                .is_some_and(|held| held.leader.is_none()),
            "the detector was not reaped, or its group was dropped with its child running"
        );
        assert!(process::tests::is_listed(group));
        assert!(unlisted_within_10s(&detector, group));
    }
}
