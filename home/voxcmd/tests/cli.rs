//! argv to subcommand, exit codes (0, 1, 2 only) and the stderr contract `voxcmd: <subcommand>: <message>`.
use std::path::Path;
use std::process::{Command, Output};

fn voxcmd(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_voxcmd"))
        .args(args)
        .env_clear()
        .env("PATH", std::env::var_os("PATH").unwrap_or_default())
        .env("HOME", "/nonexistent")
        .env("TZ", "America/New_York")
        .env("LC_ALL", "C")
        .output()
        .expect("the binary runs")
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

/// (argv, subcommand named in the message, port item that implements it)
const NOT_IMPLEMENTED: &[(&[&str], &str, &str)] = &[
    (&["run", "open", "firefox"], "run", "2.3"),
    (&["explain", "--json", "open", "firefox"], "explain --json", "2.2b"),
    (
        &["explain", "--window", "focused", "click", "close"],
        "explain --window",
        "2.5",
    ),
    (&["explain", "--reply", "one"], "explain --reply", "2.4"),
    (&["reply", "--dry-run", "one"], "reply", "2.4"),
    (&["listen", "--start-only"], "listen", "2.4"),
    (&["stop"], "stop", "2.4"),
    (&["session", "rapid"], "session", "2.4"),
    (&["session", "end"], "session", "2.4"),
    (&["ask", "pick", "label", "[]"], "ask pick", "2.4"),
    (
        &["ask", "confirm", "--verb", "close", "Close it?"],
        "ask confirm",
        "2.4",
    ),
    (&["ask", "hints", "--listen", "label", "[]"], "ask hints", "2.4"),
    (&["wake", "on"], "wake", "2.6"),
    (&["wake", "status"], "wake", "2.6"),
    (&["wake", "listen", "--check"], "wake listen", "4.1"),
    (&["integrations", "list", "--json"], "integrations list", "2.6"),
    (&["integrations", "check", "a.toml"], "integrations check", "2.6"),
    (&["integrations", "examples", "--route"], "integrations examples", "2.6"),
    (&["integrations", "schema"], "integrations schema", "2.6"),
    (&["help"], "help", "2.6"),
    (&["log", "misses"], "log misses", "2.6"),
    (&["log", "errors", "5", "--json"], "log errors", "2.6"),
    (&["timer", "ring", "Timer", "done"], "timer ring", "2.6"),
    (&["util", "notify", "info", "title", "body"], "util notify", "2.3"),
    (
        &["util", "word-match", "--ignore", "the", "target"],
        "util word-match",
        "2.2b",
    ),
    (&["internal", "watch", "--any", "args"], "internal watch", "2.4"),
    (&["internal", "settle"], "internal settle", "2.4"),
    (
        &["internal", "cancel-owned-recording"],
        "internal cancel-owned-recording",
        "2.4",
    ),
    (
        &["internal", "wake-confirm", "clip.wav"],
        "internal wake-confirm",
        "2.4",
    ),
    (&["internal", "chain-stop"], "internal chain-stop", "2.4"),
    // The bash spellings stay as aliases until the Python listeners move, at the top level where callers run them.
    (&["internal", "_watch"], "internal watch", "2.4"),
    (&["_watch"], "internal watch", "2.4"),
    (&["_settle"], "internal settle", "2.4"),
    (&["_cancel_owned_recording"], "internal cancel-owned-recording", "2.4"),
    (&["_wake-confirm", "clip.wav"], "internal wake-confirm", "2.4"),
    (&["_chain-stop"], "internal chain-stop", "2.4"),
    // `--` ends the flags, so a phrase can start with a dash.
    (&["run", "--", "-5", "degrees"], "run", "2.3"),
];

#[test]
fn unimplemented_subcommands_exit_1_naming_their_port_item() {
    for (args, subcommand, item) in NOT_IMPLEMENTED {
        let output = voxcmd(args);
        assert_eq!(output.status.code(), Some(1), "{args:?}: {}", stderr(&output));
        assert_eq!(stdout(&output), "", "{args:?} printed to stdout");
        assert_eq!(
            stderr(&output),
            format!("voxcmd: {subcommand}: not implemented yet ({item})\n"),
            "{args:?}"
        );
    }
}

#[test]
fn usage_errors_exit_2() {
    let cases: &[&[&str]] = &[
        &[],
        &["frobnicate"],
        &["run"],
        &["explain", "--json"],
        &["log", "misses", "many"],
        &["wake", "sideways"],
        &["ask", "pick"],
        &["util", "speech"],
        &["util", "speech", "parse-duration"],
        &["session"],
    ];
    for args in cases {
        let output = voxcmd(args);
        assert_eq!(output.status.code(), Some(2), "{args:?}");
        assert_eq!(stdout(&output), "", "{args:?} printed to stdout");
        let message = stderr(&output);
        assert!(
            message.contains("Usage:") || message.starts_with("error:"),
            "{args:?}: {message}"
        );
    }
}

#[test]
fn help_and_version_exit_0() {
    let version = voxcmd(&["--version"]);
    assert_eq!(version.status.code(), Some(0));
    assert!(stdout(&version).starts_with("voxcmd 0.1.0"), "{}", stdout(&version));
    for args in [
        &["--help"][..],
        &["util", "--help"],
        &["internal", "--help"],
        &["util", "speech", "--help"],
    ] {
        assert_eq!(voxcmd(args).status.code(), Some(0), "{args:?}");
    }
}

#[test]
fn the_top_level_help_lists_the_public_subcommands_only() {
    let help = stdout(&voxcmd(&["--help"]));
    insta::assert_snapshot!(help);
    assert!(!help.contains("util") && !help.contains("internal"));
}

#[test]
fn util_speech_joins_the_remaining_words_into_one_phrase() {
    let joined = voxcmd(&["util", "speech", "parse-duration", "an", "hour", "and", "a", "half"]);
    let single = voxcmd(&["util", "speech", "parse-duration", "an hour and a half"]);
    assert_eq!((stdout(&joined), joined.status.code()), ("5400\n".to_string(), Some(0)));
    assert_eq!(stdout(&joined), stdout(&single));
}

#[test]
fn util_speech_failure_is_exit_1_with_the_contract_message() {
    let output = voxcmd(&["util", "speech", "parse-duration", "banana"]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        "voxcmd: util speech parse-duration: \"banana\" is not a duration\n"
    );
}

#[test]
fn util_voice_env_prints_the_environment_value_or_exits_1() {
    let set = Command::new(env!("CARGO_BIN_EXE_voxcmd"))
        .args(["util", "voice-env", "VOXCMD_DUCK_MEDIA_VOLUME"])
        .env_clear()
        .env("VOXCMD_DUCK_MEDIA_VOLUME", "40")
        .output()
        .unwrap();
    assert_eq!((stdout(&set), set.status.code()), ("40\n".to_string(), Some(0)));
    let unset = Command::new(env!("CARGO_BIN_EXE_voxcmd"))
        .args(["util", "voice-env", "VOXCMD_DUCK_MEDIA_VOLUME"])
        .env_clear()
        .env("VOXCMD_VOICE_ENV_FILE", "/nonexistent/voice.env")
        .output()
        .unwrap();
    assert_eq!(unset.status.code(), Some(1));
    assert_eq!(
        stderr(&unset),
        "voxcmd: util voice-env: VOXCMD_DUCK_MEDIA_VOLUME is not set\n"
    );
}

#[test]
fn a_bad_voxcmd_now_is_a_usage_error() {
    let output = Command::new(env!("CARGO_BIN_EXE_voxcmd"))
        .args(["util", "speech", "parse-time", "3 pm"])
        .env("VOXCMD_NOW", "tomorrow")
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(2));
}

