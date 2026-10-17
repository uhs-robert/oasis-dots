//! near-miss scoring for a phrase no verb matched (was near-miss.awk): the verbs whose words are all in the phrase, in
//! any order
//!
//! A pattern is read from its regex AST into slots, each a list of alternatives, each alternative a list of words that
//! must all be present:
//! - a literal word is a slot of one alternative; a `number` placeholder is a slot that a digit word fills
//! - a group with alternatives, "(move|send|bring up)", is one slot; a group followed by "?" is dropped
//! - a slot whose alternatives are all filler words ("the", "to"), or that has an empty alternative, is dropped
//! - in an alternative with a non-filler word, filler words are dropped too ("go to" needs "go")
//! - a nested group inside an alternative is dropped when optional or filler-only; any other kind makes the verb
//!   unreadable, as do character classes, anchors, "." and repetitions other than an optional group, escapes, flags,
//!   a group glued to a word ("(un)mute"), and the target anywhere but top level
//!
//! The words left over must be none (no target) or one run of non-filler speech that becomes the target. A verb with
//! no slot left, or unreadable, is skipped: guessing would let any phrase through. Top-level alternatives ("a b|c d")
//! are separate readings of the verb. The target is the first `text` placeholder; any other typed placeholder makes the
//! verb unreadable (A6), since near-miss.awk only knew `{target}` and `{number}`.
use super::pattern::{Placeholder, PlaceholderType};
use regex_syntax::ast::{self, Ast};

const FILLER: [&str; 11] = [
    "the", "a", "an", "this", "that", "my", "please", "to", "of", "on", "over",
];

/// A long phrase is dictation, not a command with its words in the wrong order.
const MAX_PHRASE_WORDS: usize = 16;

fn is_filler(word: &str) -> bool {
    FILLER.contains(&word)
}

/// A number slot's word is this prefix and the placeholder's name, so that a placement says which placeholder a digit
/// word filled.
const NUMBER_SLOT_PREFIX: &str = "#number:";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NearMiss {
    pub target: String,
    pub has_target: bool,
    /// The text placeholder the target fills, which differs between a verb's top-level alternatives.
    pub target_placeholder: Option<String>,
    /// Words of the phrase no slot took, the target's included.
    pub leftover: usize,
    /// The digit word each number placeholder took, by placeholder name; one that sat in an alternative the best
    /// placement did not use is absent.
    pub numbers: Vec<(String, String)>,
}

/// One slot: its alternatives, each the words it needs.
type Slot = Vec<Vec<String>>;

/// The verb cannot be read (near-miss.awk's `fail()`).
struct Unreadable;

struct Reader<'p> {
    placeholders: &'p [Placeholder],
    target_placeholder: Option<String>,
}

/// A verb as near-miss reads it: one reading per top-level alternative, each its slots and whether it has a target.
/// None when the verb is unreadable. Independent of the phrase, so it is read once per verb.
pub struct Readings(Option<Vec<(Vec<Slot>, Option<String>)>>);

impl Readings {
    pub fn unreadable() -> Self {
        Self(None)
    }

    /// Reads `source`, a pattern body whose placeholders are the named groups in `placeholders`.
    pub fn new(source: &str, placeholders: &[Placeholder]) -> Self {
        let Ok(parsed) = ast::parse::Parser::new().parse(source) else {
            return Self(None);
        };
        let branches: &[Ast] = match &parsed {
            Ast::Alternation(alternation) => &alternation.asts,
            other => std::slice::from_ref(other),
        };
        let mut readings = Vec::new();
        for branch in branches {
            let mut reader = Reader {
                placeholders,
                target_placeholder: None,
            };
            // One unreadable reading drops the whole verb, readings that filled before it included.
            let Ok(slots) = reader.sequence(items(branch), 0) else {
                return Self(None);
            };
            let slots: Vec<Slot> = slots.into_iter().filter(|slot| !is_filler_word_slot(slot)).collect();
            readings.push((slots, reader.target_placeholder));
        }
        Self(Some(readings))
    }

