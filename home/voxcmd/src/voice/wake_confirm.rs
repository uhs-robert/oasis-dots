//! `voxcmd internal wake-confirm <wav> [recording]` (alias `_wake-confirm`): whether a short recording (16 kHz mono
//! WAV) holds the wake word, from `voxtype transcribe` (was `wake_confirm` and `heard_wake_word`)
//!
//! voxcmd-wake asks it before a trigger starts a command, with the audio on stdin as `/dev/stdin`, and reads only the
//! exit code: prints `wake <words after it>` and exits 0, `not_wake` and exits 1, or `failed` and exits 2 when there is
//! no file, voxtype fails or outlasts `VOXCMD_WAKE_CONFIRM_TIMEOUT_SECS`. A clip cut during a dictation names the
//! recording it was heard in, whose ending it may be (`session::dictation::wake_heard`). Nothing it heard is logged.
//!
//! Whisper gets the daemon's initial prompt (`voxtype-prompt`, in the voxtype package), so it hears the wake word the
//! way a dictation does; without that script the audio is still transcribed, just without the prompt.
use crate::debug::debug;
use crate::exit::CliError;
use crate::paths;
use crate::process;
use crate::session::dictation;
use crate::text::normalize::Replacements;
use crate::text::wake_word::WakeWords;
use std::io::Write;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

const SUBCOMMAND: &str = "internal wake-confirm";
const PROMPT_TIMEOUT: Duration = Duration::from_secs(3);

pub fn run(args: &[String]) -> Result<Option<String>, CliError> {
    let wav = args.first().map_or("", String::as_str);
    let recording = args.get(1).map_or("", String::as_str);
    let transcript = if wav.is_empty() { None } else { transcribe(wav) };
    let Some(transcript) = transcript else {
        say("failed");
        // Exit 2 is "failed" to voxcmd-wake, not a usage error; the message stays empty so nothing goes to stderr.
        return Err(CliError::usage(SUBCOMMAND, ""));
    };
    let wake = WakeWords::from_env();
    let replacements = Replacements::load(&paths::config_dir().join("replacements.d"));
    let Some(rest) = wake.heard(&transcript, &replacements) else {
        debug("wake confirm: not the wake word");
        say("not_wake");
        return Err(CliError::quiet(SUBCOMMAND));
    };
    debug("wake confirm: the wake word");
    if !recording.is_empty() {
        dictation::wake_heard(&rest, recording, &wake);
    }
    Ok(Some(if rest.is_empty() {
        "wake".to_string()
    } else {
        format!("wake {rest}")
    }))
}

fn say(verdict: &str) {
    let _ = writeln!(std::io::stdout(), "{verdict}");
}

/// Runs its arguments (voxtype's) as a child of the group's leader, which this process's death (`die_with_parent`)
/// TERMs: the leader then TERMs the whole group, so a child voxtype started goes too. The clip stays on stdin: a background
/// job of a non-interactive shell would otherwise get /dev/null.
const VOXTYPE_AS_GROUP_LEADER: &str = r#"trap 'trap "" TERM; kill -TERM -- -$$' TERM; "$@" <&0 & wait $!"#;

/// What voxtype heard in the clip: "" for no speech, none when it failed or ran out of time.
fn transcribe(wav: &str) -> Option<String> {
    let prompt = initial_prompt();
    let mut command = Command::new("sh");
    command.args(["-c", VOXTYPE_AS_GROUP_LEADER, "voxtype", "voxtype"]);
    // -q keeps voxtype's INFO lines (which hold the transcript) out of the output; the progress lines stay on stdout.
    command.arg("-q");
    if let Some(model) = downloaded_model() {
        command.args(["--model", &model]);
    }
    if let Some(prompt) = prompt {
        command.args(["--initial-prompt", &prompt]);
    }
    command.args(["transcribe", wav]);
    // voxcmd-wake kills this process's group when it outlasts its own limit; voxtype's group is told by its leader.
    process::die_with_parent(&mut command);
    let limit = confirm_limit(std::env::var("VOXCMD_WAKE_CONFIRM_TIMEOUT_SECS").ok().as_deref());
    match process::run_with_timeout_on_stdin(&mut command, limit) {
        Ok(outcome) if outcome.code() == Some(0) => Some(after_blank_line(&outcome.stdout)),
        _ => {
            debug("wake confirm: voxtype transcribe failed or timed out");
            None
        }
    }
}

