//! `voxcmd reply <phrase>`: a spoken answer to the open picker, confirm card or hints overlay, matched to one of its
//! choices and written to its FIFO as if picked there (was the bash `reply`); `--dry-run` and `explain --reply` print
//! the match instead
//!
//! A pick reply matches like a candidate target: a cancel word, "expand" and an ordinal, an ordinal or a direction,
//! then the label exactly, by the words it shares with the reply, as a substring, and fuzzily; only a single hit
//! counts. A confirm reply is yes, no or unclear. An unclear reply leaves the question open and, once, listens again.
//! A picker the bar published is answered over its IPC instead of a FIFO.
use super::{
    Owner, PendingPick, PickChoice, listen_start_only, qs_ipc_call, read_pending, still_pending, write_answer,
};
use crate::cli::ReplyArgs;
use crate::debug::debug;
use crate::exit::CliError;
use crate::notify::{self, Kind};
use crate::paths;
use crate::route::resolve::fzf_filter;
use crate::text::normalize::{Replacements, apply_replacements, normalize};
use crate::text::speech::spoken_position;
use regex::Regex;
use serde::Serialize;
use std::sync::LazyLock;

/// What a reply would do.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Verdict {
    Cancel,
    /// The displayed label of the choice it names.
    Pick(String),
    /// The 1-based position of the choice whose list to open, as Tab does.
    Expand(usize),
    Yes,
    No,
    /// Why it names no single choice.
    Unclear(String),
}

impl Verdict {
    /// As the dry run prints it: "pick: 2. Next - bottom", "unclear: 2 choices match".
    pub fn text(&self) -> String {
        match self {
            Self::Cancel => "cancel".to_string(),
            Self::Pick(label) => format!("pick: {label}"),
            Self::Expand(position) => format!("expand: {position}"),
            Self::Yes => "yes".to_string(),
            Self::No => "no".to_string(),
            Self::Unclear(why) => format!("unclear: {why}"),
        }
    }

    fn name(&self) -> &'static str {
        match self {
            Self::Cancel => "cancel",
            Self::Pick(_) => "pick",
            Self::Expand(_) => "expand",
            Self::Yes => "yes",
            Self::No => "no",
            Self::Unclear(_) => "unclear",
        }
    }
}

/// `explain --reply --json`'s `reply`: the question the reply answers and what it would do.
#[derive(Debug, Serialize)]
pub struct ReplyTrace {
    pub transcript: String,
    /// Normalized, with replacements applied: the text matched.
    pub normalized: String,
    /// `pick`, `hints` or `confirm`.
    pub kind: String,
    /// The question, and for an expansion the title of the list on screen: "Which one? > Windows".
    pub question: String,
    /// The expansion on screen, none for the top level.
    pub shown_list: Option<String>,
    /// The labels of the list on screen.
    pub choices: Vec<String>,
    /// `pick`, `expand`, `cancel`, `yes`, `no` or `unclear`.
    pub verdict: String,
    pub picked: Option<String>,
    /// Why an unclear reply names no single choice.
    pub unclear: Option<String>,
}

/// A reply read against the open question.
struct Reading {
    transcript: String,
    normalized: String,
    state: PendingPick,
    /// The expansion on screen, "" for the top level.
    shown_key: String,
    shown_title: String,
    shown: Vec<PickChoice>,
    verdict: Verdict,
}

impl Reading {
    fn is_confirm(&self) -> bool {
        self.state.kind.as_deref() == Some("confirm")
    }

    /// The bash dry run's four lines.
    fn dry_run_text(&self) -> String {
        let question = if self.is_confirm() {
            format!("confirm:     {}", self.state.label)
        } else {
            format!("picker:      {}", self.question())
        };
        format!(
            "transcript:  {}\nnormalized:  {}\n{question}\nresult:      {}",
            self.transcript,
            self.normalized,
            self.verdict.text()
        )
    }

    fn question(&self) -> String {
        if self.shown_key.is_empty() {
            self.state.label.clone()
        } else {
            format!("{} > {}", self.state.label, self.shown_title)
        }
    }