    /// The best reading for the normalized phrase, or none when the verb is no near miss for it.
    pub fn best(&self, phrase: &str) -> Option<NearMiss> {
        let phrase: Vec<&str> = phrase.split_whitespace().collect();
        if phrase.len() > MAX_PHRASE_WORDS {
            return None;
        }
        let mut best: Option<NearMiss> = None;
        for (slots, target_placeholder) in self.0.as_ref()? {
            if let Some(found) = Search::best(slots, &phrase, target_placeholder.as_deref())
                && best.as_ref().is_none_or(|kept| found.leftover < kept.leftover)
            {
                best = Some(found);
            }
        }
        best
    }
}

fn items(ast: &Ast) -> &[Ast] {
    match ast {
        Ast::Concat(concat) => &concat.asts,
        Ast::Empty(_) => &[],
        other => std::slice::from_ref(other),
    }
}

fn is_filler_word_slot(slot: &Slot) -> bool {
    slot.len() == 1 && slot[0].len() == 1 && is_filler(&slot[0][0])
}

/// The first character the group's content reads, the way near-miss.awk looked one character past a "(".
fn first_char(ast: &Ast) -> Option<char> {
    match ast {
        Ast::Literal(literal) => Some(literal.c),
        Ast::Concat(concat) => concat.asts.first().and_then(first_char),
        Ast::Alternation(alternation) => alternation.asts.first().and_then(first_char),
        Ast::Repetition(repetition) => first_char(&repetition.ast),
        Ast::Group(_) => Some('('),
        _ => None,
    }
}

fn is_space(ast: &Ast) -> bool {
    matches!(ast, Ast::Literal(literal) if literal.c == ' ' && literal.kind == ast::LiteralKind::Verbatim)
}

/// A group, bare or optional, that starts with a space: "(a|b)( c)?" reads as two slots, "(a|b)(c)" does not.
fn is_group_starting_with_space(ast: &Ast) -> bool {
    let group = match ast {
        Ast::Group(group) => group,
        Ast::Repetition(repetition) => match &*repetition.ast {
            Ast::Group(group) => group,
            _ => return false,
        },
        _ => return false,
    };
    first_char(&group.ast) == Some(' ')
}

fn is_optional(repetition: &ast::Repetition) -> bool {
    repetition.greedy && matches!(repetition.op.kind, ast::RepetitionKind::ZeroOrOne)
}

