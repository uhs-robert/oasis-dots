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

/// The checkout this binary was built from: where its shared scripts and the Python helpers live, so the live build
/// finds them whatever else is (or is not) installed in `~/.local/bin`.
const BUILT_FROM: &str = env!("CARGO_MANIFEST_DIR");

/// The directory of voxcmd's shared scripts (`spoken-time.sh` and the like), which hooks find as `$VOXCMD_SHARE_DIR`.
pub fn share_dir() -> PathBuf {
    share_dir_from(env_dir("VOXCMD_SHARE_DIR"), env_dir("VOXCMD_LEGACY_BIN"))
}

/// `share_override`, else `share/voxcmd` beside the `bin` of `legacy_override`, else the built-from checkout's. The
/// suites set `VOXCMD_LEGACY_BIN` to a stand-in so its neighbours are found; nothing live does, so nothing live needs
/// the bash script to exist.
fn share_dir_from(share_override: Option<PathBuf>, legacy_override: Option<PathBuf>) -> PathBuf {
    share_override.unwrap_or_else(|| match legacy_override {
        Some(bin) => bin
            .parent()
            .and_then(std::path::Path::parent)
            .unwrap_or(std::path::Path::new("/"))
            .join("share/voxcmd"),
        None => PathBuf::from(BUILT_FROM).join(".local/share/voxcmd"),
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

/// A sound the Quickshell config ships, such as `alarm.ogg`.
pub fn bar_sound(name: &str) -> PathBuf {
    env_dir("XDG_CONFIG_HOME")
        .unwrap_or_else(|| home().join(".config"))
        .join("quickshell/sounds")
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

/// The speech detector that ends a recording after a pause (Python until voxcmd-port 4.2).
pub fn autostop() -> PathBuf {
    autostop_from(env_dir("VOXCMD_LEGACY_BIN"))
}

/// Beside `legacy_override` (the suites' stand-in), else in the built-from checkout.
fn autostop_from(legacy_override: Option<PathBuf>) -> PathBuf {
    match legacy_override {
        Some(bin) => bin
            .parent()
            .unwrap_or(std::path::Path::new("/"))
            .join("voxcmd-autostop"),
        None => PathBuf::from(BUILT_FROM).join(".local/bin/voxcmd-autostop"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn share_dir_and_autostop_come_from_the_checkout_not_the_bash_script() {
        let root = PathBuf::from(BUILT_FROM);
        assert_eq!(share_dir_from(None, None), root.join(".local/share/voxcmd"));
        assert_eq!(autostop_from(None), root.join(".local/bin/voxcmd-autostop"));
    }

    #[test]
    fn a_stand_in_legacy_bin_still_places_its_neighbours() {
        let legacy = Some(PathBuf::from("/copy/.local/bin/voxcmd"));
        assert_eq!(
            share_dir_from(None, legacy.clone()),
            PathBuf::from("/copy/.local/share/voxcmd")
        );
        assert_eq!(autostop_from(legacy), PathBuf::from("/copy/.local/bin/voxcmd-autostop"));
    }

    #[test]
    fn an_explicit_share_dir_wins() {
        assert_eq!(
            share_dir_from(
                Some(PathBuf::from("/share")),
                Some(PathBuf::from("/copy/.local/bin/voxcmd"))
            ),
            PathBuf::from("/share")
        );
    }
}
