//! Runs the built `oasis-djinn` against a temp manifest and a stub qs-ipc that records its arguments.

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
        let path = std::env::temp_dir().join(format!("djinn-stub-{}", std::process::id()));
        std::fs::write(
            &path,
            "#!/bin/sh\necho \"$@\" >> \"$STUB_LOG\"\n[ -z \"$STUB_OUT\" ] || echo \"$STUB_OUT\"\n[ -z \"$STUB_BACKGROUND\" ] || sleep 10 &\n[ -z \"$STUB_FAIL\" ]\n",
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
        let root = std::env::temp_dir().join(format!("djinn-test-{}-{name}", std::process::id()));
        let manifest = root.join("oasis-djinn");
        std::fs::create_dir_all(manifest.join("bindings")).unwrap();
        std::fs::write(manifest.join("actions.json"), ACTIONS).unwrap();
        let bindings = BINDINGS.replace("{stub}", stub().to_str().unwrap());
        std::fs::write(manifest.join("bindings/quickshell.json"), bindings).unwrap();
        Sandbox { root, manifest }
    }

    /// Replaces the manifest with one action `t.x` taking `params` (a JSON array) and calling `thing x` with `args`.
    fn with_action(&self, params: &str, args: &str) {
        let actions = format!(
            r#"{{"actions": [{{"id": "t.x", "label": "X", "intent": "X.", "params": {params},
              "key": {{"key": "X", "leader": true, "universal": false}}, "extra_keys": []}}]}}"#
        );
        let bindings = format!(
            r#"{{"bindings": {{"t.x": {{"kind": "ipc", "target": "thing", "function": "x", "args": {args}}}}}}}"#
        );
        std::fs::write(self.manifest.join("actions.json"), actions).unwrap();
        std::fs::write(self.manifest.join("bindings/quickshell.json"), bindings).unwrap();
    }

    /// Adds `bindings/hyprland.json` with `text`, the lua-kind bindings performed through `hyprctl eval`.
    fn with_hyprland(&self, text: &str) {
        std::fs::write(self.manifest.join("bindings/hyprland.json"), text).unwrap();
    }

    fn log(&self) -> PathBuf {
        self.root.join("log")
    }

    fn run_in(&self, manifest: &Path, env: &[(&str, &str)], args: &[&str]) -> (i32, String) {
        let done = Command::new(env!("CARGO_BIN_EXE_oasis-djinn"))
            .args(args)
            .env("OASIS_DJINN_CONFIG_DIR", manifest)
            .env("OASIS_DJINN_QS_IPC", stub())
            .env("OASIS_DJINN_HYPRCTL", stub())
            .env("STUB_LOG", self.log())
            .envs(env.iter().copied())
            .output()
            .unwrap();
        (
            done.status.code().unwrap(),
            String::from_utf8_lossy(&done.stderr).into_owned(),
        )
    }

    fn run(&self, args: &[&str]) -> (i32, String) {
        self.run_in(&self.manifest, &[], args)
    }

    fn calls(&self) -> Vec<String> {
        std::fs::read_to_string(self.log())
            .map(|text| text.lines().map(String::from).collect())
            .unwrap_or_default()
    }

    /// Exits 2 with `needle` in the message and no call made.
    fn rejected(&self, args: &[&str], needle: &str) {
        let (code, message) = self.run(args);
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
    Path::new(env!("CARGO_MANIFEST_DIR")).join(".config/oasis-djinn")
}

#[test]
fn an_ipc_action_calls_qs_ipc_with_its_params() {
    let sandbox = Sandbox::new("ipc");
    assert_eq!(sandbox.run(&["t.go", "3", "b", "true"]).0, 0);
    assert_eq!(sandbox.calls(), ["call thing go 3 b true"]);
}

#[test]
fn defaults_fill_the_params_left_out() {
    let sandbox = Sandbox::new("defaults");
    sandbox.run(&["t.go", "3"]);
    assert_eq!(sandbox.calls(), ["call thing go 3 a false"]);
}

#[test]
fn a_command_action_runs_its_argv() {
    let sandbox = Sandbox::new("command");
    assert_eq!(sandbox.run(&["t.run"]).0, 0);
    assert_eq!(sandbox.calls(), ["ran --x"]);
}

