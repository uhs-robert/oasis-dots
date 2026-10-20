//! verb pattern → anchored regex with typed named captures; define/intents/mode_exit expansion; the required literals
//! the matcher's prefilter reads
//!
//! Two dialects, by the integration's format:
//! - **Bash** (legacy): a POSIX ERE as `compile_pattern` built it: `{intent}` becomes a group of its forms, then only
//!   the first of `{target}` (`.+`, greedy) or `{number}` (`[0-9]+`) becomes a capture. Rust's leftmost-first
//!   captures equal bash's on the match goldens (tests/fixtures/gen-match-goldens.sh).
//! - **TOML** (1.1 section 2): a Rust regex whose `{name}`s resolve to a placeholder (`{target}`, `{number}`,
//!   `{name:type}`; words captured lazily), a `define`, `{mode_object}`/`{mode_exit}`, or an intent, in that order.
//!
//! Both compile with `.` matching newlines and Unicode off: phrases are normalized to `[a-z0-9 ]` (a newline can
//! survive), and the ASCII engine builds faster.
use crate::config::intents::Intents;
use crate::config::schema::{Format, Integration, Verb};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlaceholderType {
    Text,
    Number,
    Position,
    Ordinal,
    Duration,
    Time,
    Day,
}

impl PlaceholderType {
    fn from_name(name: &str) -> Result<Self, String> {
        Ok(match name {
            "text" => Self::Text,
            "number" => Self::Number,
            "position" => Self::Position,
            "ordinal" => Self::Ordinal,
            "duration" => Self::Duration,
            "time" => Self::Time,
            "day" => Self::Day,
            "monitor" => return Err("the monitor placeholder type comes with the 3.3 providers".to_string()),
            other => return Err(format!("unknown placeholder type {other:?}")),
        })
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Text => "text",
            Self::Number => "number",
            Self::Position => "position",
            Self::Ordinal => "ordinal",
            Self::Duration => "duration",
            Self::Time => "time",
            Self::Day => "day",
        }
    }

    /// What the capture group matches. Bash captures words greedily ("how far ahead is tokyo please" gives "tokyo
    /// please"), and the legacy dialect must equal it. TOML captures them lazily (1.1), so optional words after a slot,
    /// as in `open {target}( in firefox)?`, stay out of the target; a title that really ends in one gets cut.
    fn capture_body(self, format: Format) -> &'static str {
        match (self, format) {
            (Self::Number, _) => "[0-9]+",
            (_, Format::Toml) => ".+?",
            _ => ".+",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Placeholder {
    /// The capture group's name in `regex`, and the argument's name (`VOXCMD_ARG_<NAME>`).
    pub name: String,
    pub kind: PlaceholderType,
}

#[derive(Debug, Clone)]
pub struct CompiledPattern {
    /// Anchored, with flags: what the matcher compiles.
    pub regex: String,
    /// The expanded pattern with no anchors or flags. Its placeholders are named groups too, which near-miss reads.
    pub body: String,
    pub placeholders: Vec<Placeholder>,
}

const FLAGS: &str = "(?s-u)";

/// A TOML pattern's expanded body as the anchored regex source the matcher compiles.
fn anchored(body: &str) -> String {
    format!("{FLAGS}^(?:{body})$")
}

/// A pattern that must match a whole text, compiled exactly as a TOML verb is (`regex::bytes`, `FLAGS`), so a mode's
/// patterns and its verbs accept and match the same things.
#[derive(Debug, Clone)]
pub struct WholeText(regex::bytes::Regex);

impl WholeText {
    pub fn new(body: &str) -> Result<Self, regex::Error> {
        regex::bytes::Regex::new(&anchored(body)).map(Self)
    }

    pub fn is_match(&self, text: &str) -> bool {
        self.0.is_match(text.as_bytes())
    }

    /// The regex source, flags and anchors included.
    pub fn as_str(&self) -> &str {
        self.0.as_str()
    }
}

impl PartialEq for WholeText {
    fn eq(&self, other: &Self) -> bool {
        self.as_str() == other.as_str()
    }
}

impl Eq for WholeText {}

/// A verb's pattern in its integration's dialect. Errors name what does not resolve.
pub fn compile(integration: &Integration, verb: &Verb, intents: &Intents) -> Result<CompiledPattern, String> {
    match integration.format {
        Format::Bash => Ok(compile_legacy(&verb.pattern, intents)),
        Format::Toml => compile_toml(integration, &verb.pattern, intents),
    }
}

/// Every `{intent}` as a group of its forms, as bash's `expand_intents` replaces them; any other `{...}` stays.
fn expand_legacy_intents(pattern: &str, intents: &Intents) -> String {
    let mut expanded = String::with_capacity(pattern.len() * 2);
    let mut rest = pattern;
    while let Some(open) = rest.find('{') {
        expanded.push_str(&rest[..open]);
        let token = &rest[open..];
        let forms = token
            .find('}')
            .and_then(|close| Some((close, intents.forms(&token[1..close])?)));
        match forms {
            Some((close, forms)) => {
                expanded.push('(');
                expanded.push_str(&forms.join("|"));
                expanded.push(')');
                rest = &token[close + 1..];
            }
            None => {
                expanded.push('{');
                rest = &token[1..];
            }
        }
    }
    expanded.push_str(rest);
    expanded
}

fn compile_legacy(pattern: &str, intents: &Intents) -> CompiledPattern {
    let mut body = expand_legacy_intents(pattern, intents);
    let mut placeholders = Vec::new();
    for (token, kind) in [
        ("{target}", PlaceholderType::Text),
        ("{number}", PlaceholderType::Number),
    ] {
        if body.contains(token) {
            let name = token.trim_matches(['{', '}']).to_string();
            body = body.replacen(token, &format!("(?P<{name}>{})", kind.capture_body(Format::Bash)), 1);
            placeholders.push(Placeholder { name, kind });
            break;
        }
    }
    CompiledPattern {
        regex: format!("{FLAGS}^({body})$"),
        body,
        placeholders,
    }
}

/// near-miss.awk's view of a legacy pattern: intents expanded, and every `{target}` and `{number}` a marker (the
/// regex compile keeps only the first). Markers are named groups `p<index>` over `placeholders`.
pub fn legacy_near_miss_source(pattern: &str, intents: &Intents) -> (String, Vec<Placeholder>) {
    let expanded = expand_legacy_intents(pattern, intents);
    let mut source = String::with_capacity(expanded.len());
    let mut placeholders = Vec::new();
    let mut rest = expanded.as_str();
    while let Some(start) = rest.find('{') {
        source.push_str(&rest[..start]);
        let token = &rest[start..];
        let kind = if token.starts_with("{target}") {
            Some(PlaceholderType::Text)
        } else if token.starts_with("{number}") {
            Some(PlaceholderType::Number)
        } else {
            None
        };
        match kind {
            Some(kind) => {
                source.push_str(&format!("(?P<p{}>x)", placeholders.len()));
                placeholders.push(Placeholder {
                    name: format!("p{}", placeholders.len()),
                    kind,
                });
                rest = &token["{target}".len()..];
            }
            None => {
                source.push('{');
                rest = &token[1..];
            }
        }
    }
    source.push_str(rest);
    (source, placeholders)
}

/// A `[mode]`'s patterns, compiled.
#[derive(Debug, Clone, Default)]
pub struct ModePatterns {
    pub exit_phrases: Option<WholeText>,
    pub drop: Option<WholeText>,
    pub keep: Option<WholeText>,
    /// Each of `endings` as its action and its pattern expanded to a regex body, in order; `session::dictation::Ending`
    /// anchors it in the ways an ending is matched.
    pub endings: Vec<(String, String)>,
}

/// Compiles the patterns of the integration's `[mode]` (`exit_phrases`, `rewrite.drop`, `rewrite.keep`, each of
/// `endings`) in the verbs' dialect, minus placeholders: a turn's words are all there is to capture. None without a
/// `[mode]`. The error is `file:line: message`.
pub fn compile_mode(integration: &Integration, intents: &Intents) -> Result<Option<ModePatterns>, String> {
    let Some(mode) = &integration.mode else {
        return Ok(None);
    };
    let expand_at = |key: &'static str, line: usize, pattern: &str| -> Result<String, String> {
        let fail = |message: String| format!("{}:{line}: [mode] {key}: {message}", integration.file.display());
        let mut placeholders = Vec::new();
        let body = expand_toml(integration, pattern, intents, &mut placeholders, 0).map_err(fail)?;
        if let Some(placeholder) = placeholders.first() {
            return Err(fail(format!("{{{}}} has nothing to capture here", placeholder.name)));
        }
        WholeText::new(&body).map_err(|error| fail(error.to_string()))?;
        Ok(body)
    };
    let compile_one = |key: &'static str, pattern: &str| -> Result<WholeText, String> {
        let line = mode.pattern_lines.get(key).copied().unwrap_or(1);
        let body = expand_at(key, line, pattern)?;
        Ok(WholeText::new(&body).expect("checked by expand_at"))
    };
    let endings = mode
        .endings
        .iter()
        .map(|ending| {
            Ok((
                ending.action.clone(),
                expand_at("endings", ending.line, &ending.pattern)?,
            ))
        })
        .collect::<Result<Vec<_>, String>>()?;
    let rewrite = mode.rewrite.as_ref();
    Ok(Some(ModePatterns {
        exit_phrases: Some(mode.exit_phrases.as_str())
            .filter(|pattern| !pattern.is_empty())
            .map(|pattern| compile_one("exit_phrases", pattern))
            .transpose()?,
        drop: rewrite
            .and_then(|rewrite| rewrite.drop.as_deref())
            .map(|pattern| compile_one("drop", pattern))
            .transpose()?,
        keep: rewrite
            .and_then(|rewrite| rewrite.keep.as_deref())
            .map(|pattern| compile_one("keep", pattern))
            .transpose()?,
        endings,
    }))
}