    fn trace(&self) -> ReplyTrace {
        ReplyTrace {
            transcript: self.transcript.clone(),
            normalized: self.normalized.clone(),
            kind: self.state.kind.clone().unwrap_or_else(|| "pick".to_string()),
            question: self.question(),
            shown_list: (!self.shown_key.is_empty()).then(|| self.shown_key.clone()),
            choices: self.shown.iter().map(|choice| choice.label.clone()).collect(),
            verdict: self.verdict.name().to_string(),
            picked: match &self.verdict {
                Verdict::Pick(label) => Some(label.clone()),
                _ => None,
            },
            unclear: match &self.verdict {
                Verdict::Unclear(why) => Some(why.clone()),
                _ => None,
            },
        }
    }
}

/// The reply matched against the open question; none when nothing waits for one. A confirm reply's verdict is logged,
/// dry run or not.
fn read(transcript: &str) -> Option<Reading> {
    let replacements = Replacements::load(&paths::config_dir().join("replacements.d"));
    let normalized = apply_replacements(&normalize(transcript), &replacements);
    let state = read_pending()?;
    if state.kind.as_deref() == Some("confirm") {
        let verdict = match_confirm_reply(&normalized, state.verb.as_deref().unwrap_or_default());
        debug(&format!(
            "confirm reply \"{transcript}\" ({normalized}): {}",
            verdict.name()
        ));
        return Some(Reading {
            transcript: transcript.to_string(),
            normalized,
            shown_key: String::new(),
            shown_title: String::new(),
            shown: state.choices.clone(),
            state,
            verdict,
        });
    }
    // The list on screen: the top level, or the expansion Tab opened, whose picks go back prefixed with its key.
    let viewed = match state.owner {
        Owner::Bar => state.view_key.clone().unwrap_or_default(),
        Owner::Ask => state
            .view
            .as_ref()
            .and_then(|view| std::fs::read_to_string(view).ok())
            .map(|key| key.trim_end_matches('\n').to_string())
            .unwrap_or_default(),
    };
    let (shown_key, shown_title, shown) = match state.expansions.get(&viewed) {
        Some(expansion) if !viewed.is_empty() => (viewed, expansion.title.clone(), expansion.choices.clone()),
        _ => (String::new(), String::new(), state.choices.clone()),
    };
    let verdict = match_reply(&normalized, &shown);
    Some(Reading {
        transcript: transcript.to_string(),
        normalized,
        state,
        shown_key,
        shown_title,
        shown,
        verdict,
    })
}

const NO_PICKER: &str = "No picker is waiting for a reply";

/// `voxcmd reply [--dry-run] <phrase>`. Exit 1 when nothing waits for a reply, the reply was unclear, or the answer
/// could not be handed over.
pub fn run(args: ReplyArgs) -> Result<Option<String>, CliError> {
    let transcript = args.phrase.join(" ");
    let Some(reading) = read(&transcript) else {
        if args.dry_run {
            eprintln!("voxcmd: {NO_PICKER}");
        } else {
            notify::notify(Kind::Info, "voxcmd", NO_PICKER);
        }
        return Err(CliError::quiet("reply"));
    };
    if args.dry_run {
        return Ok(Some(reading.dry_run_text()));
    }
    if let Verdict::Unclear(why) = &reading.verdict {
        ask_again(&reading, why);
        return Err(CliError::quiet("reply"));
    }
    let fifo = reading.state.fifo.clone().unwrap_or_default();
    if reading.is_confirm() {
        // The asker reads anything but "yes" as a no.
        let answer = if reading.verdict == Verdict::Yes { "yes" } else { "no" };
        if write_answer(&fifo, answer) {
            debug(&format!("confirm reply written: {answer}"));
        } else {
            debug("confirm reply not written: nobody read the FIFO");
        }
        return Ok(None);
    }
    let answer = match &reading.verdict {
        Verdict::Pick(label) if reading.shown_key.is_empty() => label.clone(),
        Verdict::Pick(label) => format!("{}\t{label}", reading.shown_key),
        _ => String::new(),
    };
    let token = reading.state.token.as_deref().unwrap_or_default();
    // An ask's picker is the bar's too when the bar shows it, so "expand" goes to the bar for both. Without a token,
    // the bar expands whatever choices picker is open.
    let bar_call = match (&reading.verdict, reading.state.owner) {
        (Verdict::Expand(position), owner) => {
            let token = if owner == Owner::Bar { token } else { "" };
            Some(vec!["expand".to_string(), position.to_string(), token.to_string()])
        }
        (Verdict::Cancel, Owner::Bar) => Some(vec!["cancel".to_string(), token.to_string()]),
        (_, Owner::Bar) => Some(vec!["answer".to_string(), token.to_string(), answer.clone()]),
        (_, Owner::Ask) => None,
    };
    let handed_over = match bar_call {
        Some(call) => answer_through_bar(&call, reading.state.owner),
        None => write_answer(&fifo, &answer),
    };
    if handed_over {
        Ok(None)
    } else {
        Err(CliError::quiet("reply"))
    }
}