/// The module list is how an agent finds the code for a behaviour: every file says what it owns in its first line.
#[test]
fn every_source_file_starts_with_a_module_doc_line() {
    fn visit(dir: &Path, files: &mut Vec<std::path::PathBuf>) {
        for entry in std::fs::read_dir(dir).unwrap().flatten() {
            let path = entry.path();
            if path.is_dir() {
                visit(&path, files);
            } else if path.extension().is_some_and(|extension| extension == "rs") {
                files.push(path);
            }
        }
    }
    let mut files = Vec::new();
    visit(&Path::new(env!("CARGO_MANIFEST_DIR")).join("src"), &mut files);
    assert!(!files.is_empty());
    for file in files {
        let first_line = std::fs::read_to_string(&file)
            .unwrap()
            .lines()
            .next()
            .unwrap_or("")
            .to_string();
        assert!(
            first_line.starts_with("//! ") && first_line.len() > 8,
            "{} must start with a `//! <what it owns>` line, found {first_line:?}",
            file.display()
        );
    }
}

/// A config dir holding copies of the TOML fixtures, so `explain` needs no bash.
fn toml_config(stems: &[&str]) -> tempfile::TempDir {
    let dir = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(dir.path().join("integrations")).unwrap();
    for stem in stems {
        let source = Path::new(env!("CARGO_MANIFEST_DIR")).join(format!("tests/fixtures/integrations/{stem}.toml"));
        std::fs::copy(source, dir.path().join(format!("integrations/{stem}.toml"))).unwrap();
    }
    std::fs::write(dir.path().join("intents.local"), "zap = zap, blast\n").unwrap();
    dir
}