/// The words an exit from a mode is said with, around its object (was mode-phrases.sh `mode_exit_phrase`).
fn mode_exit(object: &str) -> String {
    let filler = "(?:okay|ok|alright|please|now)";
    format!(
        "(?:{filler} )*(?:(?:stop|exit|quit|end|leave|finish|close|turn off|switch off) (?:{object})|(?:{object}) off)(?: {filler})*"
    )
}

/// A `{...}` that names something: a word, optionally `:type`. Repetitions (`{3}`, `{1,2}`) are not names.
fn brace_name(inner: &str) -> Option<(&str, Option<&str>)> {
    let (name, kind) = match inner.split_once(':') {
        Some((name, kind)) => (name, Some(kind)),
        None => (inner, None),
    };
    let is_word = |word: &str| {
        word.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_')
            && word.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
    };
    (is_word(name) && kind.is_none_or(is_word)).then_some((name, kind))
}

const MAX_DEFINE_DEPTH: usize = 16;

fn compile_toml(integration: &Integration, pattern: &str, intents: &Intents) -> Result<CompiledPattern, String> {
    let mut placeholders = Vec::new();
    let body = expand_toml(integration, pattern, intents, &mut placeholders, 0)?;
    Ok(CompiledPattern {
        regex: anchored(&body),
        body,
        placeholders,
    })
}

