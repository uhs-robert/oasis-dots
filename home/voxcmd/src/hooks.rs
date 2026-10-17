//! asking an integration's hooks what a phrase names: a `candidates` lookup and a `surface_open` check
//!
//! A TOML integration's hook is a shell string run by `ShellHooks` (1.1 section 2.5): `bash -c` over the integration's
//! `<stem>.sh` library, the match handed over in `VOXCMD_*` variables, a 3 s deadline, exit 3 meaning "yield". A bash
//! integration's hook is reached through the bash voxcmd's hidden `_legacy-hook` (a bash start plus sourcing per
//! call); `Dispatch` picks by the integration's format. The legacy half is deleted in 3.2.
use crate::config::schema::{Candidates, Format, Integration, Surface};
use crate::paths;
use crate::process;
use crate::route::matcher::Arg;
use crate::route::resolve::arg_env;
use serde::Serialize;
use serde_json::Value;
use std::collections::{BTreeMap, HashMap};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

/// How long a `candidates` hook may run unless its action sets `timeout_secs`.
const DEFAULT_TIMEOUT: Duration = Duration::from_secs(3);

/// A `candidates` hook's exit code for "nothing to offer for this phrase": another integration may take it, and the
/// action's `no_match` does not run.
const YIELD_EXIT: i32 = 3;
/// One thing an action can be run on: a window, an app, a keybind.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Candidate {
    pub id: String,
    pub label: String,
    /// What the target is matched against in place of the label.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub match_text: Option<String>,
    /// Set by `word_match`: a match that always goes through the picker.
    #[serde(skip)]
    pub weak: bool,
}

impl Candidate {
    pub fn plain(id: &str, label: &str) -> Self {
        Self {
            id: id.to_string(),
            label: label.to_string(),
            match_text: None,
            weak: false,
        }
    }
}

/// What a `candidates` hook said.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Lookup {
    /// No hook, or it printed nothing: the target text is the id, as one option.
    Unhooked,
    /// The candidates, possibly none: the target is matched against them.
    Candidates(Vec<Candidate>),
    /// The integration offers nothing for the phrase (TOML exit 3).
    Yield,
    /// The hook failed or printed something unreadable: the match yields no option.
    Broken,
}

/// One hook call, as `explain --json` lists it.
#[derive(Debug, Clone, Serialize)]
pub struct HookRun {
    pub integration: String,
    pub action: String,
    /// `candidates`; `provider`, `wait_hook`, `list` and `run` come with 2.3b.
    pub kind: String,
    pub command: String,
    pub exit: Option<i32>,
    pub timed_out: bool,
    pub millis: f64,
    pub lines: Vec<Candidate>,
    pub stderr_tail: Vec<String>,
    /// Why a TOML hook offered nothing: it failed, timed out or printed lines that cannot be read.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub problem: Option<String>,
    /// The answer of an identical query already made for this phrase, not a run of its own (`millis` is 0).
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub reused: bool,
    #[serde(skip)]
    pub lookup: Lookup,
}

impl HookRun {
    /// A lookup that did not run a hook.
    pub fn unhooked(integration: &Integration, action: &str, command: &str) -> Self {
        Self {
            integration: integration.name.clone(),
            action: action.to_string(),
            kind: "candidates".to_string(),
            command: command.to_string(),
            exit: None,
            timed_out: false,
            millis: 0.0,
            lines: Vec::new(),
            stderr_tail: Vec::new(),
            problem: None,
            reused: false,
            lookup: Lookup::Unhooked,
        }
    }
}

/// What a hook is asked about: the verb that matched and the text it matched.
pub struct HookQuery<'a> {
    pub action: &'a str,
    pub target: &'a str,
    pub args: &'a [Arg],
    /// The step after normalization and replacements.
    pub phrase: &'a str,
    /// The step as spoken, which some hooks read in place of the target.
    pub raw_transcript: &'a str,
}

pub trait Hooks: Sync {
    fn candidates(&self, integration: &Integration, query: &HookQuery) -> HookRun;
    /// Whether the integration's bar surface is open and takes the phrase before any other integration.
    fn surface_open(&self, integration: &Integration) -> bool;
}

/// The hooks of the bash integrations, through the bash voxcmd.
pub struct LegacyHooks {
    bin: PathBuf,
    config_dir: PathBuf,
}

impl LegacyHooks {
    pub fn new(config_dir: PathBuf) -> Self {
        Self::with_bin(paths::legacy_bin(), config_dir)
    }

    pub fn with_bin(bin: PathBuf, config_dir: PathBuf) -> Self {
        Self { bin, config_dir }
    }

    fn call(&self, kind: &str, integration: &Integration) -> Command {
        let mut command = Command::new(&self.bin);
        command
            .args(["_legacy-hook", kind])
            .arg(&integration.file)
            .env("VOXCMD_CONFIG_DIR", &self.config_dir)
            .stdin(Stdio::null());
        command
    }
}

