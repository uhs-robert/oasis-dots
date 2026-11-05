//! the listener loop: capture, scorer, decider, pause gate and the confirmation, one step at a time
//!
//! A trigger is only a candidate. The 2 s of audio that end 0.16 s after it go to `voxcmd internal wake-confirm`, which
//! has Whisper transcribe them, and only when that hears the wake word does the listener run `voxcmd listen
//! --start-only`, as the voice key does. The audio stays in memory (an anonymous memfd for the confirmation).
//!
//! `Listener::step` does one thing per call and takes its audio, time and commands as parameters, so the lifecycle
//! tests drive it with fakes.
use super::capture::{Frames, SAMPLE_RATE, SourceEnded};
use super::capture::{PcmFile, PwRecord};
use super::decider::Decider;
use super::gate::Gate;
use super::gate::{PauseGate, other_app_recording, playerctl_playing};
use super::scorer::TractScorer;
use super::scorer::{FRAME_SAMPLES, Scorer};
use super::settings::Settings;
use super::state::State;
use super::state::StateFile;
use super::{models, signal};
use crate::debug::debug;
use crate::exit::CliError;
use crate::notify::{Kind, notify};
use crate::paths;
use std::collections::VecDeque;
use std::os::fd::FromRawFd;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use std::time::Instant;

/// How long the loop sleeps while paused or waiting to retry a stream, and how long a read waits for a frame (a stop ends the wait).
const PAUSED_SLEEP_SECS: f64 = 0.5;
const READ_TIMEOUT: Duration = Duration::from_millis(500);
/// After a trigger, how long voxtype gets to report that it is recording before the "ready" cue is given up, and how
/// often its state is looked at meanwhile.
const READY_WAIT_SECS: f64 = 5.0;
const READY_POLL_SECS: f64 = 0.1;

/// A pw-record that dies is restarted after a wait that doubles up to the cap, and the wait resets after a run this long.
pub const BACKOFF_FIRST_SECS: f64 = 1.0;
pub const BACKOFF_CAP_SECS: f64 = 30.0;
pub const STABLE_STREAM_SECS: f64 = 10.0;

/// Scores below this are not worth a debug line at 12 a second.
const LOG_SCORE_FLOOR: f32 = 0.2;

/// The audio a confirmation transcribes: 2 s ending `CONFIRM_TAIL_FRAMES` after the trigger. The trigger fires near the
/// end of the word, and a lenient level triggers earlier still, so the tail keeps the word's end in the clip. It is short
/// on purpose: the verdict cannot start before the last tail frame, so the tail is latency.
pub const CONFIRM_AUDIO_FRAMES: usize = 25;
const CONFIRM_TAIL_FRAMES: u32 = 2;
/// A verdict older than this when it is collected is dropped: what it heard is no longer happening.
const CONFIRM_MAX_AGE_SECS: f64 = 4.0;