fn expand_toml(
    integration: &Integration,
    pattern: &str,
    intents: &Intents,
    placeholders: &mut Vec<Placeholder>,
    depth: usize,
) -> Result<String, String> {
    if depth > MAX_DEFINE_DEPTH {
        return Err("defines nest too deep (a define that uses itself?)".to_string());
    }
    let mut out = String::with_capacity(pattern.len());
    let mut chars = pattern.char_indices().peekable();
    while let Some((index, c)) = chars.next() {
        match c {
            '\\' => {
                out.push(c);
                if let Some((_, escaped)) = chars.next() {
                    out.push(escaped);
                }
            }
            '{' => {
                let Some(close) = pattern[index..].find('}') else {
                    out.push(c);
                    continue;
                };
                let inner = &pattern[index + 1..index + close];
                let Some((name, kind)) = brace_name(inner) else {
                    out.push(c);
                    continue;
                };
                while chars.peek().is_some_and(|&(at, _)| at <= index + close) {
                    chars.next();
                }
                out.push_str(&resolve_name(integration, name, kind, intents, placeholders, depth)?);
            }
            _ => out.push(c),
        }
    }
    Ok(out)
}

fn resolve_name(
    integration: &Integration,
    name: &str,
    kind: Option<&str>,
    intents: &Intents,
    placeholders: &mut Vec<Placeholder>,
    depth: usize,
) -> Result<String, String> {
    let placeholder_kind = match (name, kind) {
        (_, Some(kind)) => Some(PlaceholderType::from_name(kind)?),
        ("target", None) => Some(PlaceholderType::Text),
        ("number", None) => Some(PlaceholderType::Number),
        _ => None,
    };
    if let Some(kind) = placeholder_kind {
        if placeholders.iter().any(|placeholder| placeholder.name == name) {
            return Err(format!("{{{name}}} appears twice"));
        }
        placeholders.push(Placeholder {
            name: name.to_string(),
            kind,
        });
        return Ok(format!("(?P<{name}>{})", kind.capture_body(Format::Toml)));
    }
    if let Some(fragment) = integration.defines.get(name) {
        let expanded = expand_toml(integration, fragment, intents, placeholders, depth + 1)?;
        return Ok(format!("(?:{expanded})"));
    }
    if name == "mode_object" || name == "mode_exit" {
        let object = integration
            .mode_exit_object
            .as_deref()
            .ok_or_else(|| format!("{{{name}}} needs [mode] exit_object"))?;
        let object = expand_toml(integration, object, intents, placeholders, depth + 1)?;
        return Ok(if name == "mode_object" {
            format!("(?:{object})")
        } else {
            format!("(?:{})", mode_exit(&object))
        });
    }
    if let Some(forms) = intents.forms(name) {
        return Ok(format!("(?:{})", forms.join("|")));
    }
    Err(format!("{{{name}}}: no placeholder, define or intent of that name"))
}

