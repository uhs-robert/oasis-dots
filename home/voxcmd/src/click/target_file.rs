//! `click-target`: the window the OCR coordinates belong to, for the click that follows. A picker can wait seconds
//! before the click, and by then another window, or this one moved, may sit under the point.
use serde_json::{Value, json};
use std::io::Write;
use std::os::unix::fs::DirBuilderExt;
use std::path::PathBuf;

fn runtime_dir() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .filter(|dir| !dir.is_empty())
        .map_or_else(|| "/tmp".into(), PathBuf::from)
}

/// Written whole to a file of the process's own, then renamed into place, so a reader never sees half of it.
pub fn write(window: &Value) -> std::io::Result<()> {
    let dir = runtime_dir().join("voxcmd");
    std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&dir)?;
    let captured_at = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |since| since.as_secs());
    let staged = dir.join(format!("click-target.{}", std::process::id()));
    let mut file = std::fs::File::create(&staged)?;
    writeln!(file, "{}", json!({"captured_at": captured_at, "window": window}))?;
    std::fs::rename(&staged, dir.join("click-target"))
}