pub trait Clock {
    fn now(&self) -> f64;
    fn sleep(&self, secs: f64);
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Answer {
    Confirmed,
    Rejected,
    Failed,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Verdict {
    pub answer: Answer,
    /// Which stream the audio came from, so a verdict for audio from before a pause is known by its number.
    pub generation: u64,
    pub started_at: f64,
}

/// Runs a confirmation off the audio loop, one at a time, so frames keep being read while Whisper works.
pub trait Confirmer {
    fn busy(&self) -> bool;
    fn start(&mut self, wav: Vec<u8>, generation: u64, started_at: f64);
    fn take_verdict(&mut self) -> Option<Verdict>;
}

pub type OpenSource = Box<dyn FnMut() -> std::io::Result<Box<dyn Frames>>>;
/// The scorer, the audio source, the pause gate and the confirmation: the pieces that talk to the outside.
pub type Parts = (Box<dyn Scorer>, OpenSource, Box<dyn Gate>, Box<dyn Confirmer>);
pub type Publish = Box<dyn FnMut(State, Option<&str>)>;

pub struct Listener {
    pub scorer: Box<dyn Scorer>,
    pub open_source: OpenSource,
    pub gate: Box<dyn Gate>,
    pub confirmation: Box<dyn Confirmer>,
    pub run_listen: Box<dyn FnMut()>,
    pub publish: Publish,
    pub clock: Box<dyn Clock>,
    pub log: Box<dyn Fn(&str)>,
    pub stop_requested: Box<dyn Fn() -> bool>,
    pub decider: Decider,
    recent_frames: VecDeque<Vec<i16>>,
    /// Frames still to read after a trigger before its clip is cut, or None when no trigger waits.
    tail_frames_left: Option<u32>,
    stream_generation: u64,
    source: Option<Box<dyn Frames>>,
    opened_at: f64,
    backoff_secs: f64,
    retry_at: f64,
    /// Set at a trigger until the recording it started has ended: the bar is told "ready" while voxtype records.
    ready_deadline: Option<f64>,
    ready_seen: bool,
}

impl Listener {
    pub fn new(
        parts: Parts,
        run_listen: Box<dyn FnMut()>,
        publish: Publish,
        clock: Box<dyn Clock>,
        log: Box<dyn Fn(&str)>,
        stop_requested: Box<dyn Fn() -> bool>,
        decider: Decider,
    ) -> Self {
        let (scorer, open_source, gate, confirmation) = parts;
        Self {
            scorer,
            open_source,
            gate,
            confirmation,
            run_listen,
            publish,
            clock,
            log,
            stop_requested,
            decider,
            recent_frames: VecDeque::new(),
            tail_frames_left: None,
            stream_generation: 0,
            source: None,
            opened_at: 0.0,
            backoff_secs: BACKOFF_FIRST_SECS,
            retry_at: 0.0,
            ready_deadline: None,
            ready_seen: false,
        }
    }

    pub fn run(&mut self) {
        while !(self.stop_requested)() {
            self.step();
        }
        self.close_stream();
    }

    /// Closes the microphone and forgets the audio, the phrase under way and the scorer's buffers.
    fn close_stream(&mut self) {
        if let Some(mut source) = self.source.take() {
            source.close();
        }
        self.decider.reset();
        self.scorer.reset();
        self.recent_frames.clear();
        self.tail_frames_left = None;
        self.stream_generation += 1;
    }

    fn fail_stream(&mut self, reason: &str) {
        self.close_stream();
        (self.log)(&format!("stream: {reason}, retry in {}s", self.backoff_secs));
        self.retry_at = self.clock.now() + self.backoff_secs;
        self.backoff_secs = (self.backoff_secs * 2.0).min(BACKOFF_CAP_SECS);
        (self.publish)(State::Paused, None);
    }

    /// "ready" while the recording a wake trigger started is under way, else "paused".
    fn paused_state(&mut self) -> State {
        let Some(deadline) = self.ready_deadline else {
            return State::Paused;
        };
        if self.gate.voxtype_recording() {
            self.ready_seen = true;
            return State::Ready;
        }
        if self.ready_seen || self.clock.now() >= deadline {
            self.ready_deadline = None;
            self.ready_seen = false;
        }
        State::Paused
    }

    fn act_on_verdict(&mut self, verdict: Verdict) {
        match verdict.answer {
            Answer::Confirmed => {
                (self.log)("confirmed");
                self.ready_deadline = Some(self.clock.now() + READY_WAIT_SECS);
                self.ready_seen = false;
                (self.run_listen)();
            }
            Answer::Rejected => (self.log)("rejected"),
            Answer::Failed => (self.log)("confirm failed, not listening"),
        }
    }

    pub fn step(&mut self) {
        let verdict = self.confirmation.take_verdict();
        if self.gate.paused(self.clock.now()) {
            if let Some(verdict) = verdict {
                // What paused it (the voice key, a session, a call) has the microphone now.
                (self.log)(&format!("{:?} while paused, dropped", verdict.answer));
            }
            if self.source.is_some() {
                (self.log)("paused");
                self.close_stream();
            }
            let state = self.paused_state();
            let reason = if state == State::Paused {
                self.gate.reason()
            } else {
                None
            };
            (self.publish)(state, reason);
            self.clock.sleep(if self.ready_deadline.is_some() {
                READY_POLL_SECS
            } else {
                PAUSED_SLEEP_SECS
            });
            return;
        }
        if let Some(verdict) = verdict {
            // A pause that ended since the trigger closed the stream, so its verdict must not start a recording now.
            if verdict.generation != self.stream_generation {
                (self.log)(&format!(
                    "{:?} from before the stream was reopened, dropped",
                    verdict.answer
                ));
            } else if self.clock.now() - verdict.started_at > CONFIRM_MAX_AGE_SECS {
                (self.log)(&format!("{:?} too old, dropped", verdict.answer));
            } else {
                self.act_on_verdict(verdict);
            }
        }
        if self
            .ready_deadline
            .is_some_and(|deadline| self.ready_seen || self.clock.now() >= deadline)
        {
            self.ready_deadline = None;
            self.ready_seen = false;
        }
        if self.source.is_none() {
            let wait = self.retry_at - self.clock.now();
            if wait > 0.0 {
                self.clock.sleep(wait.min(PAUSED_SLEEP_SECS));
                return;
            }
            match (self.open_source)() {
                Ok(source) => self.source = Some(source),
                Err(error) => {
                    self.fail_stream(&format!("cannot start pw-record ({error})"));
                    return;
                }
            }
            self.opened_at = self.clock.now();
            (self.log)("armed");
            (self.publish)(State::Armed, None);
        }
        let Some(source) = self.source.as_mut() else { return };
        let frame = match source.next_frame(READ_TIMEOUT) {
            Ok(Some(frame)) => frame,
            Ok(None) => return,
            Err(SourceEnded) => {
                self.fail_stream("pw-record ended");
                return;
            }
        };
        self.on_frame(frame);
    }

    fn on_frame(&mut self, frame: Vec<i16>) {
        let now = self.clock.now();
        let score = self.scorer.score(&frame);
        self.recent_frames.push_back(frame);
        if self.recent_frames.len() > CONFIRM_AUDIO_FRAMES {
            self.recent_frames.pop_front();
        }
        if let Some(left) = self.tail_frames_left {
            if left <= 1 {
                self.tail_frames_left = None;
                self.cut_clip(now);
            } else {
                self.tail_frames_left = Some(left - 1);
            }
        }
        if now - self.opened_at >= STABLE_STREAM_SECS {
            self.backoff_secs = BACKOFF_FIRST_SECS;
        }
        if score >= LOG_SCORE_FLOOR {
            (self.log)(&format!("score {score:.2}"));
        }
        if self.decider.update(score, now) {
            if self.tail_frames_left.is_some() || self.confirmation.busy() {
                (self.log)(&format!("trigger score {score:.2} skipped, still confirming"));
                return;
            }
            (self.log)(&format!("trigger score {score:.2}, confirming"));
            // The frames after the trigger are read by the loop as usual; the clip is cut when the last one is in.
            self.tail_frames_left = Some(CONFIRM_TAIL_FRAMES);
        }
    }

    /// Sends the clip a trigger waited for to be confirmed.
    fn cut_clip(&mut self, now: f64) {
        if !self.confirmation.busy() {
            let wav = wav_bytes(&self.recent_frames);
            self.confirmation.start(wav, self.stream_generation, now);
        }
    }
}

/// The frames as a 16 kHz mono s16 WAV file's content.
pub fn wav_bytes<'a>(frames: impl IntoIterator<Item = &'a Vec<i16>>) -> Vec<u8> {
    let pcm: Vec<u8> = frames
        .into_iter()
        .flat_map(|frame| frame.iter().flat_map(|sample| sample.to_le_bytes()))
        .collect();
    let mut wav = Vec::with_capacity(44 + pcm.len());
    wav.extend_from_slice(b"RIFF");
    wav.extend_from_slice(&(36 + pcm.len() as u32).to_le_bytes());
    wav.extend_from_slice(b"WAVEfmt ");
    wav.extend_from_slice(&16u32.to_le_bytes());
    wav.extend_from_slice(&1u16.to_le_bytes());
    wav.extend_from_slice(&1u16.to_le_bytes());
    wav.extend_from_slice(&SAMPLE_RATE.to_le_bytes());
    wav.extend_from_slice(&(SAMPLE_RATE * 2).to_le_bytes());
    wav.extend_from_slice(&2u16.to_le_bytes());
    wav.extend_from_slice(&16u16.to_le_bytes());
    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&(pcm.len() as u32).to_le_bytes());
    wav.extend_from_slice(&pcm);
    wav
}

