//! a verb match into the options a user could be offered: the hook's candidates, the target matched against them, and
//! the flags that decide whether an option runs, asks first or goes through the picker (was `resolve_match`,
//! `runnable_options`, `fuzzy_match` and `word_match`)
//!
//! A match whose verb has a target and whose integration lists candidates gets one option per candidate the target
//! names. What the hook printed matters beyond the list: nothing at all means "no hook", the target text is the id;
//! `[]` means "nothing matches", so the integration's `no_match` action may take the phrase (hooks.rs `Lookup`).
use super::matcher::Arg;
use crate::config::Config;
use crate::config::schema::{Integration, TargetMatch};
use crate::exit::CliError;
use crate::hooks::{Candidate, HookQuery, HookRun, Hooks, Lookup};
use regex::RegexBuilder;
use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};

/// A verb that matched (or nearly matched) a phrase, before its target is resolved.
#[derive(Debug, Clone)]
pub struct PendingMatch {
    pub integration: usize,
    /// The action the verb names; `no_match_actions` may change the option's own.
    pub verb_action: String,
    /// The text the candidates are matched against, empty when the verb has none.
    pub target: String,
    pub has_target: bool,
    pub args: Vec<Arg>,
    /// Words of the phrase no slot took, for a near miss.
    pub near_miss: Option<usize>,
}

impl PendingMatch {
    /// A legacy verb has one capture and it is the target; a TOML verb's target is its `target` argument, else its
    /// first free-text one.
    pub fn from_args(integration: usize, config: &Config, verb_action: &str, args: Vec<Arg>) -> Self {
        let legacy = config.integrations[integration].format == crate::config::schema::Format::Bash;
        let target_arg = if legacy {
            args.first()
        } else {
            args.iter().find(|arg| arg.name == "target").or_else(|| {
                args.iter()
                    .find(|arg| arg.kind == super::pattern::PlaceholderType::Text)
            })
        };
        let target = target_arg.and_then(|arg| arg.value.clone()).unwrap_or_default();
        let has_target = target_arg.is_some();
        Self {
            integration,
            verb_action: verb_action.to_string(),
            target,
            has_target,
            args,
            near_miss: None,
        }
    }
}

/// One thing the phrase could do: an integration's action on one candidate (or on the target text).
#[derive(Debug, Clone)]
pub struct RouteOption {
    pub integration: usize,
    pub name: String,
    pub file: PathBuf,
    pub fallback: bool,
    /// What runs; the verb's action unless `no_match_actions` took it.
    pub action: String,
    pub verb_action: String,
    pub target: String,
    pub args: Vec<Arg>,
    pub id: String,
    pub label: String,
    pub command: String,
    pub weak: bool,
    pub silent: bool,
    /// Why it asks before running: `confirm = true`, or the `confirm_labels` entry its label matches.
    pub confirm: Option<String>,
    /// How many candidates the hook offered, before the target narrowed them.
    pub candidates: usize,
    pub near_miss: bool,
    pub leftover: usize,
}

/// What resolving one match found.
pub struct Resolved {
    pub options: Vec<RouteOption>,
    pub hook: Option<HookRun>,
}

pub fn resolve(config: &Config, hooks: &dyn Hooks, pending: &PendingMatch, texts: Texts) -> Resolved {
    let integration = &config.integrations[pending.integration];
    let settings = &integration.settings;
    let mut action = pending.verb_action.clone();
    // A bash `candidates` function is only asked about a verb that captured something; a TOML hook is asked always.
    let asks_hook = integration.candidates_for(&action).is_some() && (pending.has_target || !is_legacy(integration));
    let hook = asks_hook.then(|| {
        let query = HookQuery {
            action: &action,
            target: &pending.target,
            args: &pending.args,
            phrase: texts.phrase,
            raw_transcript: texts.raw_transcript,
        };
        hooks.candidates(integration, &query)
    });
    let lookup = hook.as_ref().map_or(&Lookup::Unhooked, |run| &run.lookup);
    let target_only = || vec![Candidate::plain(&pending.target, &pending.target)];
    let (candidate_count, entries) = match lookup {
        Lookup::Unhooked => (0, Some(target_only())),
        Lookup::Yield | Lookup::Broken => (0, Some(Vec::new())),
        Lookup::Candidates(list) => {
            let mut picked = if pending.target.is_empty() {
                Some(list.clone())
            } else if settings.target_match == TargetMatch::Words {
                word_match(&pending.target, list, &settings.match_ignore_words)
            } else {
                Some(fuzzy_match(&pending.target, list))
            };
            // A target that names no candidate is reported by the action `no_match_actions` maps this one to; a target
            // of filler words only (`None`) names nothing to report missing.
            if !pending.target.is_empty()
                && picked.as_ref().is_some_and(Vec::is_empty)
                && let Some(report) = integration
                    .actions
                    .get(&action)
                    .and_then(|declared| declared.no_match.clone())
            {
                action = report;
                picked = Some(vec![Candidate::plain("", &pending.target)]);
            }
            (list.len(), picked)
        }
    };
    let options = entries
        .unwrap_or_default()
        .into_iter()
        .map(|entry| runnable(integration, pending, &action, candidate_count, entry))
        .collect();
    Resolved { options, hook }
}

