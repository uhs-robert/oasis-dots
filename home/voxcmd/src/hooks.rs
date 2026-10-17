//! asking an integration's hooks what a phrase names: a `candidates` lookup and a `surface_open` check
//!
//! Minimal, for the router (2.2b): only the legacy bash functions, reached through the bash voxcmd's hidden
//! `_legacy-hook` (so each call costs a bash start plus sourcing the file). The hook runner for TOML integrations
//! (environment, timeouts, exit 3 = yield, `run` and `wait_hook`) is 2.3; until then a TOML `candidates` hook is not
//! run and reads as "no hook". The module is deleted down to that runner in 3.2.
use crate::config::schema::{Candidates, Format, Integration, Surface};
use crate::paths;
use serde::Serialize;
use serde_json::Value;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::Instant;

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
    /// `candidates`; `provider`, `wait_hook`, `list` and `run` come with 2.3.
    pub kind: String,
    pub command: String,
    pub exit: Option<i32>,
    pub timed_out: bool,
    pub millis: f64,
    pub lines: Vec<Candidate>,
    pub stderr_tail: Vec<String>,
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
            lookup: Lookup::Unhooked,
        }
    }
}

pub trait Hooks: Sync {
    /// `raw_transcript` is the step as spoken, which some hooks read in place of the target.
    fn candidates(&self, integration: &Integration, action: &str, target: &str, raw_transcript: &str) -> HookRun;
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
    fn candidates(&self, integration: &Integration, action: &str, target: &str, raw_transcript: &str) -> HookRun {
        let shown = format!(
            "voxcmd _legacy-hook candidates {} {action} {target}",
            integration.file.display()
        );
        if integration.format != Format::Bash {
            return unrun(integration, action, &shown);
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

/// Hooks that are never run: the legacy dump was given as a file (`VOXCMD_LEGACY_DUMP_FILE`), so there is no bash
/// integration to source, and the latency test must not wait on bash.
pub struct NoHooks;

impl Hooks for NoHooks {
    fn candidates(&self, integration: &Integration, action: &str, target: &str, _raw_transcript: &str) -> HookRun {
        unrun(
            integration,
            action,
            &format!("(hooks off) candidates {} {target}", integration.file.display()),
        )
    }

    fn surface_open(&self, _integration: &Integration) -> bool {
        false
    }
}

/// A lookup the hook runner cannot do yet: a TOML hook before 2.3.
fn unrun(integration: &Integration, action: &str, command: &str) -> HookRun {
    let mut run = HookRun::unhooked(integration, action, command);
    if let Some(Candidates::Shell(shell)) = integration.candidates_for(action) {
        run.command.clone_from(shell);
        run.stderr_tail = vec!["not run: the TOML hook runner is 2.3".to_string()];
    }
    run
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
        let run = hooks.candidates(&integration, "find", "tea cup", "Find Tea Cup");
        assert_eq!(run.exit, Some(0));
        assert_eq!(
            run.lookup,
            Lookup::Candidates(vec![Candidate::plain("find|tea cup", "Find Tea Cup")])
        );
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
