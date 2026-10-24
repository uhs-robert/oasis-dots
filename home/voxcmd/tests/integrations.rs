//! `integrations list` and `integrations check` over the fixture integrations, with the bash `voxcmd` beside them as a
//! tripwire that must never run when there is no legacy file to load.
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::{Command, Output};

const FIXTURES: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures");

struct Sandbox {
    root: tempfile::TempDir,
}

impl Sandbox {
    /// A config dir holding the fixture integrations named by `stems`.
    fn with(stems: &[&str]) -> Self {
        let sandbox = Self {
            root: tempfile::tempdir().unwrap(),
        };
        std::fs::create_dir_all(sandbox.config().join("integrations")).unwrap();
        for stem in stems {
            std::fs::copy(
                format!("{FIXTURES}/integrations/{stem}.toml"),
                sandbox.config().join(format!("integrations/{stem}.toml")),
            )
            .unwrap();
        }
        // The tripwire: _legacy-dump runs this, and nothing here needs it to.
        let bash = sandbox.root.path().join("bash-voxcmd");
        std::fs::write(
            &bash,
            format!(
                "#!/bin/sh\necho 'BASH-RAN voxcmd' >> {}\nexit 1\n",
                sandbox.calls().display()
            ),
        )
        .unwrap();
        std::fs::set_permissions(&bash, std::fs::Permissions::from_mode(0o755)).unwrap();
        sandbox
    }

    fn config(&self) -> std::path::PathBuf {
        self.root.path().join("config/voxcmd")
    }

    fn calls(&self) -> std::path::PathBuf {
        self.root.path().join("calls.log")
    }

    fn write(&self, relative: &str, text: &str) {
        std::fs::write(self.config().join(relative), text).unwrap();
    }

    fn voxcmd(&self, args: &[&str], env: &[(&str, &Path)]) -> Output {
        let root = self.root.path();
        Command::new(env!("CARGO_BIN_EXE_voxcmd"))
            .args(args)
            .env_clear()
            .env("PATH", "/usr/bin:/bin")
            .env("HOME", root.join("home"))
            .env("XDG_CONFIG_HOME", root.join("config"))
            .env("XDG_CACHE_HOME", root.join("cache"))
            .env("VOXCMD_LEGACY_BIN", root.join("bash-voxcmd"))
            .envs(env.iter().copied())
            .output()
            .unwrap()
    }