/// Substrings every match of the pattern contains, as clauses: a phrase can match only when each clause has a
/// literal that occurs in it. Empty when nothing is required, or when the pattern holds syntax the scan does not know
/// (flags, say `(?i)`, under which literals are not what they look like).
///
/// Read from the regex text rather than regex-syntax's AST: parsing every verb's AST takes 1.6 ms of a route, the scan
/// a tenth of that. A clause the scan misses only costs a compile; one it invents would hide a verb, which the match
/// goldens would show.
pub fn required_literals(regex: &str) -> Vec<Vec<String>> {
    let mut scan = Scan {
        text: regex.strip_prefix(FLAGS).unwrap_or(regex).as_bytes(),
        position: 0,
    };
    match scan.alternation() {
        Some(clauses) if scan.position == scan.text.len() => clauses,
        _ => Vec::new(),
    }
}

/// How much a clause narrows the phrases: its weakest literal's length without spaces, which every phrase has.
fn selectivity(clause: &[String]) -> usize {
    clause.iter().map(|literal| literal.trim().len()).min().unwrap_or(0)
}

type Clauses = Vec<Vec<String>>;

/// A recursive descent over the regex subset verb patterns use. Each method returns None to give up on the pattern.
struct Scan<'t> {
    text: &'t [u8],
    position: usize,
}

