//! leading/trailing wake word split, correction tails ("no, I meant ...")
use super::normalize::{Replacements, apply_replacements, normalize};
use super::speech::split_words;
use regex::Regex;
use std::sync::LazyLock;

const WAKE_WORD: &str = "cortana";
const DEFAULT_ALIASES: &str = "kortana|cortona";

/// Words that open a retry when a phrase matched nothing: a speaker who corrects themselves faster than the pause
/// that ends a turn gets both attempts in one transcript. Said alone, "no" and "sorry" are not commands.
const CORRECTION_PHRASES: &str = "no wait|let me rephrase|scratch that|i mean|actually|sorry|wait|no";
const LEADING_FILLER: &str = "um|umm|uh|uhh|hmm|okay|ok|so|hey";

/// The wake word and its aliases, compiled once. The wake word is fixed because the wake listener's acoustic model
/// only knows it; the aliases are the spellings Whisper still produces.
pub struct WakeWords {
    leading: Regex,
    trailing: Regex,
    heard: Regex,
}

impl WakeWords {
    /// Aliases come from `VOXCMD_WAKE_ALIASES` ("kortana|cortona" when unset); set, even empty, it replaces them.
    pub fn from_env() -> Self {
        let aliases = std::env::var("VOXCMD_WAKE_ALIASES").unwrap_or_else(|_| DEFAULT_ALIASES.to_string());
        Self::new(&aliases)
    }

    pub fn new(aliases: &str) -> Self {
        let mut forms: Vec<String> = format!("{WAKE_WORD}|{aliases}")
            .split(['|', ','])
            .map(normalize)
            .filter(|form| !form.is_empty())
            .collect();
        // A wake word that normalizes to nothing would match every transcript.
        if forms.is_empty() {
            forms.push(WAKE_WORD.to_string());
        }
        // Longest first: the bash regex took the longest alternative, this engine takes the first that fits.
        forms.sort_by_key(|form| std::cmp::Reverse(form.len()));
        let any = forms.join("|");
        let compile = |pattern: String| Regex::new(&pattern).expect("wake forms are plain words");
        Self {
            leading: compile(format!("(?s)^(?:hey )?(?:{any})(?: (.*))?$")),
            trailing: compile(format!(r"(?is)^(.*[^\p{{L}}\p{{N}}])(?:{any})[^\p{{L}}\p{{N}}]+(.*)$")),
            heard: compile(format!("(?s) (?:{any}) (.*)$")),
        }
    }

    /// The rest of normalized text that starts with the wake word, an optional "hey" dropped too.
    pub fn split_leading(&self, normalized: &str) -> Option<String> {
        let captures = self.leading.captures(normalized)?;
        Some(captures.get(1).map_or("", |rest| rest.as_str()).to_string())
    }

    /// For a raw transcript holding the wake word after something else: what came before the last wake word as
    /// spoken (trailing blanks cut) and what follows it, normalized.
    pub fn split_trailing(&self, transcript: &str) -> Option<(String, String)> {
        let captures = self.trailing.captures(transcript)?;
        let before = captures[1].trim_end_matches(char::is_whitespace);
        (!before.is_empty()).then(|| (before.to_string(), normalize(&captures[2])))
    }

    /// The normalized words after the first wake word of a transcript, normalized and replaced as a phrase is.
    pub fn heard(&self, transcript: &str, replacements: &Replacements) -> Option<String> {
        let text = apply_replacements(&normalize(transcript), replacements);
        let padded = format!(" {text} ");
        let captures = self.heard.captures(&padded)?;
        let rest = &captures[1];
        Some(rest.strip_suffix(' ').unwrap_or(rest).to_string())
    }
}

static FILLER: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(&format!("(?s)^(?:{LEADING_FILLER}) (.+)$")).expect("fixed pattern"));
static CORRECTION: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(&format!("^({CORRECTION_PHRASES})( |$)")).expect("fixed pattern"));

/// What follows each correction point of normalized text, the last point's tail first: after a correction phrase,
/// after the leading filler, and from the second occurrence of the first word ("exit exit overview"). Never an
/// arbitrary tail: a leftover "four" can be a command of its own.
pub fn correction_tails(normalized: &str) -> Vec<String> {
    let words = split_words(normalized);
    let mut starts: Vec<usize> = Vec::new();
    let mut rest = normalized;
    let mut index = 0;
    while let Some(captures) = FILLER.captures(rest) {
        rest = captures.get(1).expect("group 1 always takes part").as_str();
        index += 1;
        starts.push(index);
    }
    for index in 0..words.len() {
        if index != 0 && words[index] == words[0] {
            starts.push(index);
        }
        let tail = words[index..].join(" ");
        if let Some(captures) = CORRECTION.captures(&tail) {
            starts.push(index + captures[1].split(' ').count());
        }
    }
    starts.sort_unstable_by(|a, b| b.cmp(a));
    starts.dedup();
    starts
        .into_iter()
        .filter(|&start| start > 0 && start < words.len())
        .map(|start| words[start..].join(" "))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn leading_wake_word_is_split_off() {
        let wake = WakeWords::new(DEFAULT_ALIASES);
        assert_eq!(
            wake.split_leading("cortana open firefox").as_deref(),
            Some("open firefox")
        );
        assert_eq!(
            wake.split_leading("hey kortana open firefox").as_deref(),
            Some("open firefox")
        );
        assert_eq!(wake.split_leading("cortana").as_deref(), Some(""));
        assert_eq!(wake.split_leading("open cortana"), None);
        assert_eq!(wake.split_leading("cortanas"), None);
    }

    #[test]
    fn trailing_wake_word_needs_something_before_it() {
        let wake = WakeWords::new(DEFAULT_ALIASES);
        assert_eq!(
            wake.split_trailing("Open Firefox, Cortana, close it"),
            Some(("Open Firefox,".to_string(), "close it".to_string()))
        );
        assert_eq!(wake.split_trailing("Cortana, close it"), None);
    }

    #[test]
    fn corrections_are_listed_last_first() {
        assert_eq!(correction_tails("exit exit overview"), vec!["exit overview"]);
        assert_eq!(correction_tails("open firefox no wait open kitty"), vec!["open kitty"]);
        assert_eq!(correction_tails("um open firefox"), vec!["open firefox"]);
        assert!(correction_tails("no").is_empty());
    }
}