    fn no_bash_ran(&self) {
        let calls = std::fs::read_to_string(self.calls()).unwrap_or_default();
        assert!(!calls.contains("BASH-RAN"), "the bash voxcmd ran:\n{calls}");
    }
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

#[test]
fn the_fixture_integrations_check_clean() {
    let sandbox = Sandbox::with(&["apps", "click", "media"]);
    let output = sandbox.voxcmd(&["integrations", "check"], &[]);
    assert_eq!(output.status.code(), Some(0), "{}", stdout(&output));
    assert_eq!(
        stdout(&output),
        "3 TOML files checked, 0 problems; 0 legacy files only loaded and compiled, not checked in depth\n"
    );
    assert_eq!(stderr(&output), "");
    sandbox.no_bash_ran();
}

#[test]
fn problems_are_file_line_column_lines_and_exit_1() {
    let sandbox = Sandbox::with(&["media"]);
    sandbox.write(
        "integrations/broken.toml",
        r#"name = "Broken"
colour = "red"
verbs = [
  { action = "go", match = 'go {nowhere}' },
  { action = "stop", match = 'stop (' },
  { action = "wander", match = 'wander', tone = 1 },
  { action = "twice", match = '{number} and {number}' },
  { action = "yield", match = 'never mind' },
]
[actions]
go = "true"
stop = "true"
twice = { run = "true", colour = "red" }
"#,
    );
    sandbox.write("integrations/syntax.toml", "verbs = 3\n");
    sandbox.write("integrations/hooked.toml", "verbs = []\n");
    sandbox.write("integrations/hooked.sh", "ok() {\nif then\n}\n");
    let output = sandbox.voxcmd(&["integrations", "check"], &[]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(
        stdout(&output),
        "integrations/broken.toml:2:1: error: unknown key \"colour\"\n\
         integrations/broken.toml:6:42: error: unknown verb key \"tone\"\n\
         integrations/broken.toml:13:25: error: action twice: unknown key \"colour\"\n\
         integrations/broken.toml:4:3: error: verb \"go {nowhere}\": {nowhere}: no placeholder, define or intent of that name\n\
         integrations/broken.toml:5:3: error: verb \"stop (\": regex parse error:\n\
         \x20   (?s-u)^(?:stop ()$\n\
         \x20          ^\n\
         error: unclosed group\n\
         integrations/broken.toml:7:3: error: verb \"{number} and {number}\": {number} appears twice\n\
         integrations/broken.toml:6:15: error: verb action \"wander\" is not declared under [actions]\n\
         integrations/hooked.sh:2:1: error: syntax error near unexpected token `then'\n\
         integrations/syntax.toml:1:9: error: invalid type: integer `3`, expected a sequence\n\
         4 TOML files checked, 9 problems; 0 legacy files only loaded and compiled, not checked in depth\n"
    );
    assert_eq!(stderr(&output), "");
    sandbox.no_bash_ran();
}

#[test]
fn check_as_json_and_of_named_files() {
    let sandbox = Sandbox::with(&["media"]);
    sandbox.write(
        "integrations/typo.toml",
        "verbs = [\n  { action = \"go\", match = 'go {nowhere}' },\n]\n[actions]\ngo = \"true\"\n",
    );
    let output = sandbox.voxcmd(&["integrations", "check", "--json", "integrations/typo.toml"], &[]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(
        stdout(&output),
        "{\"ok\":false,\"files\":1,\"problems\":[{\"file\":\"integrations/typo.toml\",\"line\":2,\"column\":3,\
         \"severity\":\"error\",\"code\":\"unknown-name\",\"message\":\"verb \\\"go {nowhere}\\\": {nowhere}: \
         no placeholder, define or intent of that name\"}]}\n"
    );
    let clean = sandbox.voxcmd(&["integrations", "check", "--json", "integrations/media.toml"], &[]);
    assert_eq!(stdout(&clean), "{\"ok\":true,\"files\":1,\"problems\":[]}\n");
    sandbox.no_bash_ran();
}

#[test]
fn list_prints_name_file_and_verbs() {
    let sandbox = Sandbox::with(&["click", "media"]);
    let output = sandbox.voxcmd(&["integrations", "list"], &[]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let text = stdout(&output);
    let file = sandbox.config().join("integrations/media.toml");
    assert!(
        text.contains(&format!("Media ({})\n  toggle play pause|toggle", file.display())),
        "{text}"
    );
    assert!(text.starts_with(&format!(
        "Click ({})\n",
        sandbox.config().join("integrations/click.toml").display()
    )));
    sandbox.no_bash_ran();
}

#[test]
fn list_as_json_has_the_summary_shape() {
    let sandbox = Sandbox::with(&["media"]);
    let output = sandbox.voxcmd(&["integrations", "list", "--json"], &[]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let list: serde_json::Value = serde_json::from_str(&stdout(&output)).unwrap();
    let media = &list[0];
    assert_eq!(media["name"], "Media");
    assert_eq!(media["stem"], "media");
    assert_eq!(media["file"], "integrations/media.toml");
    assert_eq!(media["hook_file"], serde_json::Value::Null);
    assert_eq!(media["fallback"], false);
    assert_eq!(media["verbs"][0]["index"], 0);
    assert_eq!(media["verbs"][0]["line"], 8);
    assert_eq!(media["verbs"][0]["action"], "toggle");
    assert!(
        media["verbs"][0]["regex"]
            .as_str()
            .unwrap()
            .starts_with("(?s-u)^(?:play pause|")
    );
    assert!(media["actions"].as_array().unwrap().contains(&"toggle".into()));
    sandbox.no_bash_ran();
}

#[test]
fn legacy_files_are_loaded_and_counted_but_not_checked_in_depth() {
    let sandbox = Sandbox::with(&["media"]);
    std::fs::create_dir_all(sandbox.config().join("integrations.d")).unwrap();
    // Any content will do: the dump comes from the fixture, not from sourcing the files.
    let dump = Path::new(FIXTURES).join("legacy-dump.jsonl");
    for name in dumped_file_names(&dump) {
        sandbox.write(&format!("integrations.d/{name}"), "");
    }
    let loaded = std::fs::read_to_string(&dump).unwrap().lines().count();
    let output = sandbox.voxcmd(&["integrations", "check"], &[("VOXCMD_LEGACY_DUMP_FILE", &dump)]);
    assert_eq!(output.status.code(), Some(0), "{}", stdout(&output));
    // media.sh is in the dump and media.toml shadows it.
    assert_eq!(
        stdout(&output),
        format!(
            "1 TOML files checked, 0 problems; {} legacy files only loaded and compiled, not checked in depth\n",
            loaded - 1
        )
    );
    sandbox.no_bash_ran();
}

#[test]
fn a_shadowed_verb_is_a_warning_and_leaves_the_check_clean() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write(
        "integrations/twice.toml",
        "verbs = [\n  { action = \"a\", match = 'go' },\n  { action = \"b\", match = 'go' },\n]\n[actions]\na = \"true\"\nb = \"true\"\n",
    );
    let output = sandbox.voxcmd(&["integrations", "check"], &[]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(
        stdout(&output),
        "integrations/twice.toml:3:3: warning: verb \"go\" can never match: verb 0 (\"a\") matches the same phrases first\n\
         1 TOML files checked, 1 problems; 0 legacy files only loaded and compiled, not checked in depth\n"
    );
    let json = sandbox.voxcmd(&["integrations", "check", "--json"], &[]);
    assert_eq!(json.status.code(), Some(0));
    assert!(stdout(&json).starts_with("{\"ok\":true,\"files\":1,\"problems\":[{"));
    assert!(stdout(&json).contains("\"severity\":\"warning\",\"code\":\"shadowed-verb\""));
    sandbox.no_bash_ran();
}

#[test]
fn a_named_legacy_file_is_loaded_itself_and_a_missing_one_is_a_problem() {
    let sandbox = Sandbox::with(&[]);
    let dump = Path::new(FIXTURES).join("legacy-dump.jsonl");
    let dump_env = [("VOXCMD_LEGACY_DUMP_FILE", dump.as_path())];
    // Outside the config dir, and no integrations.d at all.
    let outside = sandbox.root.path().join("apps.sh");
    std::fs::write(&outside, "").unwrap();
    let outside_arg = outside.to_str().unwrap();
    let loaded = sandbox.voxcmd(&["integrations", "check", outside_arg], &dump_env);
    assert_eq!(loaded.status.code(), Some(0), "{}", stdout(&loaded));
    assert!(
        stdout(&loaded).contains("1 legacy files only loaded"),
        "{}",
        stdout(&loaded)
    );
    let missing = sandbox.voxcmd(&["integrations", "check", "--json", "nowhere.sh"], &dump_env);
    assert_eq!(missing.status.code(), Some(1));
    assert!(
        stdout(&missing).contains("\"code\":\"unreadable\""),
        "{}",
        stdout(&missing)
    );
    sandbox.no_bash_ran();
}

#[test]
fn a_shadowed_verb_needs_the_earlier_verb_to_be_as_eligible() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write(
        "integrations/gated.toml",
        "verbs = [\n  { action = \"a\", match = 'go', requires = 'absent' },\n  { action = \"b\", match = 'go' },\n]\n[actions]\na = \"true\"\nb = \"true\"\n",
    );
    let output = sandbox.voxcmd(&["integrations", "check"], &[]);
    assert_eq!(output.status.code(), Some(0));
    assert!(!stdout(&output).contains("shadowed-verb") && !stdout(&output).contains("can never match"));
}

#[test]
fn a_verb_whose_typed_capture_can_reject_does_not_shadow_a_later_one() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write(
        "integrations/typed.toml",
        "verbs = [\n  { action = \"a\", match = 'go {value:position}' },\n  { action = \"b\", match = 'go {value:text}' },\n]\n[actions]\na = \"true\"\nb = \"true\"\n",
    );
    let output = sandbox.voxcmd(&["integrations", "check"], &[]);
    assert_eq!(output.status.code(), Some(0));
    assert!(!stdout(&output).contains("shadowed-verb") && !stdout(&output).contains("can never match"));
}

#[test]
fn a_mistyped_surface_key_is_an_unknown_key() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write(
        "integrations/surf.toml",
        "verbs = [\n  { action = \"a\", match = 'go' },\n]\n[actions]\na = \"true\"\n[surface]\nstate_file = \"/tmp/x\"\nstate_flie = \"/tmp/x\"\n",
    );
    let output = sandbox.voxcmd(&["integrations", "check"], &[]);
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stdout(&output).contains("integrations/surf.toml:8:1: error: unknown surface key \"state_flie\""),
        "{}",
        stdout(&output)
    );
}

fn dumped_file_names(dump: &Path) -> Vec<String> {
    std::fs::read_to_string(dump)
        .unwrap()
        .lines()
        .map(|line| {
            let value: serde_json::Value = serde_json::from_str(line).unwrap();
            let file = value["file"].as_str().unwrap().to_string();
            file.rsplit('/').next().unwrap().to_string()
        })
        .collect()
}

#[test]
fn a_legacy_file_that_fails_to_source_is_a_legacy_load_problem() {
    let sandbox = Sandbox::with(&[]);
    std::fs::create_dir_all(sandbox.config().join("integrations.d")).unwrap();
    for name in dumped_file_names(&Path::new(FIXTURES).join("legacy-dump.jsonl")) {
        sandbox.write(&format!("integrations.d/{name}"), "");
    }
    // On disk but absent from the dump, as a file that fails while sourced is.
    sandbox.write("integrations.d/broken.sh", "");
    let dump = Path::new(FIXTURES).join("legacy-dump.jsonl");
    let output = sandbox.voxcmd(
        &["integrations", "check", "--json"],
        &[("VOXCMD_LEGACY_DUMP_FILE", &dump)],
    );
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stdout(&output).contains("\"code\":\"legacy-load\""),
        "{}",
        stdout(&output)
    );
    assert!(
        stdout(&output).contains("integrations.d/broken.sh"),
        "{}",
        stdout(&output)
    );
}

