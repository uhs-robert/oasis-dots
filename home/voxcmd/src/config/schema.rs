//! the integration types the router reads, and the serde types of an integration TOML (1.1 section 2) that load into them
//!
//! `Integration` is the only shape the router sees: TOML files and the legacy bash files (config/legacy.rs) both load
//! into it. So far it holds the subset of 1.1's schema that routing reads; unknown TOML keys are accepted until
//! `integrations check` (2.6) reports them.
use serde::Deserialize;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    Toml,
    /// An `integrations.d/*.sh` file read through the bash voxcmd's `_legacy-dump`. Goes in 3.2.
    Bash,
}

/// Which pass of routing tries the integration: the normal tier first, the fallback tier only when nothing else
/// (the LLM hook included) offered an option.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tier {
    Normal,
    Fallback,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum TargetMatch {
    #[default]
    Fuzzy,
    Words,
}

#[derive(Debug, Clone)]
pub struct Integration {
    pub name: String,
    pub stem: String,
    pub file: PathBuf,
    pub format: Format,
    pub tier: Tier,
    /// As written; the router normalizes them like the phrase.
    pub force_prefixes: Vec<String>,
    /// Pattern fragments usable as `{name}` (TOML only).
    pub defines: BTreeMap<String, String>,
    /// `[mode] exit_object`, the `{mode_object}` of patterns and the object of `{mode_exit}` (TOML only).
    pub mode_exit_object: Option<String>,
    pub verbs: Vec<Verb>,
    pub settings: MatchSettings,
    pub actions: BTreeMap<String, Action>,
    pub surface: Option<Surface>,
}