impl Reader<'_> {
    fn placeholder(&self, group: &ast::Group) -> Option<PlaceholderType> {
        let ast::GroupKind::CaptureName { name, .. } = &group.kind else {
            return None;
        };
        let placeholder = self
            .placeholders
            .iter()
            .find(|placeholder| placeholder.name == name.name)?;
        Some(placeholder.kind)
    }

    fn placeholder_name(&self, group: &ast::Group) -> String {
        match &group.kind {
            ast::GroupKind::CaptureName { name, .. } => name.name.clone(),
            _ => String::new(),
        }
    }

    /// The slots of a sequence, up to the end of its group or alternative.
    fn sequence(&mut self, items: &[Ast], depth: usize) -> Result<Vec<Slot>, Unreadable> {
        let mut slots: Vec<Slot> = Vec::new();
        let mut word = String::new();
        let push_word = |slots: &mut Vec<Slot>, word: &mut String| {
            if !word.is_empty() {
                slots.push(vec![vec![std::mem::take(word)]]);
            }
        };
        for (index, item) in items.iter().enumerate() {
            let next = items.get(index + 1);
            match item {
                Ast::Literal(literal) if literal.kind == ast::LiteralKind::Verbatim => match literal.c {
                    ' ' => push_word(&mut slots, &mut word),
                    c if c.is_ascii_lowercase() || c.is_ascii_digit() || c == '\'' => word.push(c),
                    _ => return Err(Unreadable),
                },
                Ast::Group(group) if self.placeholder(group).is_some() => {
                    if !word.is_empty() || !next.is_none_or(is_space) {
                        return Err(Unreadable);
                    }
                    match self.placeholder(group) {
                        Some(PlaceholderType::Text) if depth == 0 && self.target_placeholder.is_none() => {
                            self.target_placeholder = Some(self.placeholder_name(group));
                        }
                        Some(PlaceholderType::Number) => {
                            slots.push(vec![vec![format!(
                                "{NUMBER_SLOT_PREFIX}{}",
                                self.placeholder_name(group)
                            )]]);
                        }
                        _ => return Err(Unreadable),
                    }
                }
                Ast::Group(group) if matches!(&group.kind, ast::GroupKind::NonCapturing(flags) if !flags.items.is_empty()) =>
                {
                    return Err(Unreadable);
                }
                Ast::Group(group) => {
                    let glued = !word.is_empty();
                    let (slot, unreadable) = self.group(&group.ast, depth + 1)?;
                    let separated = next.is_none_or(|next| is_space(next) || is_group_starting_with_space(next));
                    if unreadable || glued || !separated {
                        return Err(Unreadable);
                    }
                    slots.extend(slot);
                }
                // Dropped, though a word around it carries on: "(un)?mute" reads "mute", "mute(s)? x" reads "mute x".
                Ast::Repetition(repetition) if is_optional(repetition) => match &*repetition.ast {
                    Ast::Group(group) if self.placeholder(group).is_none() => {
                        self.group(&group.ast, depth + 1)?;
                    }
                    _ => return Err(Unreadable),
                },
                Ast::Empty(_) => {}
                _ => return Err(Unreadable),
            }
        }
        push_word(&mut slots, &mut word);
        Ok(slots)
    }

    /// A group's alternatives as its slot, or none when it does not constrain the phrase (an empty alternative, or
    /// only filler words). The flag says an alternative held a nested group with alternatives of its own, which cannot
    /// be kept apart from the rest: harmless when the group is optional, the verb's end when required.
    fn group(&mut self, content: &Ast, depth: usize) -> Result<(Option<Slot>, bool), Unreadable> {
        let branches: &[Ast] = match content {
            Ast::Alternation(alternation) => &alternation.asts,
            other => std::slice::from_ref(other),
        };
        let (mut alternatives, mut unreadable, mut optional, mut all_filler) = (Vec::new(), false, false, true);
        for branch in branches {
            let slots = self.sequence(items(branch), depth)?;
            let words: Vec<String> = if slots.iter().any(|slot| slot.len() > 1) {
                unreadable = true;
                Vec::new()
            } else {
                slots.into_iter().flat_map(|mut slot| slot.remove(0)).collect()
            };
            if words.is_empty() {
                optional = true;
                continue;
            }
            let kept: Vec<String> = words.iter().filter(|word| !is_filler(word)).cloned().collect();
            if kept.is_empty() {
                alternatives.push(words);
            } else {
                all_filler = false;
                alternatives.push(kept);
            }
        }
        let slot = (!optional && !all_filler).then_some(alternatives);
        Ok((slot, unreadable))
    }
}

/// The backtracking placement of near-miss.awk: every way the slots can take phrase words, keeping the one with the
/// fewest words left over (the first found among equals).
struct Search<'s> {
    slots: &'s [Slot],
    phrase: &'s [&'s str],
    has_target: bool,
    target_placeholder: Option<&'s str>,
    used: Vec<bool>,
    /// Number placeholders and the phrase word each holds in the placement being tried.
    numbers: Vec<(String, usize)>,
    best: Option<NearMiss>,
}

