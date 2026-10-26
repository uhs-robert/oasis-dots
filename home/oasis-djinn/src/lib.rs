//! The action manifest: load it, check the params of a request, and turn an action into the command that performs it.
//!
//! The JSON schemas in specs/schema/ and the `registry` check step guarantee the manifest's shape, so this reader
//! accepts unknown fields and reports only what a request needs: an unknown id, a bad param, a missing binding.

use std::collections::HashMap;
use std::fmt;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use serde::Deserialize;

/// A problem with the request or the manifest, reported as one line. `oasis-djinn` exits 2 on it.
#[derive(Debug, PartialEq)]
pub struct ActionError(pub String);

impl fmt::Display for ActionError {
    fn fmt(&self, out: &mut fmt::Formatter) -> fmt::Result {
        out.write_str(&self.0)
    }
}

fn fail<T>(message: String) -> Result<T, ActionError> {
    Err(ActionError(message))
}

#[derive(Debug, Deserialize, Clone, Copy, PartialEq)]
#[serde(rename_all = "lowercase")]
enum ParamKind {
    Int,
    Float,
    String,
    Bool,
    Enum,
}

#[derive(Debug, Deserialize)]
struct Param {
    name: String,
    #[serde(rename = "type")]
    kind: ParamKind,
    #[serde(default)]
    values: Vec<String>,
    default: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
struct Action {
    id: String,
    #[serde(default)]
    params: Vec<Param>,
}

#[derive(Debug, Deserialize)]
struct ActionFile {
    actions: Vec<Action>,
}

/// How a tool performs an action: a typed IpcHandler function through qs-ipc, a program for what has no IPC
/// function, or a function of hypr's `lib/actions/performers.lua` run inside Hyprland through `hyprctl eval`.
#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
enum Binding {
    Ipc {
        target: String,
        function: String,
        args: Vec<String>,
    },
    Command {
        argv: Vec<String>,
    },
    Lua,
}

#[derive(Debug, Deserialize)]
struct BindingFile {
    bindings: HashMap<String, Binding>,
}

/// The programs a plan names, so tests can stand in for them.
pub struct Tools<'a> {
    pub qs_ipc: &'a Path,
    pub hyprctl: &'a Path,
    pub home: &'a Path,
}

/// The module whose `run(id, ...)` performs every `lua` binding.
const PERFORMERS: &str = "lib.actions.performers";

#[derive(Debug)]
pub struct Manifest {
    actions: Vec<Action>,
    bindings: HashMap<String, Binding>,
}

/// The manifest folder: `OASIS_DJINN_CONFIG_DIR` (tests, running from a checkout), else `$XDG_CONFIG_HOME/oasis-djinn`.
pub fn config_dir() -> PathBuf {
    let from_env = |name: &str| {
        std::env::var_os(name)
            .filter(|value| !value.is_empty())
            .map(PathBuf::from)
    };
    from_env("OASIS_DJINN_CONFIG_DIR")
        .or_else(|| from_env("XDG_CONFIG_HOME").map(|dir| dir.join("oasis-djinn")))
        .or_else(|| from_env("HOME").map(|dir| dir.join(".config/oasis-djinn")))
        .unwrap_or_else(|| PathBuf::from("oasis-djinn"))
}

fn read<T: for<'a> Deserialize<'a>>(path: &Path) -> Result<T, ActionError> {
    let text = std::fs::read_to_string(path)
        .map_err(|error| ActionError(format!("cannot read {}: {error}", path.display())))?;
    serde_json::from_str(&text)
        .map_err(|error| ActionError(format!("{} is not a valid manifest file: {error}", path.display())))
}

