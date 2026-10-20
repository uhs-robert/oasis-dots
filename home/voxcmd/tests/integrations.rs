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
         integrations/broken.toml:6:1: error: unknown verb key \"tone\"\n\
         integrations/broken.toml:13:1: error: action twice: unknown key \"colour\"\n\
         integrations/broken.toml:4:1: error: verb \"go {nowhere}\": {nowhere}: no placeholder, define or intent of that name\n\
         integrations/broken.toml:5:1: error: verb \"stop (\": regex parse error:\n\
         \x20   (?s-u)^(?:stop ()$\n\
         \x20          ^\n\
         error: unclosed group\n\
         integrations/broken.toml:7:1: error: verb \"{number} and {number}\": {number} appears twice\n\
         integrations/broken.toml:6:1: error: verb action \"wander\" is not declared under [actions]\n\
         integrations/hooked.sh:2:1: error: syntax error near unexpected token `then'\n\
         integrations/syntax.toml:1:1: error: invalid type: integer `3`, expected a sequence\n\
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
        "{\"ok\":false,\"files\":1,\"problems\":[{\"file\":\"integrations/typo.toml\",\"line\":2,\"column\":1,\
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
    // Any file will do: the dump comes from the fixture, not from sourcing it.
    sandbox.write("integrations.d/anything.sh", "");
    let dump = Path::new(FIXTURES).join("legacy-dump.jsonl");
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
