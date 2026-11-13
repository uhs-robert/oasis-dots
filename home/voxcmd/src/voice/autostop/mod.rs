//! `voxcmd internal autostop [--pcm FILE|-] [--state-file FILE] [--verbose] [--check]`: tells voxcmd when a voice
//! command recording has heard speech and then a pause (was the Python `voxcmd-autostop`)
//!
//! It listens to the default source through `pw-record` (16 kHz mono s16) and exits with a verdict, the only protocol
//! with the watcher (`watch::Detector`) and the chain's stopper (`chain_stop`), so the codes never change:
//!   0  speech, then silence_secs of quiet: stop the recording
//!   3  no speech at all within no_speech_secs: cancel it
//!   4  nothing to do: the recording ended some other way, the audio ended, a signal came, or auto-stop is off
//!   5  max_secs of recording with speech in it: stop the recording, which hit its length limit
//!   1  error (pw-record missing, a bad setting)
//! A signal exits 4, where the wake listener exits 0 on one. It stays a process of its own, leading the process group the
//! watcher kills, so its `pw-record` goes with it.
//!
//! Settings: `autostop.conf`, overridden by `VOXCMD_AUTOSTOP_*` (`settings`). `--pcm` reads raw PCM instead of the
//! microphone and `--verbose` logs the levels, for tuning and tests. With voxcmd's debug log on, a summary of what it
//! heard is appended there. `--check` exits 0 when a recording would be listened to, else 1 and prints why (a voice
//! session needs auto-stop).
pub mod detector;
pub mod pause_checks;
pub mod settings;
pub mod state;

use super::capture::{AUTOSTOP_TAG, Frames, PcmFile, PcmStdin, PwRecord};
use super::signal;
use crate::paths;
use detector::{FRAME_SAMPLES, SpeechThenSilence, Verdict};
use pause_checks::PauseChecks;
use settings::Settings;
use state::RecordingState;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, ExitCode};
use std::rc::Rc;
use std::time::{Duration, Instant};

const STATE_POLL: Duration = Duration::from_millis(200);
const PROGRAM: &str = "voxcmd-autostop";

/// The command that runs auto-stop: this binary's `internal autostop`, or the stand-in script `VOXCMD_AUTOSTOP_CMD`
/// names (the suites'). None when that stand-in is not executable.
pub fn command() -> Option<Command> {
    match paths::autostop_override() {
        Some(stand_in) => crate::ask::is_executable(&stand_in).then(|| Command::new(stand_in)),
        None => {
            let mut command = Command::new(crate::ask::this_binary());
            command.args(["internal", "autostop"]);
            Some(command)
        }
    }
}

#[derive(Default)]
struct Args {
    pcm: Option<String>,
    state_file: Option<PathBuf>,
    verbose: bool,
    check: bool,
}

fn parse(args: &[String]) -> Result<Args, String> {
    let mut parsed = Args::default();
    let mut rest = args.iter();
    while let Some(arg) = rest.next() {
        let mut value = || rest.next().cloned().ok_or(format!("{arg} needs a value"));
        match arg.as_str() {
            "--pcm" => parsed.pcm = Some(value()?),
            "--state-file" => parsed.state_file = Some(value()?.into()),
            "--verbose" => parsed.verbose = true,
            "--check" => parsed.check = true,
            other => return Err(format!("unrecognized argument: {other}")),
        }
    }
    Ok(parsed)
}

/// Appends to voxcmd's debug log while it is on (`VOXCMD_DEBUG`, or the file exists), in voxcmd's line format with this
/// program's name, as the Python script did.
struct DebugTrace {
    enabled: std::cell::Cell<bool>,
}

impl DebugTrace {
    fn new() -> Self {
        let on = std::env::var_os("VOXCMD_DEBUG").is_some_and(|value| !value.is_empty()) || paths::debug_log().exists();
        Self {
            enabled: std::cell::Cell::new(on),
        }
    }

    fn write(&self, message: &str) {
        if !self.enabled.get() {
            return;
        }
        let path = paths::debug_log();
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let time = jiff::Zoned::now().strftime("%H:%M:%S.%3f");
        let written = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
            .and_then(|mut file| writeln!(file, "{time} {PROGRAM}[{}] {message}", std::process::id()));
        if written.is_err() {
            self.enabled.set(false);
        }
    }
}

fn stop_here(code: Verdict) -> ExitCode {
    ExitCode::from(code.code())
}

