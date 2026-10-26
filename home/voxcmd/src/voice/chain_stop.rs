//! `voxcmd internal chain-stop <recording> <detector settings>` (alias `_chain-stop`): the stopper a chained dictation
//! ending leaves behind (was `dictation_chain_autostop_settings`, `dictation_chain_stop` and
//! `dictation_chain_stop_locked`)
//!
//! "cortana stop and then ..." keeps the recording going, so the commands after the ending are in its transcript. This
//! waits for the pause (or the deadline) after them, then stops the recording, if it is still the one the ending was
//! recorded in and still waits for this stop. Only the detector's stop verdicts do, as in the watcher; an error or
//! "ended elsewhere" leaves the recording to the voice key and the other limits.
use super::watch::{VERDICT_MAX_LENGTH, VERDICT_NO_SPEECH, VERDICT_SILENCE};
use super::{secs_setting, voxtype_record};
use crate::ask;
use crate::debug::debug;
use crate::exit::CliError;
use crate::paths;
use crate::process;
use crate::session::{SessionLock, dictation, text_of};
use std::os::unix::process::ExitStatusExt;
use std::process::{Command, Stdio};

/// `recording` names the recording as the wake confirmation did (`<frame_id>:<owner>:<owner_start>`); the settings are
/// the detector's `VAR=value` lines (`autostop_settings`).
pub fn run(args: &[String]) -> Result<(), CliError> {
    let recording = args.first().map_or("", String::as_str);
    let settings = args.get(1).map_or("", String::as_str);
    let program = paths::autostop();
    if !ask::is_executable(&program) {
        return Ok(());
    }
    let mut command = Command::new(program);
    for (name, value) in settings.lines().filter_map(|line| line.split_once('=')) {
        command.env(name, value);
    }
    process::die_with_parent(&mut command);
    // 127 as `env` exits when it cannot run the detector.
    let verdict = command.status().map_or(127, |status| {
        status
            .code()
            .or_else(|| status.signal().map(|signal| 128 + signal))
            .unwrap_or(127)
    });
    if ![VERDICT_SILENCE, VERDICT_NO_SPEECH, VERDICT_MAX_LENGTH].contains(&verdict) {
        debug(&format!(
            "dictation: the chain's detector gave verdict {verdict}, recording left alone"
        ));
        return Ok(());
    }
    let lock = SessionLock::take();
    let Some(state) = dictation::heard_in_locked(&lock, recording) else {
        return Ok(());
    };
    // Stop Voice makes the ending a key one, and then it has stopped the recording itself.
    let ending = &state["ending"];
    if text_of(&ending["by"]) != "voice" || text_of(&ending["chain"]) != "true" {
        return Ok(());
    }
    debug("dictation: the pause after the chained ending, stopping");
    voxtype_record("stop", &[]);
    Ok(())
}

/// Detaches the stopper for `recording` through the `setsid` binary, as `listen` detaches a watcher, so it outlives
/// the wake confirmation that recorded the chain (voxcmd-wake kills that one's group at its own limit). It never
/// holds the session lock its caller holds: that is close-on-exec.
pub fn start(recording: &str, settings: &str) {
    let mut command = Command::new("setsid");
    command
        .arg(ask::this_binary())
        .args(["internal", "chain-stop", recording, settings])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    process::hear_stop_signals(&mut command);
    // Not waited for, as bash's `&` was not: this process exits right after.
    if let Err(error) = command.spawn() {
        debug(&format!("dictation: cannot start the chain's stopper: {error}"));
    }
}

/// The detector settings of the pause that ends a recording after a chained ending: a session turn's pause and
/// deadline. The detector starts only after the wake clip is cut and transcribed, by when the chain is under way or
/// spoken, so it needs no speech of its own (min speech 0): the first pause of silence_secs stops the recording, and
/// speech still going on holds it off. For the same reason it cannot measure the room (its first 0.3 s would be the
/// voice), so it takes the threshold the recording's own detector, under watcher `owner`, measured before any speech,
/// when that has written one.
pub fn autostop_settings(owner: &str) -> String {
    let room_threshold = owner
        .parse::<u32>()
        .ok()
        .and_then(|owner| std::fs::read_to_string(paths::threshold_file(owner)).ok())
        .map(|threshold| threshold.trim_end_matches('\n').to_string())
        .unwrap_or_default();
    let no_speech_secs = secs_setting("VOXCMD_SESSION_NO_SPEECH_SECS", "10");
    let mut lines = Vec::new();
    if !room_threshold.is_empty() {
        lines.push(format!("VOXCMD_AUTOSTOP_THRESHOLD_DB={room_threshold}"));
    }
    lines.extend([
        format!("VOXCMD_AUTOSTOP_NO_SPEECH_SECS={no_speech_secs}"),
        "VOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0".to_string(),
        format!(
            "VOXCMD_AUTOSTOP_SILENCE_SECS={}",
            secs_setting("VOXCMD_SESSION_SILENCE_SECS", "1.5")
        ),
        format!("VOXCMD_AUTOSTOP_MAX_SECS={no_speech_secs}"),
    ]);
    lines.join("\n")
}
