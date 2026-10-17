//! the debug log, `HH:MM:SS.mmm voxcmd[pid] message` lines that the test suites grep and people read
//!
//! On while the log file exists or `VOXCMD_DEBUG` is set, so a user turns it on with `touch`.
use crate::paths;
use std::io::Write;

fn enabled() -> bool {
    std::env::var_os("VOXCMD_DEBUG").is_some_and(|value| !value.is_empty()) || paths::debug_log().exists()
}

pub fn debug(message: &str) {
    if !enabled() {
        return;
    }
    let path = paths::debug_log();
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(path) else {
        return;
    };
    let time = jiff::Zoned::now().strftime("%H:%M:%S.%3f");
    let _ = writeln!(file, "{time} voxcmd[{}] {message}", std::process::id());
}