/// `qs-ipc call picker <call>`. The bar says `stale` when the token is no longer its open picker's (it closed or
/// reopened since the file was read) and `locked` while the screen is locked. Either one, or a bar that is gone,
/// means the picker the reply was meant for is not waiting.
fn answer_through_bar(call: &[String], owner: Owner) -> bool {
    let mut args = vec![std::ffi::OsStr::new("picker")];
    args.extend(call.iter().map(std::ffi::OsStr::new));
    let said = qs_ipc_call(&args);
    if said == "ok" {
        return true;
    }
    debug(&format!(
        "reply: the bar answered {said:?} to picker {}",
        call.join(" ")
    ));
    if owner == Owner::Bar {
        notify::notify(Kind::Info, "voxcmd", NO_PICKER);
    }
    false
}

/// Leaves the question open. Only an ask that listens for its reply leaves a `listen_again` file, and only one removal
/// of it succeeds, so one unclear reply gets the extra listen.
fn ask_again(reading: &Reading, why: &str) {
    let transcript = &reading.transcript;
    let listens_again = reading
        .state
        .listen_again
        .as_deref()
        .is_some_and(|file| !file.is_empty() && std::fs::remove_file(file).is_ok());
    let (summary, body) = match (reading.is_confirm(), listens_again) {
        (true, true) => ("voxcmd: yes or no?", format!("\"{transcript}\": listening again")),
        (true, false) => (
            "voxcmd: yes or no?",
            format!("\"{transcript}\": say yes or no, or press y or n."),
        ),
        (false, true) => (
            "voxcmd: which one?",
            format!("\"{transcript}\": {why}. Listening again."),
        ),
        (false, false) => (
            "voxcmd: which one?",
            format!("\"{transcript}\": {why}. Say a choice, a number, or cancel."),
        ),
    };
    notify::notify(Kind::Info, summary, &body);
    if listens_again && still_pending(&reading.state) {
        listen_start_only(None);
    }
}

/// `voxcmd explain --reply [--json] <phrase>`: the dry run's lines, or the trace as JSON. Exit 1 when nothing waits for
/// a reply, as the dry run.
pub fn explain(phrase: &str, json: bool) -> Result<String, CliError> {
    let Some(reading) = read(phrase) else {
        eprintln!("voxcmd: {NO_PICKER}");
        return Err(CliError::quiet("explain"));
    };
    if !json {
        return Ok(reading.dry_run_text());
    }
    let explain = crate::route::trace::Explain {
        phrase: phrase.to_string(),
        sequence: None,
        steps: Vec::new(),
        click: None,
        reply: Some(reading.trace()),
    };
    serde_json::to_string_pretty(&explain).map_err(|error| CliError::failed("explain", error.to_string()))
}

// ---- matching a pick reply ------------------------------------------------------------------------------------------

fn regex(pattern: &str) -> Regex {
    Regex::new(pattern).expect("a valid pattern")
}

static EXPAND: LazyLock<Regex> = LazyLock::new(|| regex("^expand (.+)$"));
static CANCEL: LazyLock<Regex> =
    LazyLock::new(|| regex("^(cancel|never ?mind|none( of (them|these|those))?|nothing|forget it)$"));
