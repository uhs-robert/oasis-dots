//! speech, then a pause: fed 30 ms frames, it reports a verdict once one is reached
//!
//! Time is counted in audio frames, not on the clock, and the float sums are accumulated frame by frame, so a verdict
//! lands on the same frame as the Python detector's did (the parity runs in `.logs` hold the goldens).
use super::settings::Settings;
use std::collections::VecDeque;

/// The detector's verdicts; `code` is the exit code the watcher and the chain's stopper read, the only protocol
/// between them (the same numbers as `watch::VERDICT_*`, which a test holds equal).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Verdict {
    /// Speech, then silence_secs of quiet: stop the recording.
    Silence,
    /// No speech within no_speech_secs: cancel it.
    NoSpeech,
    /// The recording ended some other way, the audio ended, a signal came, or auto-stop is off.
    NothingToDo,
    /// max_secs of recording with speech in it: stop the recording, which hit its length limit.
    MaxLength,
    /// An error: pw-record missing, a bad setting.
    Error,
}

impl Verdict {
    pub fn code(self) -> u8 {
        match self {
            Self::Silence => 0,
            Self::NoSpeech => 3,
            Self::NothingToDo => 4,
            Self::MaxLength => 5,
            Self::Error => 1,
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::Silence => "speech then quiet",
            Self::NoSpeech => "no speech",
            Self::NothingToDo | Self::Error => "ended elsewhere",
            Self::MaxLength => "length limit",
        }
    }
}

pub const FRAME_SAMPLES: usize = 480;
pub const FRAME_SECS: f64 = 0.03;

// With threshold_db = auto, speech is margin_db above the room: a low percentile of the last ROOM_WINDOW_SECS, first
// measured over CALIBRATION_SECS. Following the room this way keeps a fan or music from counting as speech forever,
// and speech already under way when the recording starts still has quieter gaps between words.
const CALIBRATION_SECS: f64 = 0.3;
const ROOM_WINDOW_SECS: f64 = 2.0;
const ROOM_PERCENTILE: f64 = 0.1;
// A quiet laptop mic still picks up clicks and rustle above this; a voice close to it is well over.
const MIN_AUTO_THRESHOLD_DB: f64 = -45.0;
// pw-record's first buffers, and some mics between sounds, are digital silence, which says nothing about the room.
const DIGITAL_SILENCE_DB: f64 = -90.0;
// Loud frames count as speech only in runs this long: a syllable lasts longer than a key click or a tap on the desk.
const MIN_SPEECH_RUN_FRAMES: usize = 3;

pub fn frame_level_db(frame: &[i16]) -> f64 {
    let sum: f64 = frame.iter().map(|&sample| f64::from(sample) * f64::from(sample)).sum();
    let rms = (sum / frame.len() as f64).sqrt();
    20.0 * (rms.max(1.0) / 32768.0).log10()
}

/// A float as Python's `repr` prints it, for the trace lines the suites grep ("0.0", not "0").
fn py_float(value: f64) -> String {
    if value.is_finite() && value.fract() == 0.0 {
        format!("{value:.1}")
    } else {
        value.to_string()
    }
}

/// Loud frames long enough to count as speech, kept for the debug trace.
struct SpeechRun {
    start_secs: f64,
    levels: Vec<f64>,
    threshold_db: f64,
}

impl SpeechRun {
    fn describe(&self) -> String {
        let mean = self.levels.iter().sum::<f64>() / self.levels.len() as f64;
        let peak = self.levels.iter().copied().fold(f64::MIN, f64::max);
        format!(
            "speech run {:.2}s +{:.2}s: mean {mean:.1} peak {peak:.1} threshold {:.1} dBFS",
            self.start_secs,
            self.levels.len() as f64 * FRAME_SECS,
            self.threshold_db
        )
    }
}

pub struct SpeechThenSilence {
    silence_secs: f64,
    min_speech_secs: f64,
    no_speech_secs: f64,
    max_secs: f64,
    fixed_threshold_db: Option<f64>,
    margin_db: f64,
    threshold_file: String,
    published_threshold_db: Option<f64>,
    log: Box<dyn Fn(&str)>,
    trace: Box<dyn Fn(&str)>,
    pub elapsed_secs: f64,
    room_levels: VecDeque<f64>,
    room_capacity: usize,
    /// Every level heard, rescored against each new threshold until speech is heard, and again before a pause ends
    /// the recording. A recording is at most voxtype's max_duration_secs.
    levels: Vec<f64>,
    calibrated: bool,
    pub speech_secs: f64,
    loud_run_frames: usize,
    pub quiet_secs: f64,
    speech_runs: Vec<SpeechRun>,
}

