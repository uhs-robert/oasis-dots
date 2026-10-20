//! `integrations check`: validates integration files and reports `file:line:col: error: message`
//!
//! A TOML file is checked in depth: it parses, every verb's pattern compiles, every verb's action exists, no key is
//! mistyped, its modes' patterns compile and its `<stem>.sh` hook library passes `bash -n`. A legacy `.sh` file is only
//! loaded and its patterns compiled, since 3.2 deletes it; the summary says how many got only that.
use super::intents::Intents;
use super::list::relative;
use super::schema::{self, Format, Integration};
use super::{legacy, toml_files};
use crate::exit::CliError;
use crate::route::pattern;
use serde::Serialize;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Serialize)]
struct Report {
    ok: bool,
    files: usize,
    problems: Vec<Problem>,
}

#[derive(Serialize)]
struct Problem {
    file: PathBuf,
    line: usize,
    /// 1 where the source of the problem has no column (toml spans are read as lines only).
    column: usize,
    severity: Severity,
    code: &'static str,
    message: String,
}

#[derive(Serialize)]
#[serde(rename_all = "lowercase")]
enum Severity {
    Error,
}

pub fn run(files: &[String], json: bool) -> Result<Option<String>, CliError> {
    let dir = crate::paths::config_dir();
    let (report, legacy_loaded) = check(&dir, files);
    let text = if json {
        serde_json::to_string(&report).map_err(|error| CliError::failed("integrations check", error.to_string()))?
    } else {
        let mut lines: Vec<String> = report
            .problems
            .iter()
            .map(|problem| {
                format!(
                    "{}:{}:{}: error: {}",
                    problem.file.display(),
                    problem.line,
                    problem.column,
                    problem.message
                )
            })
            .collect();
        lines.push(format!(
            "{} TOML files checked, {} problems; {legacy_loaded} legacy files only loaded and compiled, not checked in depth",
            report.files,
            report.problems.len()
        ));
        lines.join("\n")
    };
    if report.ok {
        return Ok(Some(text));
    }
    // Problems are the output, not an error message: print them, then exit 1 without a stderr line.
    println!("{text}");
    Err(CliError::quiet("integrations check"))
}

/// The report, and how many legacy files were loaded without a deep check.
fn check(dir: &Path, args: &[String]) -> (Report, usize) {
    let intents = Intents::load(dir);
    let mut problems = Vec::new();
    let (mut toml, mut legacy_wanted): (Vec<PathBuf>, Vec<PathBuf>) = (Vec::new(), Vec::new());
    if args.is_empty() {
        toml = toml_files(dir);
        legacy_wanted = legacy::legacy_files(dir);
    }
    for arg in args {
        let given = PathBuf::from(arg);
        let file = if given.exists() { given } else { dir.join(arg) };
        if file.extension().is_some_and(|extension| extension == "sh") {
            legacy_wanted.push(file);
        } else {
            toml.push(file);
        }
    }
    for file in &toml {
        check_toml(dir, file, &intents, &mut problems);
    }
    // A legacy file whose stem has a TOML file is shadowed (Config::load drops it), so it is not loaded either.
    let shadowed = |file: &Path| toml.iter().any(|toml| toml.file_stem() == file.file_stem());
    legacy_wanted.retain(|file| !shadowed(file));
    let is_shadowed = |integration: &Integration| shadowed(&integration.file);
    let mut legacy_loaded = 0;
    if !legacy_wanted.is_empty() {
        match legacy::load(dir) {
            Ok(loaded) => {
                for integration in loaded.iter().filter(|integration| {
                    !is_shadowed(integration)
                        && (args.is_empty() || legacy_wanted.iter().any(|file| file == &integration.file))
                }) {
                    legacy_loaded += 1;
                    check_patterns(dir, integration, &intents, &mut problems);
                }
            }
            Err(message) => problems.push(Problem {
                file: relative(dir, &dir.join("integrations.d")),
                line: 1,
                column: 1,
                severity: Severity::Error,
                code: "legacy-load",
                message,
            }),
        }
    }
    let report = Report {
        ok: problems.is_empty(),
        files: toml.len(),
        problems,
    };
    (report, legacy_loaded)
}

