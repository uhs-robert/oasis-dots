//! running a phrase of several steps: each routed only once the one before has finished and settled (was
//! `run_sequence`, `wait_for_step` and `report_sequence_stop`)
//!
//! The first step that does not run stops the rest, and one toast says where. Stop Voice flags a running sequence
//! with a `discard.<pid>` file; the sequence notices between steps and while it waits.
use super::resolve::RouteOption;
use super::runner::Runner;
use super::sequence::{Steps, refusal};
use crate::actions::{Spoken, StepOutcome, legacy_env};
use crate::bar;
use crate::config::schema::Wait;
use crate::debug::debug;
use crate::hooks::{DEFAULT_TIMEOUT, HookEnv};
use crate::hypr;
use crate::notify::Kind;
use crate::paths;
use crate::process;
use serde::{Deserialize, Serialize};
use std::time::{Duration, Instant};

/// The first look at the active window, before any step's wait: not bounded by a step.
const ACTIVE_BEFORE_WITHIN: Duration = Duration::from_secs(2);

/// How long the waits between steps take, from the environment the suites shorten.
pub struct Pacing {
    /// How long one step's wait may last (`VOXCMD_STEP_TIMEOUT_SECS`), as written for the timeout toast.
    pub step_timeout: Duration,
    pub step_timeout_text: String,
    /// A moment for the app the user acted on to draw its result (`VOXCMD_APP_SETTLE_SECS`).
    pub app_settle: Duration,
    /// Between two looks at a condition: 0.1 s, times `VOXCMD_TIME_SCALE`.
    pub poll: Duration,
}

impl Pacing {
    pub fn from_env() -> Self {
        let text = |name: &str, default: &str| {
            std::env::var(name)
                .ok()
                .filter(|value| !value.is_empty())
                .unwrap_or_else(|| default.to_string())
        };
        let (step_timeout, step_timeout_text) = step_timeout(&text("VOXCMD_STEP_TIMEOUT_SECS", "15"));
        let time_scale = text("VOXCMD_TIME_SCALE", "1");
        Self {
            step_timeout,
            step_timeout_text,
            app_settle: pacing_duration(&text("VOXCMD_APP_SETTLE_SECS", "0.3"), 1.0, 0.3),
            poll: pacing_duration(&time_scale, 0.1, 0.1),
        }
    }
}

/// The step timeout for `value` and its text for the toast: as written when `value` is usable, else the default 15 s
/// and "15". Usable also means a deadline can be built from it (`Instant + Duration` panics past the clock's range).
fn step_timeout(value: &str) -> (Duration, String) {
    let usable = value
        .parse::<f64>()
        .ok()
        .and_then(|secs| Duration::try_from_secs_f64(secs).ok())
        .filter(|timeout| Instant::now().checked_add(*timeout).is_some());
    match usable {
        Some(timeout) => (timeout, value.to_string()),
        None => (Duration::from_secs(15), "15".to_string()),
    }
}

/// `value` seconds times `factor`, or `default_secs` when `value` is not a number, or is negative, infinite or too
/// large for a `Duration` (`from_secs_f64` panics on those, which would crash every multi-step run).
fn pacing_duration(value: &str, factor: f64, default_secs: f64) -> Duration {
    value
        .parse::<f64>()
        .ok()
        .and_then(|secs| Duration::try_from_secs_f64(secs * factor).ok())
        .unwrap_or_else(|| Duration::from_secs_f64(default_secs))
}

/// `sequences/<pid>.json`, `{pid, start}`: lets Stop Voice find the sequences running, and tell a recycled pid from
/// the process that wrote it (`start` is the process's start time, /proc/<pid>/stat field 22).
#[derive(Serialize, Deserialize)]
pub struct SequenceRecord {
    pub pid: u32,
    pub start: String,
}

/// The start time of a process, from the 22nd field of /proc/<pid>/stat, counted past the command name (which may
/// hold spaces and parentheses).
pub fn process_start_time(pid: u32) -> Option<String> {
    let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    let after_name = stat.rsplit_once(") ")?.1;
    after_name.split(' ').nth(19).map(str::to_string)
}

