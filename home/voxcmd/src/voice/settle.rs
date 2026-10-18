//! `voxcmd internal settle`: waits, up to `VOXCMD_UI_SETTLE_MAX_SECS`, until neither the click overlay nor a popup is
//! open or animating, then gives the app the user acted on `VOXCMD_APP_SETTLE_SECS` to draw its result, so the next
//! turn's screen read sees it (was `wait_until_ui_settled`). Exit 1 when the screen never settled.
use super::{secs_setting, time_scaled};
use crate::ask;
use crate::bar;
use crate::exit::CliError;
use crate::paths;
use std::time::{Duration, Instant};

pub fn run() -> Result<(), CliError> {
    let max_wait = seconds(&secs_setting("VOXCMD_UI_SETTLE_MAX_SECS", "2"));
    let app_settle = seconds(&secs_setting("VOXCMD_APP_SETTLE_SECS", "0.3"));
    let poll = time_scaled(0.1);
    let mut timed_out = false;
    // No bar to ask counts as settled.
    if ask::is_executable(&paths::qs_ipc()) {
        let deadline = Instant::now() + max_wait;
        while bar::ui_busy() {
            if Instant::now() >= deadline {
                timed_out = true;
                break;
            }
            std::thread::sleep(poll);
        }
    }
    std::thread::sleep(app_settle);
    if timed_out {
        Err(CliError::quiet("internal settle"))
    } else {
        Ok(())
    }
}

/// A setting in seconds; one that is not a usable number is none, as the bash `awk` and `sleep` read it.
fn seconds(value: &str) -> Duration {
    value
        .parse::<f64>()
        .ok()
        .and_then(|secs| Duration::try_from_secs_f64(secs).ok())
        .filter(|wait| Instant::now().checked_add(*wait).is_some())
        .unwrap_or_default()
}
