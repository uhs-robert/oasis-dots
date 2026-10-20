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
    /// The voice-session mode this integration opens (`[mode]`, TOML only).
    pub mode: Option<Mode>,
    pub verbs: Vec<Verb>,
    /// Phrases for Voice Help; `<name>` marks a spoken part.
    pub examples: Vec<String>,
    /// A legacy file lists runnable choices in Voice Help (`help_choices`, or `help_action` over `candidates`), which
    /// only the bash voxcmd can produce. A TOML file's are its `help` entries instead.
    pub legacy_help: bool,
    /// What Tab lists in Voice Help (TOML only), in file order.
    pub help: Vec<Help>,
    pub settings: MatchSettings,
    pub actions: BTreeMap<String, Action>,
    pub surface: Option<Surface>,
    /// How several options are shown when the integration can place each on screen.
    pub picker: Option<Picker>,
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
    /// Column of the verb's entry in that line, for `integrations check`.
    pub column: Option<usize>,
    /// Another integration's stem that must be loaded for this verb to count.
    pub requires: Option<String>,
    /// The legacy `verbs` entry as written, alignment spaces included, which `integrations list` prints.
    pub listed: Option<String>,
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
    /// What voxcmd does itself instead of running `run`, which stays as the text explain prints.
    pub builtin: Option<Builtin>,
    pub no_match: Option<String>,
    pub silent: bool,
    pub free_text: bool,
    pub mode_switch: bool,
    pub mode_entry: bool,
    /// Opens the integration's mode before `run`; `run` may then be empty.
    pub enter_mode: bool,
    /// Leaves the integration's mode with this reason; nothing happens when it is not open.
    pub leave_mode: Option<String>,
    /// The action ran but found nothing to act on: the session turn counts as unclear.
    pub miss: bool,
    pub wait: Option<Wait>,
    /// Seconds the action's hooks may run; the hook default (3) when unset.
    pub timeout_secs: Option<f64>,
}

/// A voice-session mode, as `[mode]` declares it. Patterns are as written (same `{define}`/`{mode_object}` dialect as
/// verbs); `route::pattern::compile_mode` compiles them.
#[derive(Debug, Clone)]
pub struct Mode {
    pub label: String,
    pub exit_phrases: String,
    pub exit_hint: String,
    pub bare_exits: bool,
    pub default_exits: bool,
    pub allows_switches: bool,
    pub private: bool,
    pub open_ended: bool,
    pub wake_listens: bool,
    pub listen: ModeListen,
    pub rewrite: Option<Rewrite>,
    pub rewrite_hook: Option<String>,
    pub ended: Option<String>,
    pub alive: Option<String>,
    /// Takes the turn's words itself (`VOXCMD_TEXT`), and a one-recording mode's text with its ending's action
    /// (`VOXCMD_ENDING`).
    pub handle_turn: Option<String>,
    /// Hears one recording, handed to `handle_turn` once it ends.
    pub one_recording: bool,
    /// How a one-recording mode's recording ends after the wake word, first match first.
    pub endings: Vec<ModeEnding>,
    /// Seconds the mode's hooks may run; the hook default (3) when unset. `handle_turn` has a limit that grows with
    /// the text (`session::mode`), and this can only lengthen it, never cut a long dictation short.
    pub timeout_secs: Option<f64>,
    /// Lines in the TOML file of the keys holding patterns, for error messages.
    pub pattern_lines: BTreeMap<&'static str, usize>,
}

/// One of `[mode] endings`: `discard` cancels the recording, `end_session` ends the session once the text is handled,
/// and any other action is handed to `handle_turn` as `VOXCMD_ENDING`.
#[derive(Debug, Clone)]
pub struct ModeEnding {
    pub action: String,
    pub pattern: String,
    pub line: usize,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ModeListen {
    pub silence_secs: Option<f64>,
    pub max_secs: Option<f64>,
    pub no_speech_secs: Option<f64>,
}

/// A turn's words with the first rule that applies: `drop` routes nothing, `keep` routes them as spoken, else the
/// `prefix` goes before them. Whole-text patterns.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Rewrite {
    pub drop: Option<String>,
    pub keep: Option<String>,
    #[serde(default)]
    pub prefix: String,
}