/// The record of this process's sequence and its discard flag, removed when it ends however it ends: on return here,
/// or by the stop-signal handler (as the bash EXIT trap removed the record). A flag left behind would stop a later
/// sequence that reuses the pid.
struct OwnRecord {
    path: std::path::PathBuf,
    _removed_on_signal: [process::RemovedOnSignal; 2],
}

impl OwnRecord {
    fn create() -> Self {
        let pid = std::process::id();
        let path = paths::sequence_dir().join(format!("{pid}.json"));
        // Listed before the file exists, so no signal falls between the two.
        let removed_on_signal = [
            process::RemovedOnSignal::new(&path),
            process::RemovedOnSignal::new(&paths::discard_flag(pid)),
        ];
        let record = SequenceRecord {
            pid,
            start: process_start_time(pid).unwrap_or_default(),
        };
        let _ = std::fs::create_dir_all(paths::sequence_dir());
        let _ = std::fs::write(&path, serde_json::to_string(&record).unwrap_or_default());
        Self {
            path,
            _removed_on_signal: removed_on_signal,
        }
    }
}

impl Drop for OwnRecord {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

pub(super) fn sequence_stopped() -> bool {
    paths::discard_flag(std::process::id()).exists()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WaitEnd {
    Done,
    TimedOut,
    Stopped,
}

/// Looks at the condition every poll until it holds, for at most the step timeout. The condition is handed the time
/// left, and a command it runs must end by then: a look still running at the deadline would otherwise hold the sequence
/// past it. A look that holds only once the deadline has passed is a timeout. (The bash `poll_until` ran an unbounded
/// `eval` and took a late success.)
fn poll_until(pacing: &Pacing, mut condition: impl FnMut(Duration) -> bool) -> WaitEnd {
    let deadline = Instant::now() + pacing.step_timeout;
    loop {
        let time_left = deadline.saturating_duration_since(Instant::now());
        let held_in_time = condition(time_left) && Instant::now() <= deadline;
        if held_in_time {
            return WaitEnd::Done;
        }
        if sequence_stopped() {
            return WaitEnd::Stopped;
        }
        if Instant::now() >= deadline {
            return WaitEnd::TimedOut;
        }
        std::thread::sleep(pacing.poll.min(deadline.saturating_duration_since(Instant::now())));
    }
}

impl Runner<'_> {
    /// Waits for the step just run: the condition its action declares, else the bar settling and a moment for the app.
    fn wait_for_step(&self, option: &RouteOption, said: &Spoken, pacing: &Pacing) -> WaitEnd {
        let integration = &self.rt.config.integrations[option.integration];
        let declared = integration
            .actions
            .get(&option.action)
            .and_then(|action| action.wait.as_ref());
        let settled_then_app = |end: WaitEnd| {
            if end == WaitEnd::Done {
                std::thread::sleep(pacing.app_settle);
            }
            end
        };
        match declared {
            None => settled_then_app(poll_until(pacing, bar::ui_settled)),
            Some(Wait::Builtin(name)) if name == "ui_settled" => settled_then_app(poll_until(pacing, bar::ui_settled)),
            Some(Wait::Builtin(name)) => poll_until(pacing, |time_left| {
                builtin_wait(name, option, said.active_before, time_left)
            }),
            Some(Wait::Hook(shell)) => {
                let timeout = integration
                    .actions
                    .get(&option.action)
                    .and_then(|action| action.timeout_secs)
                    .map_or(DEFAULT_TIMEOUT, Duration::from_secs_f64);
                poll_until(pacing, |time_left| {
                    let env = HookEnv {
                        integration,
                        action: &option.action,
                        args: &option.args,
                        phrase: said.phrase,
                        raw_transcript: said.raw_transcript,
                        id: Some(&option.id),
                        label: Some(&option.label),
                        confirmed: false,
                        active_before: Some(said.active_before),
                        spoken: false,
                    };
                    let mut command = self.rt.shell.command(shell, &env, false);
                    process::run_with_timeout(&mut command, timeout.min(time_left))
                        .is_ok_and(|outcome| outcome.code() == Some(0))
                })
            }
            Some(Wait::LegacyCondition(_)) => poll_until(pacing, |time_left| {
                let mut command = self.rt.legacy.call("wait", integration);
                command.arg(&option.action).envs(legacy_env(option, said, false));
                process::run_with_timeout(&mut command, time_left).is_ok_and(|outcome| outcome.code() == Some(0))
            }),
        }
    }

    /// Runs the steps in order, each routed only after the one before finished and what it started has settled. Fails
    /// (1) when no step ran, or the sequence is refused before any does.
    pub fn run_sequence(&self, split: &Steps, pacing: &Pacing) -> i32 {
        if let Some(why) = refusal(self.router, &split.steps) {
            self.rt
                .notifier
                .notify(Kind::Info, "voxcmd", &format!("Nothing ran: {why}"));
            return 1;
        }
        let _record = OwnRecord::create();
        let total = split.steps.len();
        let (mut ran, mut outcome, mut index) = (0, StepOutcome::Ran, 0);
        let (mut label, mut detail) = (String::new(), String::new());
        for step in &split.steps {
            index += 1;
            if sequence_stopped() {
                outcome = StepOutcome::Discarded;
                break;
            }
            debug(&format!("sequence: step {index} of {total}"));
            let active_before = hypr::active_window_address(ACTIVE_BEFORE_WITHIN);
            let result = self.run_step(step, true, &active_before);
            outcome = result.outcome;
            (label, detail) = (result.label.clone(), result.detail.clone());
            if outcome != StepOutcome::Ran {
                break;
            }
            ran += 1;
            let (Some(option), true) = (&result.ran, index < total) else {
                continue;
            };
            let said = Spoken {
                phrase: &result.phrase,
                raw_transcript: &result.raw_transcript,
                active_before: &active_before,
                in_sequence: true,
            };
            match self.wait_for_step(option, &said, pacing) {
                WaitEnd::Done => {}
                WaitEnd::TimedOut => {
                    outcome = StepOutcome::TimedOut;
                    break;
                }
                WaitEnd::Stopped => {
                    outcome = StepOutcome::Discarded;
                    break;
                }
            }
        }
        if outcome != StepOutcome::Ran {
            let stop = Stop {
                index,
                total,
                step: &split.steps[index.saturating_sub(1).min(total - 1)],
                free_text: split.free_text_step == Some(index),
                outcome,
                label: &label,
                detail: &detail,
            };
            self.report_stop(&stop, pacing);
        }
        // The sequence is over, whoever flagged it. A watcher's flag also discards its recording, and its exit removes it.
        if !self.rt.came_by_voice {
            let _ = std::fs::remove_file(paths::discard_flag(std::process::id()));
        }
        i32::from(ran == 0)
    }

    /// Tells why the sequence stopped. Silent after Stop Voice, which is its own answer.
    fn report_stop(&self, stop: &Stop, pacing: &Pacing) {
        let Stop {
            index,
            total,
            step,
            free_text,
            outcome,
            label,
            detail,
        } = *stop;
        let left = total - index;
        let more = match left {
            0 => String::new(),
            1 => "\n1 more step not run".to_string(),
            _ => format!("\n{left} more steps not run"),
        };
        let summary = format!("voxcmd: stopped at step {index} of {total}");
        if sequence_stopped() || outcome == StepOutcome::Discarded {
            debug(&format!(
                "sequence: ended without a toast at step {index} of {total} (stop or discard)"
            ));
            return;
        }
        debug(&format!("sequence: step {index} of {total} {}", outcome_name(outcome)));
        let named = if label.is_empty() {
            format!("step {index}")
        } else {
            label.to_string()
        };
        let notifier = self.rt.notifier;
        match outcome {
            StepOutcome::NoMatch if free_text => notifier.notify(Kind::NoMatch, &summary, &format!("no match{more}")),
            StepOutcome::NoMatch => notifier.notify(Kind::NoMatch, &summary, &format!("no match for \"{step}\"{more}")),
            StepOutcome::Declined => notifier.notify(
                Kind::Info,
                "voxcmd",
                &format!("Stopped at step {index} of {total}: not confirmed{more}"),
            ),
            StepOutcome::Cancelled => notifier.notify(
                Kind::Info,
                "voxcmd",
                &format!("Stopped at step {index} of {total}: cancelled{more}"),
            ),
            StepOutcome::TimedOut => notifier.notify(
                Kind::Error,
                &summary,
                &format!("{named}: timed out after {}s{more}", pacing.step_timeout_text),
            ),
            _ => {
                let why = if detail.is_empty() {
                    String::new()
                } else {
                    format!(": {detail}")
                };
                notifier.notify(Kind::Error, &summary, &format!("{named}{why}{more}"));
            }
        }
    }
}

/// Where and why a sequence stopped.
#[derive(Clone, Copy)]
struct Stop<'a> {
    index: usize,
    total: usize,
    step: &'a str,
    /// A free-text action took the rest of the phrase at this step.
    free_text: bool,
    outcome: StepOutcome,
    label: &'a str,
    detail: &'a str,
}