impl Integration {
    /// The hook that lists candidates for the action. A legacy file has one `candidates` function for all its actions,
    /// including a verb's action the file never declared.
    pub fn candidates_for(&self, action: &str) -> Option<&Candidates> {
        match self.actions.get(action) {
            Some(declared) => declared.candidates.as_ref(),
            None if self.format == Format::Bash => {
                self.actions.values().find_map(|declared| declared.candidates.as_ref())
            }
            None => None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct Verb {
    /// An action id, or `yield` (TOML only): the integration offers nothing for the phrase.
    pub action: String,
    pub pattern: String,
    /// Line in the TOML file; legacy verbs have none.
    pub line: Option<usize>,
    /// Another integration's stem that must be loaded for this verb to count.
    pub requires: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct MatchSettings {
    pub target_match: TargetMatch,
    pub match_ignore_words: Vec<String>,
    pub confirm: bool,
    pub confirm_labels: Vec<String>,
    pub private_labels: bool,
    pub action_labels: bool,
}

#[derive(Debug, Clone, Default)]
pub struct Action {
    pub run: String,
    pub candidates: Option<Candidates>,
    pub no_match: Option<String>,
    pub silent: bool,
    pub free_text: bool,
    pub mode_switch: bool,
    pub mode_entry: bool,
    pub wait: Option<Wait>,
    /// Seconds the action's hooks may run; the hook default (3) when unset.
    pub timeout_secs: Option<f64>,
}

#[derive(Debug, Clone)]
pub enum Candidates {
    Shell(String),
    /// The legacy file's `candidates <action> <target>` function, run through `_legacy-hook`. Goes in 3.2.
    LegacyFunction,
}

#[derive(Debug, Clone)]
pub enum Wait {
    Builtin(String),
    Hook(String),
    /// A legacy `step_waits` shell condition. Goes in 3.2.
    LegacyCondition(String),
}

#[derive(Debug, Clone)]
pub enum Surface {
    /// Under `$XDG_RUNTIME_DIR/voxcmd`; open while its top-level `open` is true.
    StateFile(PathBuf),
    /// The legacy file's `surface_open` function. Goes in 3.2.
    LegacyHook,
}

// ---- the TOML file --------------------------------------------------------------------------------------------------

#[derive(Deserialize)]
struct IntegrationFile {
    name: Option<String>,
    #[serde(default)]
    fallback: bool,
    #[serde(default)]
    confirm: bool,
    #[serde(default)]
    confirm_labels: Vec<String>,
    #[serde(default)]
    silent: bool,
    #[serde(default)]
    private_labels: bool,
    #[serde(default)]
    target_match: TargetMatch,
    #[serde(default)]
    match_ignore_words: Vec<String>,
    action_labels: Option<bool>,
    #[serde(default)]
    force_prefixes: Vec<String>,
    #[serde(default)]
    define: BTreeMap<String, String>,
    verbs: Vec<toml::Spanned<VerbEntry>>,
    #[serde(default)]
    actions: BTreeMap<String, ActionEntry>,
    surface: Option<SurfaceEntry>,
    mode: Option<ModeEntry>,
}

#[derive(Deserialize)]
struct VerbEntry {
    action: String,
    #[serde(rename = "match")]
    pattern: String,
    requires: Option<String>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum ActionEntry {
    Run(String),
    Table(ActionTable),
}

#[derive(Deserialize, Default)]
struct ActionTable {
    #[serde(default)]
    run: String,
    candidates: Option<String>,
    no_match: Option<String>,
    silent: Option<bool>,
    #[serde(default)]
    free_text: bool,
    #[serde(default)]
    mode_switch: bool,
    #[serde(default)]
    mode_entry: bool,
    wait: Option<String>,
    wait_hook: Option<String>,
    timeout_secs: Option<f64>,
}

#[derive(Deserialize)]
struct SurfaceEntry {
    state_file: PathBuf,
}

#[derive(Deserialize)]
struct ModeEntry {
    exit_object: Option<String>,
}

/// Reads one `integrations/<stem>.toml`. The error is `file:line: message`.
pub fn load_toml(file: &Path) -> Result<Integration, String> {
    let text = std::fs::read_to_string(file).map_err(|error| format!("{}: {error}", file.display()))?;
    parse_toml(file, &text)
}

pub fn parse_toml(file: &Path, text: &str) -> Result<Integration, String> {
    let line_of = |offset: usize| text[..offset.min(text.len())].matches('\n').count() + 1;
    let parsed: IntegrationFile = toml::from_str(text).map_err(|error| {
        let line = error.span().map_or(1, |span| line_of(span.start));
        format!("{}:{line}: {}", file.display(), error.message())
    })?;
    let stem = file.file_stem().unwrap_or_default().to_string_lossy().into_owned();
    let verbs = parsed
        .verbs
        .into_iter()
        .map(|spanned| {
            let line = line_of(spanned.span().start);
            let entry = spanned.into_inner();
            Verb {
                action: entry.action,
                pattern: entry.pattern,
                line: Some(line),
                requires: entry.requires,
            }
        })
        .collect();
    let actions = parsed
        .actions
        .into_iter()
        .map(|(id, entry)| {
            let table = match entry {
                ActionEntry::Run(run) => ActionTable {
                    run,
                    ..ActionTable::default()
                },
                ActionEntry::Table(table) => table,
            };
            let wait = match (table.wait, table.wait_hook) {
                (_, Some(hook)) => Some(Wait::Hook(hook)),
                (Some(builtin), None) => Some(Wait::Builtin(builtin)),
                (None, None) => None,
            };
            let timeout_secs = match table.timeout_secs {
                // The untagged `ActionEntry` cannot carry a span, so the line is looked up in the text.
                Some(secs) => Some(checked_timeout(secs, || match timeout_offset(text, &id) {
                    Some(offset) => format!("{}:{}", file.display(), line_of(offset)),
                    None => file.display().to_string(),
                })?),
                None => None,
            };
            let action = Action {
                run: table.run,
                candidates: table.candidates.map(Candidates::Shell),
                no_match: table.no_match,
                silent: table.silent.unwrap_or(parsed.silent),
                free_text: table.free_text,
                mode_switch: table.mode_switch,
                mode_entry: table.mode_entry,
                wait,
                timeout_secs,
            };
            Ok((id, action))
        })
        .collect::<Result<BTreeMap<_, _>, String>>()?;
    Ok(Integration {
        name: parsed.name.unwrap_or_else(|| stem.clone()),
        stem,
        file: file.to_path_buf(),
        format: Format::Toml,
        tier: if parsed.fallback { Tier::Fallback } else { Tier::Normal },
        force_prefixes: parsed.force_prefixes,
        defines: parsed.define,
        mode_exit_object: parsed.mode.and_then(|mode| mode.exit_object),
        verbs,
        settings: MatchSettings {
            target_match: parsed.target_match,
            match_ignore_words: parsed.match_ignore_words,
            confirm: parsed.confirm,
            confirm_labels: parsed.confirm_labels,
            private_labels: parsed.private_labels,
            action_labels: parsed.action_labels.unwrap_or(true),
        },
        actions,
        surface: parsed.surface.map(|surface| Surface::StateFile(surface.state_file)),
    })
}

/// Where an action's `timeout_secs` is written: inside the action's own `[actions.<id>]` table, or on its key's line
/// under `[actions]`. None when it is not found there (a dotted key elsewhere), and the error then names only the file.
fn timeout_offset(text: &str, action: &str) -> Option<usize> {
    let table = format!("[actions.{action}]");
    let (start, end) = match text.find(&table) {
        Some(start) => (
            start,
            text[start + 1..]
                .find("\n[")
                .map_or(text.len(), |next| start + 1 + next),
        ),
        None => {
            let start = text.find(&format!("\n{action} = "))? + 1;
            (start, text[start..].find('\n').map_or(text.len(), |next| start + next))
        }
    };
    text[start..end].find("timeout_secs").map(|found| start + found)
}

/// The longest a hook may be given; anything longer is a typo for a hook that never ends.
const MAX_TIMEOUT_SECS: f64 = 300.0;

/// `timeout_secs` as a duration in seconds: finite, above zero (zero would time every hook out) and at most
/// `MAX_TIMEOUT_SECS`. `place` names the file and line for the error.
fn checked_timeout(secs: f64, place: impl Fn() -> String) -> Result<f64, String> {
    if secs.is_finite() && secs > 0.0 && secs <= MAX_TIMEOUT_SECS {
        Ok(secs)
    } else {
        Err(format!(
            "{}: timeout_secs must be above 0 and at most {MAX_TIMEOUT_SECS}, not {secs}",
            place()
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(stem: &str) -> Integration {
        let file = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(format!("tests/fixtures/integrations/{stem}.toml"));
        load_toml(&file).unwrap()
    }

    #[test]
    fn media_toml_loads_its_verbs_actions_and_defaults() {
        let media = fixture("media");
        assert_eq!(media.name, "Media");
        assert_eq!(media.tier, Tier::Normal);
        assert_eq!(media.verbs.len(), 13);
        assert_eq!(media.verbs[0].action, "toggle");
        assert_eq!(media.verbs[0].line, Some(8));
        assert_eq!(media.actions["next"].run, "playerctl next");
        assert!(media.actions["mute"].silent);
        assert!(!media.actions["next"].silent);
        assert!(matches!(
            media.actions["play_on"].candidates,
            Some(Candidates::Shell(_))
        ));
    }

    #[test]
    fn apps_toml_keeps_defines_and_requires() {
        let apps = fixture("apps");
        assert!(apps.defines.contains_key("names_window"));
        assert_eq!(apps.verbs[2].requires.as_deref(), Some("firefox"));
        assert_eq!(apps.settings.target_match, TargetMatch::Words);
    }

    #[test]
    fn a_bad_file_names_its_line() {
        let error = parse_toml(Path::new("bad.toml"), "name = \"x\"\nverbs = [ { action = 1 } ]\n").unwrap_err();
        assert!(error.starts_with("bad.toml:2: "), "{error}");
    }

    #[test]
    fn timeout_secs_must_be_a_usable_number_of_seconds() {
        let with = |value: &str| {
            let text = format!("verbs = []\n[actions.go]\nrun = \"true\"\ntimeout_secs = {value}\n");
            parse_toml(Path::new("t.toml"), &text)
        };
        assert_eq!(with("0.5").unwrap().actions["go"].timeout_secs, Some(0.5));
        assert_eq!(with("300").unwrap().actions["go"].timeout_secs, Some(300.0));
        for bad in ["0", "-1", "nan", "inf", "-inf", "301"] {
            let error = with(bad).unwrap_err();
            assert!(
                error.starts_with("t.toml:4: timeout_secs must be above 0"),
                "{bad}: {error}"
            );
        }
    }

    #[test]
    fn a_bad_timeout_names_the_line_of_its_own_action() {
        let text = "verbs = []\n[actions.a]\nrun = \"true\"\ntimeout_secs = 1\n[actions.b]\nrun = \"true\"\ntimeout_secs = 0\n";
        let error = parse_toml(Path::new("t.toml"), text).unwrap_err();
        assert!(error.starts_with("t.toml:7: "), "{error}");
        let no_key = "verbs = []\n[actions.a]\nrun = \"true\"\ntimeout_secs = 1\n[actions.b]\nrun = \"true\"\n";
        assert_eq!(timeout_offset(no_key, "b"), None);
    }
}