fn voxcmd_in(config: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_voxcmd"))
        .args(args)
        .env_clear()
        .env("PATH", std::env::var_os("PATH").unwrap_or_default())
        .env("HOME", "/nonexistent")
        .env("TZ", "America/New_York")
        .env("LC_ALL", "C")
        .env("VOXCMD_CONFIG_DIR", config)
        .output()
        .expect("the binary runs")
}

#[test]
fn explain_prints_the_match_layer() {
    let config = toml_config(&["media", "apps"]);
    let output = voxcmd_in(config.path(), &["explain", "Cortana,", "volume", "up", "by", "10"]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let text = stdout(&output);
    assert!(
        text.starts_with("transcript: Cortana, volume up by 10\nnormalized: volume up by 10\n"),
        "{text}"
    );
    assert!(
        text.contains("match: Media (media.toml) verb 5 (line 13) action=volume_up number=10\n"),
        "{text}"
    );
    assert!(!text.contains("result:"), "{text}");

    let text = stdout(&voxcmd_in(config.path(), &["explain", "mute", "toggle"]));
    assert!(
        text.contains("near miss: Media (media.toml) verb 8 (line 16) action=toggle_mute target= leftover=0\n"),
        "{text}"
    );
}

#[test]
fn explain_with_an_unreadable_integration_is_a_usage_error() {
    let config = toml_config(&[]);
    std::fs::write(config.path().join("integrations/bad.toml"), "verbs = 3\n").unwrap();
    let output = voxcmd_in(config.path(), &["explain", "volume", "up"]);
    assert_eq!(output.status.code(), Some(2));
    assert!(stderr(&output).starts_with("voxcmd: explain: "), "{}", stderr(&output));
}

#[test]
fn util_intents_prints_the_forms_with_intents_local() {
    let config = toml_config(&[]);
    let output = voxcmd_in(config.path(), &["util", "intents", "close"]);
    assert_eq!(
        (output.status.code(), stdout(&output)),
        (Some(0), "close\nquit\nkill\n".to_string())
    );
    assert_eq!(
        stdout(&voxcmd_in(config.path(), &["util", "intents", "zap"])),
        "zap\nblast\n"
    );
    let output = voxcmd_in(config.path(), &["util", "intents", "nope"]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(stderr(&output), "voxcmd: util intents: no intent named \"nope\"\n");
}
