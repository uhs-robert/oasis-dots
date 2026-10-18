//! every file path voxcmd reads or writes (config, runtime, state, share), each from one fn
use std::path::PathBuf;

/// An environment variable, with empty counting as unset as `${VAR:-default}` does in the bash voxcmd.
fn env_dir(name: &str) -> Option<PathBuf> {
    std::env::var_os(name)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

fn home() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
}

/// `$VOXCMD_CONFIG_DIR`, else `$XDG_CONFIG_HOME/voxcmd`, else `~/.config/voxcmd`.
pub fn config_dir() -> PathBuf {
    env_dir("VOXCMD_CONFIG_DIR").unwrap_or_else(|| {
        env_dir("XDG_CONFIG_HOME")
            .unwrap_or_else(|| home().join(".config"))
            .join("voxcmd")
    })
}

/// `$XDG_CACHE_HOME/voxcmd`, else `~/.cache/voxcmd`. Only derived data lives here; deleting it costs one rebuild.
pub fn cache_dir() -> PathBuf {
    env_dir("XDG_CACHE_HOME")
        .unwrap_or_else(|| home().join(".cache"))
        .join("voxcmd")
}

/// The bash voxcmd that `_legacy-dump` runs from, until 3.2 deletes it: `$VOXCMD_LEGACY_BIN`, else the one in the
/// checkout this binary was built from, which is the copy stow links into `~/.local/bin`.
pub fn legacy_bin() -> PathBuf {
    env_dir("VOXCMD_LEGACY_BIN")
        .unwrap_or_else(|| PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/.local/bin/voxcmd")))
}

/// A file of `_legacy-dump` output read in place of running bash: tests and benchmarks set it so they need no bash.
pub fn legacy_dump_override() -> Option<PathBuf> {
    env_dir("VOXCMD_LEGACY_DUMP_FILE")
}

/// `$XDG_RUNTIME_DIR`, else `/tmp`: where voxcmd's own directory and the asks' private ones live.
pub fn user_runtime_dir() -> PathBuf {
    env_dir("XDG_RUNTIME_DIR").unwrap_or_else(|| PathBuf::from("/tmp"))
}

/// `$XDG_RUNTIME_DIR/voxcmd`, else `/tmp/voxcmd`: sockets, state files the bar reads, pending picks.
pub fn runtime_dir() -> PathBuf {
    user_runtime_dir().join("voxcmd")
}

/// The open picker, confirm card or hints overlay that a spoken reply can answer.
pub fn pending_pick() -> PathBuf {
    runtime_dir().join("pending-pick.json")
}

/// voxtype's `idle`/`recording`/`transcribing`, rewritten on every transition.
pub fn voxtype_state() -> PathBuf {
    user_runtime_dir().join("voxtype/state")
}

/// The directory of voxcmd's shared scripts (`spoken-time.sh` and the like), which hooks find as `$VOXCMD_SHARE_DIR`:
/// `$VOXCMD_SHARE_DIR`, else `share/voxcmd` beside the `bin` of the legacy voxcmd, as the bash script finds it.
pub fn share_dir() -> PathBuf {
    env_dir("VOXCMD_SHARE_DIR").unwrap_or_else(|| {
        legacy_bin()
            .parent()
            .and_then(std::path::Path::parent)
            .unwrap_or(std::path::Path::new("/"))
            .join("share/voxcmd")
    })
}

/// `$XDG_STATE_HOME/voxcmd`, else `~/.local/state/voxcmd`: what is kept between runs (the no-match log).
pub fn state_dir() -> PathBuf {
    env_dir("XDG_STATE_HOME")
        .unwrap_or_else(|| home().join(".local/state"))
        .join("voxcmd")
}

pub fn no_match_log() -> PathBuf {
    state_dir().join("no-match.log")
}

/// One `<pid>.json` per running sequence, so Stop Voice reaches all of them.
pub fn sequence_dir() -> PathBuf {
    runtime_dir().join("sequences")
}

/// Present when Stop Voice has flagged the sequence the process runs.
pub fn discard_flag(pid: u32) -> PathBuf {
    runtime_dir().join(format!("discard.{pid}"))
}

/// The trace of listening, routing and replies that the suites read; written while the file exists or `VOXCMD_DEBUG`
/// is set.
pub fn debug_log() -> PathBuf {
    runtime_dir().join("debug.log")
}

/// A script of Hyprland's config that talks to the bar: `qs-ipc`, `qs-picker`.
pub fn hypr_script(name: &str) -> PathBuf {
    env_dir("XDG_CONFIG_HOME")
        .unwrap_or_else(|| home().join(".config"))
        .join("hypr/scripts")
        .join(name)
}

/// The bar's command line, which `qs-ipc call ...` talks to.
pub fn qs_ipc() -> PathBuf {
    hypr_script("qs-ipc")
}

/// The open voice session (`session/`), which the bar reads too.
pub fn session_file() -> PathBuf {
    runtime_dir().join("session.json")
}

/// The flock target for every change to the session file, shared with the bash voxcmd.
pub fn session_lock() -> PathBuf {
    runtime_dir().join("session.lock")
}

/// Where voxtype writes a recording's transcript for the watcher (`voxtype record start --file`).
pub fn transcript() -> PathBuf {
    runtime_dir().join("transcript.txt")
}

/// The auto threshold the detector of the watcher with this pid measured, where the room was quiet.
pub fn threshold_file(pid: u32) -> PathBuf {
    runtime_dir().join(format!("threshold.{pid}"))
}

/// The speech detector that ends a recording after a pause (Python until voxcmd-port 4.2), beside the bash voxcmd.
pub fn autostop() -> PathBuf {
    legacy_bin()
        .parent()
        .unwrap_or(std::path::Path::new("/"))
        .join("voxcmd-autostop")
}
