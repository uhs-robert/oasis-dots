//! `voxcmd wake on|off|toggle|status`: start or stop the wake word listener (voxcmd-wake.service) for this login
//!
//! The unit is never enabled, so it is off after a login until switched on; the microphone is held only while it runs.
use crate::exit::CliError;
use crate::notify::{self, Kind};
use std::process::{Command, Stdio};

const UNIT: &str = "voxcmd-wake.service";
const SUBCOMMAND: &str = "wake";

pub enum Switch {
    On,
    Off,
    Toggle,
    Status,
}

pub fn run(switch: Switch) -> Result<Option<String>, CliError> {
    match switch {
        Switch::On => switch_on().map(|()| None),
        Switch::Off => switch_off().map(|()| None),
        Switch::Toggle if is_on() => switch_off().map(|()| None),
        Switch::Toggle => switch_on().map(|()| None),
        Switch::Status if is_on() => Ok(Some("on".to_string())),
        Switch::Status => {
            println!("off");
            Err(CliError::quiet(SUBCOMMAND))
        }
    }
}

/// Whether `systemctl --user <args>` succeeded, and what it printed.
fn systemctl(args: &[&str]) -> (bool, String) {
    let output = Command::new("systemctl")
        .arg("--user")
        .args(args)
        .stdin(Stdio::null())
        .stderr(Stdio::inherit())
        .output();
    match output {
        Ok(output) => (
            output.status.success(),
            String::from_utf8_lossy(&output.stdout).into_owned(),
        ),
        Err(_) => (false, String::new()),
    }
}

/// `activating` counts: the first start downloads the models before the listener runs.
fn is_on() -> bool {
    matches!(
        systemctl(&["is-active", UNIT]).1.trim_end_matches('\n'),
        "active" | "activating" | "reloading"
    )
}

fn switch_on() -> Result<(), CliError> {
    if is_on() {
        notify::notify(Kind::Info, "Wake word", "Already on");
        return Ok(());
    }
    // --no-block: the first start waits on the model download.
    if !systemctl(&["start", "--no-block", UNIT]).0 {
        notify::notify(Kind::Info, "Wake word", &format!("Could not start {UNIT}"));
        return Err(CliError::quiet(SUBCOMMAND));
    }
    notify::notify(Kind::Info, "Wake word on", "Say \"Cortana\"");
    Ok(())
}

/// Says the microphone is released only once the unit has stopped: a failed stop leaves the listener holding it.
fn switch_off() -> Result<(), CliError> {
    if !systemctl(&["stop", UNIT]).0 || is_on() {
        notify::notify(
            Kind::Info,
            "Wake word",
            &format!("Could not stop {UNIT}; the microphone may still be in use"),
        );
        return Err(CliError::quiet(SUBCOMMAND));
    }
    notify::notify(Kind::Info, "Wake word off", "Microphone released");
    Ok(())
}