pub fn run(args: &[String]) -> ExitCode {
    let args = match parse(args) {
        Ok(args) => args,
        Err(message) => {
            eprintln!("{PROGRAM}: {message}");
            return ExitCode::from(2);
        }
    };
    let say_error = |message: &str| {
        if args.check {
            println!("{PROGRAM}: {message}");
        } else {
            eprintln!("{PROGRAM}: {message}");
        }
    };
    let settings = match Settings::load() {
        Ok(settings) => settings,
        Err(message) => {
            say_error(&message);
            return stop_here(Verdict::Error);
        }
    };
    if !settings.is_enabled() {
        if args.check {
            println!("auto-stop is turned off (enabled = false)");
            return stop_here(Verdict::Error);
        }
        return stop_here(Verdict::NothingToDo);
    }
    let trace = Rc::new(DebugTrace::new());
    let trace_to = |trace: &Rc<DebugTrace>| -> Box<dyn Fn(&str)> {
        let trace = Rc::clone(trace);
        Box::new(move |message| trace.write(message))
    };
    let verbose = args.verbose;
    let log: Box<dyn Fn(&str)> = Box::new(move |message| {
        if verbose {
            eprintln!("{message}");
        }
    });
    let built = SpeechThenSilence::new(&settings, log, trace_to(&trace))
        .and_then(|detector| Ok((detector, PauseChecks::new(&settings, trace_to(&trace))?)));
    let (mut detector, mut pause_checks) = match built {
        Ok(built) => built,
        Err(message) => {
            say_error(&message);
            return stop_here(Verdict::Error);
        }
    };
    if args.check {
        if !pw_record_on_path() {
            println!("pw-record is not installed");
            return stop_here(Verdict::Error);
        }
        return ExitCode::SUCCESS;
    }
    let state_file = args
        .state_file
        .clone()
        .or_else(|| args.pcm.is_none().then(paths::voxtype_state));
    let mut recording_state = state_file.map(RecordingState::new);
    // A signal ends the loop (exit 4) through the same cleanup as any verdict, so `pw-record` never outlives this.
    if let Err(error) = signal::install_for(&[libc::SIGTERM, libc::SIGHUP, libc::SIGINT]) {
        say_error(&format!("cannot handle signals: {error}"));
        return stop_here(Verdict::Error);
    }
    trace.write(&format!(
        "listening: {}s pause after {}s of speech, nothing by {}s cancels; threshold {}, margin {} dB",
        settings.text("silence_secs"),
        settings.text("min_speech_secs"),
        settings.text("no_speech_secs"),
        settings.text("threshold_db"),
        settings.text("margin_db")
    ));
    let source: std::io::Result<Box<dyn Frames>> = match args.pcm.as_deref() {
        None => PwRecord::spawn(AUTOSTOP_TAG, FRAME_SAMPLES).map(|source| Box::new(source) as Box<dyn Frames>),
        Some("-") => PcmStdin::new(FRAME_SAMPLES).map(|source| Box::new(source) as Box<dyn Frames>),
        Some(file) => {
            PcmFile::open(std::path::Path::new(file), FRAME_SAMPLES).map(|source| Box::new(source) as Box<dyn Frames>)
        }
    };
    let verdict = match source {
        Ok(mut source) => {
            let verdict = wait_for_verdict(&mut *source, &mut detector, recording_state.as_mut(), &mut pause_checks);
            if args.verbose {
                eprintln!("verdict {}", verdict.code());
            }
            source.close();
            verdict
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound && args.pcm.is_none() => {
            eprintln!("{PROGRAM}: pw-record is not installed");
            return finish(&detector, Verdict::NothingToDo, Verdict::Error);
        }
        Err(error) => {
            eprintln!("{PROGRAM}: {error}");
            return finish(&detector, Verdict::NothingToDo, Verdict::Error);
        }
    };
    finish(&detector, verdict, verdict)
}

/// Writes the trace summary, which names `traced` (an error shows as "ended elsewhere"), and exits with `exit_with`.
fn finish(detector: &SpeechThenSilence, traced: Verdict, exit_with: Verdict) -> ExitCode {
    detector.trace_summary(traced);
    stop_here(exit_with)
}

fn pw_record_on_path() -> bool {
    std::env::var_os("PATH").is_some_and(|path| {
        std::env::split_paths(&path).any(|dir| {
            let candidate = dir.join("pw-record");
            candidate.is_file() && crate::ask::is_executable(&candidate)
        })
    })
}

fn wait_for_verdict(
    source: &mut dyn Frames,
    detector: &mut SpeechThenSilence,
    mut recording_state: Option<&mut RecordingState>,
    pause_checks: &mut PauseChecks,
) -> Verdict {
    let mut next_state_poll = Instant::now();
    loop {
        if signal::requested() {
            return Verdict::NothingToDo;
        }
        let now = Instant::now();
        if let Some(state) = recording_state.as_deref_mut()
            && now >= next_state_poll
        {
            if state.ended() {
                return Verdict::NothingToDo;
            }
            next_state_poll = now + STATE_POLL;
        }
        if pause_checks.enabled() {
            pause_checks.start_waiting();
        }
        let frame = match source.next_frame(STATE_POLL) {
            Ok(Some(frame)) => frame,
            Ok(None) => continue,
            Err(_) => return Verdict::NothingToDo,
        };
        let verdict = detector.feed(&frame);
        if verdict == Some(Verdict::Silence) && pause_checks.enabled() {
            // With pause_check_secs at silence_secs, this frame is the pause's first, so it has no check queued yet.
            pause_checks.queue_pause(&frame, detector);
            if !pause_checks.wait_for_pending_checks(recording_state.as_deref_mut()) {
                return Verdict::NothingToDo;
            }
        }
        if let Some(verdict) = verdict {
            return verdict;
        }
        if pause_checks.enabled() {
            pause_checks.after_frame(&frame, detector);
        }
    }
}