/// Whether the label matches a `confirm_labels` regex, in any case.
fn label_matches(pattern: &str, label: &str) -> bool {
    RegexBuilder::new(pattern)
        .case_insensitive(true)
        .build()
        .is_ok_and(|regex| regex.is_match(label))
}

fn is_legacy(integration: &Integration) -> bool {
    integration.format == crate::config::schema::Format::Bash
}

pub(crate) fn runnable(
    integration: &Integration,
    pending: &PendingMatch,
    action: &str,
    candidate_count: usize,
    entry: Candidate,
) -> RouteOption {
    let declared = integration.actions.get(action);
    let settings = &integration.settings;
    let confirm = if settings.confirm {
        Some("confirm = true".to_string())
    } else {
        settings
            .confirm_labels
            .iter()
            .position(|pattern| label_matches(pattern, &entry.label))
            .map(|index| format!("confirm_labels[{index}]"))
    };
    RouteOption {
        integration: pending.integration,
        name: integration.name.clone(),
        file: integration.file.clone(),
        fallback: integration.tier == crate::config::schema::Tier::Fallback,
        action: action.to_string(),
        verb_action: pending.verb_action.clone(),
        target: pending.target.clone(),
        args: pending.args.clone(),
        id: entry.id,
        label: entry.label,
        command: declared.map(|declared| declared.run.clone()).unwrap_or_default(),
        weak: entry.weak,
        silent: declared.is_some_and(|declared| declared.silent),
        confirm,
        candidates: candidate_count,
        near_miss: pending.near_miss.is_some(),
        leftover: pending.near_miss.unwrap_or(0),
    }
}

/// The two spellings of the step a match came from, which hooks read.
#[derive(Clone, Copy)]
pub struct Texts<'a> {
    /// Normalized, with replacements applied.
    pub phrase: &'a str,
    /// As spoken.
    pub raw_transcript: &'a str,
}

/// Resolves matches side by side, hooks being queries of live state that need not wait on each other, and returns
/// them in the order given.
pub fn resolve_all(config: &Config, hooks: &dyn Hooks, pending: &[PendingMatch], texts: Texts) -> Vec<Resolved> {
    let hooked = pending
        .iter()
        .filter(|one| {
            config.integrations[one.integration]
                .candidates_for(&one.verb_action)
                .is_some()
        })
        .count();
    if hooked < 2 {
        return pending.iter().map(|one| resolve(config, hooks, one, texts)).collect();
    }
    std::thread::scope(|scope| {
        let running: Vec<_> = pending
            .iter()
            .map(|one| scope.spawn(move || resolve(config, hooks, one, texts)))
            .collect();
        running
            .into_iter()
            .map(|handle| handle.join().expect("a resolve thread panicked"))
            .collect()
    })
}

// ---- matching a target against candidates ---------------------------------------------------------------------------