impl Hooks for LegacyHooks {
    fn candidates(&self, integration: &Integration, query: &HookQuery) -> HookRun {
        let HookQuery {
            action,
            target,
            raw_transcript,
            ..
        } = *query;
        let shown = format!(
            "voxcmd _legacy-hook candidates {} {action} {target}",
            integration.file.display()
        );
        if integration.format != Format::Bash {
            return HookRun::unhooked(integration, action, &shown);
        }
        let started = Instant::now();
        let output = self
            .call("candidates", integration)
            .args([action, target])
            .env("VOXCMD_LEGACY_RAW_TRANSCRIPT", raw_transcript)
            .stderr(Stdio::piped())
            .output();
        let millis = started.elapsed().as_secs_f64() * 1000.0;
        let mut run = HookRun::unhooked(integration, action, &shown);
        run.millis = millis;
        match output {
            Ok(output) => {
                run.exit = output.status.code();
                run.stderr_tail = tail_lines(&String::from_utf8_lossy(&output.stderr), 3);
                run.lookup = if output.status.success() {
                    parse_legacy_output(&String::from_utf8_lossy(&output.stdout))
                } else {
                    Lookup::Broken
                };
            }
            Err(error) => {
                run.stderr_tail = vec![format!("{}: {error}", self.bin.display())];
                run.lookup = Lookup::Broken;
            }
        }
        if let Lookup::Candidates(lines) = &run.lookup {
            run.lines.clone_from(lines);
        }
        run
    }

    fn surface_open(&self, integration: &Integration) -> bool {
        match &integration.surface {
            Some(Surface::LegacyHook) if integration.format == Format::Bash => self
                .call("surface", integration)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .is_ok_and(|status| status.success()),
            Some(Surface::StateFile(path)) => state_file_open(path),
            _ => false,
        }
    }
}

/// Asks each distinct query once per phrase: routing resolves the same match again in the near-miss pass, and an
/// action with several verbs matches the same hook from each, so the hook's answer is kept and handed out again.
/// Matches that differ still run side by side; a query being run holds up only an identical one.
///
/// Two kinds of "identical": normally the whole query (action, target, arguments and both spellings of the phrase);
/// while `reuse_any_target` is on (the near-miss pass), the action and the phrase alone, since a near miss reads the
/// phrase's words in another order and so names another target, and its options are only offered through the picker.
pub struct Memoized<'a> {
    inner: &'a dyn Hooks,
    answers: Mutex<HashMap<String, Arc<OnceLock<HookRun>>>>,
    reuse_any_target: AtomicBool,
}

impl<'a> Memoized<'a> {
    pub fn new(inner: &'a dyn Hooks) -> Self {
        Self {
            inner,
            answers: Mutex::default(),
            reuse_any_target: AtomicBool::new(false),
        }
    }

    pub fn reuse_any_target(&self, on: bool) {
        self.reuse_any_target.store(on, Ordering::SeqCst);
    }

    fn slot(&self, key: String) -> Arc<OnceLock<HookRun>> {
        Arc::clone(
            self.answers
                .lock()
                .expect("no panic holds the lock")
                .entry(key)
                .or_default(),
        )
    }

    /// Starts a new phrase: what a hook said about the last one may be stale (a step before it changed the desktop).
    pub fn forget(&self) {
        self.answers.lock().expect("no panic holds the lock").clear();
    }
}

impl Hooks for Memoized<'_> {
    fn candidates(&self, integration: &Integration, query: &HookQuery) -> HookRun {
        let any_target = format!(
            "{}\0{}\0{}\0{}",
            integration.file.display(),
            query.action,
            query.phrase,
            query.raw_transcript
        );
        let exact = format!("{any_target}\0{}\0{:?}", query.target, query.args);
        let reuse_any_target = self.reuse_any_target.load(Ordering::SeqCst);
        let slot = self.slot(if reuse_any_target { any_target.clone() } else { exact });
        let mut asked = false;
        let run = slot.get_or_init(|| {
            asked = true;
            self.inner.candidates(integration, query)
        });
        if asked && !reuse_any_target {
            // The near-miss pass may reuse this answer for another target.
            let _ = self.slot(any_target).set(run.clone());
        }
        let mut run = run.clone();
        if !asked {
            run.millis = 0.0;
            run.reused = true;
        }
        run
    }

    fn surface_open(&self, integration: &Integration) -> bool {
        self.inner.surface_open(integration)
    }
}

/// The hooks of the TOML integrations: shell strings run by `bash`, with the match in the environment.
pub struct ShellHooks {
    integration_dir: PathBuf,
    share_dir: PathBuf,
    /// Every loaded integration's stem, space separated.
    integrations: String,
    dry_run: bool,
}

