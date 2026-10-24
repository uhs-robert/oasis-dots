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
    (&["wake", "listen", "--check"], "wake listen", "4.1"),
    (&["integrations", "schema"], "integrations schema", "2.6"),
    // `--` ends the flags, so a phrase can start with a dash.
];

mod common;

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
        &["util", "speech", "split-duration"],
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
fn a_watcher_needs_a_handler_under_either_spelling() {
    for args in [&["internal", "watch", "--any", "args"][..], &["_watch"]] {
        let output = voxcmd(args);
        assert_eq!(output.status.code(), Some(2), "{args:?}");
        assert!(
            stderr(&output).starts_with("voxcmd: internal watch: usage: "),
            "{args:?}: {}",
            stderr(&output)
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
fn util_speech_split_duration_prints_seconds_and_label_like_bash() {
    let split = voxcmd(&["util", "speech", "split-duration", "5", "minutes", "for the pasta"]);
    assert_eq!(
        (stdout(&split), split.status.code()),
        ("300 for the pasta\n".to_string(), Some(0))
    );
    // bash echoes "$seconds $label", so a duration alone keeps the space.
    let alone = voxcmd(&["util", "speech", "split-duration", "an hour and a half"]);
    assert_eq!((stdout(&alone), alone.status.code()), ("5400 \n".to_string(), Some(0)));
    let none = voxcmd(&["util", "speech", "split-duration", "pasta for 5 minutes"]);
    assert_eq!((stdout(&none), none.status.code()), (String::new(), Some(1)));
    assert_eq!(
        stderr(&none),
        "voxcmd: util speech split-duration: \"pasta for 5 minutes\" is not led by a duration\n"
    );
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
fn explain_prints_the_dry_run_lines_then_why() {
    let config = toml_config(&["media", "apps"]);
    let output = voxcmd_in(config.path(), &["explain", "Cortana,", "volume", "up", "by", "10"]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let text = stdout(&output);
    let (dry_run, why) = text.split_once("\n\n").expect("a blank line before the why block");
    assert_eq!(
        dry_run,
        "transcript:  Cortana, volume up by 10\n\
         normalized:  volume up by 10\n\
         result:      run\n\
         option 1:    Media (media.toml) action=volume_up target='' id='' label=''\n             \
         candidates offered: 0, weak: false, confirm: false, silent: true\n             \
         command: pamixer --increase \"${VOXCMD_ARG_NUMBER:-5}\""
    );
    assert!(why.starts_with("why:\n"), "{why}");
    assert!(
        why.contains("Media (media.toml, normal): matched verb 5 (line 13) action=volume_up number=10\n"),
        "{why}"
    );

    let text = stdout(&voxcmd_in(config.path(), &["explain", "mute", "toggle"]));
    assert!(
        text.contains("result:      ask with the picker (1 options, weak match"),
        "{text}"
    );
    assert!(
        text.contains("option 1:    Media (media.toml) [near miss] action=toggle_mute"),
        "{text}"
    );
}

#[test]
fn explain_json_is_one_document_of_steps() {
    let config = toml_config(&["media"]);
    let output = voxcmd_in(
        config.path(),
        &["explain", "--json", "next", "track", "and", "then", "mute"],
    );
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let document: serde_json::Value = serde_json::from_str(&stdout(&output)).expect("one JSON document");
    assert_eq!(document["phrase"], "next track and then mute");
    assert_eq!(document["sequence"]["steps"], 2);
    let steps = document["steps"].as_array().unwrap();
    assert_eq!(steps.len(), 2);
    assert_eq!(steps[0]["options"][0]["action"], "next");
    assert_eq!(steps[1]["decision"]["kind"], "run");
    assert!(steps[0]["millis"].as_f64().unwrap() >= 0.0);
}

#[test]
fn explain_reads_a_legacy_dump_file_without_bash() {
    let dump = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/legacy-dump.jsonl");
    let config = toml_config(&[]);
    let output = Command::new(env!("CARGO_BIN_EXE_voxcmd"))
        .args(["explain", "volume", "up"])
        .env_clear()
        .env("HOME", "/nonexistent")
        .env("VOXCMD_CONFIG_DIR", config.path())
        .env("VOXCMD_LEGACY_DUMP_FILE", dump)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    assert!(
        stdout(&output).contains("option 1:    Media (media.sh) action=volume_up"),
        "{}",
        stdout(&output)
    );
}

fn word_match_with(args: &[&str], stdin_lines: &[u8]) -> std::process::Output {
    use std::io::Write;
    let mut child = Command::new(env!("CARGO_BIN_EXE_voxcmd"))
        .args(["util", "word-match"])
        .args(args)
        .env_clear()
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(stdin_lines).unwrap();
    child.wait_with_output().unwrap()
}

#[test]
fn util_word_match_filters_the_lines_on_stdin() {
    let output = word_match_with(
        &["--ignore", "window", "firefox window"],
        b"1\tFirefox\tfirefox\n2\tKitty\n",
    );
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "1\tFirefox\tfirefox\n");
}

#[test]
fn util_word_match_strong_drops_weak_matches_only() {
    let weak_only = b"1\tSettings Page Home\n";
    // "settings page" covers two of three words: weak, so kept without --strong and a miss with it.
    let output = word_match_with(&["settings page"], weak_only);
    assert_eq!(
        (output.status.code(), stdout(&output)),
        (Some(0), "1\tSettings Page Home\t\n".to_string())
    );
    let output = word_match_with(&["--strong", "settings page"], weak_only);
    assert_eq!((output.status.code(), stdout(&output)), (Some(1), String::new()));

    let strong = b"1\tSettings Page\n";
    for args in [&["settings page"][..], &["--strong", "settings page"]] {
        let output = word_match_with(args, strong);
        assert_eq!(
            (output.status.code(), stdout(&output)),
            (Some(0), "1\tSettings Page\t\n".to_string())
        );
    }

    let output = word_match_with(&["--strong", "zebra"], strong);
    assert_eq!(output.status.code(), Some(1));
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

/// Runs the binary with a PATH of its own, so a test never reaches the real `notify-send`.
fn voxcmd_on_path(args: &[&str], path: &Path, envs: &[(&str, &str)]) -> Output {
    let mut command = Command::new(env!("CARGO_BIN_EXE_voxcmd"));
    command
        .args(args)
        .env_clear()
        .env("PATH", path)
        .env("HOME", "/nonexistent")
        .env("LC_ALL", "C");
    for (name, value) in envs {
        command.env(name, value);
    }
    command.output().expect("the binary runs")
}

/// Runs the script once in probe mode until it execs. Renaming does not help (the inode is the same), but a fork on
/// another test thread that held the write fd lets go of it at its exec, so after this no later exec is ETXTBSY.
fn settle_exec(path: &Path) {
    for _ in 0..500 {
        match Command::new(path).env("VOXCMD_TEST_PROBE", "1").status() {
            Err(error) if error.kind() == std::io::ErrorKind::ExecutableFileBusy => {
                std::thread::sleep(std::time::Duration::from_millis(10));
            }
            _ => return,
        }
    }
}

/// A directory holding a `notify-send` that appends its arguments, one per line, to `calls`.
fn stub_notify_send() -> (tempfile::TempDir, std::path::PathBuf) {
    use std::os::unix::fs::PermissionsExt;
    let dir = tempfile::tempdir().unwrap();
    let calls = dir.path().join("calls");
    let stub = dir.path().join("notify-send");
    let temp = dir.path().join(".notify-send.tmp");
    std::fs::write(
        &temp,
        format!(
            "#!/bin/sh\n[ -z \"$VOXCMD_TEST_PROBE\" ] || exit 0\nprintf '%s\\n' \"$@\" >> '{}'\nprintf -- '---\\n' >> '{0}'\n",
            calls.display()
        ),
    )
    .unwrap();
    std::fs::set_permissions(&temp, std::fs::Permissions::from_mode(0o755)).unwrap();
    std::fs::rename(&temp, &stub).unwrap();
    settle_exec(&stub);
    (dir, calls)
}

#[test]
fn util_notify_sends_info_transient_and_error_in_the_history() {
    let (dir, calls) = stub_notify_send();
    let path = dir.path();
    assert_eq!(
        voxcmd_on_path(&["util", "notify", "info", "Title", "Body"], path, &[])
            .status
            .code(),
        Some(0)
    );
    assert_eq!(
        voxcmd_on_path(&["util", "notify", "error", "Oops", "It broke"], path, &[])
            .status
            .code(),
        Some(0)
    );
    assert_eq!(
        std::fs::read_to_string(calls).unwrap(),
        "-a\nvoxcmd\n--transient\nTitle\nBody\n---\n-a\nvoxcmd\nOops\nIt broke\n---\n"
    );
}

#[test]
fn util_notify_prints_to_stderr_in_a_dry_run_or_without_notify_send() {
    let (dir, calls) = stub_notify_send();
    let dry = voxcmd_on_path(
        &["util", "notify", "info", "Title", "Body"],
        dir.path(),
        &[("VOXCMD_DRY_RUN", "1")],
    );
    assert_eq!(
        (stderr(&dry), dry.status.code()),
        ("Title: Body\n".to_string(), Some(0))
    );
    assert!(!calls.exists(), "a dry run sent a toast");
    let empty = tempfile::tempdir().unwrap();
    let none = voxcmd_on_path(&["util", "notify", "error", "Title", "Body"], empty.path(), &[]);
    assert_eq!(stderr(&none), "Title: Body\n");
}

#[test]
fn util_notify_no_match_keeps_text_that_starts_with_a_dash_as_text() {
    let (dir, calls) = stub_notify_send();
    let path = std::env::join_paths([dir.path(), Path::new("/usr/bin"), Path::new("/bin")]).unwrap();
    let output = voxcmd_on_path(
        &["util", "notify", "no-match", "--", "-title", "-u"],
        Path::new(&path),
        &[],
    );
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    while !calls.exists() && std::time::Instant::now() < deadline {
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    assert_eq!(
        std::fs::read_to_string(calls).unwrap(),
        "-a\nvoxcmd\n--transient\n--action=help=Voice Help\n--\n-title\n-u\n---\n"
    );
}

#[test]
fn util_notify_no_match_offers_voice_help_without_waiting_for_the_toast() {
    let (dir, calls) = stub_notify_send();
    let path = std::env::join_paths([dir.path(), Path::new("/usr/bin"), Path::new("/bin")]).unwrap();
    let output = voxcmd_on_path(
        &["util", "notify", "no-match", "voxcmd: no match", "\"zzz\""],
        Path::new(&path),
        &[],
    );
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    // The waiter is detached, so its call lands a moment after voxcmd has exited.
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    while !calls.exists() && std::time::Instant::now() < deadline {
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    assert_eq!(
        std::fs::read_to_string(calls).unwrap(),
        "-a\nvoxcmd\n--transient\n--action=help=Voice Help\nvoxcmd: no match\n\"zzz\"\n---\n"
    );
}

#[test]
fn util_notify_rejects_an_unknown_level() {
    let output = voxcmd(&["util", "notify", "loud", "Title", "Body"]);
    assert_eq!(output.status.code(), Some(2));
    assert!(
        stderr(&output).starts_with("voxcmd: util notify: level must be"),
        "{}",
        stderr(&output)
    );
}

/// `explain` runs a TOML integration's hook for real, in a dry run: what the hook toasts goes to stderr.
#[test]
fn explain_runs_toml_hooks_in_a_dry_run_and_reports_a_failing_one() {
    let (stub, calls) = stub_notify_send();
    let config = tempfile::tempdir().unwrap();
    std::fs::create_dir(config.path().join("integrations")).unwrap();
    let integration = |name: &str, hook: &str| {
        format!(
            "name = \"{name}\"\nverbs = [{{ action = \"go\", match = '{name} {{target}}' }}]\n\
             [actions.go]\nrun = 'true'\ncandidates = '''{hook}'''\nno_match = \"gone\"\n[actions.gone]\nrun = 'true'\n"
        )
    };
    std::fs::write(
        config.path().join("integrations/good.toml"),
        integration(
            "good",
            r#""$VOXCMD_TEST_BIN" util notify info Toast "from $VOXCMD_ACTION"; printf '1\tFirst\n2\tSecond\n'"#,
        ),
    )
    .unwrap();
    std::fs::write(
        config.path().join("integrations/bad.toml"),
        integration("bad", "echo broke >&2; exit 4"),
    )
    .unwrap();
    let envs = [
        ("VOXCMD_CONFIG_DIR", config.path().to_str().unwrap()),
        ("VOXCMD_TEST_BIN", env!("CARGO_BIN_EXE_voxcmd")),
        ("XDG_RUNTIME_DIR", config.path().to_str().unwrap()),
    ];
    let path = std::env::join_paths([stub.path(), Path::new("/usr/bin"), Path::new("/bin")]).unwrap();
    let path = Path::new(&path);
    let good = voxcmd_on_path(&["explain", "good first"], path, &envs);
    assert_eq!(good.status.code(), Some(0), "{}", stderr(&good));
    let text = stdout(&good);
    assert!(text.contains("hook good go: 2 line(s)"), "{text}");
    assert!(text.contains("stderr: Toast: from go"), "{text}");
    assert!(!calls.exists(), "the hook's toast was sent, not printed");

    let bad = voxcmd_on_path(&["explain", "bad thing"], path, &envs);
    let text = stdout(&bad);
    assert!(
        text.contains("failed: exit 4; it offers nothing, and no_match is skipped"),
        "{text}"
    );
    assert!(text.contains("result:      no match"), "{text}");
}

/// A phrase nothing takes goes through the normal pass and then the near-miss pass. The hook of an action with two
/// verbs is asked the same thing in each when the target is the same, and runs once; a near miss that names another
/// target ("tea" for "the tea") is another query and runs its own hook.
#[test]
fn explain_runs_each_distinct_hook_query_once_per_phrase() {
    let config = tempfile::tempdir().unwrap();
    std::fs::create_dir(config.path().join("integrations")).unwrap();
    let counter = config.path().join("runs");
    std::fs::write(
        config.path().join("integrations/finder.toml"),
        format!(
            "name = \"Finder\"\nverbs = [\n  {{ action = \"find\", match = 'find {{target}}' }},\n  {{ action = \"find\", match = 'look for {{target}}' }},\n]\n\
             [actions.find]\nrun = 'true'\ncandidates = '''echo \"$VOXCMD_ARG_TARGET\" >> '{}'; exit 2'''\nno_match = \"gone\"\n[actions.gone]\nrun = 'true'\n",
            counter.display()
        ),
    )
    .unwrap();
    let path = std::env::join_paths([Path::new("/usr/bin"), Path::new("/bin")]).unwrap();
    let envs = [("VOXCMD_CONFIG_DIR", config.path().to_str().unwrap())];
    let targets_asked = |phrase: &str| {
        std::fs::write(&counter, "").unwrap();
        let output = voxcmd_on_path(&["explain", phrase], Path::new(&path), &envs);
        assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
        std::fs::read_to_string(&counter)
            .unwrap()
            .lines()
            .map(str::to_string)
            .collect::<Vec<_>>()
    };
    assert_eq!(targets_asked("find tea"), ["tea"]);
    assert_eq!(targets_asked("find the tea"), ["the tea", "tea"]);
}

#[test]
fn sigterm_to_voxcmd_kills_the_running_action_and_its_children() {
    let dir = tempfile::tempdir().unwrap();
    let config = dir.path().join("config");
    std::fs::create_dir_all(config.join("integrations")).unwrap();
    let pid_file = dir.path().join("child.pid");
    std::fs::write(
        config.join("integrations/slow.toml"),
        format!(
            "verbs = [ {{ action = \"go\", match = 'go slow' }} ]\n[actions.go]\nrun = \"sleep 60 & echo $! > '{}'; wait\"\n",
            pid_file.display()
        ),
    )
    .unwrap();
    let mut child = Command::new(env!("CARGO_BIN_EXE_voxcmd"))
        .args(["run", "go", "slow"])
        .env_clear()
        .env("PATH", std::env::var_os("PATH").unwrap_or_default())
        .env("HOME", "/nonexistent")
        .env("VOXCMD_CONFIG_DIR", &config)
        .env("VOXCMD_DRY_RUN", "1")
        .env("XDG_RUNTIME_DIR", dir.path())
        .env("XDG_STATE_HOME", dir.path())
        .spawn()
        .unwrap();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
    while !pid_file.exists() && std::time::Instant::now() < deadline {
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    let sleeper: i32 = std::fs::read_to_string(&pid_file).unwrap().trim().parse().unwrap();
    // SAFETY: signals a child this test started.
    unsafe { libc::kill(child.id() as i32, libc::SIGTERM) };
    child.wait().unwrap();
    assert!(
        common::gone_within(sleeper, std::time::Duration::from_secs(5)),
        "the action's child outlived voxcmd"
    );
}