#[derive(Debug, Clone)]
pub enum Candidates {
    Shell(String),
    /// The legacy file's `candidates <action> <target>` function, run through `_legacy-hook`. Goes in 3.2.
    LegacyFunction,
    /// A source voxcmd runs itself: no shell, no bridge.
    Builtin(Provider),
}

/// A built-in candidate source, named by `provider = "..."` on an action.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Provider {
    /// The text on the focused window, read by OCR.
    ScreenText,
}

impl Provider {
    pub const KNOWN: &'static str = "screen_text";

    pub fn named(name: &str) -> Option<Self> {
        (name == Self::KNOWN).then_some(Self::ScreenText)
    }
}

/// The pointer button of a click.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Button {
    Left,
    Right,
    Middle,
    /// Two left clicks: wlrctl has no double click.
    Double,
    /// Three left clicks.
    Triple,
}

impl Button {
    pub fn named(name: &str) -> Option<Self> {
        match name {
            "left" => Some(Self::Left),
            "right" => Some(Self::Right),
            "middle" => Some(Self::Middle),
            "double" => Some(Self::Double),
            "triple" => Some(Self::Triple),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Left => "left",
            Self::Right => "right",
            Self::Middle => "middle",
            Self::Double => "double",
            Self::Triple => "triple",
        }
    }
}

/// An action voxcmd performs in-process in place of a shell command.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Builtin {
    /// Moves the pointer to the candidate id's point and clicks. The button the provider chose is in the id; the one
    /// named here (`run = "click_at right"`) is what the provider puts there.
    ClickAt(Option<Button>),
    /// Says the spoken target is not on screen.
    NoText,
    /// Starts the keyboard pointer overlay.
    ShowHints,
}

/// An integration's own way of showing several options.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Picker {
    /// Numbered boxes drawn over each option's `box` (`ask hints`); the option id must say where its box is.
    Hints,
}

/// The waits a TOML action can name with `wait = "..."`. `integrations check` and the sequence runner both go through
/// `parse`, so a name one accepts is a name the other runs.
pub enum BuiltinWait<'a> {
    ActiveWindowIsId,
    ActiveWindowChanged,
    WindowGone,
    PopupOpen(&'a str),
}

impl<'a> BuiltinWait<'a> {
    pub fn parse(name: &'a str) -> Option<Self> {
        match name {
            "active_window_is_id" => Some(Self::ActiveWindowIsId),
            "active_window_changed" => Some(Self::ActiveWindowChanged),
            "window_gone" => Some(Self::WindowGone),
            _ => name.strip_prefix("popup_open:").map(Self::PopupOpen),
        }
    }
}

#[derive(Debug, Clone)]
pub enum Wait {
    Builtin(String),
    Hook(String),
    /// A legacy `step_waits` shell condition. Goes in 3.2.
    LegacyCondition(String),
}

/// One `[[help]]` entry: the runnable rows Tab shows for the integration in Voice Help, each run as `action`.
#[derive(Debug, Clone)]
pub struct Help {
    pub action: String,
    pub rows: HelpRows,
    pub line: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HelpRows {
    /// The action's `candidates` asked with no target.
    Candidates,
    /// A shell hook printing `id<TAB>label` lines.
    Hook(String),
    /// One fixed row; the id may be empty.
    Static { id: String, label: String },
}

#[derive(Debug, Clone)]
pub enum Surface {
    /// Under `$XDG_RUNTIME_DIR/voxcmd`; open while its top-level `open` is true.
    StateFile(PathBuf),
    /// The legacy file's `surface_open` function. Goes in 3.2.
    LegacyHook,
}

// ---- the TOML file --------------------------------------------------------------------------------------------------

/// The keys each table accepts, for `integrations check` to name a mistyped one. The loader ignores unknown keys, and
/// ignores `label` and `candidate_arg` too (nothing reads them yet), so these lists are 1.1's schema, not the
/// serde structs below.
pub const FILE_KEYS: &[&str] = &[
    "name",
    "fallback",
    "confirm",
    "confirm_labels",
    "silent",
    "private_labels",
    "target_match",
    "match_ignore_words",
    "action_labels",
    "force_prefixes",
    "define",
    "verbs",
    "help",
    "examples",
    "actions",
    "picker",
    "surface",
    "mode",
];
pub const VERB_KEYS: &[&str] = &["action", "match", "label", "requires"];
pub const HELP_KEYS: &[&str] = &["action", "list", "id", "label"];
pub const SURFACE_KEYS: &[&str] = &["state_file"];
pub const ACTION_KEYS: &[&str] = &[
    "run",
    "candidates",
    "provider",
    "candidate_arg",
    "no_match",
    "silent",
    "free_text",
    "mode_switch",
    "mode_entry",
    "enter_mode",
    "leave_mode",
    "miss",
    "wait",
    "wait_hook",
    "timeout_secs",
];

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
    help: Vec<toml::Spanned<HelpEntry>>,
    #[serde(default)]
    examples: Vec<String>,
    #[serde(default)]
    actions: BTreeMap<String, ActionEntry>,
    picker: Option<String>,
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

/// Checked while it is read, so a malformed entry is a toml error with the entry's own span (line and column).
#[derive(Deserialize)]
#[serde(try_from = "HelpFields")]
struct HelpEntry {
    action: String,
    rows: HelpRows,
}

#[derive(Deserialize)]
struct HelpFields {
    action: String,
    list: Option<String>,
    id: Option<String>,
    label: Option<String>,
}

impl TryFrom<HelpFields> for HelpEntry {
    type Error = String;