/// The variables a hook sees (1.1 section 2.5), built once per option.
pub struct HookEnv<'a> {
    pub integration: &'a Integration,
    pub action: &'a str,
    pub args: &'a [Arg],
    pub phrase: &'a str,
    pub raw_transcript: &'a str,
    /// The chosen option: for `run` and `wait_hook`, not for `candidates`.
    pub id: Option<&'a str>,
    pub label: Option<&'a str>,
    pub confirmed: bool,
    /// For waits only.
    pub active_before: Option<&'a str>,
    /// Whether the command came by voice (2.4).
    pub spoken: bool,
}

impl ShellHooks {
    pub fn new(config_dir: &std::path::Path, stems: impl IntoIterator<Item = String>, dry_run: bool) -> Self {
        Self {
            integration_dir: config_dir.join("integrations"),
            share_dir: paths::share_dir(),
            integrations: stems.into_iter().collect::<Vec<_>>().join(" "),
            dry_run,
        }
    }

    /// `bash -c` over the integration's library (when it has one) and then the hook string. The library path is a
    /// literal of the wrapper, quoted; spoken text only ever reaches the hook through the environment.
    fn command(&self, shell: &str, env: &HookEnv) -> Command {
        let library = format!("{}.sh", env.integration.stem);
        let script = format!(
            "if [ -f \"$VOXCMD_INTEGRATION_DIR\"/{library} ]; then . \"$VOXCMD_INTEGRATION_DIR\"/{library}; fi\n{shell}",
            library = shell_quote(&library),
        );
        let mut command = Command::new("bash");
        command.args(["--noprofile", "--norc", "-c", &script]);
        let vars = self.env(env);
        // A variable this call does not set must not leak in from voxcmd's own environment: a stale argument or
        // option would read as part of this match. BASH_ENV would make bash run a file before the library.
        let inherited_args = std::env::vars_os()
            .filter_map(|(name, _)| name.into_string().ok())
            .filter(|name| name.starts_with("VOXCMD_ARG_"));
        let always_cleared = [
            "VOXCMD_ID",
            "VOXCMD_LABEL",
            "VOXCMD_ACTIVE_BEFORE",
            "VOXCMD_CONFIRMED",
            "VOXCMD_DRY_RUN",
            "BASH_ENV",
        ]
        .map(str::to_string);
        for name in inherited_args.chain(always_cleared) {
            if !vars.contains_key(&name) {
                command.env_remove(name);
            }
        }
        command.envs(vars);
        command
    }

    fn env(&self, env: &HookEnv) -> BTreeMap<String, String> {
        let mut vars = arg_env(env.args);
        let flag = |on: bool| if on { "1" } else { "0" }.to_string();
        let mut set = |name: &str, value: String| vars.insert(name.to_string(), value);
        set("VOXCMD_INTEGRATION", env.integration.stem.clone());
        set("VOXCMD_ACTION", env.action.to_string());
        set("VOXCMD_PHRASE", env.phrase.to_string());
        set("VOXCMD_RAW_TRANSCRIPT", env.raw_transcript.to_string());
        set("VOXCMD_CONFIRMED", flag(env.confirmed));
        set(
            "VOXCMD_MATCH_IGNORE_WORDS",
            env.integration.settings.match_ignore_words.join(" "),
        );
        set("VOXCMD_INTEGRATIONS", self.integrations.clone());
        set("VOXCMD_SHARE_DIR", self.share_dir.display().to_string());
        set("VOXCMD_INTEGRATION_DIR", self.integration_dir.display().to_string());
        set("VOXCMD_SPOKEN", flag(env.spoken));
        if self.dry_run {
            set("VOXCMD_DRY_RUN", "1".to_string());
        }
        for (name, value) in [
            ("VOXCMD_ID", env.id),
            ("VOXCMD_LABEL", env.label),
            ("VOXCMD_ACTIVE_BEFORE", env.active_before),
        ] {
            if let Some(value) = value {
                set(name, value.to_string());
            }
        }
        vars
    }
}