/// Candidates whose label (or match text) is the target, else those containing it, else those fuzzy-matching it: fuzzy
/// matching alone lets a short target hit long labels by scattered letters, so substring matches win when there are
/// any. fzf does the matching (voxcmd-port 2.2 A3); its ordering decides the order of a picker.
pub fn fuzzy_match(target: &str, candidates: &[Candidate]) -> Vec<Candidate> {
    let text_of = |candidate: &Candidate| candidate.match_text.clone().unwrap_or_else(|| candidate.label.clone());
    let exact: Vec<Candidate> = candidates
        .iter()
        .filter(|candidate| text_of(candidate).to_ascii_lowercase() == target)
        .cloned()
        .collect();
    if !exact.is_empty() || candidates.is_empty() {
        return exact;
    }
    let lines: String = candidates
        .iter()
        .enumerate()
        .map(|(index, candidate)| format!("{index}\t{}\n", text_of(candidate)))
        .collect();
    for mode in ["--exact", "--no-exact"] {
        let found: Vec<Candidate> = fzf_filter(target, mode, &lines)
            .lines()
            .filter_map(|line| line.split('\t').next()?.parse::<usize>().ok())
            .filter_map(|index| candidates.get(index).cloned())
            .collect();
        if !found.is_empty() {
            return found;
        }
    }
    Vec::new()
}

pub(crate) fn fzf_filter(target: &str, mode: &str, input: &str) -> String {
    let child = Command::new("fzf")
        .arg(format!("--filter={target}"))
        .arg(mode)
        .arg("--delimiter=\t")
        .arg("--nth=2..")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn();
    let Ok(mut child) = child else {
        return String::new();
    };
    let mut stdin = child.stdin.take().expect("piped");
    let mut stdout = child.stdout.take().expect("piped");
    // Written beside the read: fzf answers as it reads, and a full pipe both ways would stall.
    let output = std::thread::scope(|scope| {
        scope.spawn(move || {
            let _ = stdin.write_all(input.as_bytes());
        });
        let mut output = Vec::new();
        let _ = stdout.read_to_end(&mut output);
        output
    });
    let _ = child.wait();
    String::from_utf8_lossy(&output).into_owned()
}

const NUMBER_WORDS: [(&str, &str); 10] = [
    ("one", "1"),
    ("two", "2"),
    ("three", "3"),
    ("four", "4"),
    ("five", "5"),
    ("six", "6"),
    ("seven", "7"),
    ("eight", "8"),
    ("nine", "9"),
    ("ten", "10"),
];

const FILLER: [&str; 13] = [
    "the", "a", "an", "my", "this", "that", "please", "to", "of", "on", "in", "for", "it",
];

fn singular(word: &str) -> String {
    if word.len() > 3 && word.ends_with('s') && !word.ends_with("ss") {
        word[..word.len() - 1].to_string()
    } else {
        word.to_string()
    }
}

/// The words of a text: lower-case ASCII letters and digits, number words as digits, singular, and none of `ignored`.
fn words(text: &str, ignored: &[String]) -> Vec<String> {
    text.to_ascii_lowercase()
        .replace('\'', "")
        .split(|c: char| !(c.is_ascii_lowercase() || c.is_ascii_digit()))
        .filter(|word| !word.is_empty())
        .map(|word| {
            let digit = NUMBER_WORDS.iter().find(|(spoken, _)| *spoken == word);
            singular(digit.map_or(word, |(_, digit)| digit))
        })
        .filter(|word| !ignored.contains(word))
        .collect()
}

/// A spoken word names a candidate word when it is that word, or a long enough piece of a compound ("screen").
fn names(spoken: &str, candidate_word: &str) -> bool {
    spoken == candidate_word || (spoken.len() >= 4 && candidate_word.contains(spoken))
}

fn sorted_unique(words: &[String]) -> Vec<&String> {
    let mut unique: Vec<&String> = words.iter().collect();
    unique.sort();
    unique.dedup();
    unique
}

/// Word matching for integrations with `target_match = "words"`, strict enough that stray speech matches nothing. Both
/// sides drop filler and the integration's `match_ignore_words`, turn number words into digits and singularize. A
/// target with the same words as a candidate (in any order, or the same letters run together, "full screen" for
/// "fullscreen") is a strong match. Otherwise a target is a weak match when it covers at least half of a candidate's
/// words with nothing left over, or holds all of them plus one more word; weak matches always go through the picker,
/// and only the ten closest are kept.
///
/// `None` when the target has no words left after the filler and ignored words: it names nothing, which is not the
/// same as naming something that is missing.
pub fn word_match(target: &str, candidates: &[Candidate], ignore: &[String]) -> Option<Vec<Candidate>> {
    let mut kept: Vec<Judged> = judge(target, candidates, ignore)?
        .into_iter()
        .filter(|judged| judged.kept)
        .collect();
    // A strong match leaves only strong ones, in the order given; otherwise the closest weak ones come first.
    if !kept.iter().any(|judged| !judged.weak) {
        kept.sort_by_key(|judged| (judged.misses, judged.candidate.label.chars().count()));
    }
    Some(kept.into_iter().map(|judged| judged.candidate).collect())
}

