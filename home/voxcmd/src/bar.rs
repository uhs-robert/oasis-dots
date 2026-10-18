//! asking the Quickshell bar what it is showing, for the waits between the steps of a sequence and between a session's
//! turns (`internal settle`)
//!
//! Every question is bounded by two seconds and by the time the step has left, and a bar that does not answer reads as closed (or as having nothing to
//! wait for): a stalled bar must not hold a sequence past its own step timeout.
use crate::paths;
use crate::process;
use std::process::Command;
use std::time::{Duration, Instant};

const ANSWER_WITHIN: Duration = Duration::from_secs(2);

/// What `qs-ipc call <args>` printed, without its trailing newlines; none when it failed or did not answer.
fn ask(args: &[&str], within: Duration) -> Option<String> {
    let mut command = Command::new(paths::qs_ipc());
    command.arg("call").args(args);
    let outcome = process::run_with_timeout(&mut command, within.min(ANSWER_WITHIN)).ok()?;
    (outcome.code() == Some(0)).then(|| outcome.stdout.trim_end_matches('\n').to_string())
}

/// Nothing animates and no overlay waits on the user. A popup that stays open is not busy.
pub fn ui_settled(time_left: Duration) -> bool {
    let started = Instant::now();
    let overlay = ask(&["clickhints", "state"], time_left).unwrap_or_else(|| "closed".to_string());
    let popup =
        ask(&["popup", "state"], time_left.saturating_sub(started.elapsed())).unwrap_or_else(|| "closed".to_string());
    let animating = ["opening", "closing"]
        .iter()
        .any(|state| popup == *state || popup.starts_with(&format!("{state} ")));
    overlay != "open" && !animating
}

/// The named popup is fully drawn. No bar to ask counts as done: there is nothing to wait for.
pub fn popup_is_open(name: &str, time_left: Duration) -> bool {
    ask(&["popup", "state"], time_left).is_none_or(|state| state == format!("open {name}"))
}

/// The overlay is open or a popup is opening, open or closing: the screen is not yet the one the next turn should read.
/// Unlike `ui_settled`, a popup that stays open counts as busy.
pub fn ui_busy() -> bool {
    let overlay = ask(&["clickhints", "state"], ANSWER_WITHIN).unwrap_or_else(|| "closed".to_string());
    let popup = ask(&["popup", "state"], ANSWER_WITHIN).unwrap_or_else(|| "closed".to_string());
    let showing = ["opening", "open", "closing"]
        .iter()
        .any(|state| popup == *state || popup.starts_with(&format!("{state} ")));
    overlay == "open" || showing
}
