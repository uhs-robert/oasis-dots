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
