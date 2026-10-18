//! `voxcmd internal session begin|leave|end|end-all|state|end-if-mine`: the Rust session as the bash integrations
//! reach it (deleted in voxcmd-port 3.2 with the bash voxcmd)
//!
//! A bash action runs in a `_legacy-hook` child, where `$$` is that child, not the Rust process that ran it. The child
//! gets `hook_env`, and the bash voxcmd's `legacy_session_shims` then send `session_begin`, `session_leave`,
//! `session_end`, `session_end_all` and `session_state` here and map `discard_flag_of $$` to `$VOXCMD_LEGACY_PID`,
//! which these subcommands also take as "mine".
use super::{SessionLock, turn};
use crate::ask;
use crate::exit::CliError;
use std::process::Command;

/// What a bash hook needs to reach this process's session: who "this process" is, the mode the turn was heard in
/// (bash `$heard_mode`), and this binary.
pub fn hook_env(heard_mode: &str) -> [(&'static str, String); 3] {
    [
        ("VOXCMD_LEGACY_PID", std::process::id().to_string()),
        ("VOXCMD_LEGACY_HEARD_MODE", heard_mode.to_string()),
        ("VOXCMD_LEGACY_RS_BIN", ask::this_binary().display().to_string()),
    ]
}

/// The variables a bash action or hook was run with, which a process it starts must not take as its own: a watcher a
/// shim's listen leaves behind is its own process, owned by nobody's `VOXCMD_LEGACY_PID`.
pub fn clear_hook_env(command: &mut Command) {
    for name in [
        "VOXCMD_LEGACY_PID",
        "VOXCMD_LEGACY_HEARD_MODE",
        "VOXCMD_LEGACY_RS_BIN",
        "VOXCMD_LEGACY_ID",
        "VOXCMD_LEGACY_TARGET",
        "VOXCMD_LEGACY_CONFIRMED",
        "VOXCMD_LEGACY_RAW_TRANSCRIPT",
        "VOXCMD_LEGACY_ACTIVE_BEFORE",
    ] {
        command.env_remove(name);
    }
}

/// The process the session calls are made for: the one that ran the bash hook, else this one.
fn caller() -> u32 {
    std::env::var("VOXCMD_LEGACY_PID")
        .ok()
        .and_then(|pid| pid.parse().ok())
        .unwrap_or_else(std::process::id)
}

const USAGE: &str = "usage: begin <kind> <file> <label> | leave <kind> [reason] | end [reason] | end-all [reason] | \
                     state | end-if-mine <pid> <reason>";

pub fn run(args: &[String]) -> Result<Option<String>, CliError> {
    let me = caller();
    let arg = |index: usize| args.get(index).map_or("", String::as_str);
    match arg(0) {
        "begin" if args.len() == 4 => turn::begin(arg(1), arg(2), arg(3), me),
        "leave" if args.len() >= 2 => {
            if !super::leave(&SessionLock::take(), arg(1), arg(2), me) {
                return Err(CliError::quiet("internal session"));
            }
        }
        "end" => super::end_top(&SessionLock::take(), arg(1), me),
        "end-all" => super::end_all(arg(1), me),
        "state" => {
            return super::read_state()
                .map(|state| Some(state.to_string()))
                .ok_or_else(|| CliError::quiet("internal session"));
        }
        // A watcher that a stop signal ends runs this as its last act (`process::run_on_stop`), as the bash EXIT trap
        // ran `session_end_if_mine`.
        "end-if-mine" if args.len() == 3 => {
            let pid = arg(1).parse().map_err(|_| CliError::usage("internal session", USAGE))?;
            super::end_if_mine(arg(2), pid);
        }
        _ => return Err(CliError::usage("internal session", USAGE)),
    }
    Ok(None)
}
