//! desktop toasts through `notify-send`, and where they go instead when voxcmd is only explaining
//!
//! `VOXCMD_DRY_RUN=1` (set by `explain` for the hooks it runs, and honoured by `util notify` for hooks that toast)
//! sends every toast to stderr as `summary: body`, as the bash `--dry-run` does.
use crate::exit::CliError;
use std::process::{Command, Stdio};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Info,
    /// Stays in the notification history; an info toast is transient.
    Error,
    /// An info toast with a Voice Help button.
    NoMatch,
}

impl Kind {
    pub fn parse(level: &str) -> Option<Self> {
        match level {
            "info" => Some(Self::Info),
            "error" => Some(Self::Error),
            "no-match" => Some(Self::NoMatch),
            _ => None,
        }
    }
}

pub fn dry_run() -> bool {
    std::env::var("VOXCMD_DRY_RUN").is_ok_and(|value| value == "1")
}

fn notify_send_available() -> bool {
    std::env::var_os("PATH")
        .is_some_and(|path| std::env::split_paths(&path).any(|dir| dir.join("notify-send").is_file()))
}

pub fn notify(kind: Kind, summary: &str, body: &str) {
    if kind == Kind::NoMatch {
        return notify_no_match(summary, body);
    }
    if dry_run() || !notify_send_available() {
        eprintln!("{summary}: {body}");
        return;
    }
    let mut command = Command::new("notify-send");
    command.args(["-a", "voxcmd"]);
    if kind == Kind::Info {
        command.arg("--transient");
    }
    let _ = command
        .args([summary, body])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

/// The toast carries a Voice Help button. notify-send waits for the toast to close to report a clicked action, so a
/// detached waiter holds it instead of voxcmd.
fn notify_no_match(summary: &str, body: &str) {
    if dry_run() || !notify_send_available() {
        return notify(Kind::Info, summary, body);
    }
    // Text goes in as positional parameters of the inner sh, never into its script.
    let script =
        r#"[ "$(notify-send -a voxcmd --transient --action=help="Voice Help" "$1" "$2")" = help ] && exec "$3" help"#;
    let exe = std::env::current_exe().unwrap_or_else(|_| "voxcmd".into());
    let spawned = Command::new("setsid")
        .args(["sh", "-c", script, "sh", summary, body])
        .arg(exe)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
    if let Ok(mut waiter) = spawned {
        // Reaps the waiter when the toast closes, if this process lives that long.
        std::thread::spawn(move || {
            let _ = waiter.wait();
        });
    }
}

/// `voxcmd util notify <level> <title> <body>`.
pub fn run(level: &str, title: &str, body: &str) -> Result<(), CliError> {
    let kind = Kind::parse(level).ok_or_else(|| {
        CliError::usage(
            "util notify",
            format!("level must be info, error or no-match, not {level:?}"),
        )
    })?;
    notify(kind, title, body);
    Ok(())
}