/// Why `word_match` kept or dropped a candidate, worded as the bash jq did (`explain --window` prints it).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Verdict {
    Strong,
    CoversHalf { named: usize },
    HoldsAllPlusOne,
    NoSpokenWord,
    UnderHalf { named_matched: usize, named: usize },
    DroppedStrongExists,
    DroppedPastCap,
}

impl std::fmt::Display for Verdict {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Strong => formatter.write_str("strong: same words"),
            Self::CoversHalf { named } => {
                write!(
                    formatter,
                    "weak: the spoken words cover at least half of its {named} word(s)"
                )
            }
            Self::HoldsAllPlusOne => formatter.write_str("weak: holds every spoken word plus one more"),
            Self::NoSpokenWord => formatter.write_str("near miss only: no spoken word is in it"),
            Self::UnderHalf { named_matched, named } => {
                write!(
                    formatter,
                    "coverage under half: {named_matched} of {named} of its words are spoken"
                )
            }
            Self::DroppedStrongExists => formatter.write_str("dropped: a strong match exists"),
            Self::DroppedPastCap => formatter.write_str("dropped: past the ten best weak matches"),
        }
    }
}

/// A candidate with what word matching made of it.
#[derive(Debug, Clone)]
pub struct Judged {
    pub candidate: Candidate,
    /// Whether the real pick keeps it, after the strong-match rule and the cap of ten.
    pub kept: bool,
    pub weak: bool,
    pub verdict: Verdict,
    /// Spoken and named words the other side lacks; the weak ones are ranked by it.
    pub misses: usize,
}

/// Every candidate with a word to match, judged in order. `word_match` keeps what is `kept`, so a trace built from this
/// cannot call a match kept that the router drops. `None` as for `word_match`.
pub fn judge(target: &str, candidates: &[Candidate], ignore: &[String]) -> Option<Vec<Judged>> {
    let ignored: Vec<String> = FILLER
        .iter()
        .map(|word| (*word).to_string())
        .chain(ignore.iter().cloned())
        .map(|word| singular(&word.to_ascii_lowercase()))
        .collect();
    let spoken = words(target, &ignored);
    if spoken.is_empty() {
        return None;
    }
    let mut judged: Vec<Judged> = Vec::new();
    for candidate in candidates {
        let named = words(candidate.match_text.as_deref().unwrap_or(&candidate.label), &ignored);
        if named.is_empty() {
            continue;
        }
        let spoken_matched = spoken
            .iter()
            .filter(|word| named.iter().any(|candidate_word| names(word, candidate_word)))
            .count();
        let named_matched = named
            .iter()
            .filter(|candidate_word| spoken.iter().any(|word| names(word, candidate_word)))
            .count();
        let strong = sorted_unique(&spoken) == sorted_unique(&named) || spoken.concat() == named.concat();
        let covers_half = spoken_matched == spoken.len() && named_matched * 2 >= named.len();
        let holds_all_plus_one = named.iter().all(|word| spoken.contains(word)) && spoken.len() - spoken_matched <= 1;
        let verdict = if strong {
            Verdict::Strong
        } else if covers_half {
            Verdict::CoversHalf { named: named.len() }
        } else if holds_all_plus_one {
            Verdict::HoldsAllPlusOne
        } else if spoken_matched == 0 {
            Verdict::NoSpokenWord
        } else {
            Verdict::UnderHalf {
                named_matched,
                named: named.len(),
            }
        };
        let mut candidate = candidate.clone();
        candidate.weak = !strong;
        judged.push(Judged {
            candidate,
            kept: strong || covers_half || holds_all_plus_one,
            weak: !strong,
            verdict,
            misses: named.len() - named_matched + spoken.len() - spoken_matched,
        });
    }
    let has_strong = judged.iter().any(|one| one.kept && !one.weak);
    // The ten closest weak matches stay; the stable sort keeps the order of ties as the candidates came.
    let mut by_closeness: Vec<usize> = (0..judged.len()).filter(|&index| judged[index].kept).collect();
    by_closeness.sort_by_key(|&index| (judged[index].misses, judged[index].candidate.label.chars().count()));
    let past_cap: Vec<usize> = by_closeness.into_iter().skip(WEAK_KEPT).collect();
    for (index, one) in judged.iter_mut().enumerate() {
        if one.kept && one.weak && has_strong {
            one.kept = false;
            one.verdict = Verdict::DroppedStrongExists;
        } else if !has_strong && past_cap.contains(&index) {
            one.kept = false;
            one.verdict = Verdict::DroppedPastCap;
        }
    }
    Some(judged)
}

