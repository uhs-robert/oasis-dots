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
use crate::route::pattern::{self, PlaceholderType};
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
    /// 1 where the problem has no span of its own (a whole-file problem, or an error the loader words with a line only).
    column: usize,
    severity: Severity,
    code: &'static str,
    message: String,
}

#[derive(Serialize)]
#[serde(rename_all = "lowercase")]
enum Severity {
    Error,
    Warning,
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
                    "{}:{}:{}: {}: {}",
                    problem.file.display(),
                    problem.line,
                    problem.column,
                    problem.severity.label(),
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
        if legacy_wanted.is_empty() {
            problems.extend(legacy::stray_files(dir).iter().map(|file| Problem {
                file: relative(dir, file),
                line: 1,
                column: 1,
                severity: Severity::Warning,
                code: "stray-integration",
                message: format!(
                    "integrations.d/{} is no longer read; convert it to TOML",
                    file.file_name().unwrap_or_default().to_string_lossy()
                ),
            }));
        }
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
    let mut legacy_loaded = 0;
    if !legacy_wanted.is_empty() {
        let loaded = if args.is_empty() {
            legacy::load(dir)
        } else {
            // A named file is loaded itself, wherever it is: a missing one is a problem, not a file with nothing to check.
            let (present, missing): (Vec<_>, Vec<_>) = legacy_wanted.iter().cloned().partition(|file| file.is_file());
            for file in missing {
                problems.push(Problem {
                    file: relative(dir, &file),
                    line: 1,
                    column: 1,
                    severity: Severity::Error,
                    code: "unreadable",
                    message: "not a readable file".to_string(),
                });
            }
            if present.is_empty() {
                Ok(Vec::new())
            } else {
                legacy::load_files(&present)
            }
        };
        match loaded {
            Ok(loaded) => {
                for integration in loaded.iter().filter(|integration| !shadowed(&integration.file)) {
                    legacy_loaded += 1;
                    check_patterns(dir, integration, &intents, &mut problems);
                }
                for file in legacy_wanted.iter().filter(|file| {
                    file.is_file()
                        && !loaded
                            .iter()
                            .any(|integration| integration.file.file_name() == file.file_name())
                }) {
                    problems.push(Problem {
                        file: relative(dir, file),
                        line: 1,
                        column: 1,
                        severity: Severity::Error,
                        code: "legacy-load",
                        message: "the file did not load".to_string(),
                    });
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
        ok: problems
            .iter()
            .all(|problem| matches!(problem.severity, Severity::Warning)),
        files: toml.len(),
        problems,
    };
    (report, legacy_loaded)
}

fn check_toml(dir: &Path, file: &Path, intents: &Intents, problems: &mut Vec<Problem>) {
    let shown = relative(dir, file);
    let problem = |(line, column): (usize, usize), code: &'static str, message: String| Problem {
        file: shown.clone(),
        line,
        column,
        severity: Severity::Error,
        code,
        message,
    };
    let text = match std::fs::read_to_string(file) {
        Ok(text) => text,
        Err(error) => {
            problems.push(problem((1, 1), "unreadable", error.to_string()));
            return;
        }
    };
    let integration = match schema::parse_toml(file, &text) {
        Ok(integration) => integration,
        Err(error) => {
            let (line, message) = split_located(file, &error);
            let column = schema::syntax_error_column(&text).unwrap_or(1);
            problems.push(problem((line, column), "invalid", message));
            return;
        }
    };
    unknown_keys(&text, &integration, &problem, problems);
    check_patterns(dir, &integration, intents, problems);
    for verb in &integration.verbs {
        if verb.action != "yield" && !integration.actions.contains_key(&verb.action) {
            let line = verb.line.unwrap_or(1);
            let column = column_in(&text, line, &verb.action).or(verb.column).unwrap_or(1);
            problems.push(problem(
                (line, column),
                "missing-action",
                format!("verb action {:?} is not declared under [actions]", verb.action),
            ));
        }
    }
    for entry in &integration.help {
        if !integration.actions.contains_key(&entry.action) {
            problems.push(problem(
                line_in_text_from_line(&text, "action", entry.line),
                "missing-action",
                format!("[[help]] action {:?} is not declared under [actions]", entry.action),
            ));
        }
    }
    for (id, action) in &integration.actions {
        if let Some(schema::Wait::Builtin(name)) = &action.wait
            && schema::BuiltinWait::parse(name).is_none()
        {
            let from = text.find(&format!("[actions.{id}]")).unwrap_or(0);
            problems.push(problem(
                line_in_text(&text, "wait", from),
                "unknown-wait",
                format!("action {id}: unknown wait {name:?}"),
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
                    ..problem((line, 1), "hook-syntax", message)
                });
            }
            Ok(_) => {}
            Err(error) => problems.push(problem((1, 1), "hook-syntax", format!("cannot run bash -n: {error}"))),
        }
    }
}

/// Patterns of verbs and mode, as the router compiles them.
fn check_patterns(dir: &Path, integration: &Integration, intents: &Intents, problems: &mut Vec<Problem>) {
    let shown = relative(dir, &integration.file);
    let mut report = |(line, column): (usize, usize), code: &'static str, message: String| {
        problems.push(Problem {
            file: shown.clone(),
            line,
            column,
            severity: if code == "shadowed-verb" {
                Severity::Warning
            } else {
                Severity::Error
            },
            code,
            message,
        });
    };
    let mut earlier_with_regex: std::collections::HashMap<String, Vec<usize>> = std::collections::HashMap::new();
    for (index, verb) in integration.verbs.iter().enumerate() {
        let at = (verb.line.unwrap_or(1), verb.column.unwrap_or(1));
        match pattern::compile(integration, verb, intents) {
            Err(message) => {
                let code = if message.contains("no placeholder, define or intent") {
                    "unknown-name"
                } else if message.contains("appears twice") {
                    "duplicate-placeholder"
                } else {
                    "bad-regex"
                };
                report(at, code, format!("verb {:?}: {message}", verb.pattern));
            }
            Ok(compiled) => {
                if let Err(error) = regex::bytes::Regex::new(&compiled.regex) {
                    report(at, "bad-regex", format!("verb {:?}: {error}", verb.pattern));
                }
                // Within one integration the first matching verb wins. Across integrations nothing is shadowed:
                // every one of a tier offers its option and several go to a picker. A legacy file is only loaded.
                // `requires` is the one per-verb eligibility the matcher checks: a verb that needs an integration
                // that is not loaded is skipped, so it shadows a later verb only if that verb needs the same one.
                // The matcher also moves on when a typed capture does not parse, so only a verb whose captures take
                // any words (text, number) can shadow: `go {value:position}` leaves `go tokyo` to a later `go {value}`.
                let earlier_verbs = earlier_with_regex.entry(compiled.regex).or_default();
                if integration.format == Format::Toml
                    && let Some(&earlier) = earlier_verbs.iter().find(|&&earlier| {
                        let required = &integration.verbs[earlier].requires;
                        required.is_none() || *required == verb.requires
                    })
                {
                    report(
                        at,
                        "shadowed-verb",
                        format!(
                            "verb {:?} can never match: verb {} ({:?}) matches the same phrases first",
                            verb.pattern, earlier, integration.verbs[earlier].action
                        ),
                    );
                }
                let takes_any_words = compiled
                    .placeholders
                    .iter()
                    .all(|placeholder| matches!(placeholder.kind, PlaceholderType::Text | PlaceholderType::Number));
                if takes_any_words {
                    earlier_verbs.push(index);
                }
            }
        }
    }
    if integration.format == Format::Toml
        && let Err(error) = pattern::compile_mode(integration, intents)
    {
        let (line, message) = split_located(&integration.file, &error);
        report((line, 1), "bad-regex", message);
    }
}