#[test]
fn an_unknown_builtin_wait_is_a_problem() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write(
        "integrations/waits.toml",
        "verbs = [\n  { action = \"a\", match = 'go' },\n]\n[actions.a]\nrun = \"true\"\nwait = \"active_window_chagned\"\n",
    );
    let output = sandbox.voxcmd(&["integrations", "check"], &[]);
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stdout(&output)
            .contains("integrations/waits.toml:6:1: error: action a: unknown wait \"active_window_chagned\""),
        "{}",
        stdout(&output)
    );
    sandbox.write(
        "integrations/waits.toml",
        "verbs = [\n  { action = \"a\", match = 'go' },\n]\n[actions.a]\nrun = \"true\"\nwait = \"popup_open:menu\"\n",
    );
    assert_eq!(sandbox.voxcmd(&["integrations", "check"], &[]).status.code(), Some(0));
}

// ---- examples and help ----------------------------------------------------------------------------------------------

const LAMP: &str = r#"name = "Lamp"
verbs = [{ action = "on", match = "lamp on" }]
examples = ["lamp on", "lamp dim to <level>"]
[actions]
on = "echo lit >> LOG"
"#;

impl Sandbox {
    /// A stub `notify-send` (logging `summary: body` lines) and an ask stub that logs its arguments and answers `pick`
    /// when asked to; returns the paths of both logs.
    fn with_stubs(&self, pick: &str) -> (std::path::PathBuf, std::path::PathBuf) {
        let bin = self.root.path().join("bin");
        std::fs::create_dir_all(&bin).unwrap();
        let toasts = self.root.path().join("toasts.log");
        let asked = self.root.path().join("asked.log");
        let script = |name: &str, body: String| {
            let path = bin.join(name);
            std::fs::write(&path, format!("#!/bin/sh\n{body}\n")).unwrap();
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        };
        script("notify-send", format!("echo \"$4: $5\" >> {}", toasts.display()));
        script("ask", format!("echo \"$@\" >> {}\n{pick}", asked.display()));
        (toasts, asked)
    }