/// How long voxtype may transcribe, read as bash's `timeout` read the setting: a number of seconds, decimals allowed,
/// with an optional s, m, h or d; 0 is no limit (none). Unset or unreadable, 6 s.
fn confirm_limit(setting: Option<&str>) -> Option<Duration> {
    let setting = setting.unwrap_or_default();
    let (number, unit_secs) = match setting.chars().last() {
        Some('s') => (&setting[..setting.len() - 1], 1.0),
        Some('m') => (&setting[..setting.len() - 1], 60.0),
        Some('h') => (&setting[..setting.len() - 1], 3600.0),
        Some('d') => (&setting[..setting.len() - 1], 86400.0),
        _ => (setting, 1.0),
    };
    let secs = number
        .parse::<f64>()
        .ok()
        .filter(|secs| secs.is_finite() && *secs >= 0.0);
    match secs.map(|secs| Duration::try_from_secs_f64(secs * unit_secs)) {
        Some(Ok(limit)) if limit.is_zero() => None,
        Some(Ok(limit)) => Some(limit),
        _ => Some(Duration::from_secs(6)),
    }
}

/// voxtype prints progress first ("Loading audio file: <path>", the format, samples, VAD), then a blank line and the
/// transcript, also with -q. Without the blank line it heard no speech.
fn after_blank_line(output: &str) -> String {
    let mut lines = output.split('\n');
    lines.by_ref().find(|line| line.is_empty());
    lines.collect::<Vec<_>>().join("\n").trim_end_matches('\n').to_string()
}

/// base.en, not the daemon's model: with the prompt the larger model heard the wake word in 20 of 300 clips that were
/// not. Without the model file voxtype would fail, so the daemon's model answers instead (none).
fn downloaded_model() -> Option<String> {
    let model = std::env::var("VOXCMD_WAKE_CONFIRM_MODEL")
        .ok()
        .filter(|model| !model.is_empty())
        .unwrap_or_else(|| "base.en".to_string());
    let data_home = std::env::var_os("XDG_DATA_HOME")
        .filter(|dir| !dir.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/share"));
    let model_file = data_home.join(format!("voxtype/models/ggml-{model}.bin"));
    if model_file.is_file() {
        Some(model)
    } else {
        debug(&format!(
            "wake confirm: {} is missing, transcribing with the daemon's model",
            model_file.display()
        ));
        None
    }
}

/// The daemon's initial prompt, from `voxtype-prompt` on PATH.
fn initial_prompt() -> Option<String> {
    let prompt = on_path("voxtype-prompt")
        .and_then(|script| process::run_with_timeout(&mut Command::new(script), PROMPT_TIMEOUT).ok())
        .filter(|outcome| outcome.code() == Some(0))
        .map(|outcome| outcome.stdout.trim_end_matches('\n').to_string())
        .filter(|prompt| !prompt.is_empty());
    if prompt.is_none() {
        debug("wake confirm: no initial prompt, transcribing without it");
    }
    prompt
}

fn on_path(name: &str) -> Option<PathBuf> {
    std::env::split_paths(&std::env::var_os("PATH")?)
        .map(|dir| dir.join(name))
        .find(|path| path.is_file() && crate::ask::is_executable(path))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_limit_reads_as_bash_s_timeout_reads_it() {
        let secs = |secs: f64| Some(Duration::from_secs_f64(secs));
        for (setting, limit) in [
            ("1", secs(1.0)),
            ("6s", secs(6.0)),
            ("1m", secs(60.0)),
            ("2h", secs(7200.0)),
            ("1d", secs(86400.0)),
            ("1.5", secs(1.5)),
            ("0.5s", secs(0.5)),
            ("0", None),
            ("0s", None),
            ("0.0", None),
            ("", secs(6.0)),
            ("soon", secs(6.0)),
            ("s", secs(6.0)),
            ("-1", secs(6.0)),
            ("1x", secs(6.0)),
        ] {
            assert_eq!(confirm_limit(Some(setting)), limit, "{setting:?}");
        }
        assert_eq!(confirm_limit(None), secs(6.0));
    }

    #[test]
    fn the_transcript_is_what_follows_the_first_blank_line() {
        let output = "Loading audio file: \"/dev/stdin\"\nVAD: 0.54s speech\n\nCortana, stop.\n";
        assert_eq!(after_blank_line(output), "Cortana, stop.");
        assert_eq!(after_blank_line("Loading audio file: \"x\"\nNo speech detected.\n"), "");
        assert_eq!(after_blank_line("progress\n\nfirst\n\nsecond\n\n"), "first\n\nsecond");
    }
}