impl Manifest {
    /// Reads `actions.json` and every `bindings/*.json`. An id bound in two files fails the whole load, as an
    /// unreadable file does: which tool should perform it is a manifest error, not a choice to make at run time.
    pub fn load(dir: &Path) -> Result<Manifest, ActionError> {
        let actions: ActionFile = read(&dir.join("actions.json"))?;
        let binding_dir = dir.join("bindings");
        let listing = std::fs::read_dir(&binding_dir)
            .map_err(|error| ActionError(format!("cannot read {}: {error}", binding_dir.display())))?;
        let mut files: Vec<PathBuf> = listing
            .filter_map(|entry| entry.ok().map(|entry| entry.path()))
            .filter(|path| path.extension().is_some_and(|ext| ext == "json"))
            .collect();
        files.sort();
        let mut bindings = HashMap::new();
        let mut bound_in: HashMap<String, String> = HashMap::new();
        for file in files {
            let name = format!("bindings/{}", file.file_name().unwrap_or_default().to_string_lossy());
            let parsed: BindingFile = read(&file)?;
            for (id, binding) in parsed.bindings {
                if let Some(first) = bound_in.insert(id.clone(), name.clone()) {
                    return fail(format!("{id} is bound in both {first} and {name}"));
                }
                bindings.insert(id, binding);
            }
        }
        Ok(Manifest {
            actions: actions.actions,
            bindings,
        })
    }

    /// Every action id, sorted.
    pub fn ids(&self) -> Vec<&str> {
        let mut ids: Vec<&str> = self.actions.iter().map(|action| action.id.as_str()).collect();
        ids.sort();
        ids
    }

    /// The program and arguments that perform `id` with the given command-line words. Nothing runs: an unknown id,
    /// a missing binding or a bad param is an error here, so the caller never half-performs a request.
    pub fn plan(&self, id: &str, words: &[String], tools: &Tools) -> Result<Vec<String>, ActionError> {
        let Some(action) = self.actions.iter().find(|action| action.id == id) else {
            return fail(format!("unknown action '{id}' (known: {})", self.ids().join(", ")));
        };
        let Some(binding) = self.bindings.get(id) else {
            return fail(format!("{id} has no binding"));
        };
        let values = bind_params(action, words)?;
        let argv: Vec<String> = match binding {
            Binding::Lua => {
                // Each param is already canonical for its type (bind_params), so numbers and bools go in bare.
                let mut call = vec![lua_string(id)];
                for (param, (_, text)) in action.params.iter().zip(&values) {
                    call.push(match param.kind {
                        ParamKind::String | ParamKind::Enum => lua_string(text),
                        ParamKind::Int | ParamKind::Float | ParamKind::Bool => text.clone(),
                    });
                }
                let code = format!("require({}).run({})", lua_string(PERFORMERS), call.join(", "));
                return Ok(vec![tools.hyprctl.to_string_lossy().into_owned(), "eval".into(), code]);
            }
            Binding::Ipc { target, function, args } => {
                let mut argv = vec![
                    tools.qs_ipc.to_string_lossy().into_owned(),
                    "call".into(),
                    target.clone(),
                    function.clone(),
                ];
                argv.extend(args.iter().cloned());
                argv
            }
            Binding::Command { argv } => argv.clone(),
        };
        Ok(argv
            .iter()
            .map(|word| expand_home(&render(word, &values), tools.home))
            .collect())
    }
}

/// The text of each param after checking it against its type; a param with a default may be left out.
/// Defaults are checked like words even when a word replaces them, so a bad manifest fails on every call.
fn bind_params(action: &Action, words: &[String]) -> Result<Vec<(String, String)>, ActionError> {
    if words.len() > action.params.len() {
        return fail(format!(
            "{} takes {} param(s), got {}",
            action.id,
            action.params.len(),
            words.len()
        ));
    }
    // Params are positional, so only a trailing run can be left out; an earlier default could never be skipped.
    let first_default = action.params.iter().position(|param| param.default.is_some());
    let stranded = first_default.and_then(|first| action.params[first..].iter().find(|param| param.default.is_none()));
    if let Some(required) = stranded {
        return fail(format!(
            "{}: required param {} follows a param with a default",
            action.id, required.name
        ));
    }
    let mut values = Vec::new();
    for (index, param) in action.params.iter().enumerate() {
        let default = param
            .default
            .as_ref()
            .map(|default| default_text(param, default))
            .transpose()?;
        let text = match (words.get(index), default) {
            (Some(word), _) => convert(param, word)?,
            (None, Some(default)) => default,
            (None, None) => return fail(format!("{} needs param {}", action.id, param.name)),
        };
        values.push((param.name.clone(), text));
    }
    Ok(values)
}