impl<'s> Search<'s> {
    fn best(slots: &'s [Slot], phrase: &'s [&'s str], target_placeholder: Option<&'s str>) -> Option<NearMiss> {
        if slots.is_empty() {
            return None;
        }
        let mut search = Search {
            slots,
            phrase,
            has_target: target_placeholder.is_some(),
            target_placeholder,
            used: vec![false; phrase.len()],
            numbers: Vec::new(),
            best: None,
        };
        search.solve(0);
        search.best
    }

    fn solve(&mut self, slot: usize) {
        if slot == self.slots.len() {
            self.finish();
            return;
        }
        for alternative in &self.slots[slot] {
            self.place(slot, alternative, 0);
        }
    }

    fn place(&mut self, slot: usize, alternative: &[String], word: usize) {
        if word == alternative.len() {
            self.solve(slot + 1);
            return;
        }
        for position in 0..self.phrase.len() {
            if self.used[position] {
                continue;
            }
            let spoken = self.phrase[position];
            let number = alternative[word].strip_prefix(NUMBER_SLOT_PREFIX);
            let fits = if number.is_some() {
                !spoken.is_empty() && spoken.bytes().all(|b| b.is_ascii_digit())
            } else {
                spoken == alternative[word]
            };
            if fits {
                self.used[position] = true;
                if let Some(name) = number {
                    self.numbers.push((name.to_string(), position));
                }
                self.place(slot, alternative, word + 1);
                if number.is_some() {
                    self.numbers.pop();
                }
                self.used[position] = false;
            }
        }
    }

    /// Every slot is filled: with a target the words left must hold non-filler speech in one run, which becomes the
    /// target; without one, nothing but filler may remain, so stray speech stays a miss.
    fn finish(&mut self) {
        let unused: Vec<usize> = (0..self.phrase.len()).filter(|&p| !self.used[p]).collect();
        let speech: Vec<usize> = unused.iter().copied().filter(|&p| !is_filler(self.phrase[p])).collect();
        if self.has_target == speech.is_empty() {
            return;
        }
        let (first, last) = (
            speech.first().copied().unwrap_or(0),
            speech.last().copied().unwrap_or(0),
        );
        // A slot's word between two target words ("double click it") splits it in two.
        if self.has_target && (first..=last).any(|p| self.used[p]) {
            return;
        }
        if self.best.as_ref().is_some_and(|best| unused.len() >= best.leftover) {
            return;
        }
        let target = if self.has_target {
            self.phrase[first..=last].join(" ")
        } else {
            String::new()
        };
        self.best = Some(NearMiss {
            target,
            has_target: self.has_target,
            target_placeholder: self.target_placeholder.map(str::to_string),
            leftover: unused.len(),
            numbers: self
                .numbers
                .iter()
                .map(|(name, position)| (name.clone(), self.phrase[*position].to_string()))
                .collect(),
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn near_miss(source: &str, placeholders: &[Placeholder], phrase: &str) -> Option<NearMiss> {
        Readings::new(source, placeholders).best(phrase)
    }

    fn target() -> Vec<Placeholder> {
        vec![Placeholder {
            name: "t".into(),
            kind: PlaceholderType::Text,
        }]
    }

    #[test]
    fn the_target_names_the_placeholder_of_the_alternative_read() {
        let two = vec![
            Placeholder {
                name: "foo".into(),
                kind: PlaceholderType::Text,
            },
            Placeholder {
                name: "bar".into(),
                kind: PlaceholderType::Text,
            },
        ];
        let source = "(?P<foo>x) open|close (?P<bar>x)";
        let found = near_miss(source, &two, "thing close").unwrap();
        assert_eq!(found.target_placeholder.as_deref(), Some("bar"));
        let found = near_miss(source, &two, "thing open").unwrap();
        assert_eq!(found.target_placeholder.as_deref(), Some("foo"));
    }

    #[test]
    fn words_in_another_order_are_a_near_miss() {
        let found = near_miss("(open|launch) (?P<t>x)", &target(), "firefox open").unwrap();
        assert_eq!(
            found,
            NearMiss {
                target: "firefox".into(),
                has_target: true,
                target_placeholder: Some("t".into()),
                leftover: 1,
                numbers: Vec::new(),
            }
        );
    }

    #[test]
    fn stray_speech_without_a_target_is_no_near_miss() {
        assert!(near_miss("volume up", &[], "up volume").is_some());
        assert!(near_miss("volume up", &[], "up the volume").is_some());
        assert!(near_miss("volume up", &[], "up volume now").is_none());
    }

    #[test]
    fn unreadable_constructs_skip_the_verb() {
        for source in [
            "right ?click (?P<t>x)",
            "(un)mute",
            "[0-9]+ px",
            "(a|b)(c)",
            "( (?P<t>x))?",
            "a|b.c",
        ] {
            assert!(
                near_miss(source, &target(), "a b c mute right click px").is_none(),
                "{source}"
            );
        }
    }

    #[test]
    fn a_target_split_by_a_slot_word_is_no_reading() {
        assert!(near_miss("double click (?P<t>x)", &target(), "double it click now").is_none());
        assert!(near_miss("double click (?P<t>x)", &target(), "it now click double").is_some());
    }
}