/// Seconds of audio per frame, for the clock of a `--pcm` run.
pub const FRAME_SECS: f64 = FRAME_SAMPLES as f64 / SAMPLE_RATE as f64;

// ---- the real clock, confirmation worker and entry point ----

const SUBCOMMAND: &str = "wake listen";
/// How long `voxtype transcribe` may take (passed to `wake-confirm`, which enforces it), and how much longer the
/// listener waits before it kills the whole confirmation.
const CONFIRM_TIMEOUT_SECS: u64 = 6;
const CONFIRM_KILL_GRACE_SECS: u64 = 2;
const LISTEN_TIMEOUT: Duration = Duration::from_secs(15);

struct SystemClock {
    started: Instant,
}

impl Clock for SystemClock {
    fn now(&self) -> f64 {
        self.started.elapsed().as_secs_f64()
    }

    fn sleep(&self, secs: f64) {
        signal::sleep(Duration::from_secs_f64(secs.max(0.0)));
    }
}

#[derive(Default)]
struct Shared {
    running: bool,
    verdict: Option<Verdict>,
}

/// `voxcmd internal wake-confirm /dev/stdin` with the clip as its stdin, on a worker thread.
struct ConfirmWorker {
    shared: Arc<Mutex<Shared>>,
    /// The process group of the confirmation under way, 0 when none, so a stop can end it.
    group: Arc<AtomicI32>,
}

impl ConfirmWorker {
    fn new() -> Self {
        Self {
            shared: Arc::default(),
            group: Arc::new(AtomicI32::new(0)),
        }
    }
}

impl Confirmer for ConfirmWorker {
    fn busy(&self) -> bool {
        let shared = self.shared.lock().unwrap();
        shared.running || shared.verdict.is_some()
    }

    fn start(&mut self, wav: Vec<u8>, generation: u64, started_at: f64) {
        self.shared.lock().unwrap().running = true;
        let shared = Arc::clone(&self.shared);
        let group = Arc::clone(&self.group);
        let spawned = std::thread::Builder::new().name("wake-confirm".into()).spawn(move || {
            let answer = confirm(&wav, &group);
            group.store(0, Ordering::SeqCst);
            let mut shared = shared.lock().unwrap();
            shared.verdict = Some(Verdict {
                answer,
                generation,
                started_at,
            });
            shared.running = false;
        });
        if spawned.is_err() {
            // A thread that never started would leave `busy` true for good.
            self.shared.lock().unwrap().running = false;
        }
    }

    fn take_verdict(&mut self) -> Option<Verdict> {
        self.shared.lock().unwrap().verdict.take()
    }
}

/// The installed voxcmd for the commands the listener runs. This binary by default, through `/proc/self/exe` so a
/// rebuild that replaces the file does not break it; `VOXCMD_WAKE_VOXCMD` names another (the suites' stub).
fn voxcmd_command() -> std::ffi::OsString {
    std::env::var_os("VOXCMD_WAKE_VOXCMD")
        .filter(|path| !path.is_empty())
        .unwrap_or_else(|| "/proc/self/exe".into())
}

/// `content` in an anonymous memfd, read from the start: no path another process can open, gone when closed.
fn private_audio_file(content: &[u8]) -> std::io::Result<std::fs::File> {
    use std::io::{Seek, Write};
    // SAFETY: memfd_create with a NUL-terminated name; the descriptor it returns is owned by the File.
    let fd = unsafe { libc::memfd_create(c"voxcmd-wake-audio".as_ptr(), libc::MFD_CLOEXEC) };
    if fd < 0 {
        return Err(std::io::Error::last_os_error());
    }
    // SAFETY: `fd` is a fresh descriptor nothing else owns.
    let mut file = unsafe { std::fs::File::from_raw_fd(fd) };
    file.write_all(content)?;
    file.rewind()?;
    Ok(file)
}

/// Waits for the child up to `limit`. On the deadline it kills the child's group (it leads one) and waits for it.
fn wait_within(child: &mut Child, limit: Duration) -> Option<ExitStatus> {
    let deadline = Instant::now() + limit;
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return Some(status),
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(20)),
            _ => {
                // SAFETY: signals the group of a child this process spawned and has not reaped.
                unsafe { libc::kill(-(child.id() as libc::pid_t), libc::SIGKILL) };
                let _ = child.wait();
                return None;
            }
        }
    }
}