/// Replies that take or turn down the only choice without naming it: a picker with one choice (a weak match's) only
/// asks whether that is the one meant.
static SINGLE_CHOICE_YES: LazyLock<Regex> = LazyLock::new(|| {
    regex("^(yes|yeah|yep|yup|sure|okay|ok|do it|go ahead|(that|this)( one)?|thats it|thats the one)( please)?$")
});
static SINGLE_CHOICE_NO: LazyLock<Regex> = LazyLock::new(|| regex("^(no|nope|nah|dont|do not)( thanks| thank you)?$"));
static ORDINAL_LEAD: LazyLock<Regex> =
    LazyLock::new(|| regex("^(pick|choose|select|take|use|go with|the|number|option|choice|item|entry) (.+)$"));
static ENDS_IN_ONE: LazyLock<Regex> = LazyLock::new(|| regex("^(.+) one$"));
static DIRECTION: LazyLock<Regex> = LazyLock::new(|| {
    regex("^((pick|choose|select|take|use|go with|the) )*(top|upper|bottom|lower|left|right)(most)?( one)?$")
});

/// What a normalized reply does to the choices shown.
pub fn match_reply(text: &str, choices: &[PickChoice]) -> Verdict {
    let count = choices.len();
    if CANCEL.is_match(text) || (count == 1 && SINGLE_CHOICE_NO.is_match(text)) {
        return Verdict::Cancel;
    }
    if let Some(named) = EXPAND.captures(text) {
        return match ordinal_position(&named[1], count).and_then(|position| usize::try_from(position).ok()) {
            Some(position) if (1..=count).contains(&position) && choices[position - 1].expand.is_some() => {
                Verdict::Expand(position)
            }
            Some(position) if (1..=count).contains(&position) => {
                Verdict::Unclear(format!("choice {position} has no list to expand"))
            }
            Some(_) => Verdict::Unclear(format!("there are only {count} choices")),
            None => Verdict::Unclear("say expand and a number".to_string()),
        };
    }
    if let Some(position) = ordinal_position(text, count).or_else(|| direction_position(text, choices)) {
        return match usize::try_from(position)
            .ok()
            .filter(|&position| (1..=count).contains(&position))
        {
            Some(position) => Verdict::Pick(choices[position - 1].label.clone()),
            None => Verdict::Unclear(format!("there are only {count} choices")),
        };
    }
    // Each label without its number, normalized like the reply. A Lua list's labels carry no number, and one may hold
    // ". " itself ("St. Louis").
    let spoken: Vec<String> = choices
        .iter()
        .map(|choice| {
            let label = choice
                .label
                .split_once(". ")
                .filter(|(number, _)| !number.is_empty() && number.bytes().all(|byte| byte.is_ascii_digit()))
                .map_or(choice.label.as_str(), |(_, rest)| rest);
            normalize(label)
        })
        .collect();
    let mut hits: Vec<usize> = (0..count).filter(|&index| spoken[index] == text).collect();
    if hits.is_empty() && count == 1 && SINGLE_CHOICE_YES.is_match(text) {
        hits = vec![0];
    }
    // Shared words that tie are left for the substring and fuzzy passes to settle.
    let mut word_hits = Vec::new();
    if hits.is_empty() {
        word_hits = labels_sharing_most_words(text, &spoken);
        if word_hits.len() == 1 {
            hits.clone_from(&word_hits);
        }
    }
    let lines: String = spoken
        .iter()
        .enumerate()
        .map(|(index, label)| format!("{index}\t{label}\n"))
        .collect();
    for mode in ["--exact", "--no-exact"] {
        if !hits.is_empty() {
            break;
        }
        hits = fzf_filter(text, mode, &lines)
            .lines()
            .filter_map(|line| line.split('\t').next()?.parse().ok())
            .collect();
    }
    if hits.is_empty() {
        hits = word_hits;
    }
    match hits.as_slice() {
        [] => Verdict::Unclear("no choice matches".to_string()),
        [only] => Verdict::Pick(choices[*only].label.clone()),
        many => Verdict::Unclear(format!("{} choices match", many.len())),
    }
}

