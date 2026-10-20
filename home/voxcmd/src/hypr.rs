//! asking Hyprland about windows, for the waits between the steps of a sequence
//!
//! Bounded by two seconds and by the step's time left, like the bar's questions, since waits poll these and cannot interrupt one that hangs on a
//! stalled compositor.
use crate::process;
use serde_json::Value;
use std::process::Command;
use std::time::Duration;

const ANSWER_WITHIN: Duration = Duration::from_secs(2);

fn query(what: &str, within: Duration) -> Option<Value> {
    let mut command = Command::new("hyprctl");
    command.args([what, "-j"]);
    let outcome = process::run_with_timeout(&mut command, within.min(ANSWER_WITHIN)).ok()?;
    serde_json::from_str(&outcome.stdout).ok()
}

/// The focused window's address, empty when none has focus or Hyprland did not answer.
pub fn active_window_address(within: Duration) -> String {
    query("activewindow", within)
        .and_then(|window| window.get("address").and_then(Value::as_str).map(str::to_string))
        .unwrap_or_default()
}

/// Whether a window with the address is open. Hyprland not answering reads as no.
pub fn window_exists(address: &str, within: Duration) -> bool {
    query("clients", within)
        .and_then(|clients| clients.as_array().cloned())
        .is_some_and(|clients| {
            clients
                .iter()
                .any(|client| client.get("address").and_then(Value::as_str) == Some(address))
        })
}

/// The focused window's object as hyprctl prints it, None when none has focus or Hyprland did not answer.
pub fn active_window() -> Option<Value> {
    query("activewindow", ANSWER_WITHIN).filter(|window| window.get("at").is_some())
}

/// Every client, None when Hyprland did not answer with a list.
pub fn clients() -> Option<Value> {
    query("clients", ANSWER_WITHIN).filter(Value::is_array)
}

/// Every monitor, None when Hyprland did not answer with a list.
pub fn monitors() -> Option<Value> {
    query("monitors", ANSWER_WITHIN).filter(Value::is_array)
}

/// The client with this stableId, None when it is gone or Hyprland did not answer.
pub fn window_by_stable_id(stable_id: &str) -> Option<Value> {
    query("clients", ANSWER_WITHIN)?
        .as_array()?
        .iter()
        .find(|client| client.get("stableId").and_then(Value::as_str) == Some(stable_id))
        .cloned()
}
