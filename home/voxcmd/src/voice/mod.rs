//! the voice key's loop: starting a recording (`listen`), the watcher that hands its transcript on (`internal
//! watch`), Stop Voice (`stop`), the wait for the screen to settle between turns (`internal settle`), the wake
//! listener's confirmation of a trigger (`internal wake-confirm`) and the stopper a chained dictation ending leaves
//! (`internal chain-stop`)
//!
//! voxtype records and transcribes; voxcmd only reads its state file and calls `voxtype record start|stop|cancel`.
pub mod chain_stop;
pub mod listen;
pub mod settle;
pub mod stop;
pub mod wake_confirm;
pub mod watch;

use crate::paths;
use std::process::Command;
use std::time::Duration;

/// voxtype's state, `idle`, `recording` or `transcribing`, as `cat` would print it; "" while voxtype rewrites the file,
/// and `idle` when there is no file.
pub fn voxtype_state() -> String {
    std::fs::read(paths::voxtype_state()).map_or_else(
        |_| "idle".to_string(),
        |bytes| String::from_utf8_lossy(&bytes).trim_end_matches('\n').to_string(),
    )
}

/// When voxtype last wrote its state file: it rewrites it on every transition and only then, so a new mark means a new
/// transition. Read before the state, a write landing in between makes the mark look older than the state, never newer.
pub fn voxtype_write_mark() -> Option<(i64, i64)> {
    use std::os::unix::fs::MetadataExt;
    std::fs::metadata(paths::voxtype_state())
        .ok()
        .map(|meta| (meta.mtime(), meta.mtime_nsec()))
}

/// `voxtype record <action> [args]`; whether it succeeded.
pub fn voxtype_record(action: &str, args: &[&str]) -> bool {
    Command::new("voxtype")
        .args(["record", action])
        .args(args)
        .status()
        .is_ok_and(|status| status.success())
}

/// `secs` times `VOXCMD_TIME_SCALE` (the suites' 0.1 makes fixed polls ten times as frequent), as bash `scaled_secs`.
pub fn time_scaled(secs: f64) -> Duration {
    let scale = std::env::var("VOXCMD_TIME_SCALE")
        .ok()
        .and_then(|scale| scale.parse::<f64>().ok())
        .unwrap_or(1.0);
    Duration::try_from_secs_f64(secs * scale).unwrap_or_else(|_| Duration::from_secs_f64(secs))
}

/// A setting in seconds from the environment, with empty or unset taking the default.
pub fn secs_setting(name: &str, default: &str) -> String {
    std::env::var(name)
        .ok()
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| default.to_string())
}