impl Hooks for ShellHooks {
    fn candidates(&self, integration: &Integration, query: &HookQuery) -> HookRun {
        let mut run = HookRun::unhooked(integration, query.action, "");
        let Some(Candidates::Shell(shell)) = integration.candidates_for(query.action) else {
            return run;
        };
        run.command.clone_from(shell);
        let timeout = integration
            .actions
            .get(query.action)
            .and_then(|declared| declared.timeout_secs)
            .map_or(DEFAULT_TIMEOUT, Duration::from_secs_f64);
        let env = HookEnv {
            integration,
            action: query.action,
            args: query.args,
            phrase: query.phrase,
            raw_transcript: query.raw_transcript,
            id: None,
            label: None,
            confirmed: false,
            active_before: None,
            spoken: false,
        };
        let started = Instant::now();
        let outcome = process::run_with_timeout(&mut self.command(shell, &env), timeout);
        run.millis = started.elapsed().as_secs_f64() * 1000.0;
        run.lookup = match outcome {
            Err(error) => {
                run.problem = Some(format!("could not start bash: {error}"));
                Lookup::Broken
            }
            Ok(outcome) => {
                run.exit = outcome.code();
                run.timed_out = outcome.timed_out;
                run.stderr_tail = tail_lines(&outcome.stderr, 3);
                match outcome.code() {
                    _ if outcome.timed_out => {
                        run.problem = Some(format!("timed out after {} s", timeout.as_secs_f64()));
                        Lookup::Broken
                    }
                    Some(0) => match parse_lines(&outcome.stdout) {
                        Ok(lines) => Lookup::Candidates(lines),
                        Err(message) => {
                            run.problem = Some(message);
                            Lookup::Broken
                        }
                    },
                    Some(YIELD_EXIT) => Lookup::Yield,
                    _ => {
                        run.problem = Some(outcome.how_it_ended());
                        Lookup::Broken
                    }
                }
            }
        };
        if let Lookup::Candidates(lines) = &run.lookup {
            run.lines.clone_from(lines);
        }
        run
    }

    fn surface_open(&self, integration: &Integration) -> bool {
        match &integration.surface {
            Some(Surface::StateFile(path)) => state_file_open(path),
            _ => false,
        }
    }
}

/// The lines of a hook's output: `id<TAB>label<TAB>match_text`, the last two optional, one option per line. A blank
/// line is skipped; a line with no id is an error, since the id is what `run` is later given. (Help lists, 2.6, will
/// want id-less rows and need their own reader.)
pub fn parse_lines(stdout: &str) -> Result<Vec<Candidate>, String> {
    let mut candidates = Vec::new();
    for (index, line) in stdout.split('\n').enumerate() {
        let line = line.strip_suffix('\r').unwrap_or(line);
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() > 3 {
            return Err(format!(
                "output line {} has {} tab-separated fields, at most 3 are read",
                index + 1,
                fields.len()
            ));
        }
        let id = fields[0];
        if id.trim().is_empty() {
            return Err(format!("output line {} has an empty id", index + 1));
        }
        let label = fields.get(1).copied().filter(|label| !label.is_empty()).unwrap_or(id);
        let match_text = fields.get(2).copied().filter(|text| !text.is_empty());
        candidates.push(Candidate {
            id: id.to_string(),
            label: label.to_string(),
            match_text: match_text.map(str::to_string),
            weak: false,
        });
    }
    Ok(candidates)
}

fn shell_quote(text: &str) -> String {
    format!("'{}'", text.replace('\'', r"'\''"))
}

/// Each integration's hooks by its format: the shell runner for TOML, the bash voxcmd for the bash files.
pub struct Dispatch {
    shell: ShellHooks,
    legacy: Box<dyn Hooks>,
}

impl Dispatch {
    pub fn new(shell: ShellHooks, legacy: Box<dyn Hooks>) -> Self {
        Self { shell, legacy }
    }

    fn for_format(&self, integration: &Integration) -> &dyn Hooks {
        match integration.format {
            Format::Toml => &self.shell,
            Format::Bash => self.legacy.as_ref(),
        }
    }
}

impl Hooks for Dispatch {
    fn candidates(&self, integration: &Integration, query: &HookQuery) -> HookRun {
        self.for_format(integration).candidates(integration, query)
    }

    fn surface_open(&self, integration: &Integration) -> bool {
        self.for_format(integration).surface_open(integration)
    }
}

/// Hooks that are never run: the legacy dump was given as a file (`VOXCMD_LEGACY_DUMP_FILE`), so there is no bash
/// integration to source, and the latency test must not wait on bash.
pub struct NoHooks;

impl Hooks for NoHooks {
    fn candidates(&self, integration: &Integration, query: &HookQuery) -> HookRun {
        let mut run = HookRun::unhooked(
            integration,
            query.action,
            &format!("(hooks off) candidates {} {}", integration.file.display(), query.target),
        );
        if let Some(Candidates::Shell(shell)) = integration.candidates_for(query.action) {
            run.command.clone_from(shell);
            run.stderr_tail = vec!["not run: hooks are off".to_string()];
        }
        run
    }

    fn surface_open(&self, _integration: &Integration) -> bool {
        false
    }
}

/// Under `$XDG_RUNTIME_DIR/voxcmd`; open while the file's top-level `open` is true.
fn state_file_open(path: &std::path::Path) -> bool {
    let full = if path.is_absolute() {
        path.to_path_buf()
    } else {
        paths::runtime_dir().join(path)
    };
    std::fs::read_to_string(full)
        .ok()
        .and_then(|text| serde_json::from_str::<Value>(&text).ok())
        .is_some_and(|state| state.get("open").and_then(Value::as_bool) == Some(true))
}