    fn try_from(fields: HelpFields) -> Result<Self, String> {
        if fields.action.trim().is_empty() {
            return Err("[[help]] action must name an action".to_string());
        }
        let rows = match (fields.list, fields.id, fields.label) {
            (Some(hook), None, None) if hook.trim().is_empty() => return Err("[[help]] list is empty".to_string()),
            (Some(hook), None, None) => HelpRows::Hook(hook),
            (Some(_), _, _) => return Err("[[help]] list and id/label are both set; use one".to_string()),
            (None, _, Some(label)) if label.is_empty() => return Err("[[help]] label is empty".to_string()),
            (None, id, Some(label)) => HelpRows::Static {
                id: id.unwrap_or_default(),
                label,
            },
            (None, Some(_), None) => return Err("[[help]] a static row with an id needs a label".to_string()),
            (None, None, None) => HelpRows::Candidates,
        };
        Ok(Self {
            action: fields.action,
            rows,
        })
    }
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
    provider: Option<String>,
    no_match: Option<String>,
    silent: Option<bool>,
    #[serde(default)]
    free_text: bool,
    #[serde(default)]
    mode_switch: bool,
    #[serde(default)]
    mode_entry: bool,
    #[serde(default)]
    enter_mode: bool,
    leave_mode: Option<String>,
    #[serde(default)]
    miss: bool,
    wait: Option<String>,
    wait_hook: Option<String>,
    timeout_secs: Option<f64>,
}

#[derive(Deserialize)]
struct SurfaceEntry {
    state_file: PathBuf,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ModeEntry {
    label: Option<String>,
    exit_object: Option<String>,
    #[serde(default)]
    exit_phrases: String,
    #[serde(default)]
    exit_hint: String,
    bare_exits: Option<bool>,
    default_exits: Option<bool>,
    #[serde(default)]
    allows_switches: bool,
    #[serde(default)]
    private: bool,
    #[serde(default)]
    open_ended: bool,
    #[serde(default)]
    wake_listens: bool,
    #[serde(default)]
    listen: ModeListen,
    rewrite: Option<Rewrite>,
    rewrite_hook: Option<String>,
    ended: Option<String>,
    alive: Option<String>,
    timeout_secs: Option<f64>,
    handle_turn: Option<String>,
    endings: Option<Vec<toml::Spanned<EndingEntry>>>,
    #[serde(default)]
    one_recording: bool,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct EndingEntry {
    action: String,
    #[serde(rename = "match")]
    pattern: String,
}

/// 1-based column of a byte offset, counted in characters.
pub fn column_of(text: &str, offset: usize) -> usize {
    let before = &text[..offset.min(text.len())];
    before.rsplit('\n').next().map_or(0, |line| line.chars().count()) + 1
}

/// Where the toml parser says `text` is malformed: the one place an error carries a column.
pub fn syntax_error_column(text: &str) -> Option<usize> {
    let error = toml::from_str::<IntegrationFile>(text).err()?;
    Some(column_of(text, error.span()?.start))
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
    let has_mode = parsed.mode.is_some();
    let (mode, mode_exit_object) = match parsed.mode {
        Some(entry) => {
            let label = entry
                .label
                .clone()
                .unwrap_or_else(|| parsed.name.clone().unwrap_or_else(|| stem.clone()));
            let exit_object = entry.exit_object.clone();
            (Some(build_mode(file, text, entry, label)?), exit_object)
        }
        None => (None, None),
    };
    let verbs = parsed
        .verbs
        .into_iter()
        .map(|spanned| {
            let line = line_of(spanned.span().start);
            let column = column_of(text, spanned.span().start);
            let entry = spanned.into_inner();
            Verb {
                action: entry.action,
                pattern: entry.pattern,
                line: Some(line),
                column: Some(column),
                requires: entry.requires,
                listed: None,
            }
        })
        .collect();
    let help = parsed
        .help
        .into_iter()
        .map(|spanned| {
            let line = line_of(spanned.span().start);
            let entry = spanned.into_inner();
            Help {
                action: entry.action,
                rows: entry.rows,
                line,
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
            // The untagged `ActionEntry` cannot carry a span, so the line is looked up in the text.
            let place = |key: &str| match key_offset(text, &id, key) {
                Some(offset) => format!("{}:{}", file.display(), line_of(offset)),
                None => file.display().to_string(),
            };
            let timeout_secs = match table.timeout_secs {
                Some(secs) => Some(checked_timeout(secs, || place("timeout_secs"))?),
                None => None,
            };
            if table.enter_mode && !has_mode {
                return Err(format!(
                    "{}: action {id}: enter_mode needs a [mode] table",
                    place("enter_mode")
                ));
            }
            if table.enter_mode && table.leave_mode.is_some() {
                return Err(format!(
                    "{}: action {id}: enter_mode and leave_mode cannot share an action",
                    place("leave_mode")
                ));
            }
            let (candidates, builtin) = match (table.candidates, table.provider) {
                (Some(_), Some(_)) => {
                    return Err(format!(
                        "{}: action {id}: candidates and provider are both set; use one",
                        place("provider")
                    ));
                }
                (Some(shell), None) => (Some(Candidates::Shell(shell)), None),
                (None, Some(name)) => {
                    let provider = Provider::named(&name).ok_or_else(|| {
                        format!(
                            "{}: action {id}: unknown provider {name:?} (the known one is {})",
                            place("provider"),
                            Provider::KNOWN
                        )
                    })?;
                    let builtin = builtin_of_run(&table.run)
                        .map_err(|message| format!("{}: action {id}: {message}", place("run")))?;
                    (Some(Candidates::Builtin(provider)), builtin)
                }
                (None, None) => (None, None),
            };
            let action = Action {
                run: table.run,
                candidates,
                builtin,
                no_match: table.no_match,
                silent: table.silent.unwrap_or(parsed.silent),
                free_text: table.free_text,
                mode_switch: table.mode_switch,
                mode_entry: table.mode_entry,
                enter_mode: table.enter_mode,
                leave_mode: table.leave_mode,
                miss: table.miss,
                wait,
                timeout_secs,
            };
            Ok((id, action))
        })
        .collect::<Result<BTreeMap<_, _>, String>>()?;
    let picker = match parsed.picker.as_deref() {
        None => None,
        Some("hints") => Some(Picker::Hints),
        Some(other) => {
            let line = regex::Regex::new(r"(?m)^picker\s*=")
                .expect("fixed pattern")
                .find(text)
                .map_or(1, |found| line_of(found.start()));
            return Err(format!(
                "{}:{line}: unknown picker {other:?} (the known one is \"hints\")",
                file.display()
            ));
        }
    };
    Ok(Integration {
        name: parsed.name.unwrap_or_else(|| stem.clone()),
        stem,
        file: file.to_path_buf(),
        format: Format::Toml,
        tier: if parsed.fallback { Tier::Fallback } else { Tier::Normal },
        force_prefixes: parsed.force_prefixes,
        defines: parsed.define,
        mode_exit_object,
        mode,
        verbs,
        examples: parsed.examples,
        legacy_help: false,
        help,
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
        picker,
    })
}

/// `click_at <button>` on an action with a provider is the built-in click; any other `run` stays a shell command.
fn builtin_of_run(run: &str) -> Result<Option<Builtin>, String> {
    let mut words = run.split_whitespace();
    if words.next() != Some("click_at") {
        return Ok(None);
    }
    match (words.next(), words.next()) {
        (Some(name), None) => Button::named(name)
            .map(|button| Some(Builtin::ClickAt(Some(button))))
            .ok_or_else(|| format!("click_at: unknown button {name:?} (left, right, middle, double or triple)")),
        _ => Err("click_at takes one button (left, right, middle, double or triple)".to_string()),
    }
}

/// Where an action's `key` is written: inside the action's own `[actions.<id>]` table, or on its key's line under
/// `[actions]`. None when it is not found there (a dotted key elsewhere), and the error then names only the file.
fn key_offset(text: &str, action: &str, key: &str) -> Option<usize> {
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
    text[start..end].find(key).map(|found| start + found)
}

/// The `[mode]` table as a `Mode`, rejecting one that contradicts itself. Errors are `file:line: message`.
fn build_mode(file: &Path, text: &str, entry: ModeEntry, label: String) -> Result<Mode, String> {
    let header = regex::Regex::new(r"(?m)^\[mode\]")
        .expect("fixed pattern")
        .find(text)
        .map_or(0, |found| found.start());
    // The first `key =` inside the table: its line, or the table's own when the key is not found.
    let line_number = |key: &str| {
        let found = regex::Regex::new(&format!(r"\b{key}\s*="))
            .expect("fixed pattern")
            .find(&text[header..])
            .map_or(header, |found| header + found.start());
        text[..found].matches('\n').count() + 1
    };
    let line = |key: &str| format!("{}:{}", file.display(), line_number(key));
    if entry.one_recording && entry.handle_turn.is_none() {
        return Err(format!(
            "{}: [mode] one_recording needs a handle_turn hook to hand the recording to",
            line("one_recording")
        ));
    }
    if entry.endings.is_some() && !entry.one_recording {
        return Err(format!("{}: [mode] endings need one_recording = true", line("endings")));
    }
    let line_of = |offset: usize| text[..offset.min(text.len())].matches('\n').count() + 1;
    let endings = entry
        .endings
        .unwrap_or_default()
        .into_iter()
        .map(|spanned| {
            let line = line_of(spanned.span().start);
            let ending = spanned.into_inner();
            // Passed on as an environment variable, and compared with the reserved words, so it must be one word.
            if ending.action.is_empty() || ending.action.contains(char::is_whitespace) {
                return Err(format!(
                    "{}:{line}: [mode] endings: action {:?} must be one word (discard and end_session are voxcmd's, \
                     any other goes to handle_turn as VOXCMD_ENDING)",
                    file.display(),
                    ending.action
                ));
            }
            Ok(ModeEnding {
                action: ending.action,
                pattern: ending.pattern,
                line,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    if entry.rewrite.is_some() && entry.rewrite_hook.is_some() {
        return Err(format!(
            "{}: [mode] rewrite and rewrite_hook are both set; use one",
            line("rewrite_hook")
        ));
    }
    let timeout_secs = match entry.timeout_secs {
        Some(secs) => Some(checked_timeout(secs, || line("timeout_secs"))?),
        None => None,
    };
    let pattern_lines = ["exit_phrases", "drop", "keep"]
        .into_iter()
        .map(|key| (key, line_number(key)))
        .collect();
    Ok(Mode {
        label,
        exit_phrases: entry.exit_phrases,
        exit_hint: entry.exit_hint,
        bare_exits: entry.bare_exits.unwrap_or(true),
        default_exits: entry.default_exits.unwrap_or(true),
        allows_switches: entry.allows_switches,
        private: entry.private,
        open_ended: entry.open_ended,
        wake_listens: entry.wake_listens,
        listen: entry.listen,
        rewrite: entry.rewrite,
        rewrite_hook: entry.rewrite_hook,
        ended: entry.ended,
        alive: entry.alive,
        handle_turn: entry.handle_turn,
        one_recording: entry.one_recording,
        endings,
        timeout_secs,
        pattern_lines,
    })
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
    fn examples_load_with_their_placeholders_as_written() {
        let media = fixture("media");
        assert_eq!(media.examples.len(), 7);
        assert_eq!(media.examples[0], "play pause");
        assert_eq!(media.examples[3], "volume up by <number>");
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

    /// The fixture used to load with its `provider` and `picker` silently ignored, so it offered no candidates.
    #[test]
    fn the_click_fixture_resolves_its_provider_buttons_and_picker() {
        let click = fixture("click");
        for (action, button) in [
            ("click", Button::Left),
            ("right_click", Button::Right),
            ("double_click", Button::Double),
            ("triple_click", Button::Triple),
        ] {
            let declared = &click.actions[action];
            assert!(
                matches!(declared.candidates, Some(Candidates::Builtin(Provider::ScreenText))),
                "{action} lost its provider"
            );
            assert_eq!(declared.builtin, Some(Builtin::ClickAt(Some(button))), "{action}");
        }
        // Its other actions are shell commands.
        assert!(click.actions["no_text"].builtin.is_none() && click.actions["no_text"].candidates.is_none());
        assert_eq!(click.picker, Some(Picker::Hints));
    }

    #[test]
    fn candidates_and_provider_together_are_an_error_at_the_provider_line() {
        let text =
            "verbs = []\n[actions.go]\ncandidates = \"true\"\nprovider = \"screen_text\"\nrun = \"click_at left\"\n";
        let error = parse_toml(Path::new("p.toml"), text).unwrap_err();
        assert!(
            error.starts_with("p.toml:4: action go: candidates and provider are both set"),
            "{error}"
        );
    }

    #[test]
    fn an_unknown_provider_names_the_known_one() {
        let text = "verbs = []\n[actions.go]\nprovider = \"ocr\"\nrun = \"true\"\n";
        let error = parse_toml(Path::new("p.toml"), text).unwrap_err();
        assert!(
            error.starts_with("p.toml:3: action go: unknown provider \"ocr\""),
            "{error}"
        );
        assert!(error.contains("screen_text"), "{error}");
    }

    #[test]
    fn click_at_with_a_provider_is_the_built_in_and_anything_else_stays_a_shell_command() {
        let with = |run: &str| {
            let text = format!("verbs = []\n[actions.go]\nprovider = \"screen_text\"\nrun = '{run}'\n");
            parse_toml(Path::new("p.toml"), &text)
        };
        assert_eq!(
            with("click_at middle").unwrap().actions["go"].builtin,
            Some(Builtin::ClickAt(Some(Button::Middle)))
        );
        assert_eq!(with("echo $VOXCMD_ID").unwrap().actions["go"].builtin, None);
        assert!(
            with("click_at sideways")
                .unwrap_err()
                .starts_with("p.toml:4: action go: click_at: unknown button")
        );
        assert!(with("click_at left right").unwrap_err().contains("one button"));
        // Without a provider it is just a command: there is nothing for it to read.
        let plain = parse_toml(
            Path::new("p.toml"),
            "verbs = []\n[actions.go]\nrun = \"click_at left\"\n",
        )
        .unwrap();
        assert_eq!(plain.actions["go"].builtin, None);
    }

    #[test]
    fn an_unknown_picker_is_an_error_at_its_line() {
        let error = parse_toml(Path::new("p.toml"), "name = \"x\"\npicker = \"grid\"\nverbs = []\n").unwrap_err();
        assert!(error.starts_with("p.toml:2: unknown picker \"grid\""), "{error}");
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
        assert_eq!(key_offset(no_key, "b", "timeout_secs"), None);
    }

    fn mode_error(text: &str) -> String {
        parse_toml(Path::new("m.toml"), &format!("verbs = []\n{text}")).unwrap_err()
    }

    #[test]
    fn a_mode_table_loads_with_its_defaults_and_its_action_keys() {
        let text = "verbs = []\n[actions.go]\nenter_mode = true\n[actions.stop]\nleave_mode = \"done\"\n\
                    [actions.lost]\nrun = \"true\"\nmiss = true\n[mode]\nlabel = \"Go\"\n\
                    rewrite = { prefix = \"go \" }\nlisten = { max_secs = 295 }\n";
        let integration = parse_toml(Path::new("m.toml"), text).unwrap();
        let mode = integration.mode.unwrap();
        assert!(mode.bare_exits && mode.default_exits && !mode.allows_switches);
        assert_eq!(mode.rewrite.unwrap().prefix, "go ");
        assert_eq!(mode.listen.max_secs, Some(295.0));
        assert!(integration.actions["go"].enter_mode && integration.actions["go"].run.is_empty());
        assert_eq!(integration.actions["stop"].leave_mode.as_deref(), Some("done"));
        assert!(integration.actions["lost"].miss);
    }

    #[test]
    fn a_mistyped_listen_key_is_an_error_not_a_default() {
        let error = mode_error("[mode]\nlisten = { silence_sec = 2 }\n");
        assert!(error.contains("silence_sec"), "{error}");
        assert!(mode_error("[mode]\n[mode.listen]\nmax = 9\n").contains("max"));
    }

    #[test]
    fn a_mode_that_contradicts_itself_is_an_error_at_its_line() {
        assert!(mode_error("[mode]\nlabel = \"x\"\nfrobnicate = 1\n").starts_with("m.toml:4: "));
        let both = mode_error("[mode]\nrewrite = { prefix = \"a \" }\nrewrite_hook = \"echo\"\n");
        assert!(both.starts_with("m.toml:4: ") && both.contains("both set"), "{both}");
        for (keys, line, says) in [
            ("one_recording = true", 3, "needs a handle_turn"),
            ("handle_turn = \"x\"\nendings = []", 4, "need one_recording"),
            (
                "one_recording = true\nhandle_turn = \"x\"\nendings = [\n  { action = \"type\", match = 'stop' },\n  \
                 { action = \"\", match = 'go' },\n]",
                7,
                "must be one word",
            ),
            (
                "one_recording = true\nhandle_turn = \"x\"\nendings = [ { action = \"send it\", match = 'send' } ]",
                5,
                "must be one word",
            ),
            (
                "one_recording = true\nhandle_turn = \"x\"\nendings = [ { action = \"send\", regex = 'send' } ]",
                5,
                "regex",
            ),
        ] {
            let error = mode_error(&format!("[mode]\n{keys}\n"));
            assert!(error.starts_with(&format!("m.toml:{line}: ")), "{error}");
            assert!(error.contains(says), "{error}");
        }
        assert!(parse_toml(Path::new("m.toml"), "verbs = []\n[mode]\none_recording = false\n").is_ok());
        let bad_timeout = mode_error("[mode]\ntimeout_secs = 0\n");
        assert!(
            bad_timeout.starts_with("m.toml:3: timeout_secs must be above 0"),
            "{bad_timeout}"
        );
    }

    #[test]
    fn a_one_recording_mode_loads_its_hook_and_endings_in_order_with_their_lines() {
        let text = "verbs = []\n[mode]\none_recording = true\nhandle_turn = 'type-it'\nendings = [\n  \
                    { action = \"type\", match = 'stop' },\n  { action = \"discard\", match = 'cancel' },\n]\n";
        let mode = parse_toml(Path::new("m.toml"), text).unwrap().mode.unwrap();
        assert!(mode.one_recording);
        assert_eq!(mode.handle_turn.as_deref(), Some("type-it"));
        let endings: Vec<_> = mode
            .endings
            .iter()
            .map(|ending| (ending.action.as_str(), ending.pattern.as_str(), ending.line))
            .collect();
        assert_eq!(endings, [("type", "stop", 6), ("discard", "cancel", 7)]);
        // A handler without one_recording takes every turn's words.
        let handler = parse_toml(Path::new("m.toml"), "verbs = []\n[mode]\nhandle_turn = 'x'\n").unwrap();
        let handler = handler.mode.unwrap();
        assert!(!handler.one_recording && handler.endings.is_empty());
    }

    #[test]
    fn enter_mode_needs_a_mode_and_cannot_share_an_action_with_leave_mode() {
        let without = mode_error("[actions.go]\nenter_mode = true\n");
        assert!(
            without.starts_with("m.toml:3: ") && without.contains("needs a [mode]"),
            "{without}"
        );
        let both = mode_error("[actions.go]\nenter_mode = true\nleave_mode = \"x\"\n[mode]\n");
        assert!(
            both.starts_with("m.toml:4: ") && both.contains("cannot share"),
            "{both}"
        );
    }
}