/// How many weak matches go to the picker.
const WEAK_KEPT: usize = 10;

/// `voxcmd util word-match [--ignore <words>] <target>`: the `id<TAB>label<TAB>match_text` lines on stdin that the
/// target names, in `word_match`'s order. Exit 1 when none does.
pub fn run_word_match(ignore: Option<&str>, target: &str) -> Result<String, CliError> {
    let mut input = String::new();
    let _ = std::io::stdin().read_to_string(&mut input);
    let candidates: Vec<Candidate> = input
        .lines()
        .filter(|line| !line.is_empty())
        .map(|line| {
            let mut fields = line.splitn(3, '\t');
            let id = fields.next().unwrap_or_default();
            let label = fields.next().unwrap_or(id);
            Candidate {
                id: id.to_string(),
                label: label.to_string(),
                match_text: fields.next().filter(|text| !text.is_empty()).map(str::to_string),
                weak: false,
            }
        })
        .collect();
    let ignore: Vec<String> = ignore
        .unwrap_or_default()
        .split_whitespace()
        .map(str::to_string)
        .collect();
    let found = word_match(target, &candidates, &ignore).unwrap_or_default();
    if found.is_empty() {
        return Err(CliError::failed("util word-match", "no candidate matches"));
    }
    Ok(found
        .iter()
        .map(|candidate| {
            format!(
                "{}\t{}\t{}",
                candidate.id,
                candidate.label,
                candidate.match_text.as_deref().unwrap_or_default()
            )
        })
        .collect::<Vec<_>>()
        .join("\n"))
}

/// The arguments of a match as environment variables a TOML hook would get.
pub fn arg_env(args: &[Arg]) -> BTreeMap<String, String> {
    let mut env = BTreeMap::new();
    for arg in args {
        let name = arg.name.to_ascii_uppercase();
        if let Some(value) = &arg.value {
            env.insert(format!("VOXCMD_ARG_{name}"), value.clone());
        }
        if let Some(words) = &arg.words {
            env.insert(format!("VOXCMD_ARG_{name}_WORDS"), words.clone());
        }
    }
    env
}

#[cfg(test)]
mod tests {
    use super::*;

    fn candidate(id: &str, label: &str) -> Candidate {
        Candidate::plain(id, label)
    }

    fn ids(found: &[Candidate]) -> Vec<&str> {
        found.iter().map(|c| c.id.as_str()).collect()
    }

    fn verdicts(target: &str, candidates: &[Candidate]) -> Vec<(bool, String)> {
        judge(target, candidates, &[])
            .unwrap()
            .iter()
            .map(|one| (one.kept, one.verdict.to_string()))
            .collect()
    }

    #[test]
    fn twelve_equal_weak_matches_keep_ten_and_drop_two_past_the_cap() {
        // The bash trace check (run.sh) of the same case, which sourced the bash jq.
        let candidates: Vec<Candidate> = (0..12)
            .map(|index| candidate(&format!("i{index}"), "Open Settings"))
            .collect();
        let judged = judge("settings", &candidates, &[]).unwrap();
        assert_eq!(judged.iter().filter(|one| one.kept).count(), 10);
        let dropped: Vec<&str> = judged
            .iter()
            .filter(|one| !one.kept)
            .map(|one| one.candidate.id.as_str())
            .collect();
        assert_eq!(dropped, ["i10", "i11"]);
        assert!(judged[10..].iter().all(|one| one.verdict == Verdict::DroppedPastCap));
        assert_eq!(word_match("settings", &candidates, &[]).unwrap().len(), 10);
    }