impl SpeechThenSilence {
    pub fn new(settings: &Settings, log: Box<dyn Fn(&str)>, trace: Box<dyn Fn(&str)>) -> Result<Self, String> {
        let fixed_threshold_db = match settings.text("threshold_db") {
            "auto" => None,
            _ => Some(settings.number("threshold_db")?),
        };
        let mut detector = Self {
            silence_secs: settings.number("silence_secs")?,
            min_speech_secs: settings.number("min_speech_secs")?,
            no_speech_secs: settings.number("no_speech_secs")?,
            max_secs: settings.number("max_secs")?,
            fixed_threshold_db,
            margin_db: settings.number("margin_db")?,
            threshold_file: settings.text("threshold_file").to_string(),
            published_threshold_db: None,
            log,
            trace,
            elapsed_secs: 0.0,
            room_levels: VecDeque::new(),
            // Python's round(): 66.67 is 67.
            room_capacity: (ROOM_WINDOW_SECS / FRAME_SECS).round() as usize,
            levels: Vec::new(),
            calibrated: false,
            speech_secs: 0.0,
            loud_run_frames: 0,
            quiet_secs: 0.0,
            speech_runs: Vec::new(),
        };
        detector.clear_speech();
        Ok(detector)
    }

    fn clear_speech(&mut self) {
        self.speech_secs = 0.0;
        self.loud_run_frames = 0;
        self.quiet_secs = 0.0;
        self.speech_runs.clear();
    }

    fn room_db(&self) -> f64 {
        let mut sorted: Vec<f64> = self.room_levels.iter().copied().collect();
        sorted.sort_by(f64::total_cmp);
        sorted[(self.room_levels.len() as f64 * ROOM_PERCENTILE) as usize]
    }

    fn threshold_db(&self) -> f64 {
        if let Some(fixed) = self.fixed_threshold_db {
            return fixed;
        }
        if self.room_levels.is_empty() {
            return MIN_AUTO_THRESHOLD_DB;
        }
        (self.room_db() + self.margin_db).max(MIN_AUTO_THRESHOLD_DB)
    }

    /// Writes the auto threshold to threshold_file, for a detector that starts mid-speech. Only a threshold from a
    /// stretch of quiet as long as the room window counts, so the voice cannot raise it: the first reading, then each
    /// one that follows ROOM_WINDOW_SECS of quiet and has moved by a dB or more, which follows a room that was
    /// quieter at the start (a fan) up to its real level.
    ///
    /// Written to `<file>.new` and renamed, so the chain's stopper reading it never sees half a number.
    fn publish_threshold(&mut self, threshold_db: f64) {
        if self.threshold_file.is_empty() || self.fixed_threshold_db.is_some() {
            return;
        }
        let published = self.published_threshold_db;
        if let Some(published) = published
            && (self.quiet_secs < ROOM_WINDOW_SECS || (threshold_db - published).abs() < 1.0)
        {
            return;
        }
        self.published_threshold_db = Some(threshold_db);
        let temporary = format!("{}.new", self.threshold_file);
        let written = std::fs::write(&temporary, format!("{threshold_db:.1}\n"))
            .and_then(|()| std::fs::rename(&temporary, &self.threshold_file));
        if written.is_err() {
            self.threshold_file.clear();
        }
    }

    /// Past no_speech_secs any speech run will do: a short word ("yes", "cancel") is still an answer, and voxtype's
    /// own voice detection drops a recording that held no speech before the transcriber can make words of it.
    fn speech_heard(&self) -> bool {
        if self.elapsed_secs >= self.no_speech_secs {
            return self.speech_secs > 0.0;
        }
        self.speech_secs >= self.min_speech_secs
    }