#[test]
fn a_failing_performer_exits_1() {
    let sandbox = Sandbox::new("failing");
    assert_eq!(
        sandbox.run_in(&sandbox.manifest, &[("STUB_FAIL", "1")], &["t.run"]).0,
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
    assert_eq!(sandbox.run(&["t.run"]).0, 1);
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
    Sandbox::new("nobind").rejected(&["t.nobind"], "t.nobind has no binding");
}

#[test]
fn a_missing_manifest_exits_2() {
    let sandbox = Sandbox::new("nomanifest");
    let (code, message) = sandbox.run_in(&sandbox.root.join("none"), &[], &["t.run"]);
    assert_eq!(code, 2, "{message}");
}

#[test]
fn the_real_manifest_performs_the_ipc_actions() {
    let sandbox = Sandbox::new("real-ipc");
    for (action, call) in [
        ("zoom.toggle", "call zoom toggle"),
        ("overview.open", "call overview open"),
    ] {
        assert_eq!(sandbox.run_in(&real_manifest(), &[], &[action]).0, 0);
        assert_eq!(sandbox.calls().last().unwrap(), call);
    }
}

#[test]
fn the_real_screenshot_actions_name_the_script_under_home() {
    let sandbox = Sandbox::new("real-shot");
    let home = sandbox.root.to_str().unwrap();
    for action in ["screenshot.take", "screenshot.pixel"] {
        let (code, message) = sandbox.run_in(&real_manifest(), &[("HOME", home)], &[action]);
        assert_eq!(code, 1, "{message}"); // no script in the fake home: the command was built and tried
        assert!(
            message.contains(&format!("{home}/.config/hypr/scripts/screenshot.sh")),
            "{message}"
        );
    }
}

#[test]
fn a_value_holding_a_placeholder_is_not_expanded_again() {
    let sandbox = Sandbox::new("single-pass");
    sandbox.with_action(
        r#"[{"name": "a", "type": "string"}, {"name": "b", "type": "string"}]"#,
        r#"["{a}", "{b}"]"#,
    );
    assert_eq!(sandbox.run(&["t.x", "{b}", "end"]).0, 0);
    assert_eq!(sandbox.calls(), ["call thing x {b} end"]);
}

#[test]
fn a_string_starting_with_a_dash_exits_2() {
    let sandbox = Sandbox::new("dash");
    sandbox.with_action(r#"[{"name": "a", "type": "string"}]"#, r#"["{a}"]"#);
    sandbox.rejected(&["t.x", "--pid"], "starts with '-'");
}

#[test]
fn a_negative_int_is_still_accepted() {
    let sandbox = Sandbox::new("negative");
    sandbox.with_action(r#"[{"name": "n", "type": "int"}]"#, r#"["{n}"]"#);
    assert_eq!(sandbox.run(&["t.x", "-5"]).0, 0);
    assert_eq!(sandbox.calls(), ["call thing x -5"]);
}

#[test]
fn a_default_of_the_wrong_type_exits_2_even_when_given() {
    let sandbox = Sandbox::new("bad-default");
    sandbox.with_action(r#"[{"name": "n", "type": "int", "default": "x"}]"#, r#"["{n}"]"#);
    sandbox.rejected(&["t.x"], "default");
    sandbox.rejected(&["t.x", "3"], "default");
}

#[test]
fn an_enum_default_outside_its_values_exits_2() {
    let sandbox = Sandbox::new("enum-default");
    let param = r#"[{"name": "m", "type": "enum", "values": ["a", "b"], "default": "c"}]"#;
    sandbox.with_action(param, r#"["{m}"]"#);
    sandbox.rejected(&["t.x"], "not one of a, b");
}

#[test]
fn a_required_param_after_a_defaulted_one_exits_2() {
    let sandbox = Sandbox::new("suffix");
    let params = r#"[{"name": "a", "type": "int", "default": 1}, {"name": "b", "type": "int"}]"#;
    sandbox.with_action(params, r#"["{a}", "{b}"]"#);
    sandbox.rejected(&["t.x", "2"], "required param b follows");
}

#[test]
fn an_int_default_that_is_not_a_whole_i64_exits_2() {
    let sandbox = Sandbox::new("int-default");
    for default in ["1.0", "9223372036854775808"] {
        sandbox.with_action(
            &format!(r#"[{{"name": "n", "type": "int", "default": {default}}}]"#),
            r#"["{n}"]"#,
        );
        sandbox.rejected(&["t.x"], "default");
    }
}

const LUA_ACTIONS: &str = r#"{"actions": [
  {"id": "t.lua", "label": "Lua", "intent": "Lua.", "params": [
    {"name": "text", "type": "string"},
    {"name": "n", "type": "int", "default": 3},
    {"name": "on", "type": "bool", "default": true},
    {"name": "f", "type": "float", "default": 1.5}],
   "key": {"key": "L", "leader": true, "universal": false}, "extra_keys": []},
  {"id": "t.bare", "label": "Bare", "intent": "Bare.", "params": [], "extra_keys": []}
]}"#;

const LUA_BINDINGS: &str = r#"{"bindings": {"t.lua": {"kind": "lua"}, "t.bare": {"kind": "lua"}}}"#;

fn lua_sandbox(name: &str) -> Sandbox {
    let sandbox = Sandbox::new(name);
    std::fs::write(sandbox.manifest.join("actions.json"), LUA_ACTIONS).unwrap();
    std::fs::write(sandbox.manifest.join("bindings/quickshell.json"), r#"{"bindings": {}}"#).unwrap();
    sandbox.with_hyprland(LUA_BINDINGS);
    sandbox
}

#[test]
fn a_lua_action_evals_its_performer_through_hyprctl() {
    let sandbox = lua_sandbox("lua");
    assert_eq!(sandbox.run(&["t.bare"]).0, 0);
    assert_eq!(
        sandbox.calls(),
        [r#"eval require("lib.actions.performers").run("t.bare")"#]
    );
}

#[test]
fn lua_params_are_literals_of_their_type() {
    let sandbox = lua_sandbox("lua-params");
    assert_eq!(sandbox.run(&["t.lua", "hi", "007", "false"]).0, 0);
    assert_eq!(
        sandbox.calls(),
        [r#"eval require("lib.actions.performers").run("t.lua", "hi", 7, false, 1.5)"#]
    );
}

#[test]
fn a_lua_string_param_cannot_break_out_of_its_literal() {
    let sandbox = lua_sandbox("lua-quote");
    let hostile = "a'b\"c]]d\\e\nf\")os.exit(1)--";
    assert_eq!(sandbox.run(&["t.lua", hostile]).0, 0);
    let call = sandbox.calls().join("\n");
    let code = call.strip_prefix("eval ").unwrap();
    // Only the literal's own two quotes remain; every risky byte is a decimal escape.
    let literal = code
        .strip_prefix(r#"require("lib.actions.performers").run("t.lua", "#)
        .and_then(|rest| rest.strip_suffix(", 3, true, 1.5)"))
        .unwrap();
    assert!(literal.starts_with('"') && literal.ends_with('"'), "{literal}");
    let body = &literal[1..literal.len() - 1];
    assert!(
        !body.contains(['"', '\'', '\n', ']']) && !body.contains("\\\\"),
        "{body}"
    );
    // When lua is installed, evaluating the literal gives back the exact word.
    let evaluated = Command::new("lua")
        .arg("-e")
        .arg(format!("io.write({literal})"))
        .output();
    if let Ok(done) = evaluated {
        assert_eq!(String::from_utf8_lossy(&done.stdout), hostile);
    }
}

#[test]
fn a_failing_lua_performer_exits_1() {
    // hyprctl eval exits non-zero (7 on Hyprland 0.5x) when the Lua raises, e.g. an id performers.lua lacks.
    let sandbox = lua_sandbox("lua-fail");
    assert_eq!(
        sandbox.run_in(&sandbox.manifest, &[("STUB_FAIL", "1")], &["t.bare"]).0,
        1
    );
}

#[test]
fn a_failing_performer_forwards_its_stdout_to_stderr() {
    // hyprctl eval reports the Lua error on stdout, so a bare exit 1 would leave the caller without the reason.
    let sandbox = lua_sandbox("lua-fail-output");
    let (code, stderr) = sandbox.run_in(
        &sandbox.manifest,
        &[("STUB_FAIL", "1"), ("STUB_OUT", "lua error: boom")],
        &["t.bare"],
    );
    assert_eq!(code, 1);
    assert!(stderr.contains("lua error: boom"), "stderr was: {stderr}");
}

#[test]
fn a_non_lua_performer_leaving_a_child_on_stdout_returns_promptly() {
    // The test's own stdout is a file, so the lingering child cannot stall this harness, only djinn itself.
    let sandbox = Sandbox::new("child-holds-stdout");
    let out = std::fs::File::create(sandbox.root.join("stdout")).unwrap();
    let started = std::time::Instant::now();
    let status = Command::new(env!("CARGO_BIN_EXE_oasis-djinn"))
        .arg("t.run")
        .env("OASIS_DJINN_CONFIG_DIR", &sandbox.manifest)
        .env("OASIS_DJINN_QS_IPC", stub())
        .env("STUB_LOG", sandbox.log())
        .env("STUB_BACKGROUND", "1")
        .stdout(out)
        .stderr(std::process::Stdio::null())
        .status()
        .unwrap();
    assert!(status.success());
    assert!(
        started.elapsed() < std::time::Duration::from_secs(3),
        "took {:?}",
        started.elapsed()
    );
}

#[test]
fn an_id_bound_in_two_files_exits_2() {
    let sandbox = Sandbox::new("two-files");
    sandbox.with_hyprland(r#"{"bindings": {"t.run": {"kind": "lua"}}}"#);
    sandbox.rejected(&["t.go", "3"], "t.run is bound in both");
}

#[test]
fn an_action_without_a_key_is_still_performed() {
    let sandbox = lua_sandbox("keyless");
    assert_eq!(sandbox.run(&["t.bare"]).0, 0);
}

#[test]
fn the_real_lua_actions_eval_their_performer() {
    let sandbox = Sandbox::new("real-lua");
    for action in [
        "picker.clipboard",
        "picker.clipboard_delete",
        "picker.directory",
        "picker.emoji",
        "hyprvim.terminal",
        "hyprvim.jump_mark",
    ] {
        assert_eq!(sandbox.run_in(&real_manifest(), &[], &[action]).0, 0, "{action}");
        assert_eq!(
            sandbox.calls().last().unwrap(),
            &format!(r#"eval require("lib.actions.performers").run("{action}")"#)
        );
    }
}