fn check_toml(dir: &Path, file: &Path, intents: &Intents, problems: &mut Vec<Problem>) {
    let shown = relative(dir, file);
    let problem = |line: usize, code: &'static str, message: String| Problem {
        file: shown.clone(),
        line,
        column: 1,
        severity: Severity::Error,
        code,
        message,
    };
    let text = match std::fs::read_to_string(file) {
        Ok(text) => text,
        Err(error) => {
            problems.push(problem(1, "unreadable", error.to_string()));
            return;
        }
    };
    let integration = match schema::parse_toml(file, &text) {
        Ok(integration) => integration,
        Err(error) => {
            let (line, message) = split_located(file, &error);
            problems.push(problem(line, "invalid", message));
            return;
        }
    };
    unknown_keys(&text, &integration, &problem, problems);
    check_patterns(dir, &integration, intents, problems);
    for verb in &integration.verbs {
        if verb.action != "yield" && !integration.actions.contains_key(&verb.action) {
            problems.push(problem(
                verb.line.unwrap_or(1),
                "missing-action",
                format!("verb action {:?} is not declared under [actions]", verb.action),
            ));
        }
    }
    let hook = file.with_extension("sh");
    if hook.is_file() {
        // bash -n's stderr is the finding, so it is captured and never reaches the terminal.
        match Command::new("bash").arg("-n").arg(&hook).output() {
            Ok(output) if !output.status.success() => {
                let stderr = String::from_utf8_lossy(&output.stderr);
                let first = stderr.lines().next().unwrap_or_default();
                // `bash: line 3: msg`, or `hook.sh: line 3: msg`
                let (line, message) = first
                    .split_once(": line ")
                    .and_then(|(_, rest)| rest.split_once(": "))
                    .and_then(|(number, message)| Some((number.parse().ok()?, message.to_string())))
                    .unwrap_or((1, first.to_string()));
                problems.push(Problem {
                    file: relative(dir, &hook),
                    ..problem(line, "hook-syntax", message)
                });
            }
            Ok(_) => {}
            Err(error) => problems.push(problem(1, "hook-syntax", format!("cannot run bash -n: {error}"))),
        }
    }
}

/// Patterns of verbs and mode, as the router compiles them.
fn check_patterns(dir: &Path, integration: &Integration, intents: &Intents, problems: &mut Vec<Problem>) {
    let shown = relative(dir, &integration.file);
    let mut report = |line: usize, code: &'static str, message: String| {
        problems.push(Problem {
            file: shown.clone(),
            line,
            column: 1,
            severity: Severity::Error,
            code,
            message,
        });
    };
    for verb in &integration.verbs {
        let line = verb.line.unwrap_or(1);
        match pattern::compile(integration, verb, intents) {
            Err(message) => {
                let code = if message.contains("no placeholder, define or intent") {
                    "unknown-name"
                } else if message.contains("appears twice") {
                    "duplicate-placeholder"
                } else {
                    "bad-regex"
                };
                report(line, code, format!("verb {:?}: {message}", verb.pattern));
            }
            Ok(compiled) => {
                if let Err(error) = regex::bytes::Regex::new(&compiled.regex) {
                    report(line, "bad-regex", format!("verb {:?}: {error}", verb.pattern));
                }
            }
        }
    }
    if integration.format == Format::Toml
        && let Err(error) = pattern::compile_mode(integration, intents)
    {
        let (line, message) = split_located(&integration.file, &error);
        report(line, "bad-regex", message);
    }
}

fn unknown_keys(
    text: &str,
    integration: &Integration,
    problem: &impl Fn(usize, &'static str, String) -> Problem,
    problems: &mut Vec<Problem>,
) {
    let Ok(table) = text.parse::<toml::Table>() else {
        return;
    };
    let line_of_key = |key: &str, from: usize| {
        let found = regex::Regex::new(&format!(r#"(?m)\b{}"?\s*="#, regex::escape(key)))
            .ok()
            .and_then(|pattern| pattern.find_at(text, from));
        found.map_or(1, |found| text[..found.start()].matches('\n').count() + 1)
    };
    for key in table.keys().filter(|key| !schema::FILE_KEYS.contains(&key.as_str())) {
        problems.push(problem(
            line_of_key(key, 0),
            "unknown-key",
            format!("unknown key {key:?}"),
        ));
    }
    if let Some(toml::Value::Array(verbs)) = table.get("verbs") {
        for (verb, line) in verbs.iter().zip(integration.verbs.iter().map(|verb| verb.line)) {
            for key in verb
                .as_table()
                .into_iter()
                .flat_map(toml::Table::keys)
                .filter(|key| !schema::VERB_KEYS.contains(&key.as_str()))
            {
                problems.push(problem(
                    line.unwrap_or(1),
                    "unknown-key",
                    format!("unknown verb key {key:?}"),
                ));
            }
        }
    }
    if let Some(toml::Value::Table(actions)) = table.get("actions") {
        for (id, action) in actions {
            // Under its own header, or on its line under [actions] when written inline.
            let from = text
                .find(&format!("[actions.{id}]"))
                .or_else(|| {
                    regex::Regex::new(&format!(r"(?m)^\s*{}\s*=", regex::escape(id)))
                        .ok()?
                        .find(text)
                        .map(|found| found.start())
                })
                .unwrap_or(0);
            for key in action
                .as_table()
                .into_iter()
                .flat_map(toml::Table::keys)
                .filter(|key| !schema::ACTION_KEYS.contains(&key.as_str()))
            {
                problems.push(problem(
                    line_of_key(key, from),
                    "unknown-key",
                    format!("action {id}: unknown key {key:?}"),
                ));
            }
        }
    }
}

/// `file:line: message` (the loader's error form) as a line and a message; line 1 when there is none.
fn split_located(file: &Path, error: &str) -> (usize, String) {
    let rest = error
        .strip_prefix(&format!("{}:", file.display()))
        .unwrap_or(error)
        .trim_start();
    match rest.split_once(": ") {
        Some((number, message)) if number.parse::<usize>().is_ok() => {
            (number.parse().unwrap_or(1), message.to_string())
        }
        _ => (1, rest.to_string()),
    }
}
