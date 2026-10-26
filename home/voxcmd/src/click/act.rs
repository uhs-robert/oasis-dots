//! What the click integration does once an option is chosen: `click_at`.
//!
//! The suites grep the argv of the tools, so the toasts use `notify-send`'s long options and bare text (not the
//! `notify` module, which spawns `-a voxcmd`), and the pointer moves through `hyprctl dispatch`, because Hyprland's Lua
//! config has no movecursor dispatcher and wlrctl can only move the pointer relative to where it is. Every spawn goes
//! through `process`, so Stop Voice ends it.
use super::target_file;
use crate::config::schema::Builtin;
use crate::hypr;
use crate::process::{self, Outcome};
use serde_json::json;
use std::os::unix::process::ExitStatusExt;
use std::process::{Command, ExitStatus};

/// A built-in action as the synthetic process `run_option` reads its result from: exit 0, or 1 with the reason on
/// stdout. Fails only for a spawn refused because voxcmd is stopping, which `run_option` already knows not to report.
pub fn run(builtin: &Builtin, id: &str, spoken_target: &str) -> std::io::Result<Outcome> {
    let finished = match builtin {
        Builtin::ClickAt(_) => click_at(id, spoken_target)?.map(|()| String::new()),
    };
    Ok(as_process(finished))
}

fn as_process(finished: Reason<String>) -> Outcome {
    let (code, stdout) = match finished {
        Ok(output) => (0, output),
        // An empty reason prints nothing, like bash's silent failure, so the toast has no ": detail" tail.
        Err(reason) if reason.is_empty() => (1, String::new()),
        Err(reason) => (1, format!("{reason}\n")),
    };
    Outcome {
        status: Some(ExitStatus::from_raw(code << 8)),
        stdout,
        stderr: String::new(),
        timed_out: false,
    }
}

/// Err is why it failed, which is what the user's error toast says.
type Reason<T = ()> = Result<T, String>;

/// The outer error is a spawn refused while voxcmd stops; any other failure to start a tool is a reason like the
/// tool's own.
type Done<T = ()> = std::io::Result<Reason<T>>;

fn spawn(command: &mut Command) -> Done<Outcome> {
    match process::run_to_end(command) {
        Ok(outcome) => Ok(Ok(outcome)),
        Err(error) if process::refused_while_stopping(&error) => Err(error),
        Err(error) => Ok(Err(format!("{}: {error}", command.get_program().to_string_lossy()))),
    }
}

/// `tail -n 1` of what a command substitution made of the output.
fn last_line(text: &str) -> &str {
    text.trim_end_matches('\n').lines().next_back().unwrap_or("")
}

fn toast(text: &str) -> Done<Outcome> {
    spawn(
        Command::new("notify-send")
            .args(["--transient", "--app-name=voxcmd"])
            .arg(text),
    )
}

fn now_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |since| since.as_secs())
}

/// `id` is `x,y,button,left,top,width,height` in global logical coordinates; only the point and the button are used
/// here. A capture error (`error:<reason>`) is reported as that reason. A target covered by another window is said so
/// and not clicked, and so is a window that is no longer the one the point was read from.
pub fn click_at(id: &str, spoken_target: &str) -> Done {
    if let Some(reason) = id.strip_prefix("error:") {
        return Ok(Err(reason.to_string()));
    }
    if id.starts_with("covered:") {
        let _ = toast(&format!("\"{spoken_target}\" is covered by another window"))?;
        return Ok(Ok(()));
    }
    let unchanged = target_file::window_unchanged(|| hypr::active_window().unwrap_or_else(|| json!({})), now_secs());
    if !unchanged {
        let _ = toast("The window changed; say it again")?;
        return Ok(Ok(()));
    }
    // The raw text goes into the Lua call, as the shell put it.
    let mut fields = id.splitn(4, ',');
    let (x, y, button) = (
        fields.next().unwrap_or(""),
        fields.next().unwrap_or(""),
        fields.next().unwrap_or(""),
    );
    if let Err(reason) = move_pointer(x, y)? {
        return Ok(Err(reason));
    }
    click(button)
}

fn move_pointer(x: &str, y: &str) -> Done {
    let mut command = Command::new("hyprctl");
    command.args(["dispatch", &format!("hl.dsp.cursor.move({{x={x},y={y}}})")]);
    // bash's `$(...)` leaves hyprctl's stderr to the action's merged output, so it precedes the reason in the toast.
    let (moved, said) = match spawn(&mut command)? {
        Ok(outcome) if outcome.code() == Some(0) => (outcome.stdout.trim_end_matches('\n').to_string(), outcome.stderr),
        Ok(outcome) => ("hyprctl failed".to_string(), outcome.stderr),
        Err(_) => ("hyprctl failed".to_string(), String::new()),
    };
    Ok(pointer_moved(&moved, &said))
}

fn pointer_moved(moved: &str, said: &str) -> Reason {
    if moved == "ok" {
        Ok(())
    } else {
        Err(format!("{said}{}", last_line(moved)))
    }
}

/// wlrctl has no double or triple click, so those are two or three left clicks, stopping at the first failure.
fn click(button: &str) -> Done {
    let (name, times) = match button {
        "double" => ("left", 2),
        "triple" => ("left", 3),
        other => (other, 1),
    };
    let mut said = String::new();
    for _ in 0..times {
        let mut command = Command::new("wlrctl");
        command.args(["pointer", "click", name]);
        match spawn(&mut command)? {
            Ok(outcome) => {
                said.push_str(&outcome.stdout);
                said.push_str(&outcome.stderr);
                if outcome.code() != Some(0) {
                    return Ok(Err(last_line(&said).to_string()));
                }
            }
            Err(reason) => return Ok(Err(reason)),
        }
    }
    Ok(Ok(()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_failure_with_no_reason_prints_nothing() {
        let outcome = as_process(Err(String::new()));
        assert_eq!((outcome.code(), outcome.stdout.as_str()), (Some(1), ""));
        assert_eq!(as_process(Err("x".into())).stdout, "x\n");
    }

    #[test]
    fn hyprctls_stderr_comes_before_the_reason() {
        assert_eq!(pointer_moved("ok", "noise\n"), Ok(()));
        assert_eq!(
            pointer_moved("invalid dispatcher", "warn\n"),
            Err("warn\ninvalid dispatcher".to_string())
        );
    }
}