/// The canonical text of one word for a param (`007` for an int is `7`), or the error naming the param.
fn convert(param: &Param, word: &str) -> Result<String, ActionError> {
    let name = &param.name;
    let bad = |kind: &str| ActionError(format!("param {name}: '{word}' is not a valid {kind}"));
    match param.kind {
        ParamKind::Int => word
            .parse::<i64>()
            .map(|value| value.to_string())
            .map_err(|_| bad("int")),
        ParamKind::Float => match word.parse::<f64>() {
            Ok(value) if value.is_finite() => Ok(value.to_string()),
            _ => Err(bad("float")),
        },
        ParamKind::Bool if word == "true" || word == "false" => Ok(word.to_string()),
        ParamKind::Bool => Err(bad("bool")),
        // qs-ipc and scripts would take a leading '-' as a flag; refusing it beats guessing where a `--` is understood.
        ParamKind::String if word.starts_with('-') => Err(ActionError(format!(
            "param {name}: '{word}' starts with '-', which a performer would read as a flag"
        ))),
        ParamKind::String => Ok(word.to_string()),
        ParamKind::Enum if param.values.iter().any(|value| value == word) => Ok(word.to_string()),
        ParamKind::Enum => Err(ActionError(format!(
            "param {name}: '{word}' is not one of {}",
            param.values.join(", ")
        ))),
    }
}

/// The text of a manifest default, after the same checks as a word. Its JSON type must match the param's.
fn default_text(param: &Param, default: &serde_json::Value) -> Result<String, ActionError> {
    use serde_json::Value;
    let text = match (param.kind, default) {
        (ParamKind::Int | ParamKind::Float, Value::Number(number)) => number.to_string(),
        (ParamKind::Bool, Value::Bool(flag)) => flag.to_string(),
        (ParamKind::String | ParamKind::Enum, Value::String(text)) => text.clone(),
        _ => {
            return fail(format!(
                "param {}: default {default} does not match its type",
                param.name
            ));
        }
    };
    convert(param, &text).map_err(|error| ActionError(format!("default of {error}")))
}

/// A binding word with each `{param}` replaced by its value. One pass over the word, so a value holding `{other}`
/// stays literal, and a `{...}` naming no param is kept as written.
fn render(word: &str, values: &[(String, String)]) -> String {
    let mut out = String::new();
    let mut rest = word;
    while let Some(open) = rest.find('{') {
        out.push_str(&rest[..open]);
        let tail = &rest[open..];
        let named = tail.find('}').and_then(|close| {
            values
                .iter()
                .find(|(name, _)| name == &tail[1..close])
                .map(|(_, value)| (close, value))
        });
        match named {
            Some((close, value)) => {
                out.push_str(value);
                rest = &tail[close + 1..];
            }
            None => {
                out.push('{');
                rest = &tail[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

/// A double-quoted Lua string holding exactly `text`. Every byte outside a small plain set becomes a three-digit
/// decimal escape, so no quote, backslash, bracket or newline in a CLI word can end the literal.
fn lua_string(text: &str) -> String {
    let mut out = String::from("\"");
    for byte in text.bytes() {
        if byte.is_ascii_alphanumeric() || b" _.,:/+=@-".contains(&byte) {
            out.push(byte as char);
        } else {
            out.push_str(&format!("\\{byte:03}"));
        }
    }
    out.push('"');
    out
}

fn expand_home(word: &str, home: &Path) -> String {
    match word.strip_prefix("~/") {
        Some(rest) => home.join(rest).to_string_lossy().into_owned(),
        None => word.to_string(),
    }
}

/// Runs a planned command and waits: true when it exited 0. A program that cannot start is an `Err`.
pub fn perform(argv: &[String]) -> std::io::Result<bool> {
    // Output is captured because `hyprctl eval` prints a Lua error to stdout and exits non-zero; on failure it is
    // forwarded to stderr, where a caller looks for the reason.
    let done = Command::new(&argv[0])
        .args(&argv[1..])
        .stderr(Stdio::inherit())
        .output()?;
    if done.status.success() {
        std::io::stdout().write_all(&done.stdout)?;
    } else {
        std::io::stderr().write_all(&done.stdout)?;
    }
    Ok(done.status.success())
}