    fn count_frame(&mut self, frame_index: usize, threshold_db: f64) {
        if self.levels[frame_index] >= threshold_db {
            self.loud_run_frames += 1;
        } else {
            self.loud_run_frames = 0;
        }
        // A run counts from its first frame once it is long enough.
        if self.loud_run_frames == MIN_SPEECH_RUN_FRAMES {
            self.speech_secs += MIN_SPEECH_RUN_FRAMES as f64 * FRAME_SECS;
            let run_start = frame_index + 1 - MIN_SPEECH_RUN_FRAMES;
            self.speech_runs.push(SpeechRun {
                start_secs: run_start as f64 * FRAME_SECS,
                levels: self.levels[run_start..=frame_index].to_vec(),
                threshold_db,
            });
        } else if self.loud_run_frames > MIN_SPEECH_RUN_FRAMES {
            self.speech_secs += FRAME_SECS;
            let level = self.levels[frame_index];
            self.speech_runs.last_mut().expect("a run is open").levels.push(level);
        }
        if self.loud_run_frames >= MIN_SPEECH_RUN_FRAMES {
            self.quiet_secs = 0.0;
        } else {
            self.quiet_secs += FRAME_SECS;
        }
    }

    /// Scores every frame again against the room as it is now known. A word said as the recording starts is first
    /// taken for the room, which puts the threshold above it; once quieter frames show the real room, this counts
    /// that word, so a lone "yes" is not lost. The other way round, a microphone's first fraction of a second is
    /// often quieter than the room, so a steady fan counts as speech until that start leaves the room window and the
    /// same fan reads as a pause; scored again, the fan is no speech at all.
    fn rescore(&mut self, threshold_db: f64) {
        self.clear_speech();
        for frame_index in 0..self.levels.len() {
            self.count_frame(frame_index, threshold_db);
        }
    }

    /// Checks a pause against the room as it is now known before it ends the recording.
    fn pause_follows_speech(&mut self, threshold_db: f64) -> bool {
        let counted_secs = self.speech_secs;
        let counted_runs = std::mem::take(&mut self.speech_runs);
        self.rescore(threshold_db);
        if self.speech_heard() && self.quiet_secs >= self.silence_secs {
            return true;
        }
        for run in &counted_runs {
            (self.trace)(&run.describe());
        }
        (self.trace)(&format!(
            "{counted_secs:.2}s of speech is {:.2}s against the room now (threshold {threshold_db:.1} dBFS): noise, listening on",
            self.speech_secs
        ));
        false
    }

    pub fn trace_summary(&self, verdict: Verdict) {
        for run in &self.speech_runs {
            (self.trace)(&run.describe());
        }
        let room = if self.room_levels.is_empty() {
            String::new()
        } else {
            format!("room {:.1}, ", self.room_db())
        };
        (self.trace)(&format!(
            "verdict {} at {:.2}s: {room}threshold {:.1} dBFS, speech {:.2}s",
            verdict.name(),
            self.elapsed_secs,
            self.threshold_db(),
            self.speech_secs
        ));
    }