/// Exit 0 is the wake word and 1 is not. Any other code, a timeout included, is a failure (`wake-confirm` exits 2 for
/// its own). What it heard is never read: it goes to /dev/null.
fn confirm(wav: &[u8], group: &AtomicI32) -> Answer {
    let Ok(audio) = private_audio_file(wav) else {
        debug("wake: confirm could not make its audio file");
        return Answer::Failed;
    };
    let mut command = Command::new(voxcmd_command());
    command
        .args(["internal", "wake-confirm", "/dev/stdin"])
        .env("VOXCMD_WAKE_CONFIRM_TIMEOUT_SECS", CONFIRM_TIMEOUT_SECS.to_string())
        .stdin(Stdio::from(audio))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        // Its own group, so a hung voxtype under it goes with it.
        .process_group(0);
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            debug(&format!("wake: confirm could not run ({error})"));
            return Answer::Failed;
        }
    };
    group.store(child.id() as i32, Ordering::SeqCst);
    let limit = Duration::from_secs(CONFIRM_TIMEOUT_SECS + CONFIRM_KILL_GRACE_SECS);
    match wait_within(&mut child, limit).and_then(|status| status.code()) {
        Some(0) => Answer::Confirmed,
        Some(1) => Answer::Rejected,
        other => {
            debug(&format!("wake: confirm exit {other:?}"));
            Answer::Failed
        }
    }
}

