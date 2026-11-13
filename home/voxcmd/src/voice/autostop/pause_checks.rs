//! type mode's spoken endings. The wake listener misses "cortana exit" said in one breath, so every pause after speech
//! hands the last clip_secs of audio to `voxcmd _wake-confirm <clip> <recording> pause`, which ends the recording when
//! the words after the clip's last wake word are one of the mode's endings, and does nothing otherwise, or once that
//! recording is over.
//!
//! One check runs at a time; a pause during it keeps only the newest clip waiting. A check is detached (its own
//! session) and never killed: it may be what stops the recording, holding voxcmd's session lock as this detector exits,
//! and it bounds itself (`VOXCMD_WAKE_CONFIRM_TIMEOUT_SECS`). That is why this does not reuse the wake listener's
//! `confirm`, which kills its child on stop.
use super::detector::{FRAME_SECS, SpeechThenSilence};
use super::settings::Settings;
use super::state::RecordingState;
use crate::voice::capture::{private_audio_file, wav_bytes};
use crate::voice::signal;
use std::collections::VecDeque;
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

const CHECK_POLL: Duration = Duration::from_millis(50);

pub struct PauseChecks {
    recording: String,
    voxcmd: std::path::PathBuf,
    pause_secs: f64,
    wait_secs: f64,
    recent_frames: VecDeque<Vec<i16>>,
    recent_capacity: usize,
    trace: Box<dyn Fn(&str)>,
    last_quiet_secs: f64,
    running: Option<Child>,
    waiting_clip: Option<(f64, Vec<u8>)>,
}

impl PauseChecks {
    pub fn new(settings: &Settings, trace: Box<dyn Fn(&str)>) -> Result<Self, String> {
        let voxcmd = match settings.text("pause_check_voxcmd") {
            "" => crate::ask::this_binary(),
            named => named.into(),
        };
        Ok(Self {
            recording: settings.text("pause_check_recording").to_string(),
            voxcmd,
            pause_secs: settings.number("pause_check_secs")?,
            wait_secs: settings.number("pause_check_wait_secs")?,
            recent_frames: VecDeque::new(),
            // At least one frame: at zero the deque never evicts and the clip grows into the whole recording.
            recent_capacity: ((settings.number("pause_check_clip_secs")? / FRAME_SECS).round() as usize).max(1),
            trace,
            last_quiet_secs: 0.0,
            running: None,
            waiting_clip: None,
        })
    }

    pub fn enabled(&self) -> bool {
        !self.recording.is_empty()
    }

    /// Called with each frame once the detector has counted it.
    pub fn after_frame(&mut self, frame: &[i16], detector: &SpeechThenSilence) {
        self.queue_pause(frame, detector);
        self.start_waiting();
    }

    /// Keeps the frame for the clip and queues a check when it begins a pause. The frame that stops the recording
    /// gets this but no `start_waiting`, which the stop's wait does itself.
    pub fn queue_pause(&mut self, frame: &[i16], detector: &SpeechThenSilence) {
        if self.recent_frames.len() == self.recent_capacity {
            self.recent_frames.pop_front();
        }
        self.recent_frames.push_back(frame.to_vec());
        // The quiet only drops back under the pause length when speech is heard, so crossing it again is a new pause.
        let crossed = self.last_quiet_secs < self.pause_secs && self.pause_secs <= detector.quiet_secs;
        self.last_quiet_secs = detector.quiet_secs;
        if crossed && detector.speech_secs > 0.0 {
            self.waiting_clip = Some((detector.elapsed_secs, wav_bytes(&self.recent_frames)));
            if self.check_is_running() {
                (self.trace)(&format!(
                    "pause at {:.2}s waits for the check running",
                    detector.elapsed_secs
                ));
            }
        }
    }

    fn check_is_running(&mut self) -> bool {
        self.running
            .as_mut()
            .is_some_and(|child| matches!(child.try_wait(), Ok(None)))
    }

    fn pending(&mut self) -> bool {
        self.waiting_clip.is_some() || self.check_is_running()
    }

    /// Waits up to wait_secs (pause_check_wait_secs) for the checks still running or waiting. False when the recording
    /// ended meanwhile, as one does when a check hears "cortana cancel", so the pause must not stop it, or when a stop
    /// signal came.
    pub fn wait_for_pending_checks(&mut self, recording_state: Option<&mut RecordingState>) -> bool {
        let mut recording_state = recording_state;
        let deadline = Instant::now() + Duration::try_from_secs_f64(self.wait_secs).unwrap_or(Duration::ZERO);
        if self.pending() {
            (self.trace)("the stop waits for the pause checks");
        }
        while self.pending() && Instant::now() < deadline {
            if signal::requested() || recording_state.as_mut().is_some_and(|state| state.ended()) {
                return false;
            }
            signal::sleep(CHECK_POLL);
            self.start_waiting();
        }
        if self.pending() {
            (self.trace)(&format!(
                "pause checks still running after {}s, stopping anyway",
                general_float(self.wait_secs)
            ));
        }
        !(signal::requested() || recording_state.is_some_and(|state| state.ended()))
    }

    pub fn start_waiting(&mut self) {
        if self.check_is_running() {
            return;
        }
        self.running = None;
        let Some((at_secs, clip)) = self.waiting_clip.take() else {
            return;
        };
        (self.trace)(&format!("pause check at {at_secs:.2}s"));
        match self.spawn_check(&clip) {
            Ok(child) => self.running = Some(child),
            Err(error) => (self.trace)(&format!("pause check: cannot run {}: {error}", self.voxcmd.display())),
        }
    }

    fn spawn_check(&self, clip: &[u8]) -> std::io::Result<Child> {
        let audio = private_audio_file(clip)?;
        let mut command = Command::new(&self.voxcmd);
        command
            .args(["_wake-confirm", "/dev/stdin", &self.recording, "pause"])
            .stdin(Stdio::from(audio))
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            // The confirmation may start voxcmd's chain detector, which must not inherit this recording's settings.
            .env_remove("VOXCMD_AUTOSTOP_PAUSE_CHECK_RECORDING")
            .env_remove("VOXCMD_AUTOSTOP_THRESHOLD_FILE");
        // SAFETY: setsid is async-signal-safe and touches only the child. Its own session, so it outlives this
        // detector's process group, which the watcher kills.
        unsafe {
            command.pre_exec(|| {
                libc::setsid();
                Ok(())
            });
        }
        command.spawn()
    }
}

/// `{:g}`: "8" for a whole number, the shortest digits otherwise.
fn general_float(value: f64) -> String {
    value.to_string()
}