    pub fn feed(&mut self, frame: &[i16]) -> Option<Verdict> {
        let level_db = frame_level_db(frame);
        self.levels.push(level_db);
        self.elapsed_secs += FRAME_SECS;
        if level_db > DIGITAL_SILENCE_DB {
            if self.room_levels.len() == self.room_capacity {
                self.room_levels.pop_front();
            }
            self.room_levels.push_back(level_db);
        }
        if self.fixed_threshold_db.is_none() && self.elapsed_secs < CALIBRATION_SECS {
            return None;
        }
        let threshold_db = self.threshold_db();
        if !self.calibrated {
            self.calibrated = true;
            let room = if self.room_levels.is_empty() {
                String::new()
            } else {
                format!("room {:.1} dBFS, ", self.room_db())
            };
            (self.trace)(&format!("calibrated: {room}threshold {threshold_db:.1} dBFS"));
        }
        if self.speech_heard() {
            self.count_frame(self.levels.len() - 1, threshold_db);
        } else {
            self.rescore(threshold_db);
        }
        self.publish_threshold(threshold_db);
        (self.log)(&format!(
            "{:6.2}s level {level_db:6.1} threshold {threshold_db:6.1} dBFS speech {:.2}s quiet {:.2}s",
            self.elapsed_secs, self.speech_secs, self.quiet_secs
        ));
        if self.speech_heard() && self.quiet_secs >= self.silence_secs && self.pause_follows_speech(threshold_db) {
            if self.speech_secs < self.min_speech_secs {
                (self.trace)(&format!(
                    "{:.2}s of speech, short of {}s: a short word, stopping",
                    self.speech_secs,
                    py_float(self.min_speech_secs)
                ));
            }
            return Some(Verdict::Silence);
        }
        if self.max_secs > 0.0 && self.elapsed_secs >= self.max_secs && self.speech_secs > 0.0 {
            (self.trace)(&format!(
                "{:.2}s of recording with speech in it, cutting here",
                self.elapsed_secs
            ));
            return Some(Verdict::MaxLength);
        }
        if !self.speech_heard() && self.elapsed_secs >= self.no_speech_secs {
            return Some(Verdict::NoSpeech);
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::voice::watch;
    use std::cell::RefCell;
    use std::rc::Rc;

    #[test]
    fn the_exit_codes_are_the_watchers_protocol() {
        assert_eq!(i32::from(Verdict::Silence.code()), watch::VERDICT_SILENCE);
        assert_eq!(i32::from(Verdict::NoSpeech.code()), watch::VERDICT_NO_SPEECH);
        assert_eq!(i32::from(Verdict::MaxLength.code()), watch::VERDICT_MAX_LENGTH);
        assert_eq!(Verdict::NothingToDo.code(), 4);
        assert_eq!(Verdict::Error.code(), 1);
    }

    #[test]
    fn a_float_prints_as_python_does_in_the_trace() {
        assert_eq!(
            (py_float(0.0), py_float(0.25), py_float(3.0)),
            ("0.0".into(), "0.25".into(), "3.0".into())
        );
    }

    #[test]
    fn digital_silence_is_ninety_below_and_full_scale_is_zero() {
        assert!((frame_level_db(&[0; 480]) - 20.0 * (1.0f64 / 32768.0).log10()).abs() < 1e-9);
        assert!(frame_level_db(&[-32768; 480]).abs() < 1e-9);
    }

    pub struct Rig {
        pub detector: SpeechThenSilence,
        pub trace: Rc<RefCell<Vec<String>>>,
    }

    pub fn rig(env: &[(&str, &str)]) -> Rig {
        let owned: Vec<(String, String)> = env.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
        let settings = Settings::from_test_env(owned);
        let trace = Rc::new(RefCell::new(Vec::new()));
        let sink = Rc::clone(&trace);
        let detector = SpeechThenSilence::new(
            &settings,
            Box::new(|_| {}),
            Box::new(move |line| sink.borrow_mut().push(line.into())),
        )
        .unwrap();
        Rig { detector, trace }
    }

    fn frame(level_db: f64) -> Vec<i16> {
        let amplitude = (32768.0 * 10f64.powf(level_db / 20.0)) as i16;
        (0..FRAME_SAMPLES)
            .map(|i| if i % 2 == 0 { amplitude } else { -amplitude })
            .collect()
    }

    fn run(rig: &mut Rig, segments: &[(f64, f64)]) -> Option<Verdict> {
        for &(secs, level) in segments {
            for _ in 0..(secs / FRAME_SECS).round() as usize {
                if let Some(verdict) = rig.detector.feed(&frame(level)) {
                    return Some(verdict);
                }
            }
        }
        None
    }

    #[test]
    fn a_word_then_a_pause_stops() {
        let mut rig = rig(&[]);
        assert_eq!(
            run(&mut rig, &[(1.0, -55.0), (0.6, -18.0), (3.0, -55.0)]),
            Some(Verdict::Silence)
        );
        assert!(
            rig.trace
                .borrow()
                .iter()
                .any(|line| line.starts_with("calibrated: room -55.0 dBFS"))
        );
    }

    #[test]
    fn a_quiet_room_is_no_speech_at_the_deadline() {
        let mut rig = rig(&[]);
        assert_eq!(run(&mut rig, &[(7.0, -60.0)]), Some(Verdict::NoSpeech));
    }

    #[test]
    fn max_secs_cuts_a_long_speech() {
        let mut rig = rig(&[
            ("VOXCMD_AUTOSTOP_MAX_SECS", "4"),
            ("VOXCMD_AUTOSTOP_THRESHOLD_DB", "-40"),
        ]);
        assert_eq!(run(&mut rig, &[(0.3, -60.0), (9.0, -18.0)]), Some(Verdict::MaxLength));
        assert!(
            rig.trace
                .borrow()
                .iter()
                .any(|line| line.ends_with("of recording with speech in it, cutting here"))
        );
    }
}
