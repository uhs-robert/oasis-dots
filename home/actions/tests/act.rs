//! Runs the built `act` against a temp manifest and a stub qs-ipc that records its arguments.

use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::OnceLock;

const ACTIONS: &str = r#"{"actions": [
  {"id": "t.go", "label": "Go", "intent": "Go.", "params": [
    {"name": "n", "type": "int"},
    {"name": "mode", "type": "enum", "values": ["a", "b"], "default": "a"},
    {"name": "flag", "type": "bool", "default": false}],
   "key": {"key": "G", "leader": true, "universal": false}, "extra_keys": []},
  {"id": "t.run", "label": "Run", "intent": "Run.", "params": [],
   "key": {"key": "R", "leader": true, "universal": false}, "extra_keys": []},
  {"id": "t.nobind", "label": "None", "intent": "None.", "params": [],
   "key": {"key": "N", "leader": true, "universal": false}, "extra_keys": []}
]}"#;

const BINDINGS: &str = r#"{"bindings": {
  "t.go": {"kind": "ipc", "target": "thing", "function": "go", "args": ["{n}", "{mode}", "{flag}"]},
  "t.run": {"kind": "command", "argv": ["{stub}", "ran", "--x"]}
}}"#;

/// One stub for the whole test binary, written before any test spawns anything: a script still open for writing
/// when another thread forks fails to exec with ETXTBSY.
fn stub() -> &'static Path {
    static STUB: OnceLock<PathBuf> = OnceLock::new();
    STUB.get_or_init(|| {
        let path = std::env::temp_dir().join(format!("act-stub-{}", std::process::id()));
        std::fs::write(
            &path,
            "#!/bin/sh\necho \"$@\" >> \"$STUB_LOG\"\n[ -z \"$STUB_FAIL\" ]\n",
        )
        .unwrap();
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        path
    })
}

struct Sandbox {
    root: PathBuf,
    manifest: PathBuf,
}

impl Sandbox {
    fn new(name: &str) -> Sandbox {
        let root = std::env::temp_dir().join(format!("act-test-{}-{name}", std::process::id()));
        let manifest = root.join("actions");
        std::fs::create_dir_all(manifest.join("bindings")).unwrap();
        std::fs::write(manifest.join("actions.json"), ACTIONS).unwrap();
        let bindings = BINDINGS.replace("{stub}", stub().to_str().unwrap());
        std::fs::write(manifest.join("bindings/quickshell.json"), bindings).unwrap();
        Sandbox { root, manifest }
    }

    fn log(&self) -> PathBuf {
        self.root.join("log")
    }

    fn act_in(&self, manifest: &Path, env: &[(&str, &str)], args: &[&str]) -> (i32, String) {
        let done = Command::new(env!("CARGO_BIN_EXE_act"))
            .args(args)
            .env("ACT_CONFIG_DIR", manifest)
            .env("ACT_QS_IPC", stub())
            .env("STUB_LOG", self.log())
            .envs(env.iter().copied())
            .output()
            .unwrap();
        (
            done.status.code().unwrap(),
            String::from_utf8_lossy(&done.stderr).into_owned(),
        )
    }

    fn act(&self, args: &[&str]) -> (i32, String) {
        self.act_in(&self.manifest, &[], args)
    }

    fn calls(&self) -> Vec<String> {
        std::fs::read_to_string(self.log())
            .map(|text| text.lines().map(String::from).collect())
            .unwrap_or_default()
    }