/// The 1-based position an ordinal reply names ("two", "the second one", "number 3", "twenty first", "last").
fn ordinal_position(text: &str, count: usize) -> Option<i64> {
    let mut text = text;
    while let Some(lead) = ORDINAL_LEAD.captures(text) {
        text = lead.get(2).expect("group 2 always takes part").as_str();
    }
    let last = || i64::try_from(count).ok();
    // "twenty one" ends in the word "one" without being "twenty" and "one".
    if let Some(position) = spoken_position(text) {
        return Some(position);
    }
    if let Some(before_one) = ENDS_IN_ONE.captures(text) {
        let before_one = &before_one[1];
        return if before_one == "last" {
            last()
        } else {
            spoken_position(before_one)
        };
    }
    (text == "last").then(last).flatten()
}

/// The 1-based position of the choice a direction reply names ("the top one", "leftmost"), by the choices' boxes
/// (`[left, top, width, height]`); none when the text names no direction or a choice has no box. The extreme is of the
/// box's edge, so items in a column or row line up however wide or tall they are; edges within half the smallest box
/// height of the extreme tie, and a vertical tie goes to the leftmost, a horizontal one to the topmost.
fn direction_position(text: &str, choices: &[PickChoice]) -> Option<i64> {
    let direction = DIRECTION.captures(text)?;
    let direction = match &direction[3] {
        "upper" => "top",
        "lower" => "bottom",
        other => other,
    };
    struct Edges {
        position: i64,
        left: f64,
        top: f64,
        right: f64,
        bottom: f64,
        height: f64,
    }
    let mut boxes = Vec::new();
    for (index, choice) in choices.iter().enumerate() {
        let edges = match &choice.r#box {
            Some(serde_json::Value::Array(edges)) if edges.len() == 4 => edges,
            _ => return None,
        };
        let [left, top, width, height] = [0, 1, 2, 3].map(|i| edges[i].as_f64());
        let (left, top, width, height) = (left?, top?, width?, height?);
        boxes.push(Edges {
            position: i64::try_from(index).ok()? + 1,
            left,
            top,
            right: left + width,
            bottom: top + height,
            height,
        });
    }
    let tolerance = boxes.iter().map(|edges| edges.height).reduce(f64::min)? / 2.0;
    let signed_edge = |edges: &Edges| match direction {
        "top" => -edges.top,
        "left" => -edges.left,
        "bottom" => edges.bottom,
        _ => edges.right,
    };
    let extreme = boxes.iter().map(signed_edge).reduce(f64::max)?;
    let mut nearest: Vec<&Edges> = boxes
        .iter()
        .filter(|edges| signed_edge(edges) >= extreme - tolerance)
        .collect();
    let vertical = matches!(direction, "top" | "bottom");
    nearest.sort_by(|a, b| {
        let key = |edges: &Edges| {
            if vertical {
                [edges.left, edges.top]
            } else {
                [edges.top, edges.left]
            }
        };
        key(a).partial_cmp(&key(b)).unwrap_or(std::cmp::Ordering::Equal)
    });
    nearest.first().map(|edges| edges.position)
}

/// Words a reply says around the label it names, which never count as shared.
const FILLER: [&str; 23] = [
    "the", "a", "an", "my", "this", "that", "it", "one", "please", "to", "of", "on", "in", "for", "pick", "choose",
    "select", "take", "use", "go", "with", "do", "run",
];

/// A crude English stem, so "locked" names "Lock" and "closing" names "Close".
fn stem(word: &str) -> &str {
    let length = word.chars().count();
    let stemmed = if length > 5 && word.ends_with("ing") {
        &word[..word.len() - 3]
    } else if length > 4 && (word.ends_with("ed") || word.ends_with("es")) {
        &word[..word.len() - 2]
    } else if length > 3 && word.ends_with('s') && !word.ends_with("ss") {
        &word[..word.len() - 1]
    } else {
        word
    };
    if stemmed.chars().count() > 3 && stemmed.ends_with('e') {
        &stemmed[..stemmed.len() - 1]
    } else {
        stemmed
    }
}

fn stems(text: &str) -> std::collections::BTreeSet<&str> {
    text.split(' ')
        .filter(|word| !word.is_empty() && !FILLER.contains(word))
        .map(stem)
        .collect()
}

