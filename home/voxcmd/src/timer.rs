//! `voxcmd timer ring <summary> <body>`: rings a timer or reminder; run by its systemd unit, not by hand (was `voxcmd-alarm`)
//!
//! A critical notification stays up and goes to the bar's history; the alarm sound plays up to `VOXCMD_ALARM_RINGS` (3)
//! times, `VOXCMD_ALARM_GAP` (5) seconds apart, stopping once the notification is closed. The sound is the bar's style
//! alarm whatever Theme audio's notification switch says; without the bar, the shipped default through pw-play or paplay.
use crate::exit::CliError;
use crate::paths;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::Duration;

/// Not shipped here; sound-theme-freedesktop's, for a machine without the Quickshell config.
const SYSTEM_ALARM: &str = "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga";

pub fn ring(summary: &str, body: &str) -> Result<(), CliError> {
    let rings: u32 = setting("VOXCMD_ALARM_RINGS", 3);
    let gap = Duration::try_from_secs_f64(setting("VOXCMD_ALARM_GAP", 5.0)).unwrap_or(Duration::ZERO);

    // --wait holds notify-send until the notification closes: dismissed, cleared, or acted on. Hiding the toast keeps
    // it in history, so it keeps ringing until the rings run out.
    let mut notification = Command::new("notify-send")
        .args(["--wait", "--urgency=critical", "--app-name=voxcmd", summary, body])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .ok();
    let mut players = Vec::new();

    for ring_count in 1..=rings {
        players.extend(play_alarm());
        if ring_count == rings {
            break;
        }
        std::thread::sleep(gap);
        if notification
            .as_mut()
            .is_none_or(|child| child.try_wait().ok().flatten().is_some())
        {
            break;
        }
    }

    // SIGTERM, as the bash `kill`: it leaves a notification still up in the bar's history.
    if let Some(mut child) = notification {
        if child.try_wait().ok().flatten().is_none() {
            // SAFETY: signalling a child this function spawned and has not yet reaped.
            unsafe { libc::kill(child.id() as libc::pid_t, libc::SIGTERM) };
        }
        let _ = child.wait();
    }
    // The sound plays out before the unit finishes.
    for mut player in players {
        let _ = player.wait();
    }
    Ok(())
}

/// A setting from the environment; empty, unset or unreadable takes the default.
fn setting<T: std::str::FromStr>(name: &str, default: T) -> T {
    std::env::var(name)
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(default)
}

/// Plays the alarm once: through the bar when it answers, else a file through the first player there is. The player,
/// when one was started, is returned to be waited for.
fn play_alarm() -> Option<Child> {
    if bar_played_alarm() {
        return None;
    }
    let default_alarm = paths::bar_sound("alarm.ogg");
    let file = [default_alarm, PathBuf::from(SYSTEM_ALARM)]
        .into_iter()
        .find(|file| file.is_file())?;
    let player = ["pw-play", "paplay"].into_iter().find(|player| on_path(player))?;
    Command::new(player).arg(&file).stdin(Stdio::null()).spawn().ok()
}

/// qs ipc exits 0 even when no bar answers, so the reply is what tells.
fn bar_played_alarm() -> bool {
    let qs_ipc = paths::qs_ipc();
    let executable =
        std::fs::metadata(&qs_ipc).is_ok_and(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0);
    executable
        && Command::new(qs_ipc)
            .args(["call", "sound", "play", "alarm"])
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .output()
            .is_ok_and(|output| String::from_utf8_lossy(&output.stdout).trim_end_matches('\n') == "ok")
}

fn on_path(program: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|path| std::env::split_paths(&path).any(|dir| dir.join(program).is_file()))
}