    /// Exits 2 with `needle` in the message and no call made.
    fn rejected(&self, args: &[&str], needle: &str) {
        let (code, message) = self.act(args);
        assert_eq!(code, 2, "{message}");
        assert!(message.contains(needle), "{needle:?} not in {message:?}");
        assert!(self.calls().is_empty());
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn real_manifest() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join(".config/actions")
}

#[test]
fn an_ipc_action_calls_qs_ipc_with_its_params() {
    let sandbox = Sandbox::new("ipc");
    assert_eq!(sandbox.act(&["t.go", "3", "b", "true"]).0, 0);
    assert_eq!(sandbox.calls(), ["call thing go 3 b true"]);
}

#[test]
fn defaults_fill_the_params_left_out() {
    let sandbox = Sandbox::new("defaults");
    sandbox.act(&["t.go", "3"]);
    assert_eq!(sandbox.calls(), ["call thing go 3 a false"]);
}

#[test]
fn a_command_action_runs_its_argv() {
    let sandbox = Sandbox::new("command");
    assert_eq!(sandbox.act(&["t.run"]).0, 0);
    assert_eq!(sandbox.calls(), ["ran --x"]);
}

#[test]
fn a_failing_performer_exits_1() {
    let sandbox = Sandbox::new("failing");
    assert_eq!(
        sandbox.act_in(&sandbox.manifest, &[("STUB_FAIL", "1")], &["t.run"]).0,
        1
    );
}

#[test]
fn a_missing_program_exits_1() {
    let sandbox = Sandbox::new("missing");
    let missing = std::fs::read_to_string(sandbox.manifest.join("bindings/quickshell.json"))
        .unwrap()
        .replace(stub().to_str().unwrap(), "/nonexistent/prog");
    std::fs::write(sandbox.manifest.join("bindings/quickshell.json"), missing).unwrap();
    assert_eq!(sandbox.act(&["t.run"]).0, 1);
}

#[test]
fn an_unknown_id_exits_2_without_a_call() {
    Sandbox::new("unknown").rejected(&["nope.x"], "unknown action 'nope.x'");
}

#[test]
fn no_id_exits_2() {
    Sandbox::new("noid").rejected(&[], "usage");
}

#[test]
fn a_wrong_typed_param_exits_2() {
    Sandbox::new("type").rejected(&["t.go", "three"], "param n");
}

#[test]
fn a_value_outside_an_enum_exits_2() {
    Sandbox::new("enum").rejected(&["t.go", "3", "c"], "not one of a, b");
}

#[test]
fn a_bad_bool_exits_2() {
    Sandbox::new("bool").rejected(&["t.go", "3", "a", "yes"], "param flag");
}

#[test]
fn a_missing_required_param_exits_2() {
    Sandbox::new("required").rejected(&["t.go"], "needs param n");
}

#[test]
fn too_many_params_exit_2() {
    Sandbox::new("many").rejected(&["t.run", "extra"], "takes 0 param(s)");
}

#[test]
fn an_action_without_a_binding_exits_2() {
    Sandbox::new("nobind").rejected(&["t.nobind"], "no quickshell binding");
}

#[test]
fn a_missing_manifest_exits_2() {
    let sandbox = Sandbox::new("nomanifest");
    let (code, message) = sandbox.act_in(&sandbox.root.join("none"), &[], &["t.run"]);
    assert_eq!(code, 2, "{message}");
}

#[test]
fn the_real_manifest_performs_the_ipc_actions() {
    let sandbox = Sandbox::new("real-ipc");
    for (action, call) in [
        ("zoom.toggle", "call zoom toggle"),
        ("overview.open", "call overview open"),
    ] {
        assert_eq!(sandbox.act_in(&real_manifest(), &[], &[action]).0, 0);
        assert_eq!(sandbox.calls().last().unwrap(), call);
    }
}

#[test]
fn the_real_screenshot_actions_name_the_script_under_home() {
    let sandbox = Sandbox::new("real-shot");
    let home = sandbox.root.to_str().unwrap();
    for action in ["screenshot.take", "screenshot.pixel"] {
        let (code, message) = sandbox.act_in(&real_manifest(), &[("HOME", home)], &[action]);
        assert_eq!(code, 1, "{message}"); // no script in the fake home: the command was built and tried
        assert!(
            message.contains(&format!("{home}/.config/hypr/scripts/screenshot.sh")),
            "{message}"
        );
    }
}