impl Scan<'_> {
    fn peek(&self) -> Option<u8> {
        self.text.get(self.position).copied()
    }

    /// One branch matches, so its best clause holds: the union of each branch's best clause is required.
    fn alternation(&mut self) -> Option<Clauses> {
        let mut branches = vec![self.sequence()?];
        while self.peek() == Some(b'|') {
            self.position += 1;
            branches.push(self.sequence()?);
        }
        if branches.len() == 1 {
            return branches.pop();
        }
        let mut union: Vec<String> = Vec::new();
        for branch in branches {
            let Some(best) = branch.into_iter().max_by_key(|clause| selectivity(clause)) else {
                return Some(Vec::new());
            };
            for literal in best {
                if !union.contains(&literal) {
                    union.push(literal);
                }
            }
        }
        Some(vec![union])
    }

    /// Runs of literal characters are required as they stand; an atom under a quantifier that allows none is not.
    fn sequence(&mut self) -> Option<Clauses> {
        let mut clauses: Clauses = Vec::new();
        let mut run = String::new();
        let flush = |clauses: &mut Clauses, run: &mut String| {
            if selectivity(std::slice::from_ref(run)) > 0 {
                clauses.push(vec![std::mem::take(run)]);
            }
            run.clear();
        };
        while let Some(byte) = self.peek() {
            let atom = match byte {
                b')' | b'|' => break,
                b'(' => {
                    flush(&mut clauses, &mut run);
                    self.position += 1;
                    self.group_prefix()?;
                    let inner = self.alternation()?;
                    (self.peek() == Some(b')')).then_some(())?;
                    self.position += 1;
                    inner
                }
                b'[' => {
                    flush(&mut clauses, &mut run);
                    self.class()?;
                    Vec::new()
                }
                b'\\' => {
                    flush(&mut clauses, &mut run);
                    self.escape()?;
                    Vec::new()
                }
                b'.' | b'^' | b'$' => {
                    flush(&mut clauses, &mut run);
                    self.position += 1;
                    Vec::new()
                }
                b'?' | b'*' | b'+' | b'{' => return None,
                literal => {
                    self.position += 1;
                    if !self.at_quantifier() {
                        run.push(char::from(literal));
                        continue;
                    }
                    flush(&mut clauses, &mut run);
                    vec![vec![char::from(literal).to_string()]]
                }
            };
            if self.at_quantifier() && self.quantifier_minimum()? == 0 {
                continue;
            }
            clauses.extend(atom.into_iter().filter(|clause| selectivity(clause) > 0));
        }
        flush(&mut clauses, &mut run);
        Some(clauses)
    }

    fn at_quantifier(&self) -> bool {
        matches!(self.peek(), Some(b'?' | b'*' | b'+' | b'{'))
    }

    /// Consumes a quantifier (and a lazy `?` after it) and returns how many times it requires the atom.
    fn quantifier_minimum(&mut self) -> Option<usize> {
        let minimum = match self.peek()? {
            b'?' | b'*' => 0,
            b'+' => 1,
            _ => {
                let close = self.text[self.position..].iter().position(|&b| b == b'}')?;
                let inside = std::str::from_utf8(&self.text[self.position + 1..self.position + close]).ok()?;
                let minimum = inside.split(',').next()?.parse().ok()?;
                self.position += close;
                minimum
            }
        };
        self.position += 1;
        if self.peek() == Some(b'?') {
            self.position += 1;
        }
        Some(minimum)
    }

    /// After a "(": `?:` and a group name are skipped; any other `?` sets flags, which the scan does not follow.
    fn group_prefix(&mut self) -> Option<()> {
        if self.peek() != Some(b'?') {
            return Some(());
        }
        let rest = &self.text[self.position..];
        if rest.starts_with(b"?:") {
            self.position += 2;
        } else if rest.starts_with(b"?P<") || rest.starts_with(b"?<") {
            self.position += rest.iter().position(|&b| b == b'>')? + 1;
        } else {
            return None;
        }
        Some(())
    }

    fn class(&mut self) -> Option<()> {
        self.position += 1;
        if self.peek() == Some(b'^') {
            self.position += 1;
        }
        // A "]" first is a member, not the end.
        if self.peek() == Some(b']') {
            self.position += 1;
        }
        loop {
            match self.peek()? {
                b']' => break,
                b'\\' => self.position += 2,
                b'[' => return None,
                _ => self.position += 1,
            }
        }
        self.position += 1;
        Some(())
    }

    fn escape(&mut self) -> Option<()> {
        self.position += 1;
        let escaped = self.peek()?;
        self.position += 1;
        if matches!(escaped, b'p' | b'P' | b'x' | b'u' | b'U') && self.peek() == Some(b'{') {
            self.position += self.text[self.position..].iter().position(|&b| b == b'}')? + 1;
        } else if matches!(escaped, b'x' | b'u' | b'U') {
            // `\x66` and friends: fixed-width hex digits follow, which would otherwise read as required literal text.
            return None;
        }
        Some(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::schema::{MatchSettings, Tier};
    use std::collections::BTreeMap;

    fn integration(format: Format) -> Integration {
        Integration {
            name: "Test".into(),
            stem: "test".into(),
            file: "test".into(),
            format,
            tier: Tier::Normal,
            force_prefixes: Vec::new(),
            defines: BTreeMap::from([
                ("move".to_string(), "(move|send)".to_string()),
                ("names".to_string(), "({move}|{open})".to_string()),
                ("loop".to_string(), "{loop}".to_string()),
            ]),
            mode_exit_object: Some("click mode".into()),
            mode: None,
            verbs: Vec::new(),
            examples: Vec::new(),
            legacy_help: false,
            settings: MatchSettings::default(),
            actions: BTreeMap::new(),
            surface: None,
            picker: None,
        }
    }

    fn verb(pattern: &str) -> Verb {
        Verb {
            action: "a".into(),
            pattern: pattern.into(),
            line: None,
            column: None,
            requires: None,
            listed: None,
        }
    }

    #[test]
    fn legacy_takes_the_first_placeholder_only() {
        let intents = Intents::default();
        let compiled = compile(&integration(Format::Bash), &verb("{close} {target}"), &intents).unwrap();
        assert_eq!(compiled.regex, "(?s-u)^((close|quit|kill) (?P<target>.+))$");
        let compiled = compile(&integration(Format::Bash), &verb("by {number} x {target}"), &intents).unwrap();
        assert_eq!(compiled.placeholders[0].name, "target");
        assert!(compiled.regex.contains("{number}"));
    }

    #[test]
    fn words_are_greedy_in_bash_and_lazy_in_toml() {
        let intents = Intents::default();
        let target = |format| {
            let compiled = compile(&integration(format), &verb("is {target}( please)*"), &intents).unwrap();
            let captures = regex::bytes::Regex::new(&compiled.regex)
                .unwrap()
                .captures(b"is tokyo please")
                .unwrap();
            String::from_utf8_lossy(&captures["target"]).into_owned()
        };
        assert_eq!(target(Format::Bash), "tokyo please");
        assert_eq!(target(Format::Toml), "tokyo");
    }

    #[test]
    fn toml_resolves_placeholders_defines_modes_and_intents() {
        let intents = Intents::default();
        let toml = integration(Format::Toml);
        let compiled = compile(
            &toml,
            &verb("{names} {window:text} to {n:position}( [0-9]{3})?"),
            &intents,
        )
        .unwrap();
        assert_eq!(
            compiled.regex,
            "(?s-u)^(?:(?:((?:(move|send))|(?:open|launch|start|bring up|pull up))) (?P<window>.+?) to (?P<n>.+?)( [0-9]{3})?)$"
        );
        assert_eq!(compiled.placeholders.len(), 2);
        assert!(
            compile(&toml, &verb("{mode_exit}"), &intents)
                .unwrap()
                .regex
                .contains("(?:click mode) off")
        );
        assert!(
            compile(&toml, &verb("{nope}"), &intents)
                .unwrap_err()
                .contains("{nope}")
        );
        assert!(compile(&toml, &verb("{loop}"), &intents).is_err());
        assert!(compile(&toml, &verb("{target} {target}"), &intents).is_err());
    }

    #[test]
    fn required_literals_give_up_on_fixed_width_hex_escapes() {
        assert!(required_literals(r"\x66oo").is_empty());
        assert!(required_literals(r"\u0066oo").is_empty());
    }

    #[test]
    fn required_literals_skip_optional_parts_and_union_alternatives() {
        let intents = Intents::default();
        let compiled = compile_legacy("(turn )?(the )?(volume|sound) up( by {number})?", &intents);
        assert_eq!(
            required_literals(&compiled.regex),
            [vec!["volume", "sound"], vec![" up"]]
        );
        assert!(required_literals("(?i)^volume$").is_empty());
        assert_eq!(
            required_literals("^(?P<n>[0-9]{3}) px[]x]+ ab?c\\.d e{2,}(f|gh)*?$"),
            [vec![" px"], vec![" a"], vec!["c"], vec!["d "], vec!["e"]]
        );
        assert!(required_literals("^(a|b").is_empty());
    }

    #[test]
    fn legacy_near_miss_source_marks_every_placeholder() {
        let (source, placeholders) =
            legacy_near_miss_source("move {target} to {number} {number} {x}", &Intents::default());
        assert_eq!(source, "move (?P<p0>x) to (?P<p1>x) (?P<p2>x) {x}");
        assert_eq!(placeholders.len(), 3);
    }

    #[test]
    fn mode_patterns_expand_like_verbs_and_a_bad_one_names_its_line() {
        let text = "verbs = []\n[mode]\nexit_object = 'click mode'\nexit_phrases = 'done with {mode_object}|{mode_exit}'\n\
                    rewrite = { drop = 'click', keep = '(a|b' }\n";
        let integration = crate::config::schema::parse_toml(std::path::Path::new("m.toml"), text).unwrap();
        let error = compile_mode(&integration, &Intents::default()).unwrap_err();
        assert!(error.starts_with("m.toml:5: [mode] keep: "), "{error}");
        let text = text.replace("'(a|b'", "'a|b'");
        let integration = crate::config::schema::parse_toml(std::path::Path::new("m.toml"), &text).unwrap();
        let patterns = compile_mode(&integration, &Intents::default()).unwrap().unwrap();
        let exit_phrases = patterns.exit_phrases.unwrap();
        assert!(
            exit_phrases
                .as_str()
                .starts_with("(?s-u)^(?:done with (?:click mode)|(?:"),
            "{}",
            exit_phrases.as_str()
        );
        assert!(exit_phrases.is_match("done with click mode") && exit_phrases.is_match("stop click mode"));
        assert!(patterns.drop.unwrap().is_match("click"));
        let keep = patterns.keep.unwrap();
        assert!(keep.is_match("a") && !keep.is_match("ab"));
        for bad in ["{target}", "{nonesuch}"] {
            let text = format!("verbs = []\n[mode]\nexit_phrases = '{bad}'\n");
            let integration = crate::config::schema::parse_toml(std::path::Path::new("m.toml"), &text).unwrap();
            let error = compile_mode(&integration, &Intents::default()).unwrap_err();
            assert!(error.starts_with("m.toml:3: [mode] exit_phrases: "), "{error}");
        }
    }

    #[test]
    fn mode_endings_expand_their_object_and_a_bad_one_names_its_own_line() {
        let text = "verbs = []\n[mode]\nexit_object = 'typing'\none_recording = true\nhandle_turn = 'x'\nendings = [\n  \
                    { action = \"type\", match = 'stop|{mode_exit}' },\n  { action = \"send\", match = 'send( it)?' },\n]\n";
        let integration = crate::config::schema::parse_toml(std::path::Path::new("m.toml"), text).unwrap();
        let endings = compile_mode(&integration, &Intents::default())
            .unwrap()
            .unwrap()
            .endings;
        assert_eq!(endings.len(), 2);
        assert_eq!(endings[1], ("send".to_string(), "send( it)?".to_string()));
        let stop = WholeText::new(&endings[0].1).unwrap();
        assert!(stop.is_match("stop") && stop.is_match("okay stop typing please") && !stop.is_match("stop it"));
        for (bad, says) in [("send (", "unclosed"), ("send {target}", "nothing to capture")] {
            let broken = text.replace("send( it)?", bad);
            let integration = crate::config::schema::parse_toml(std::path::Path::new("m.toml"), &broken).unwrap();
            let error = compile_mode(&integration, &Intents::default()).unwrap_err();
            assert!(error.starts_with("m.toml:8: [mode] endings: "), "{error}");
            assert!(error.to_lowercase().contains(says), "{error}");
        }
    }

    /// Owner decision a: one dialect. Whatever a verb's pattern accepts and matches, a mode's pattern does too.
    #[test]
    fn a_mode_pattern_compiles_and_matches_as_the_same_verb_pattern() {
        let integration = integration(Format::Toml);
        let verb_matches = |pattern: &str, text: &str| {
            let compiled = compile_toml(&integration, pattern, &Intents::default()).ok()?;
            let regex = regex::bytes::Regex::new(&compiled.regex).ok()?;
            Some(regex.is_match(text.as_bytes()))
        };
        let mode_matches = |pattern: &str, text: &str| {
            let text_toml = format!(
                "verbs = []\n[mode]\nexit_phrases = '{pattern}'\nrewrite = {{ drop = '{pattern}', keep = '{pattern}' }}\n"
            );
            let integration = crate::config::schema::parse_toml(std::path::Path::new("m.toml"), &text_toml).unwrap();
            let patterns = compile_mode(&integration, &Intents::default()).ok()??;
            let each = [patterns.exit_phrases?, patterns.drop?, patterns.keep?].map(|regex| regex.is_match(text));
            assert!(each.iter().all(|matched| *matched == each[0]), "{pattern}: {each:?}");
            Some(each[0])
        };
        for (pattern, text) in [
            ("a.b", "a\nb"),
            ("done( now)?", "done now"),
            ("done", "im done"),
            (r"\p{L}+", "abc"),
            (r"(?-u:\xff)", "x"),
            (r"\w+", "abc"),
        ] {
            assert_eq!(
                mode_matches(pattern, text),
                verb_matches(pattern, text),
                "{pattern} on {text:?}"
            );
        }
    }
}