/// The labels (normalized, without their numbers) sharing the most word stems with the reply; none when none shares
/// one. The reply's other words do not count against a label: a reply to "Lock (System)" may say "lock computer" or
/// "lock it", and needs no "system".
fn labels_sharing_most_words(text: &str, spoken: &[String]) -> Vec<usize> {
    let said = stems(text);
    let shared: Vec<usize> = spoken
        .iter()
        .map(|label| stems(label).intersection(&said).count())
        .collect();
    let most = shared.iter().copied().max().unwrap_or(0);
    if most == 0 {
        return Vec::new();
    }
    (0..spoken.len()).filter(|&index| shared[index] == most).collect()
}

// ---- matching a confirm reply ---------------------------------------------------------------------------------------

/// A no word anywhere wins, so a mixed "yeah never mind" is the safe answer. Normalizing drops the apostrophe, so
/// "don't" arrives as "dont".
static CONFIRM_NO: LazyLock<Regex> =
    LazyLock::new(|| regex("(^| )(no|nope|nah|dont|do not|cancel|never ?mind|stop|forget it|leave it)( |$)"));
static CONFIRM_YES: LazyLock<Regex> =
    LazyLock::new(|| regex("^(yes|yeah|yep|yup|sure|okay|ok|confirm|do it|go ahead)( |$)"));