/// `voxcmd listen --start-only`, as the voice key runs it.
fn run_listen_start_only() {
    let mut command = Command::new(voxcmd_command());
    command
        .args(["listen", "--start-only"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0);
    match command.spawn() {
        Ok(mut child) => match wait_within(&mut child, LISTEN_TIMEOUT) {
            Some(status) => debug(&format!("wake: listen exit {}", status.code().unwrap_or(-1))),
            None => debug("wake: listen timed out"),
        },
        Err(error) => debug(&format!("wake: listen failed ({error})")),
    }
}

/// `voxcmd wake listen [--fetch-models | --check | --pcm <file>]`.
pub fn run(fetch_models: bool, check: bool, pcm: Option<&Path>) -> Result<(), CliError> {
    let settings = Settings::load().map_err(|message| CliError::setup(SUBCOMMAND, message))?;
    let wake_model = paths::share_dir().join(models::WAKE_MODEL);
    if fetch_models {
        return fetch(&settings);
    }
    let problem = models::missing_setup(&settings.model_dir, &wake_model, &models::FEATURE_MODELS);
    if check {
        return match problem {
            Some(problem) => {
                println!("{problem}");
                Err(CliError::quiet(SUBCOMMAND))
            }
            None => Ok(()),
        };
    }
    if let Some(problem) = problem {
        if pcm.is_none() {
            notify(Kind::Error, "Wake word", &problem);
        }
        return Err(CliError::setup(SUBCOMMAND, problem));
    }
    let scorer = TractScorer::load(&settings.model_dir, &wake_model)
        .map_err(|message| CliError::failed(SUBCOMMAND, format!("cannot load the models: {message}")))?;
    let decider = Decider::new(settings.threshold, settings.frames, settings.cooldown_secs);
    match pcm {
        Some(file) => run_pcm(file, Box::new(scorer), decider),
        None => run_live(&settings, Box::new(scorer), decider),
    }
}

fn fetch(settings: &Settings) -> Result<(), CliError> {
    let base_url = std::env::var("VOXCMD_WAKE_MODEL_URL")
        .ok()
        .filter(|url| !url.is_empty())
        .unwrap_or_else(|| models::RELEASE_URL.to_string());
    let result = models::fetch(&settings.model_dir, &base_url, &models::FEATURE_MODELS, &mut |line| {
        notify(Kind::Info, "Wake word", line);
    });
    result.map_err(|message| {
        notify(Kind::Error, "Wake word", "Could not fetch the models");
        CliError::failed(SUBCOMMAND, format!("model download failed: {message}"))
    })
}

/// The scores of a raw s16 file, one `frame score` line per 80 ms frame and a `trigger frame score` line where the
/// decider fires. No microphone, no confirmation and no `wake.json`; the cooldown runs on the file's own time.
fn run_pcm(file: &Path, mut scorer: Box<dyn Scorer>, mut decider: Decider) -> Result<(), CliError> {
    use std::io::Write;
    let mut source =
        PcmFile::open(file).map_err(|error| CliError::failed(SUBCOMMAND, format!("{}: {error}", file.display())))?;
    let mut out = std::io::BufWriter::new(std::io::stdout().lock());
    let mut index = 0usize;
    while let Ok(Some(frame)) = source.next_frame(Duration::ZERO) {
        let score = scorer.score(&frame);
        // A closed pipe is the reader's choice.
        if writeln!(out, "{index} {score:.4}").is_err() {
            return Ok(());
        }
        if decider.update(score, index as f64 * FRAME_SECS) {
            let _ = writeln!(out, "trigger {index} {score:.4}");
        }
        index += 1;
    }
    let _ = out.flush();
    Ok(())
}

fn run_live(settings: &Settings, scorer: Box<dyn Scorer>, decider: Decider) -> Result<(), CliError> {
    signal::install().map_err(|error| CliError::failed(SUBCOMMAND, format!("cannot handle signals: {error}")))?;
    let gate = PauseGate::new(
        paths::voxtype_state(),
        paths::session_file(),
        settings
            .pause_for_media
            .then(|| Box::new(playerctl_playing) as Box<dyn FnMut() -> bool>),
        settings
            .pause_for_mic
            .then(|| Box::new(other_app_recording) as Box<dyn FnMut() -> bool>),
    );
    let worker = ConfirmWorker::new();
    let confirm_group = Arc::clone(&worker.group);
    let mut state_file = StateFile::new(paths::wake_state(), std::process::id());
    let mut listener = Listener::new(
        (
            scorer,
            Box::new(|| PwRecord::spawn().map(|source| Box::new(source) as Box<dyn Frames>)),
            Box::new(gate),
            Box::new(worker),
        ),
        Box::new(run_listen_start_only),
        Box::new(move |state, reason| {
            if let Err(error) = state_file.publish(state, reason) {
                debug(&format!("wake: cannot write wake.json ({error})"));
            }
        }),
        Box::new(SystemClock {
            started: Instant::now(),
        }),
        Box::new(|message| debug(&format!("wake: {message}"))),
        Box::new(signal::requested),
        decider,
    );
    listener.run();
    // A confirmation still running would leave a voxtype behind. wake.json stays: the unit's ExecStopPost removes it.
    kill_group(&confirm_group);
    Ok(())
}

fn kill_group(group: &AtomicI32) {
    let group = group.load(Ordering::SeqCst);
    if group > 0 {
        // SAFETY: signals the process group of a child this process spawned.
        unsafe { libc::kill(-group, libc::SIGKILL) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::voice::wake::decider::Decider;
    use std::cell::{Cell, RefCell};
    use std::rc::Rc;

    type Published = (State, Option<String>);
    /// The sources the next opens hand out: a script, or an error for an open that fails.
    type Scripts = Rc<RefCell<VecDeque<Result<Vec<Item>, ()>>>>;

    #[derive(Clone)]
    struct FakeClock(Rc<Cell<f64>>);

    impl Clock for FakeClock {
        fn now(&self) -> f64 {
            self.0.get()
        }

        fn sleep(&self, secs: f64) {
            self.0.set(self.0.get() + secs);
        }
    }

    /// One thing a source does when read: give a frame, or end.
    #[derive(Clone, Copy, PartialEq)]
    enum Item {
        Frame,
        End,
    }

    struct FakeSource {
        clock: FakeClock,
        script: VecDeque<Item>,
        closed: Rc<Cell<u32>>,
    }

    impl Frames for FakeSource {
        fn next_frame(&mut self, _timeout: Duration) -> Result<Option<Vec<i16>>, SourceEnded> {
            match self.script.pop_front() {
                Some(Item::Frame) => {
                    self.clock.sleep(FRAME_SECS);
                    Ok(Some(vec![0; FRAME_SAMPLES]))
                }
                _ => Err(SourceEnded),
            }
        }

        fn close(&mut self) {
            self.closed.set(self.closed.get() + 1);
        }
    }

    struct ScriptedScorer(Rc<RefCell<VecDeque<f32>>>, Rc<Cell<u32>>);

    impl Scorer for ScriptedScorer {
        fn score(&mut self, _frame: &[i16]) -> f32 {
            self.0.borrow_mut().pop_front().unwrap_or(0.0)
        }

        fn reset(&mut self) {
            self.1.set(self.1.get() + 1);
        }
    }

    #[derive(Default)]
    struct FakeGateState {
        paused: bool,
        recording: bool,
        reason: Option<&'static str>,
    }

    struct FakeGate(Rc<RefCell<FakeGateState>>);

    impl Gate for FakeGate {
        fn paused(&mut self, _now: f64) -> bool {
            self.0.borrow().paused
        }

        fn reason(&self) -> Option<&'static str> {
            self.0.borrow().reason
        }

        fn voxtype_recording(&self) -> bool {
            self.0.borrow().recording
        }
    }

    #[derive(Default)]
    struct FakeConfirm {
        started: Vec<(usize, u64, f64)>,
        running: bool,
        verdict: Option<Verdict>,
    }

    struct FakeConfirmer(Rc<RefCell<FakeConfirm>>);

    impl Confirmer for FakeConfirmer {
        fn busy(&self) -> bool {
            let state = self.0.borrow();
            state.running || state.verdict.is_some()
        }

        fn start(&mut self, wav: Vec<u8>, generation: u64, started_at: f64) {
            let mut state = self.0.borrow_mut();
            state.running = true;
            state.started.push((wav.len(), generation, started_at));
        }

        fn take_verdict(&mut self) -> Option<Verdict> {
            self.0.borrow_mut().verdict.take()
        }
    }

    /// A listener on fakes, and the handles a test reads and drives.
    struct Rig {
        listener: Listener,
        clock: FakeClock,
        scores: Rc<RefCell<VecDeque<f32>>>,
        sources: Scripts,
        opened: Rc<Cell<u32>>,
        closed: Rc<Cell<u32>>,
        resets: Rc<Cell<u32>>,
        gate: Rc<RefCell<FakeGateState>>,
        confirm: Rc<RefCell<FakeConfirm>>,
        published: Rc<RefCell<Vec<Published>>>,
        listens: Rc<Cell<u32>>,
        log: Rc<RefCell<Vec<String>>>,
        stop: Rc<Cell<bool>>,
        /// The clock times at which a stream was opened.
        open_times: Rc<RefCell<Vec<f64>>>,
    }

    fn rig() -> Rig {
        let clock = FakeClock(Rc::new(Cell::new(100.0)));
        let scores = Rc::new(RefCell::new(VecDeque::new()));
        let sources: Scripts = Rc::default();
        let opened = Rc::new(Cell::new(0));
        let closed = Rc::new(Cell::new(0));
        let resets = Rc::new(Cell::new(0));
        let gate: Rc<RefCell<FakeGateState>> = Rc::default();
        let confirm: Rc<RefCell<FakeConfirm>> = Rc::default();
        let published = Rc::new(RefCell::new(Vec::new()));
        let listens = Rc::new(Cell::new(0));
        let log = Rc::new(RefCell::new(Vec::new()));
        let stop = Rc::new(Cell::new(false));
        let open_times = Rc::new(RefCell::new(Vec::new()));
        let open_source: OpenSource = {
            let (clock, sources, opened, closed, times) = (
                clock.clone(),
                Rc::clone(&sources),
                Rc::clone(&opened),
                Rc::clone(&closed),
                Rc::clone(&open_times),
            );
            Box::new(move || {
                opened.set(opened.get() + 1);
                times.borrow_mut().push(clock.now());
                match sources.borrow_mut().pop_front() {
                    Some(Ok(script)) => Ok(Box::new(FakeSource {
                        clock: clock.clone(),
                        script: script.into(),
                        closed: Rc::clone(&closed),
                    })),
                    _ => Err(std::io::Error::other("no pw-record")),
                }
            })
        };
        let listener = Listener::new(
            (
                Box::new(ScriptedScorer(Rc::clone(&scores), Rc::clone(&resets))),
                open_source,
                Box::new(FakeGate(Rc::clone(&gate))),
                Box::new(FakeConfirmer(Rc::clone(&confirm))),
            ),
            {
                let listens = Rc::clone(&listens);
                Box::new(move || listens.set(listens.get() + 1))
            },
            {
                let published = Rc::clone(&published);
                Box::new(move |state, reason| published.borrow_mut().push((state, reason.map(str::to_string))))
            },
            Box::new(clock.clone()),
            {
                let log = Rc::clone(&log);
                Box::new(move |message| log.borrow_mut().push(message.to_string()))
            },
            {
                let stop = Rc::clone(&stop);
                Box::new(move || stop.get())
            },
            Decider::new(0.8, 3, 3.0),
        );
        Rig {
            listener,
            clock,
            scores,
            sources,
            opened,
            closed,
            resets,
            gate,
            confirm,
            published,
            listens,
            log,
            stop,
            open_times,
        }
    }

    impl Rig {
        fn source(&self, frames: usize) {
            let mut script = vec![Item::Frame; frames];
            script.push(Item::End);
            self.sources.borrow_mut().push_back(Ok(script));
        }

        fn steps(&mut self, count: usize) {
            for _ in 0..count {
                self.listener.step();
            }
        }

        fn phrase(&self, scores: &[f32]) {
            self.scores.borrow_mut().extend(scores.iter().copied());
        }

        fn verdict(&self, answer: Answer) {
            let mut confirm = self.confirm.borrow_mut();
            let (_, generation, started_at) = *confirm.started.last().expect("a confirmation was started");
            confirm.running = false;
            confirm.verdict = Some(Verdict {
                answer,
                generation,
                started_at,
            });
        }

        fn states(&self) -> Vec<Published> {
            self.published.borrow().clone()
        }
    }

    // ---- the trigger, its confirmation and the recording -----------------------------------------------------------

    #[test]
    fn a_confirmed_trigger_runs_listen_once_and_a_rejected_or_failed_one_never() {
        for (answer, listens) in [(Answer::Confirmed, 1), (Answer::Rejected, 0), (Answer::Failed, 0)] {
            let mut rig = rig();
            rig.source(20);
            rig.phrase(&[0.0, 0.9, 0.9, 0.9, 0.0, 0.0, 0.0]);
            // open + 1 quiet + 3 high frames, then the two tail frames cut the clip.
            rig.steps(7);
            assert_eq!(rig.confirm.borrow().started.len(), 1, "{answer:?}");
            rig.verdict(answer);
            rig.steps(1);
            assert_eq!(rig.listens.get(), listens, "{answer:?}");
        }
    }

    #[test]
    fn the_clip_is_two_seconds_at_most_and_ends_two_frames_after_the_trigger() {
        let mut rig = rig();
        rig.source(60);
        rig.phrase(&[0.0; 40]);
        rig.phrase(&[0.9, 0.9, 0.9]);
        rig.steps(1 + 43);
        assert!(rig.confirm.borrow().started.is_empty(), "the tail is not in yet");
        rig.steps(2);
        let (wav_len, generation, _) = rig.confirm.borrow().started[0];
        assert_eq!(wav_len, 44 + CONFIRM_AUDIO_FRAMES * FRAME_SAMPLES * 2);
        assert_eq!(generation, 0);
    }

    #[test]
    fn a_trigger_while_one_is_confirming_is_skipped() {
        let mut rig = rig();
        rig.source(80);
        rig.phrase(&[0.9, 0.9, 0.9]);
        rig.steps(1 + 3 + 2);
        assert_eq!(rig.confirm.borrow().started.len(), 1);
        // The cooldown is 3 s (38 frames), so a second phrase after it meets a confirmation still running.
        rig.phrase(&[0.0; 40]);
        rig.phrase(&[0.9, 0.9, 0.9]);
        rig.steps(43);
        assert_eq!(rig.confirm.borrow().started.len(), 1);
        assert!(
            rig.log
                .borrow()
                .iter()
                .any(|line| line.contains("skipped, still confirming"))
        );
    }

    #[test]
    fn two_phrases_inside_the_cooldown_run_listen_once() {
        let mut rig = rig();
        rig.source(60);
        rig.phrase(&[0.9, 0.9, 0.9, 0.0, 0.9, 0.9, 0.9, 0.0]);
        rig.steps(1 + 3 + 2);
        rig.verdict(Answer::Confirmed);
        rig.steps(5);
        assert_eq!(rig.listens.get(), 1);
        assert_eq!(
            rig.confirm.borrow().started.len(),
            1,
            "the second phrase did not trigger"
        );
    }

    #[test]
    fn a_verdict_older_than_four_seconds_is_dropped_and_one_just_inside_counts() {
        for (age, listens) in [(4.5, 0), (3.9, 1)] {
            let mut rig = rig();
            rig.source(80);
            rig.phrase(&[0.9, 0.9, 0.9]);
            rig.steps(1 + 3 + 2);
            rig.verdict(Answer::Confirmed);
            let started = rig.confirm.borrow().started[0].2;
            rig.clock.0.set(started + age - FRAME_SECS);
            rig.steps(1);
            assert_eq!(rig.listens.get(), listens, "age {age}");
        }
    }

    #[test]
    fn a_verdict_from_before_a_pause_is_dropped_after_the_pause_ends() {
        let mut rig = rig();
        rig.source(80);
        rig.source(80);
        rig.phrase(&[0.9, 0.9, 0.9]);
        rig.steps(1 + 3 + 2);
        rig.gate.borrow_mut().paused = true;
        rig.steps(1);
        rig.verdict(Answer::Confirmed);
        rig.gate.borrow_mut().paused = false;
        rig.clock.0.set(rig.clock.0.get() + 1.0);
        rig.steps(2);
        assert_eq!(rig.listens.get(), 0);
        assert!(
            rig.log
                .borrow()
                .iter()
                .any(|line| line.contains("from before the stream was reopened"))
        );
    }

    #[test]
    fn a_verdict_that_arrives_while_paused_is_dropped() {
        let mut rig = rig();
        rig.source(80);
        rig.phrase(&[0.9, 0.9, 0.9]);
        rig.steps(1 + 3 + 2);
        rig.verdict(Answer::Confirmed);
        rig.gate.borrow_mut().paused = true;
        rig.steps(1);
        assert_eq!(rig.listens.get(), 0);
        assert!(
            rig.log
                .borrow()
                .iter()
                .any(|line| line.contains("while paused, dropped"))
        );
    }

    #[test]
    fn ready_is_published_while_the_recording_a_trigger_started_is_under_way() {
        let mut rig = rig();
        rig.source(80);
        rig.phrase(&[0.9, 0.9, 0.9]);
        rig.steps(1 + 3 + 2);
        rig.verdict(Answer::Confirmed);
        rig.steps(1);
        assert_eq!(rig.listens.get(), 1);
        // voxtype starts recording: the gate pauses, and the bar is told ready, not paused.
        {
            let mut gate = rig.gate.borrow_mut();
            gate.paused = true;
            gate.recording = true;
            gate.reason = Some("voxtype_recording");
        }
        rig.steps(1);
        assert_eq!(rig.states().last().unwrap(), &(State::Ready, None));
        // The recording ends: paused again, with its reason, and no ready cue is left waiting.
        rig.gate.borrow_mut().recording = false;
        rig.steps(2);
        assert_eq!(
            rig.states().last().unwrap(),
            &(State::Paused, Some("voxtype_recording".to_string()))
        );
    }

    #[test]
    fn a_recording_that_never_starts_gives_up_the_ready_cue() {
        let mut rig = rig();
        rig.source(80);
        rig.phrase(&[0.9, 0.9, 0.9]);
        rig.steps(1 + 3 + 2);
        rig.verdict(Answer::Confirmed);
        rig.steps(1);
        {
            let mut gate = rig.gate.borrow_mut();
            gate.paused = true;
            gate.reason = Some("session_open");
        }
        rig.steps(1);
        assert_eq!(rig.states().last().unwrap().0, State::Paused);
        rig.clock.0.set(rig.clock.0.get() + READY_WAIT_SECS + 1.0);
        rig.steps(2);
        assert_eq!(rig.states().last().unwrap().1.as_deref(), Some("session_open"));
        assert!(rig.listener.ready_deadline.is_none());
    }

    // ---- pause and resume release the microphone -------------------------------------------------------------------

    #[test]
    fn a_pause_closes_the_stream_and_resuming_opens_a_new_one() {
        let mut rig = rig();
        rig.source(100);
        rig.source(100);
        rig.steps(3);
        assert_eq!((rig.opened.get(), rig.closed.get()), (1, 0));
        assert_eq!(rig.states(), [(State::Armed, None)]);
        {
            let mut gate = rig.gate.borrow_mut();
            gate.paused = true;
            gate.reason = Some("voxtype_recording");
        }
        rig.steps(1);
        assert_eq!(rig.closed.get(), 1, "the stream was not closed on a pause");
        assert_eq!(
            rig.states().last().unwrap(),
            &(State::Paused, Some("voxtype_recording".to_string()))
        );
        rig.steps(3);
        assert_eq!(rig.opened.get(), 1, "a paused listener opened the microphone");
        rig.gate.borrow_mut().paused = false;
        rig.steps(1);
        assert_eq!(rig.opened.get(), 2);
        assert_eq!(rig.states().last().unwrap(), &(State::Armed, None));
    }

    #[test]
    fn a_pause_forgets_the_phrase_and_the_scorer_but_not_the_cooldown() {
        let mut rig = rig();
        rig.source(100);
        rig.source(100);
        rig.phrase(&[0.9, 0.9]);
        rig.steps(3);
        let resets = rig.resets.get();
        rig.gate.borrow_mut().paused = true;
        rig.steps(1);
        assert_eq!(rig.resets.get(), resets + 1);
        rig.gate.borrow_mut().paused = false;
        // Two more high frames would have been the third in a row without the reset.
        rig.phrase(&[0.9, 0.9, 0.0]);
        rig.steps(4);
        assert!(rig.confirm.borrow().started.is_empty());
        assert!(rig.listener.tail_frames_left.is_none());
    }

    #[test]
    fn a_stream_that_would_fail_while_paused_is_never_opened_and_writes_no_failure() {
        let mut rig = rig();
        // No source scripted: opening would fail.
        rig.gate.borrow_mut().paused = true;
        rig.gate.borrow_mut().reason = Some("mic_in_use");
        rig.steps(5);
        assert_eq!(rig.opened.get(), 0);
        assert!(
            rig.log.borrow().iter().all(|line| !line.contains("stream:")),
            "{:?}",
            rig.log.borrow()
        );
        assert_eq!(rig.states().iter().filter(|state| state.0 != State::Paused).count(), 0);
    }

    #[test]
    fn a_stop_closes_the_stream() {
        let mut rig = rig();
        rig.source(1000);
        rig.steps(2);
        rig.stop.set(true);
        rig.listener.run();
        assert_eq!(rig.closed.get(), 1);
    }

    // ---- the pw-record child dies ----------------------------------------------------------------------------------

    #[test]
    fn a_dying_stream_is_restarted_after_1_2_4_up_to_30_seconds() {
        let mut rig = rig();
        for _ in 0..8 {
            rig.sources.borrow_mut().push_back(Ok(vec![Item::End]));
        }
        while rig.opened.get() < 8 {
            rig.steps(1);
        }
        let times = rig.open_times.borrow().clone();
        let gaps: Vec<f64> = times.windows(2).map(|pair| (pair[1] - pair[0]).round()).collect();
        assert_eq!(gaps, [1.0, 2.0, 4.0, 8.0, 16.0, 30.0, 30.0]);
    }

    #[test]
    fn the_wait_resets_after_a_stable_stream() {
        let mut rig = rig();
        rig.sources.borrow_mut().push_back(Ok(vec![Item::End]));
        rig.sources.borrow_mut().push_back(Ok(vec![Item::End]));
        // A stream that reads for more than 10 s, then dies.
        let mut stable = vec![Item::Frame; 130];
        stable.push(Item::End);
        rig.sources.borrow_mut().push_back(Ok(stable));
        rig.sources.borrow_mut().push_back(Ok(vec![Item::End]));
        rig.sources.borrow_mut().push_back(Ok(vec![Item::End]));
        while rig.opened.get() < 5 {
            rig.steps(1);
        }
        let times = rig.open_times.borrow().clone();
        let gaps: Vec<f64> = times.windows(2).map(|pair| pair[1] - pair[0]).collect();
        assert!((gaps[0] - 1.0).abs() < 0.2 && (gaps[1] - 2.0).abs() < 0.2, "{gaps:?}");
        // The third stream read 130 frames (10.4 s) and its death waited 1 s, not the 4 s it would have after two deaths.
        let stable_run = 130.0 * FRAME_SECS;
        assert!(
            (gaps[2] - stable_run - 1.0).abs() < 0.2,
            "after the stable stream: {gaps:?}"
        );
        assert!((gaps[3] - 2.0).abs() < 0.2, "{gaps:?}");
    }

    #[test]
    fn the_listener_stays_alive_and_never_claims_a_stream_it_does_not_have() {
        let mut rig = rig();
        rig.sources.borrow_mut().push_back(Ok(vec![Item::Frame, Item::End]));
        // Every later open fails.
        rig.steps(1);
        assert_eq!(rig.states(), [(State::Armed, None)]);
        rig.steps(1);
        assert_eq!(
            rig.states().last().unwrap(),
            &(State::Paused, None),
            "a dead stream is not armed"
        );
        for _ in 0..20 {
            rig.steps(1);
        }
        let armed = rig.states().iter().filter(|state| state.0 == State::Armed).count();
        assert_eq!(armed, 1);
        assert!(rig.states().iter().all(|state| state.0 != State::Ready));
    }

    #[test]
    fn a_pw_record_that_cannot_start_is_retried() {
        let mut rig = rig();
        rig.steps(1);
        assert_eq!(rig.states(), [(State::Paused, None)]);
        rig.source(10);
        while rig.opened.get() < 2 {
            rig.steps(1);
        }
        rig.steps(1);
        assert_eq!(rig.states().last().unwrap(), &(State::Armed, None));
    }

    #[test]
    fn wav_bytes_is_a_16k_mono_s16_file() {
        let wav = wav_bytes(&[vec![1i16, -2], vec![3, 4]]);
        assert_eq!(&wav[..4], b"RIFF");
        assert_eq!(&wav[8..16], b"WAVEfmt ");
        assert_eq!(u32::from_le_bytes(wav[24..28].try_into().unwrap()), 16000);
        assert_eq!(u16::from_le_bytes(wav[22..24].try_into().unwrap()), 1);
        assert_eq!(u16::from_le_bytes(wav[34..36].try_into().unwrap()), 16);
        assert_eq!(&wav[44..], [1, 0, 254, 255, 3, 0, 4, 0]);
        assert_eq!(u32::from_le_bytes(wav[40..44].try_into().unwrap()), 8);
    }
}
