//! `voxcmd ask confirm [--listen] [--verb <verb>] <question>`: a yes/no question (was `voxcmd-confirm`)
//!
//! Exits 0 for yes, 1 for no, cancel or no answer. Uses the bar's confirm card, else rofi with Yes and No. With
//! `--listen` the reply's recording starts just before the card shows, and an unclear reply listens once more.
use super::{
    Asking, PendingPick, PickChoice, StopSignals, Stopped, is_executable, qs_ipc_call, shell_quote,
    terminate_with_children,
};
use crate::debug::debug;
use crate::exit::CliError;
use crate::paths;
use std::process::{Command, Stdio};

/// rofi has no timeout of its own, so it gets the card's, which cancels itself after 10 seconds without an answer.
const ROFI_TIMEOUT: &str = "10";

/// `voxcmd ask confirm`.
pub fn run(listen: bool, verb: Option<&str>, question: &str) -> Result<(), CliError> {
    let signals = StopSignals::hold();
    let mut asking = Asking::create("confirm")?;
    match ask(&mut asking, &signals, listen, verb.unwrap_or_default(), question) {
        Ok(Ok(answer)) if answer.to_lowercase() == "yes" => Ok(()),
        Ok(Err(error)) => Err(error),
        _ => Err(CliError::quiet("ask confirm")),
    }
}

fn ask(
    asking: &mut Asking,
    signals: &StopSignals,
    listen: bool,
    verb: &str,
    question: &str,
) -> Result<Result<String, CliError>, Stopped> {
    // Present while one more listen is left after an unclear reply; a reply removes it when it listens again.
    let listen_again = asking.dir.join("listen-again");
    let choice = |id: &str, label: &str| PickChoice {
        id: id.to_string(),
        label: label.to_string(),
        expand: None,
        r#box: None,
    };
    // Shaped like the picker's, so `reply` and `listen` find it; kind tells reply to match yes or no.
    if let Err(error) = asking.publish(&PendingPick {
        pid: std::process::id(),
        fifo: asking.fifo.clone(),
        label: question.to_string(),
        kind: Some("confirm".to_string()),
        choices: vec![choice("yes", "Yes"), choice("no", "No")],
        expansions: Default::default(),
        view: None,
        listen_again: Some(listen_again.to_string_lossy().into_owned()),
        verb: Some(verb.to_string()),
    }) {
        return Ok(Err(error));
    }
    // A signal during setup ends the ask before the question shows, as the bash trap did.
    signals.check()?;
    if listen {
        let _ = std::fs::write(&listen_again, "");
        match asking.start_reply_recording(signals)? {
            Some(waited) => debug(&format!("reply recording live after {waited}ms: {question}")),
            None => debug(&format!("voxtype busy, not listening: {question}")),
        }
    }
    // The bar and a voice reply write "yes" or "no", rofi the picked label.
    let qs_ipc = paths::qs_ipc();
    let bar_took_it = is_executable(&qs_ipc)
        && qs_ipc_call(&[
            "confirm".as_ref(),
            "ask".as_ref(),
            question.as_ref(),
            asking.fifo.as_os_str(),
        ]) == "ok";
    signals.check()?;
    let mut rofi = None;
    // The card cancels itself after 10 seconds without an answer, waiting while voice is heard; this only covers a
    // bar that dies mid-question.
    let mut timeout = super::timeout_setting("VOXCMD_CONFIRM_TIMEOUT", "120");
    if !bar_took_it {
        timeout = ROFI_TIMEOUT.to_string();
        let rofi_command = format!(
            "printf \"Yes\\nNo\\n\" | rofi -dmenu -i -p {} > {}",
            shell_quote(question.as_ref()),
            shell_quote(asking.fifo.as_os_str())
        );
        rofi = Command::new("sh")
            .args(["-c", &rofi_command])
            .stdin(Stdio::null())
            .spawn()
            .ok();
    }
    debug(&format!(
        "asked{}: {question}",
        if rofi.is_some() { " with rofi" } else { "" }
    ));
    let answer = asking.read_answer(&timeout, signals)?;
    debug(&format!("answer: {}", if answer.is_empty() { "none" } else { &answer }));
    // Removed before dismissing, so nothing the bar writes afterwards can block on the FIFO.
    asking.clean_up();
    match rofi {
        Some(rofi) => terminate_with_children(&rofi),
        // A no-op unless a voice reply or the timeout ended the question while the card was still open.
        None => {
            qs_ipc_call(&["confirm".as_ref(), "dismiss".as_ref(), asking.fifo.as_os_str()]);
        }
    }
    Ok(Ok(answer))
}