    fn help(&self, pick: &str) -> (Output, String, String) {
        let (toasts, asked) = self.with_stubs(pick);
        let bin = self.root.path().join("bin");
        let path = std::path::PathBuf::from(format!("{}:/usr/bin:/bin", bin.display()));
        let output = self.voxcmd(&["help"], &[("PATH", &path), ("VOXCMD_ASK_CMD", &bin.join("ask"))]);
        let read = |file: std::path::PathBuf| std::fs::read_to_string(file).unwrap_or_default();
        (output, read(toasts), read(asked))
    }

    fn lamp(&self) -> std::path::PathBuf {
        let log = self.root.path().join("lamp.log");
        self.write(
            "integrations/lamp.toml",
            &LAMP.replace("LOG", &log.display().to_string()),
        );
        log
    }
}

#[test]
fn examples_are_listed_by_integration() {
    let sandbox = Sandbox::with(&["media"]);
    let output = sandbox.voxcmd(&["integrations", "examples"], &[]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let text = stdout(&output);
    assert!(
        text.starts_with("Media (integrations/media.toml)\n  play pause\n  next track\n"),
        "{text}"
    );
    let json = sandbox.voxcmd(&["integrations", "examples", "--json"], &[]);
    let listed: serde_json::Value = serde_json::from_str(&stdout(&json)).unwrap();
    assert_eq!(listed[0]["stem"], "media");
    assert_eq!(listed[0]["examples"][0], "play pause");
    sandbox.no_bash_ran();
}

#[test]
fn route_is_clean_when_every_example_lands_on_its_integration() {
    let sandbox = Sandbox::with(&["media"]);
    sandbox.lamp();
    let output = sandbox.voxcmd(&["integrations", "examples", "--route"], &[]);
    assert_eq!(output.status.code(), Some(0), "{}", stdout(&output));
    // Media's three placeholder examples and Lamp's one are skipped.
    assert!(
        stdout(&output).ends_with(
            "5 examples route to their integration (0 only in their surface or mode), 0 do not; skipped 4 with a <placeholder> and 0 said inside a mode\n"
        ),
        "{}",
        stdout(&output)
    );
    sandbox.no_bash_ran();
}

#[test]
fn route_names_an_example_that_misses_or_lands_elsewhere_and_exits_1() {
    let sandbox = Sandbox::with(&["media"]);
    sandbox.write(
        "integrations/lamp.toml",
        &LAMP
            .replace("echo lit >> LOG", "true")
            .replace(r#""lamp on", "#, r#""lamp on", "mute", "lamp off", "#),
    );
    let output = sandbox.voxcmd(&["integrations", "examples", "--route"], &[]);
    assert_eq!(output.status.code(), Some(1));
    let text = stdout(&output);
    assert!(text.contains("Lamp: \"mute\" routes to Media\n"), "{text}");
    assert!(text.contains("Lamp: \"lamp off\" routes to no match\n"), "{text}");
    assert!(!text.contains("\"lamp on\""), "{text}");
    let json = sandbox.voxcmd(&["integrations", "examples", "--route", "--json"], &[]);
    let report: serde_json::Value = serde_json::from_str(&stdout(&json)).unwrap();
    assert_eq!(json.status.code(), Some(1));
    assert_eq!(report["misrouted"][1]["routed_to"], serde_json::json!([]));
    sandbox.no_bash_ran();
}

const PANE: &str = r#"name = "Pane"
verbs = [{ action = "next", match = "pane next" }]
examples = ["pane next", "next", "bogus", "<anything>"]
[actions]
next = "true"
[mode]
rewrite = { prefix = "pane " }
"#;

#[test]
fn route_checks_a_toml_mode_example_through_the_modes_rewrite() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write("integrations/pane.toml", PANE);
    let output = sandbox.voxcmd(&["integrations", "examples", "--route", "--json"], &[]);
    let report: serde_json::Value = serde_json::from_str(&stdout(&output)).unwrap();
    // "pane next" routes as spoken, "next" only once the mode has made it "pane next"; "bogus" stays wrong in the mode.
    assert_eq!(output.status.code(), Some(1), "{report}");
    assert_eq!((&report["routed"], &report["routed_in_scope"]), (&2.into(), &1.into()));
    assert_eq!((&report["skipped"], &report["in_mode"]), (&1.into(), &0.into()));
    assert_eq!(report["misrouted"].as_array().unwrap().len(), 1, "{report}");
    assert_eq!(report["misrouted"][0]["example"], "bogus");
    sandbox.no_bash_ran();
}

#[test]
fn route_checks_a_toml_surface_example_with_the_surface_open() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write(
        "integrations/dial.toml",
        "name = \"Dial\"\nverbs = [{ action = \"on\", match = \"lamp on\" }]\nexamples = [\"lamp on\"]\n\
         [actions]\non = \"true\"\n[surface]\nstate_file = \"dial.json\"\n",
    );
    sandbox.write(
        "integrations/lamp.toml",
        &LAMP.replace("echo lit >> LOG", "true").replace(r#""lamp on", "#, ""),
    );
    let output = sandbox.voxcmd(&["integrations", "examples", "--route", "--json"], &[]);
    let report: serde_json::Value = serde_json::from_str(&stdout(&output)).unwrap();
    // Lamp takes the phrase too while the dial is closed; open, the dial has it alone.
    assert_eq!(output.status.code(), Some(0), "{report}");
    assert_eq!((&report["routed"], &report["routed_in_scope"]), (&1.into(), &1.into()));
    assert_eq!(report["in_mode"], 0);
}

impl Sandbox {
    /// `integrations examples --route --json`, parsed.
    fn route_report(&self) -> (Option<i32>, serde_json::Value) {
        let output = self.voxcmd(&["integrations", "examples", "--route", "--json"], &[]);
        (output.status.code(), serde_json::from_str(&stdout(&output)).unwrap())
    }
}

fn counts(report: &serde_json::Value) -> [i64; 4] {
    ["routed", "routed_in_scope", "skipped", "in_mode"].map(|key| report[key].as_i64().unwrap())
}

#[test]
fn route_names_what_only_routes_in_scope_in_the_text_line() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write("integrations/pane.toml", &PANE.replace(r#""bogus", "#, ""));
    let output = sandbox.voxcmd(&["integrations", "examples", "--route"], &[]);
    assert_eq!(
        stdout(&output),
        "2 examples route to their integration (1 only in their surface or mode), 0 do not; \
         skipped 1 with a <placeholder> and 0 said inside a mode\n"
    );
}

#[test]
fn route_gives_a_rewritten_example_no_near_miss_pick_as_a_session_turn_has_none() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write(
        "integrations/pane.toml",
        &PANE
            .replace(r#"match = "pane next""#, r#"match = "pane go next""#)
            .replace(r#""pane next", "next", "bogus", "<anything>""#, r#""next go""#),
    );
    let (code, report) = sandbox.route_report();
    assert_eq!(code, Some(1), "{report}");
    assert_eq!(report["misrouted"][0]["example"], "next go");
    assert_eq!(counts(&report)[1], 0);
}

#[test]
fn route_skips_a_wake_word_example_and_one_the_mode_drops() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write(
        "integrations/pane.toml",
        &PANE
            .replace(r#""bogus", "<anything>""#, r#""cortana done", "stop""#)
            .replace(r#"{ prefix = "pane " }"#, r#"{ prefix = "pane ", drop = "stop" }"#),
    );
    let (code, report) = sandbox.route_report();
    assert_eq!(code, Some(0), "{report}");
    assert_eq!(counts(&report), [2, 1, 0, 2]);
}

#[test]
fn route_leaves_a_kept_phrase_as_spoken() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write(
        "integrations/pane.toml",
        &PANE.replace(r#"{ prefix = "pane " }"#, r#"{ prefix = "pane ", keep = "bogus" }"#),
    );
    let (code, report) = sandbox.route_report();
    // "bogus" is kept unprefixed, so it still misses; "next" gets the prefix.
    assert_eq!(code, Some(1), "{report}");
    assert_eq!(report["misrouted"][0]["example"], "bogus");
    assert_eq!(counts(&report)[..2], [2, 1]);
}

#[test]
fn route_skips_a_miss_of_a_mode_that_rewrites_by_hook() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write(
        "integrations/pane.toml",
        &PANE.replace(r#"rewrite = { prefix = "pane " }"#, "rewrite_hook = \"cat\""),
    );
    let (code, report) = sandbox.route_report();
    assert_eq!(code, Some(0), "{report}");
    assert_eq!(counts(&report), [1, 0, 1, 2]);
}

#[test]
fn route_tries_the_surface_before_skipping_a_hook_rewriting_mode() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write(
        "integrations/dial.toml",
        "name = \"Dial\"\nverbs = [{ action = \"on\", match = \"lamp on\" }]\nexamples = [\"lamp on\", \"bogus\"]\n\
         [actions]\non = \"true\"\n[surface]\nstate_file = \"dial.json\"\n[mode]\nrewrite_hook = \"cat\"\n",
    );
    sandbox.write(
        "integrations/lamp.toml",
        &LAMP.replace("echo lit >> LOG", "true").replace(r#""lamp on", "#, ""),
    );
    let (code, report) = sandbox.route_report();
    assert_eq!(code, Some(0), "{report}");
    // "lamp on" is the dial's only with the surface open; "bogus" misses there too, and the hook cannot be run.
    assert_eq!(counts(&report), [1, 1, 1, 1]);
}

#[test]
fn route_skips_a_miss_of_a_surface_whose_candidates_hooks_read_its_closed_state_file() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write(
        "integrations/dial.toml",
        "name = \"Dial\"\nverbs = [{ action = \"on\", match = \"turn {target} on\" }]\nexamples = [\"turn two on\"]\n\
         [actions.on]\nrun = \"true\"\ncandidates = \"printf 'one\\\\tOne\\\\n'\"\n[surface]\nstate_file = \"dial.json\"\n",
    );
    let (code, report) = sandbox.route_report();
    assert_eq!(code, Some(0), "{report}");
    assert_eq!(counts(&report), [0, 0, 0, 1]);
}

#[test]
fn route_still_skips_every_example_of_a_legacy_integration_with_a_surface() {
    let sandbox = Sandbox::with(&[]);
    let overview = std::fs::read_to_string(Path::new(FIXTURES).join("legacy-dump.jsonl"))
        .unwrap()
        .lines()
        .find(|line| line.contains("\"Overview\""))
        .unwrap()
        .to_string();
    let dump = sandbox.root.path().join("dump.jsonl");
    std::fs::write(&dump, format!("{overview}\n")).unwrap();
    std::fs::create_dir_all(sandbox.config().join("integrations.d")).unwrap();
    sandbox.write("integrations.d/overview.sh", "");
    let output = sandbox.voxcmd(
        &["integrations", "examples", "--route"],
        &[("VOXCMD_LEGACY_DUMP_FILE", &dump)],
    );
    assert_eq!(output.status.code(), Some(0), "{}", stdout(&output));
    assert_eq!(
        stdout(&output),
        "0 examples route to their integration (0 only in their surface or mode), 0 do not; \
         skipped 0 with a <placeholder> and 21 said inside a mode\n"
    );
}

#[test]
fn help_routes_a_picked_example_as_if_spoken() {
    let sandbox = Sandbox::with(&[]);
    let lit = sandbox.lamp();
    let (output, toasts, asked) = sandbox.help("echo say:lamp on");
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    assert_eq!(std::fs::read_to_string(lit).unwrap(), "lit\n");
    assert!(toasts.contains("voxcmd: Lamp: on"), "{toasts}");
    assert!(
        asked.starts_with("pick Voice Help [{\"id\":\"say:lamp on\",\"label\":\"Lamp: lamp on\"}"),
        "{asked}"
    );
    assert!(
        asked.trim_end().ends_with("{}"),
        "no integration lists choices: {asked}"
    );
    sandbox.no_bash_ran();
}

#[test]
fn help_shows_a_picked_placeholder_example_as_a_toast_and_runs_nothing() {
    let sandbox = Sandbox::with(&[]);
    let lit = sandbox.lamp();
    let (output, toasts, _) = sandbox.help("echo 'say:lamp dim to <level>'");
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    assert_eq!(toasts, "voxcmd: Say: lamp dim to &lt;level&gt;\n");
    assert!(!lit.exists());
}

#[test]
fn help_cancelled_is_not_a_failure() {
    let sandbox = Sandbox::with(&[]);
    let lit = sandbox.lamp();
    let (output, toasts, _) = sandbox.help("exit 1");
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    assert_eq!((toasts.as_str(), lit.exists()), ("", false));
}

#[test]
fn help_answered_with_nothing_cancels_like_a_cancelled_pick() {
    let sandbox = Sandbox::with(&[]);
    let lit = sandbox.lamp();
    let (output, toasts, _) = sandbox.help("exit 0");
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    assert_eq!((toasts.as_str(), lit.exists()), ("", false));
}

#[test]
fn help_without_examples_toasts_and_exits_1_without_asking() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write(
        "integrations/quiet.toml",
        "name = \"Quiet\"\nverbs = [{ action = \"a\", match = \"quiet\" }]\n[actions]\na = \"true\"\n",
    );
    let (output, toasts, asked) = sandbox.help("echo say:quiet");
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(toasts, "voxcmd: No integration declares examples\n");
    assert_eq!(asked, "");
}

// ---- [[help]] -------------------------------------------------------------------------------------------------------

/// Three `[[help]]` entries over one action: a list hook, a static row with an empty id, and the action's candidates.
const SCENES: &str = r#"name = "Scenes"
verbs = [{ action = "set", match = "scene {target}" }]
examples = ["scene movie"]
[actions.set]
run = 'echo "$VOXCMD_ID" >> LOG'
candidates = "[ -z \"${VOXCMD_ARG_TARGET:-}\" ] || exit 5; printf 'day\\tDay scene\\nnight\\tNight scene\\n'"

[[help]]
action = "set"
list = "printf 'dusk\\tDusk scene\\nbare\\n'"

[[help]]
action = "set"
id = ""
label = "Lights off"

[[help]]
action = "set"
"#;

impl Sandbox {
    fn scenes(&self) -> std::path::PathBuf {
        let log = self.root.path().join("scenes.log");
        self.write(
            "integrations/scenes.toml",
            &SCENES.replace("LOG", &log.display().to_string()),
        );
        log
    }
}

#[test]
fn help_lists_the_rows_of_every_help_entry_as_runnables_without_bash() {
    let sandbox = Sandbox::with(&[]);
    sandbox.scenes();
    let (output, _, asked) = sandbox.help("echo run:0");
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let expansion = r#""scenes":{"choices":[{"id":"run:0","label":"Dusk scene"},{"id":"run:1","label":"bare"},{"id":"run:2","label":"Lights off"},{"id":"run:3","label":"Day scene"},{"id":"run:4","label":"Night scene"}],"title":"Scenes"}"#;
    assert!(asked.contains(expansion), "{asked}");
    assert!(asked.contains(r#""expand":"scenes""#), "{asked}");
    sandbox.no_bash_ran();
}

#[test]
fn help_runs_a_picked_row_with_its_id() {
    for (pick, ran) in [("run:0", "dusk\n"), ("run:2", "\n"), ("run:4", "night\n")] {
        let sandbox = Sandbox::with(&[]);
        let log = sandbox.scenes();
        let (output, _, _) = sandbox.help(&format!("echo {pick}"));
        assert_eq!(output.status.code(), Some(0), "{pick}: {}", stderr(&output));
        assert_eq!(std::fs::read_to_string(log).unwrap_or_default(), ran, "{pick}");
    }
}

#[test]
fn a_failing_help_list_lists_nothing_and_help_still_works() {
    let sandbox = Sandbox::with(&[]);
    sandbox.write(
        "integrations/broken.toml",
        "verbs = [{ action = \"a\", match = \"go\" }]\nexamples = [\"go\"]\n[actions]\na = \"true\"\n[[help]]\naction = \"a\"\nlist = \"exit 4\"\n",
    );
    let (output, _, asked) = sandbox.help("echo say:go");
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    assert!(asked.trim_end().ends_with("{}"), "{asked}");
}

#[test]
fn check_validates_help_entries_with_file_line_column() {
    let sandbox = Sandbox::with(&[]);
    sandbox.scenes();
    assert_eq!(sandbox.voxcmd(&["integrations", "check"], &[]).status.code(), Some(0));
    let head = "verbs = [{ action = \"a\", match = \"go\" }]\n[actions]\na = \"true\"\n";
    for (entry, expected) in [
        (
            "[[help]]\naction = \"a\"\nlist = \"true\"\nlabel = \"x\"\n",
            "integrations/h.toml:4:1: error: [[help]] list and id/label are both set; use one",
        ),
        (
            "[[help]]\nid = \"x\"\n",
            "integrations/h.toml:4:1: error: missing field `action`",
        ),
        (
            "[[help]]\naction = \"a\"\nid = \"x\"\n",
            "integrations/h.toml:4:1: error: [[help]] a static row with an id needs a label",
        ),
        (
            "[[help]]\naction = \"nope\"\n",
            "integrations/h.toml:5:1: error: [[help]] action \"nope\" is not declared under [actions]",
        ),
        (
            "[[help]]\n\"action\" = \"nope\"\n",
            "integrations/h.toml:5:2: error: [[help]] action \"nope\" is not declared under [actions]",
        ),
        (
            "[[help]]\naction = \"a\"\nlabell = \"x\"\n",
            "integrations/h.toml:6:1: error: unknown help key \"labell\"",
        ),
    ] {
        sandbox.write("integrations/h.toml", &format!("{head}{entry}"));
        let output = sandbox.voxcmd(&["integrations", "check", "integrations/h.toml"], &[]);
        assert_eq!(output.status.code(), Some(1), "{entry}");
        assert!(stdout(&output).contains(expected), "{entry}\n{}", stdout(&output));
    }
}

#[test]
fn a_help_list_runs_under_its_actions_timeout_and_the_lists_run_side_by_side() {
    let sandbox = Sandbox::with(&[]);
    // `slow` outlasts the 3 s default but not its own 5 s; `cut` is held to 0.3 s. Both hooks run together.
    sandbox.write(
        "integrations/timeouts.toml",
        r#"verbs = [{ action = "slow", match = "go" }]
examples = ["go"]
[actions.slow]
run = "true"
timeout_secs = 5
[actions.cut]
run = "true"
timeout_secs = 0.3

[[help]]
action = "slow"
list = "sleep 3.2; echo late"

[[help]]
action = "cut"
list = "sleep 2; echo never"
"#,
    );
    let started = std::time::Instant::now();
    let (output, _, asked) = sandbox.help("echo run:0");
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    assert!(asked.contains(r#"{"id":"run:0","label":"late"}]"#), "{asked}");
    assert!(!asked.contains("never"), "{asked}");
    assert!(
        started.elapsed().as_secs_f64() < 5.0,
        "the lists ran one after the other"
    );
}

#[test]
fn the_shipped_click_toml_is_the_fixture_the_other_tests_read() {
    let shipped = concat!(env!("CARGO_MANIFEST_DIR"), "/.config/voxcmd/integrations/click.toml");
    assert_eq!(
        std::fs::read_to_string(shipped).unwrap(),
        std::fs::read_to_string(format!("{FIXTURES}/integrations/click.toml")).unwrap(),
        "click.toml and tests/fixtures/integrations/click.toml must stay the same file: copy one over the other"
    );
}
