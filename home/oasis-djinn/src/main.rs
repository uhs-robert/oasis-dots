//! oasis-djinn <id> [param...]: perform one action of the manifest from the logged-in desktop session.
//!
//! Exit 0 when the performer ran, 1 when it failed or could not start, 2 on an unknown id, a bad param or an
//! unreadable manifest, in which case nothing runs. Bar actions call the bar through hypr's qs-ipc; `lua` actions
//! run inside Hyprland through `hyprctl eval`, which exits non-zero when the Lua raises.

use std::path::PathBuf;
use std::process::ExitCode;

use oasis_djinn::{Manifest, Tools, config_dir, perform};

const QS_IPC: &str = ".config/hypr/scripts/qs-ipc";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some((id, words)) = args.split_first().filter(|(id, _)| !id.starts_with('-')) else {
        eprintln!("usage: oasis-djinn <id> [param...]");
        return ExitCode::from(2);
    };
    let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
    let qs_ipc = std::env::var_os("OASIS_DJINN_QS_IPC")
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(QS_IPC));
    let hyprctl = std::env::var_os("OASIS_DJINN_HYPRCTL")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("hyprctl"));
    let tools = Tools {
        qs_ipc: &qs_ipc,
        hyprctl: &hyprctl,
        home: &home,
    };
    let planned =
        Manifest::load(&config_dir()).and_then(|manifest| Ok((manifest.plan(id, words, &tools)?, manifest.is_lua(id))));
    let (argv, is_lua) = match planned {
        Ok(planned) => planned,
        Err(error) => {
            eprintln!("oasis-djinn: {error}");
            return ExitCode::from(2);
        }
    };
    match perform(&argv, is_lua) {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::from(1),
        Err(error) => {
            eprintln!("oasis-djinn: cannot run {}: {error}", argv[0]);
            ExitCode::from(1)
        }
    }
}