fn outcome_name(outcome: StepOutcome) -> &'static str {
    match outcome {
        StepOutcome::Ran => "ran",
        StepOutcome::NoMatch => "no_match",
        StepOutcome::Cancelled => "cancelled",
        StepOutcome::Declined => "declined",
        StepOutcome::Failed => "failed",
        StepOutcome::TimedOut => "timed_out",
        StepOutcome::Discarded => "discarded",
    }
}

/// The waits a TOML action can name instead of writing a condition.
fn builtin_wait(name: &str, option: &RouteOption, active_before: &str, time_left: Duration) -> bool {
    match name {
        "active_window_is_id" => hypr::active_window_address(time_left) == option.id,
        "active_window_changed" => {
            let active = hypr::active_window_address(time_left);
            !active.is_empty() && active != active_before
        }
        "window_gone" => !hypr::window_exists(&option.id, time_left),
        _ => match name.strip_prefix("popup_open:") {
            Some(popup) => bar::popup_is_open(popup, time_left),
            None => {
                // `integrations check` (2.6) rejects it; a run does not wait on a condition it cannot read.
                debug(&format!("sequence: unknown wait {name:?}, not waited for"));
                true
            }
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pacing_accepts_a_normal_value() {
        assert_eq!(pacing_duration("2.5", 1.0, 15.0), Duration::from_millis(2500));
        assert_eq!(pacing_duration("0", 1.0, 15.0), Duration::ZERO);
        assert_eq!(pacing_duration("2", 0.1, 0.1), Duration::from_millis(200));
    }

    #[test]
    fn pacing_falls_back_on_infinity_and_nan() {
        for bad in ["inf", "-inf", "infinity", "NaN", "nan", "abc"] {
            assert_eq!(pacing_duration(bad, 1.0, 15.0), Duration::from_secs(15), "{bad}");
        }
    }

    #[test]
    fn pacing_falls_back_on_a_huge_finite_value() {
        for bad in ["1e300", "1e20", "1.8e308"] {
            assert_eq!(pacing_duration(bad, 1.0, 0.3), Duration::from_millis(300), "{bad}");
        }
        // Small enough alone, too large once scaled by the factor.
        assert_eq!(pacing_duration("1e19", 10.0, 0.1), Duration::from_millis(100));
    }

    #[test]
    fn a_long_poll_interval_does_not_sleep_past_the_step_deadline() {
        let pacing = Pacing {
            step_timeout: Duration::from_millis(200),
            step_timeout_text: "0.2".to_string(),
            app_settle: Duration::ZERO,
            poll: Duration::from_secs(10),
        };
        let started = Instant::now();
        assert_eq!(poll_until(&pacing, |_| false), WaitEnd::TimedOut);
        assert!(started.elapsed() < Duration::from_secs(2), "{:?}", started.elapsed());
    }

    #[test]
    fn step_timeout_keeps_a_usable_value_and_its_text() {
        assert_eq!(step_timeout("2.5"), (Duration::from_millis(2500), "2.5".to_string()));
    }

    #[test]
    fn step_timeout_falls_back_with_the_default_text_when_unusable() {
        // 1e19 s is a valid Duration but past what Instant can add to now.
        for bad in ["NaN", "inf", "-3", "abc", "1e19", "1e300"] {
            assert_eq!(step_timeout(bad), (Duration::from_secs(15), "15".to_string()), "{bad}");
        }
    }

    #[test]
    fn pacing_falls_back_on_a_negative_value() {
        assert_eq!(pacing_duration("-1", 1.0, 15.0), Duration::from_secs(15));
        assert_eq!(pacing_duration("-0.5", 0.1, 0.1), Duration::from_millis(100));
    }
}