    #[test]
    fn the_verdicts_read_as_the_bash_jq_worded_them() {
        let candidates = [
            candidate("1", "Sign In"),
            candidate("2", "Sign In Now"),
            candidate("3", "Sign Out"),
            candidate("4", "Banana Apple Cherry Date"),
            candidate("5", "!!!"),
        ];
        // A strong match exists, so the weak "Sign In Now" is dropped for it; "!!!" has no word and no verdict.
        assert_eq!(
            verdicts("sign in", &candidates),
            [
                (true, "strong: same words".to_string()),
                (false, "dropped: a strong match exists".to_string()),
                (false, "dropped: a strong match exists".to_string()),
                (false, "near miss only: no spoken word is in it".to_string()),
            ]
        );
        let weak = [candidate("1", "Sign In Now Please Today")];
        assert_eq!(
            verdicts("sign", &weak),
            [(false, "coverage under half: 1 of 3 of its words are spoken".to_string())]
        );
        let half = [candidate("1", "Open Settings")];
        assert_eq!(
            verdicts("settings", &half),
            [(
                true,
                "weak: the spoken words cover at least half of its 2 word(s)".to_string()
            )]
        );
        let plus_one = [candidate("1", "Settings")];
        assert_eq!(
            verdicts("settings page", &plus_one),
            [(true, "weak: holds every spoken word plus one more".to_string())]
        );
    }

    #[test]
    fn a_target_of_only_filler_judges_nothing() {
        assert!(judge("the", &[candidate("1", "Sign In")], &[]).is_none());
    }

    #[test]
    fn a_strong_word_match_hides_the_weak_ones() {
        let candidates = [candidate("1", "Full Screen"), candidate("2", "Full Screen Toggle")];
        let found = word_match("fullscreen", &candidates, &[]).unwrap();
        assert_eq!(ids(&found), ["1"]);
        assert!(!found[0].weak);
    }

    #[test]
    fn weak_word_matches_are_kept_closest_first() {
        let candidates = [
            candidate("1", "Slack Window Notes Inbox"),
            candidate("2", "Slack Window Inbox"),
            candidate("3", "Window Slack Inbox Notes Extra"),
            candidate("4", "Other"),
        ];
        let found = word_match("slack window", &candidates, &[]).unwrap();
        assert_eq!(ids(&found), ["2", "1"]);
        assert!(found.iter().all(|c| c.weak));
    }

    #[test]
    fn filler_only_targets_name_nothing_and_ignored_words_drop_out() {
        let candidates = [candidate("1", "Terminal")];
        assert_eq!(word_match("the", &candidates, &[]), None);
        assert_eq!(
            word_match("terminals window", &candidates, &["window".to_string()]).map(|f| f.len()),
            Some(1)
        );
        assert_eq!(word_match("zebra", &candidates, &[]).map(|f| f.len()), Some(0));
    }

    #[test]
    fn number_words_match_digits() {
        let candidates = [candidate("1", "Workspace 2")];
        let found = word_match("workspace two", &candidates, &[]).unwrap();
        assert_eq!(ids(&found), ["1"]);
        assert!(!found[0].weak);
    }

    #[test]
    fn keybinds_delete_pattern_spares_the_submap_entries() {
        let dump =
            std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/legacy-dump.jsonl")).unwrap();
        let integrations = crate::config::legacy::parse_dump(&dump).unwrap();
        let keybinds = integrations.iter().find(|i| i.stem == "keybinds").unwrap();
        let asks = |label: &str| keybinds.settings.confirm_labels.iter().any(|p| label_matches(p, label));
        assert!(asks("Delete Window") && asks("hit hit delete twice") && asks("Submap:delete") && asks("delete"));
        assert!(!asks("Submap: Delete") && !asks("SUBMAP: delete files"));
        assert!(asks("Close Window") && !asks("Disclose"));
    }

    #[test]
    fn an_exact_label_beats_fuzzy_matching() {
        let candidates = [candidate("1", "Terminal Settings"), candidate("2", "terminal")];
        assert_eq!(ids(&fuzzy_match("terminal", &candidates)), ["2"]);
    }

    #[test]
    fn fuzzy_matching_asks_fzf_when_no_label_is_the_target() {
        if Command::new("fzf").arg("--version").output().is_err() {
            return;
        }
        let candidates = [candidate("1", "Toggle Fullscreen"), candidate("2", "Close Window")];
        assert_eq!(ids(&fuzzy_match("fullscreen", &candidates)), ["1"]);
        assert!(fuzzy_match("zzzz", &candidates).is_empty());
    }
}