fn tail_lines(text: &str, count: usize) -> Vec<String> {
    let lines: Vec<&str> = text.lines().collect();
    lines[lines.len().saturating_sub(count)..]
        .iter()
        .map(|line| (*line).to_string())
        .collect()
}

/// jq's `tostring`: a string as it is, anything else as compact JSON.
fn tostring(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        other => other.to_string(),
    }
}

/// jq's truthiness: everything but null and false.
fn truthy(value: &Value) -> bool {
    !matches!(value, Value::Null | Value::Bool(false))
}

/// What the bash router made of a `candidates` function's output: nothing at all is "no hook" (the target is the
/// id), `[]` is "nothing matches", and a JSON array is read as `map({id, label, match_text})`.
pub fn parse_legacy_output(stdout: &str) -> Lookup {
    let text = stdout.trim_end_matches('\n');
    if text.is_empty() {
        return Lookup::Unhooked;
    }
    let Ok(Value::Array(entries)) = serde_json::from_str::<Value>(text) else {
        return Lookup::Broken;
    };
    let mut candidates = Vec::with_capacity(entries.len());
    for entry in &entries {
        let Value::Object(fields) = entry else {
            return Lookup::Broken;
        };
        let id = fields.get("id").unwrap_or(&Value::Null);
        let label = fields.get("label").filter(|label| truthy(label)).unwrap_or(id);
        let match_text = fields.get("match_text").filter(|text| truthy(text)).map(tostring);
        candidates.push(Candidate {
            id: tostring(id),
            label: tostring(label),
            match_text,
            weak: false,
        });
    }
    Lookup::Candidates(candidates)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_output_is_no_hook_and_brackets_are_no_candidates() {
        assert_eq!(parse_legacy_output(""), Lookup::Unhooked);
        assert_eq!(parse_legacy_output("\n\n"), Lookup::Unhooked);
        assert_eq!(parse_legacy_output("[]\n"), Lookup::Candidates(Vec::new()));
        assert_eq!(parse_legacy_output("not json"), Lookup::Broken);
        assert_eq!(parse_legacy_output("{}"), Lookup::Broken);
    }

    #[test]
    fn the_bridge_passes_the_action_target_and_raw_transcript_to_the_bash_voxcmd() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        let bin = dir.path().join("voxcmd");
        std::fs::write(
            &bin,
            "#!/bin/sh\n[ \"$1 $2\" = '_legacy-hook candidates' ] || exit 9\n\
             printf '[{\"id\": \"%s|%s\", \"label\": \"%s\"}]' \"$4\" \"$5\" \"$VOXCMD_LEGACY_RAW_TRANSCRIPT\"\n",
        )
        .unwrap();
        std::fs::set_permissions(&bin, std::fs::Permissions::from_mode(0o755)).unwrap();
        let hooks = LegacyHooks::with_bin(bin, dir.path().to_path_buf());
        let toml = "name = \"Search\"\nverbs = []\n";
        let mut integration = crate::config::schema::parse_toml(std::path::Path::new("search.toml"), toml).unwrap();
        integration.format = Format::Bash;
        let query = HookQuery {
            action: "find",
            target: "tea cup",
            args: &[],
            phrase: "find tea cup",
            raw_transcript: "Find Tea Cup",
        };
        let run = hooks.candidates(&integration, &query);
        assert_eq!(run.exit, Some(0));
        assert_eq!(
            run.lookup,
            Lookup::Candidates(vec![Candidate::plain("find|tea cup", "Find Tea Cup")])
        );
    }

    // ---- the shell runner ----

    use crate::route::pattern::PlaceholderType;

    struct Fixture {
        dir: tempfile::TempDir,
        hooks: ShellHooks,
        integration: Integration,
    }

    /// An integration `t` whose one action `go` has the given `candidates` hook (and `timeout_secs`), with `t.sh` as
    /// its library when given.
    fn fixture(hook: &str, timeout_secs: Option<f64>, library: Option<&str>) -> Fixture {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir(dir.path().join("integrations")).unwrap();
        if let Some(library) = library {
            std::fs::write(dir.path().join("integrations/t.sh"), library).unwrap();
        }
        let timeout = timeout_secs.map_or(String::new(), |secs| format!("timeout_secs = {secs}\n"));
        let toml = format!(
            "name = \"T\"\nverbs = [{{ action = \"go\", match = 'go {{target}}' }}]\nmatch_ignore_words = [\"the\", \"a\"]\n\
             [actions.go]\nrun = \"true\"\n{timeout}candidates = '''{hook}'''\n"
        );
        let file = dir.path().join("integrations/t.toml");
        std::fs::write(&file, &toml).unwrap();
        let integration = crate::config::schema::parse_toml(&file, &toml).unwrap();
        let hooks = ShellHooks::new(dir.path(), ["t".to_string(), "other".to_string()], false);
        Fixture {
            dir,
            hooks,
            integration,
        }
    }

    impl Fixture {
        fn ask(&self, raw_transcript: &str) -> HookRun {
            let args = [Arg {
                name: "target".into(),
                kind: PlaceholderType::Text,
                words: Some("tea".into()),
                value: Some("tea".into()),
            }];
            self.hooks.candidates(
                &self.integration,
                &HookQuery {
                    action: "go",
                    target: "tea",
                    args: &args,
                    phrase: "go tea",
                    raw_transcript,
                },
            )
        }
    }

    #[test]
    fn output_lines_are_id_label_and_match_text() {
        let lines = parse_lines("a\tA\tmatch a\r\nb\tB\n\nc\n").unwrap();
        let flat: Vec<_> = lines
            .iter()
            .map(|c| (c.id.as_str(), c.label.as_str(), c.match_text.as_deref()))
            .collect();
        assert_eq!(flat, [("a", "A", Some("match a")), ("b", "B", None), ("c", "c", None),]);
        assert_eq!(parse_lines("").unwrap(), Vec::new());
        for no_id in ["\tLabel\n", " \t\tx\n", "ok\n  \n\t\n"] {
            let error = parse_lines(no_id).unwrap_err();
            assert!(error.contains("empty id"), "{no_id:?}: {error}");
        }
        let error = parse_lines("a\tb\tc\td\n").unwrap_err();
        assert!(error.contains("line 1") && error.contains("4 tab-separated"), "{error}");
        assert!(parse_lines("ok\nx\ty\tz\tw\n").unwrap_err().contains("line 2"));
    }

    #[test]
    fn exit_codes_are_options_yield_or_a_failure_that_offers_nothing() {
        let ok = fixture(r"printf 'a\tA\n'; exit 0", None, None).ask("go tea");
        assert_eq!(ok.lookup, Lookup::Candidates(vec![Candidate::plain("a", "A")]));
        assert_eq!((ok.exit, ok.problem.as_deref()), (Some(0), None));

        let empty = fixture("true", None, None).ask("go tea");
        assert_eq!(empty.lookup, Lookup::Candidates(Vec::new()));

        let yielded = fixture("echo ignored; exit 3", None, None).ask("go tea");
        assert_eq!((yielded.lookup, yielded.exit), (Lookup::Yield, Some(3)));

        let failed = fixture("echo boom >&2; exit 2", None, None).ask("go tea");
        assert_eq!((failed.lookup, failed.exit), (Lookup::Broken, Some(2)));
        assert_eq!(failed.problem.as_deref(), Some("exit 2"));
        assert_eq!(failed.stderr_tail, ["boom"]);

        let slow = fixture("sleep 30", Some(0.2), None).ask("go tea");
        assert_eq!((slow.lookup, slow.exit, slow.timed_out), (Lookup::Broken, None, true));
        assert_eq!(slow.problem.as_deref(), Some("timed out after 0.2 s"));
        assert!(slow.millis < 5000.0, "{}", slow.millis);

        let garbled = fixture(r"printf 'a\tb\tc\td\n'", None, None).ask("go tea");
        assert_eq!(garbled.lookup, Lookup::Broken);
        assert!(garbled.problem.unwrap().contains("line 1"));
    }

    #[test]
    fn a_timed_out_hook_takes_its_children_with_it() {
        let dir = tempfile::tempdir().unwrap();
        let pid_file = dir.path().join("child.pid");
        let hook = format!("sleep 30 & echo $! > '{}'; wait", pid_file.display());
        let run = fixture(&hook, Some(0.3), None).ask("go tea");
        assert!(run.timed_out);
        let child: i32 = std::fs::read_to_string(&pid_file).unwrap().trim().parse().unwrap();
        assert!(
            crate::process::tests::gone_within(child, Duration::from_secs(2)),
            "child {child} is alive"
        );
    }

    #[test]
    fn spoken_text_never_runs_as_shell() {
        let marker_dir = tempfile::tempdir().unwrap();
        let (one, two) = (marker_dir.path().join("one"), marker_dir.path().join("two"));
        let spoken = format!(
            "it's \"quoted\" $(touch {}) `touch {}` ; touch {} #",
            one.display(),
            two.display(),
            one.display()
        );
        let hook = r#"printf '%s\t%s\n' "$VOXCMD_RAW_TRANSCRIPT" "$VOXCMD_ARG_TARGET""#;
        let run = fixture(hook, None, None).ask(&spoken);
        assert_eq!(run.lookup, Lookup::Candidates(vec![Candidate::plain(&spoken, "tea")]));
        assert!(!one.exists() && !two.exists(), "spoken text ran as a command");
    }

    #[test]
    fn the_hook_sees_the_documented_environment() {
        let hook = r#"env | grep '^VOXCMD_' | while IFS== read -r name value; do printf '%s\t%s\n' "$name" "${value:-(empty)}"; done"#;
        let fixture = fixture(hook, None, None);
        let run = fixture.ask("Go Tea");
        let Lookup::Candidates(lines) = run.lookup else {
            panic!("{run:?}")
        };
        let seen: BTreeMap<&str, &str> = lines.iter().map(|c| (c.id.as_str(), c.label.as_str())).collect();
        let integration_dir = fixture.dir.path().join("integrations").display().to_string();
        assert_eq!(seen["VOXCMD_INTEGRATION"], "t");
        assert_eq!(seen["VOXCMD_ACTION"], "go");
        assert_eq!(seen["VOXCMD_ARG_TARGET"], "tea");
        assert_eq!(seen["VOXCMD_ARG_TARGET_WORDS"], "tea");
        assert_eq!(seen["VOXCMD_PHRASE"], "go tea");
        assert_eq!(seen["VOXCMD_RAW_TRANSCRIPT"], "Go Tea");
        assert_eq!(seen["VOXCMD_CONFIRMED"], "0");
        assert_eq!(seen["VOXCMD_MATCH_IGNORE_WORDS"], "the a");
        assert_eq!(seen["VOXCMD_INTEGRATIONS"], "t other");
        assert_eq!(seen["VOXCMD_INTEGRATION_DIR"], integration_dir);
        assert_eq!(seen["VOXCMD_SPOKEN"], "0");
        assert!(seen["VOXCMD_SHARE_DIR"].ends_with("share/voxcmd"), "{seen:?}");
        // Only a chosen option has an id and label, only a wait an active window, only a dry run VOXCMD_DRY_RUN.
        for absent in ["VOXCMD_ID", "VOXCMD_LABEL", "VOXCMD_ACTIVE_BEFORE", "VOXCMD_DRY_RUN"] {
            assert!(!seen.contains_key(absent), "{absent} is set");
        }
    }

    #[test]
    fn env_carries_every_placeholder_of_a_verb_and_the_chosen_option() {
        let fixture = fixture("true", None, None);
        let arg = |name: &str, kind, words: Option<&str>, value: Option<&str>| Arg {
            name: name.into(),
            kind,
            words: words.map(str::to_string),
            value: value.map(str::to_string),
        };
        let args = [
            arg("app", PlaceholderType::Text, Some("the editor"), Some("editor")),
            arg("count", PlaceholderType::Number, Some("three"), Some("3")),
            arg("skipped", PlaceholderType::Text, None, None),
        ];
        let env = fixture.hooks.env(&HookEnv {
            integration: &fixture.integration,
            action: "go",
            args: &args,
            phrase: "p",
            raw_transcript: "P",
            id: Some("7"),
            label: Some("Seven"),
            confirmed: true,
            active_before: Some("0xabc"),
            spoken: true,
        });
        let get = |name: &str| env.get(name).map(String::as_str);
        assert_eq!(get("VOXCMD_ARG_APP"), Some("editor"));
        assert_eq!(get("VOXCMD_ARG_APP_WORDS"), Some("the editor"));
        assert_eq!(get("VOXCMD_ARG_COUNT"), Some("3"));
        assert_eq!(get("VOXCMD_ARG_COUNT_WORDS"), Some("three"));
        assert_eq!(get("VOXCMD_ARG_SKIPPED"), None);
        assert_eq!(
            (get("VOXCMD_ID"), get("VOXCMD_LABEL"), get("VOXCMD_CONFIRMED")),
            (Some("7"), Some("Seven"), Some("1"))
        );
        assert_eq!(
            (get("VOXCMD_ACTIVE_BEFORE"), get("VOXCMD_SPOKEN")),
            (Some("0xabc"), Some("1"))
        );
    }

    #[test]
    fn variables_a_call_does_not_set_are_cleared_from_the_inherited_environment() {
        let fixture = fixture("true", None, None);
        let env = HookEnv {
            integration: &fixture.integration,
            action: "go",
            args: &[],
            phrase: "p",
            raw_transcript: "P",
            id: None,
            label: None,
            confirmed: false,
            active_before: None,
            spoken: false,
        };
        let command = fixture.hooks.command("true", &env);
        let cleared: Vec<String> = command
            .get_envs()
            .filter(|(_, value)| value.is_none())
            .map(|(name, _)| name.to_string_lossy().into_owned())
            .collect();
        for name in [
            "VOXCMD_ID",
            "VOXCMD_LABEL",
            "VOXCMD_ACTIVE_BEFORE",
            "VOXCMD_DRY_RUN",
            "BASH_ENV",
        ] {
            assert!(
                cleared.iter().any(|one| one == name),
                "{name} is not cleared: {cleared:?}"
            );
        }
        // Set by every call, so never cleared.
        assert!(!cleared.iter().any(|one| one == "VOXCMD_CONFIRMED"));
    }

    #[test]
    fn a_dry_run_marks_the_hooks_environment() {
        let mut fixture = fixture(r#"printf '%s\n' "$VOXCMD_DRY_RUN""#, None, None);
        fixture.hooks.dry_run = true;
        assert_eq!(
            fixture.ask("go tea").lookup,
            Lookup::Candidates(vec![Candidate::plain("1", "1")])
        );
    }

    #[test]
    fn the_integrations_library_is_sourced_before_the_hook() {
        let library = "list_teas() { printf 'green\\tGreen tea\\n'; }\n";
        let run = fixture("list_teas", None, Some(library)).ask("go tea");
        assert_eq!(
            run.lookup,
            Lookup::Candidates(vec![Candidate::plain("green", "Green tea")])
        );
        // No library file is fine for a hook that needs none.
        assert_eq!(fixture("true", None, None).ask("go tea").problem, None);
    }

    #[test]
    fn a_library_that_does_not_parse_fails_the_hook_and_says_why() {
        let run = fixture("list_teas", None, Some("list_teas() { echo ; ;\n")).ask("go tea");
        assert_eq!(run.lookup, Lookup::Broken);
        assert!(
            run.stderr_tail.iter().any(|line| line.contains("t.sh")),
            "{:?}",
            run.stderr_tail
        );
    }

    #[test]
    fn a_library_name_with_a_quote_is_still_one_literal_word() {
        assert_eq!(shell_quote("it's.sh"), r"'it'\''s.sh'");
    }

    /// Counts the runs it is asked for, and answers slowly enough for concurrent askers to overlap.
    struct Counting(std::sync::atomic::AtomicUsize);

    impl Hooks for Counting {
        fn candidates(&self, integration: &Integration, query: &HookQuery) -> HookRun {
            self.0.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            std::thread::sleep(Duration::from_millis(50));
            HookRun::unhooked(integration, query.action, query.target)
        }

        fn surface_open(&self, _integration: &Integration) -> bool {
            false
        }
    }

    #[test]
    fn an_identical_query_runs_once_even_when_asked_side_by_side_until_the_phrase_is_forgotten() {
        let fixture = fixture("true", None, None);
        let counting = Counting(Default::default());
        let memo = Memoized::new(&counting);
        let ask = |target: &str| {
            memo.candidates(
                &fixture.integration,
                &HookQuery {
                    action: "go",
                    target,
                    args: &[],
                    phrase: "go",
                    raw_transcript: "go",
                },
            )
        };
        let runs = || counting.0.load(std::sync::atomic::Ordering::SeqCst);
        let answers: Vec<HookRun> = std::thread::scope(|scope| {
            let asking: Vec<_> = (0..3).map(|_| scope.spawn(|| ask("tea"))).collect();
            asking.into_iter().map(|one| one.join().unwrap()).collect()
        });
        assert_eq!(runs(), 1);
        assert_eq!(answers.iter().filter(|answer| answer.reused).count(), 2);
        ask("coffee");
        assert_eq!(runs(), 2, "a different target is a different query");
        memo.forget();
        ask("tea");
        assert_eq!(runs(), 3, "a new phrase asks again");
    }

    #[test]
    fn a_child_that_outlives_the_hook_costs_neither_options_nor_no_match() {
        let run = fixture(r"sleep 3 & printf 'a\tA\n'", None, None).ask("go tea");
        assert_eq!(run.lookup, Lookup::Candidates(vec![Candidate::plain("a", "A")]));
        assert!(run.millis < 1000.0, "{}", run.millis);
    }

    #[test]
    fn candidates_are_read_as_the_bash_jq_read_them() {
        let lookup = parse_legacy_output(
            r#"[{"id": 8, "label": "Help"}, {"id": "a"}, {"id": "b", "label": false, "match_text": "bee"}, {"label": "x", "match_text": null}]"#,
        );
        let Lookup::Candidates(found) = lookup else {
            panic!("{lookup:?}")
        };
        let flat: Vec<(&str, &str, Option<&str>)> = found
            .iter()
            .map(|c| (c.id.as_str(), c.label.as_str(), c.match_text.as_deref()))
            .collect();
        assert_eq!(
            flat,
            [
                ("8", "Help", None),
                ("a", "a", None),
                ("b", "b", Some("bee")),
                ("null", "x", None)
            ]
        );
    }
}