/// Yes, no or unclear for a normalized reply to a yes/no question. A reply leading with a yes word or with the
/// question's verb ("close it", "close slack") is a yes.
pub fn match_confirm_reply(text: &str, verb: &str) -> Verdict {
    let leads_with_verb = !verb.is_empty() && (text == verb || text.starts_with(&format!("{verb} ")));
    if CONFIRM_NO.is_match(text) {
        Verdict::No
    } else if CONFIRM_YES.is_match(text) || leads_with_verb {
        Verdict::Yes
    } else {
        Verdict::Unclear("not a yes or no".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn choices(labels: &[&str]) -> Vec<PickChoice> {
        labels
            .iter()
            .enumerate()
            .map(|(index, label)| PickChoice {
                id: index.to_string(),
                label: format!("{}. {label}", index + 1),
                expand: None,
                r#box: None,
            })
            .collect()
    }

    fn boxed(boxes: &[[i64; 4]]) -> Vec<PickChoice> {
        boxes
            .iter()
            .enumerate()
            .map(|(index, edges)| PickChoice {
                id: index.to_string(),
                label: format!("{}. Next", index + 1),
                expand: None,
                r#box: Some(json!(edges)),
            })
            .collect()
    }

    fn verdict(text: &str, shown: &[PickChoice]) -> String {
        match_reply(text, shown).text()
    }

    #[test]
    fn ordinals_numbers_and_last_pick_by_position() {
        let three = choices(&["Next - top", "Next - bottom", "Settings - middle"]);
        for (text, expected) in [
            ("two", "pick: 2. Next - bottom"),
            ("the second one", "pick: 2. Next - bottom"),
            ("3", "pick: 3. Settings - middle"),
            ("number 8", "unclear: there are only 3 choices"),
            ("the 3rd one", "pick: 3. Settings - middle"),
            ("the twelfth one", "unclear: there are only 3 choices"),
            ("twenty first", "unclear: there are only 3 choices"),
            ("twenty one", "unclear: there are only 3 choices"),
            ("the last one", "pick: 3. Settings - middle"),
            ("last", "pick: 3. Settings - middle"),
            ("pick the first", "pick: 1. Next - top"),
            ("go with option two", "pick: 2. Next - bottom"),
        ] {
            assert_eq!(verdict(text, &three), expected, "{text}");
        }
        // "2th" is no position, so it is left to the label passes.
        assert!(!verdict("2th", &three).starts_with("pick: 2."));
        assert!(!verdict("2th", &three).contains("there are only"));
    }

    #[test]
    fn cancel_words_and_the_single_choice_yes_and_no() {
        let three = choices(&["A", "B", "C"]);
        for text in [
            "cancel",
            "never mind",
            "nevermind",
            "none of them",
            "nothing",
            "forget it",
        ] {
            assert_eq!(match_reply(text, &three), Verdict::Cancel, "{text}");
        }
        let one = choices(&["Lock (System)"]);
        assert_eq!(match_reply("no thanks", &one), Verdict::Cancel);
        assert_eq!(verdict("thats the one please", &one), "pick: 1. Lock (System)");
        assert_ne!(match_reply("no", &three), Verdict::Cancel);
    }

    #[test]
    fn expand_and_a_position_opens_that_choices_list() {
        let mut shown = choices(&["Work", "Home", "Games"]);
        shown[1].expand = Some("home".to_string());
        for (text, expected) in [
            ("expand two", "expand: 2"),
            ("expand the second one", "expand: 2"),
            ("expand 2", "expand: 2"),
            ("expand one", "unclear: choice 1 has no list to expand"),
            ("expand five", "unclear: there are only 3 choices"),
            ("expand home", "unclear: say expand and a number"),
        ] {
            assert_eq!(verdict(text, &shown), expected, "{text}");
        }
    }

    #[test]
    fn a_lua_lists_labels_carry_no_number_to_strip() {
        let lua = [
            PickChoice {
                id: "St. Louis".to_string(),
                label: "St. Louis".to_string(),
                expand: None,
                r#box: None,
            },
            PickChoice {
                id: "Louisville".to_string(),
                label: "Louisville".to_string(),
                expand: None,
                r#box: None,
            },
        ];
        assert_eq!(verdict("saint louis", &lua), "pick: St. Louis");
        assert_eq!(verdict("st louis", &lua), "pick: St. Louis");
        assert_eq!(verdict("two", &lua), "pick: Louisville");
    }

    #[test]
    fn labels_match_exactly_then_by_shared_stems() {
        let shown = choices(&["Lock (System)", "Close Window", "Closed Tabs"]);
        assert_eq!(verdict("lock system", &shown), "pick: 1. Lock (System)");
        assert_eq!(verdict("locked computer", &shown), "pick: 1. Lock (System)");
        assert_eq!(verdict("closing window", &shown), "pick: 2. Close Window");
        assert_eq!(verdict("zzz", &shown), "unclear: no choice matches");
    }

    #[test]
    fn the_stemmer_is_the_bash_one() {
        for (word, expected) in [
            ("closing", "clos"),
            ("locked", "lock"),
            ("boxes", "box"),
            ("glass", "glass"),
            ("tabs", "tab"),
            ("close", "clos"),
            ("use", "use"),
            ("sing", "sing"),
            ("bus", "bus"),
        ] {
            assert_eq!(stem(word), expected, "{word}");
        }
    }

    #[test]
    fn directions_pick_by_box_edge_with_ties() {
        // Two on the top row (the right one a few pixels lower), one lower left, one far lower right.
        let four = boxed(&[
            [100, 50, 60, 20],
            [300, 53, 70, 20],
            [100, 300, 80, 20],
            [500, 400, 80, 20],
        ]);
        for (text, expected) in [
            ("the top one", "pick: 1. Next"),
            ("top", "pick: 1. Next"),
            ("the bottom one", "pick: 4. Next"),
            ("the left one", "pick: 1. Next"),
            ("the right one", "pick: 4. Next"),
            ("rightmost", "pick: 4. Next"),
            ("lower", "pick: 4. Next"),
            ("pick the upper one", "pick: 1. Next"),
        ] {
            assert_eq!(verdict(text, &four), expected, "{text}");
        }
        let unboxed = choices(&["Next - top right", "Next - bottom right"]);
        assert!(verdict("the right one", &unboxed).starts_with("unclear"));
    }

    #[test]
    fn confirm_replies() {
        for (text, verb, expected) in [
            ("yes", "", Verdict::Yes),
            ("yeah never mind", "", Verdict::No),
            ("dont", "", Verdict::No),
            ("close it", "close", Verdict::Yes),
            ("close", "close", Verdict::Yes),
            ("closet", "close", Verdict::Unclear("not a yes or no".to_string())),
            ("stop", "close", Verdict::No),
            ("banana", "", Verdict::Unclear("not a yes or no".to_string())),
            ("ok then", "", Verdict::Yes),
        ] {
            assert_eq!(match_confirm_reply(text, verb), expected, "{text}");
        }
    }
}