fn unknown_keys(
    text: &str,
    integration: &Integration,
    problem: &impl Fn((usize, usize), &'static str, String) -> Problem,
    problems: &mut Vec<Problem>,
) {
    let Ok(table) = text.parse::<toml::Table>() else {
        return;
    };
    let line_of_key = |key: &str, from: usize| {
        let found = regex::Regex::new(&format!(r#"(?m)\b{}"?\s*="#, regex::escape(key)))
            .ok()
            .and_then(|pattern| pattern.find_at(text, from));
        found.map_or((1, 1), |found| {
            (
                text[..found.start()].matches('\n').count() + 1,
                schema::column_of(text, found.start()),
            )
        })
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
                let line = line.unwrap_or(1);
                problems.push(problem(
                    (line, column_in(text, line, key).unwrap_or(1)),
                    "unknown-key",
                    format!("unknown verb key {key:?}"),
                ));
            }
        }
    }
    if let Some(toml::Value::Array(entries)) = table.get("help") {
        for (entry, help) in entries.iter().zip(&integration.help) {
            for key in entry
                .as_table()
                .into_iter()
                .flat_map(toml::Table::keys)
                .filter(|key| !schema::HELP_KEYS.contains(&key.as_str()))
            {
                // The entry's header line, then its own lines down to the key.
                let found = line_in_text_from_line(text, key, help.line);
                problems.push(problem(found, "unknown-key", format!("unknown help key {key:?}")));
            }
        }
    }
    if let Some(toml::Value::Table(surface)) = table.get("surface") {
        let from = text.find("[surface]").unwrap_or(0);
        for key in surface
            .keys()
            .filter(|key| !schema::SURFACE_KEYS.contains(&key.as_str()))
        {
            problems.push(problem(
                line_of_key(key, from),
                "unknown-key",
                format!("unknown surface key {key:?}"),
            ));
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

/// Line and column of the first `key =` at or after byte `from`; (1, 1) when there is none.
fn line_in_text(text: &str, key: &str, from: usize) -> (usize, usize) {
    regex::Regex::new(&format!(r#"(?m)\b{}"?\s*="#, regex::escape(key)))
        .ok()
        .and_then(|pattern| pattern.find_at(text, from))
        .map_or((1, 1), |found| {
            (
                text[..found.start()].matches('\n').count() + 1,
                schema::column_of(text, found.start()),
            )
        })
}

/// `line_in_text` from the start of the 1-based `line`.
fn line_in_text_from_line(text: &str, key: &str, line: usize) -> (usize, usize) {
    let from = text
        .split_inclusive('\n')
        .take(line.saturating_sub(1))
        .map(str::len)
        .sum();
    line_in_text(text, key, from)
}

/// 1-based column of the first `needle` on the 1-based `line` of `text`.
fn column_in(text: &str, line: usize, needle: &str) -> Option<usize> {
    let line_text = text.lines().nth(line.checked_sub(1)?)?;
    Some(line_text[..line_text.find(needle)?].chars().count() + 1)
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

impl Severity {
    fn label(&self) -> &'static str {
        match self {
            Self::Error => "error",
            Self::Warning => "warning",
        }
    }
}
