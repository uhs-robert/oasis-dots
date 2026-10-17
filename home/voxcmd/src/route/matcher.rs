//! the first matching verb per integration; forced prefixes; placeholder parsing; near misses over every verb
//!
//! Compiling every verb's regex costs most of the 10 ms a route may take (7 to 8 ms for today's 219 verbs as one
//! `RegexSet`), so each verb compiles lazily: an integration's verbs are tried in order until one matches, and a verb
//! is compiled only when the phrase holds every literal its pattern requires (pattern::required_literals). Most verbs
//! fail that check, so a route compiles a handful.
use super::near_miss::{NearMiss, Readings};
use super::pattern::{self, CompiledPattern, Placeholder, PlaceholderType};
use crate::config::Config;
use crate::config::schema::{Format, Tier};
use crate::text::normalize::normalize;
use crate::text::speech::{self, Anchor, Clock};
use regex::bytes::Regex;
use std::cell::OnceCell;

/// A verb's argument: the words its placeholder captured and, for a typed one, the parsed value.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Arg {
    pub name: String,
    pub kind: PlaceholderType,
    /// None when the placeholder sat in an optional group that did not take part.
    pub words: Option<String>,
    /// The canonical value: the words for `text`, an integer for `number`/`position`/`ordinal`, seconds for
    /// `duration`, epoch seconds for `time`, `YYYY-MM-DD` for `day`.
    pub value: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Match {
    pub verb: usize,
    pub action: String,
    pub args: Vec<Arg>,
}

/// What one integration made of a phrase.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome {
    Matched(Match),
    /// A `yield` verb matched: the integration offers nothing, as if no verb had.
    Yielded {
        verb: usize,
    },
    NoVerb,
}

/// A verb whose regex matched but did not count, with why.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rejection {
    pub verb: usize,
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IntegrationMatch {
    pub outcome: Outcome,
    /// In verb order, before the one that counted.
    pub rejections: Vec<Rejection>,
}

/// One verb's derived forms, each built on first use: most verbs of a route never get past the prefilter, and a verb
/// after an integration's first match is never looked at.
#[derive(Default)]
struct LazyVerb {
    pattern: OnceCell<Result<CompiledPattern, String>>,
    required: OnceCell<Vec<Vec<String>>>,
    regex: OnceCell<Result<Regex, String>>,
    near_miss: OnceCell<Readings>,
}

/// The verbs of a config, compiled on first use. Built per route; nothing outlives the process.
pub struct Matcher<'c> {
    config: &'c Config,
    verbs: Vec<Vec<LazyVerb>>,
    /// Read for `time` and `day` placeholders only: loading the time zone costs half a millisecond.
    clock: OnceCell<Result<Clock, String>>,
}

impl<'c> Matcher<'c> {
    /// The clock comes from the environment (`VOXCMD_NOW`, the system time zone) when a placeholder first needs it.
    pub fn new(config: &'c Config) -> Self {
        let verbs = config
            .integrations
            .iter()
            .map(|integration| integration.verbs.iter().map(|_| LazyVerb::default()).collect())
            .collect();
        Self {
            config,
            verbs,
            clock: OnceCell::new(),
        }
    }

    #[cfg(test)]
    pub fn with_clock(config: &'c Config, clock: Clock) -> Self {
        let matcher = Self::new(config);
        let _ = matcher.clock.set(Ok(clock));
        matcher
    }

    /// The pattern a verb compiled to, or why it did not.
    pub fn pattern(&self, integration: usize, verb: usize) -> Result<&CompiledPattern, &str> {
        self.verbs[integration][verb]
            .pattern
            .get_or_init(|| {
                let config = &self.config.integrations[integration];
                pattern::compile(config, &config.verbs[verb], &self.config.intents)
            })
            .as_ref()
            .map_err(String::as_str)
    }

    /// Whether the text holds every literal the verb's pattern requires, the cheap check before compiling its regex.
    fn may_match(&self, integration: usize, verb: usize, text: &str) -> bool {
        let Ok(pattern) = self.pattern(integration, verb) else {
            return false;
        };
        let required = self.verbs[integration][verb]
            .required
            .get_or_init(|| pattern::required_literals(&pattern.regex));
        required
            .iter()
            .all(|clause| clause.iter().any(|literal| text.contains(literal.as_str())))
    }

    fn regex(&self, integration: usize, verb: usize) -> Result<&Regex, &str> {
        let pattern = self.pattern(integration, verb)?;
        self.verbs[integration][verb]
            .regex
            .get_or_init(|| Regex::new(&pattern.regex).map_err(|error| error.to_string()))
            .as_ref()
            .map_err(String::as_str)
    }

    #[cfg(test)]
    pub fn integrations(&self) -> &'c [crate::config::schema::Integration] {
        &self.config.integrations
    }

    /// The integrations of a tier, in routing order.
    pub fn tier(&self, tier: Tier) -> impl Iterator<Item = usize> + '_ {
        (0..self.config.integrations.len()).filter(move |&index| self.config.integrations[index].tier == tier)
    }

    /// The first integration, in file order, one of whose force prefixes (normalized, then a space) starts the text,
    /// with the rest of the text after it. Any tier: "keybind ..." reaches the fallback Keybinds directly.
    pub fn forced(&self, text: &str) -> Option<(usize, String)> {
        self.config
            .integrations
            .iter()
            .enumerate()
            .find_map(|(index, integration)| {
                integration.force_prefixes.iter().find_map(|prefix| {
                    let prefix = normalize(prefix);
                    let rest = text.strip_prefix(prefix.as_str())?.strip_prefix(' ')?;
                    (!prefix.is_empty() && !rest.is_empty()).then(|| (index, rest.to_string()))
                })
            })
    }

    /// The integration's first verb that matches the whole text and counts: its typed arguments parse and the
    /// integration it requires is loaded.
    pub fn first_match(&self, integration: usize, text: &str) -> IntegrationMatch {
        self.first_match_among(integration, text, |_| true)
    }

    /// `first_match` over the verbs whose action `listed` accepts: the integration's mode or free-text actions.
    pub fn first_match_among(&self, integration: usize, text: &str, listed: impl Fn(&str) -> bool) -> IntegrationMatch {
        let config = &self.config.integrations[integration];
        let mut rejections = Vec::new();
        for index in 0..config.verbs.len() {
            if !listed(&config.verbs[index].action) {
                continue;
            }
            if !self.may_match(integration, index, text) {
                continue;
            }
            let regex = match self.regex(integration, index) {
                Ok(regex) => regex,
                // Bash skips a pattern its regex engine rejects without a word, and the legacy dialect must equal it.
                // A TOML verb says why, so `explain` shows the broken regex instead of an unexplained no-match.
                Err(error) => {
                    if config.format == Format::Toml {
                        rejections.push(Rejection {
                            verb: index,
                            reason: format!("bad regex: {error}"),
                        });
                    }
                    continue;
                }
            };
            let Some(captures) = regex.captures(text.as_bytes()) else {
                continue;
            };
            let verb = &config.verbs[index];
            if let Some(required) = &verb.requires
                && !self.config.integrations.iter().any(|loaded| &loaded.stem == required)
            {
                rejections.push(Rejection {
                    verb: index,
                    reason: format!("requires {required}"),
                });
                continue;
            }
            let pattern = self
                .pattern(integration, index)
                .expect("a compiled regex has a pattern");
            let args = match self.arguments(config.format, &pattern.placeholders, &captures) {
                Ok(args) => args,
                Err(reason) => {
                    rejections.push(Rejection { verb: index, reason });
                    continue;
                }
            };
            let outcome = if config.format == Format::Toml && verb.action == "yield" {
                Outcome::Yielded { verb: index }
            } else {
                Outcome::Matched(Match {
                    verb: index,
                    action: verb.action.clone(),
                    args,
                })
            };
            return IntegrationMatch { outcome, rejections };
        }
        IntegrationMatch {
            outcome: Outcome::NoVerb,
            rejections,
        }
    }

    fn arguments(
        &self,
        format: Format,
        placeholders: &[Placeholder],
        captures: &regex::bytes::Captures,
    ) -> Result<Vec<Arg>, String> {
        placeholders
            .iter()
            .map(|placeholder| {
                let words = captures
                    .name(&placeholder.name)
                    .map(|capture| String::from_utf8_lossy(capture.as_bytes()).into_owned());
                // A legacy verb's capture is its target whatever it holds: the bash integration parsed it.
                let value = match (&words, format) {
                    (None, _) => None,
                    (Some(words), Format::Bash) => Some(words.clone()),
                    (Some(words), Format::Toml) => Some(self.parse(placeholder, words)?),
                };
                Ok(Arg {
                    name: placeholder.name.clone(),
                    kind: placeholder.kind,
                    words,
                    value,
                })
            })
            .collect()
    }

    fn clock(&self) -> Result<&Clock, String> {
        self.clock.get_or_init(Clock::from_env).as_ref().map_err(Clone::clone)
    }

    fn parse(&self, placeholder: &Placeholder, words: &str) -> Result<String, String> {
        let parsed = match placeholder.kind {
            PlaceholderType::Text | PlaceholderType::Number => Some(words.to_string()),
            PlaceholderType::Position => speech::spoken_position(words).map(|n| n.to_string()),
            PlaceholderType::Ordinal => speech::spoken_ordinal(words).map(|n| n.to_string()),
            PlaceholderType::Duration => speech::parse_duration(words).map(|seconds| seconds.to_string()),
            PlaceholderType::Time => {
                speech::parse_clock(words, Anchor::Next, self.clock()?).map(|epoch| epoch.to_string())
            }
            PlaceholderType::Day => speech::parse_day(words, self.clock()?).map(|date| date.to_string()),
        };
        parsed.ok_or_else(|| {
            format!(
                "{{{}:{}}} did not parse: {words:?}",
                placeholder.name,
                placeholder.kind.name()
            )
        })
    }

    /// Every verb of the integration that is a near miss for the text, in verb order, each with its best reading.
    pub fn near_misses(&self, integration: usize, text: &str) -> Vec<(usize, NearMiss)> {
        let config = &self.config.integrations[integration];
        (0..config.verbs.len())
            .filter_map(|index| {
                let readings = self.verbs[integration][index]
                    .near_miss
                    .get_or_init(|| match config.format {
                        Format::Bash => {
                            let (source, placeholders) =
                                pattern::legacy_near_miss_source(&config.verbs[index].pattern, &self.config.intents);
                            Readings::new(&source, &placeholders)
                        }
                        Format::Toml => match self.pattern(integration, index) {
                            Ok(pattern) => Readings::new(&pattern.body, &pattern.placeholders),
                            Err(_) => Readings::unreadable(),
                        },
                    });
                readings.best(text).map(|found| (index, found))
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::intents::Intents;
    use crate::config::schema;
    use crate::text::normalize::Replacements;
    use std::path::Path;

    fn fixtures(stems: &[&str]) -> Config {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/integrations");
        Config {
            integrations: stems
                .iter()
                .map(|stem| schema::load_toml(&dir.join(format!("{stem}.toml"))).unwrap())
                .collect(),
            intents: Intents::default(),
            replacements: Replacements::default(),
        }
    }

    fn wednesday_afternoon() -> Clock {
        Clock {
            now: 1_792_006_200,
            tz: jiff::tz::TimeZone::get("America/New_York").unwrap(),
        }
    }

    /// The action and each argument's name and value.
    type Matched = (String, Vec<(String, Option<String>)>);

    fn matched(matcher: &Matcher, integration: usize, text: &str) -> Option<Matched> {
        match matcher.first_match(integration, text).outcome {
            Outcome::Matched(found) => Some((
                found.action,
                found.args.into_iter().map(|arg| (arg.name, arg.value)).collect(),
            )),
            _ => None,
        }
    }

    #[test]
    fn toml_verbs_match_in_order() {
        let config = fixtures(&["media"]);
        let matcher = Matcher::new(&config);
        assert_eq!(
            matched(&matcher, 0, "volume up by 10"),
            Some(("volume_up".into(), vec![("number".into(), Some("10".into()))]))
        );
        assert_eq!(
            matched(&matcher, 0, "volume up"),
            Some(("volume_up".into(), vec![("number".into(), None)]))
        );
        assert_eq!(
            matched(&matcher, 0, "play spotify"),
            Some(("play_on".into(), vec![("target".into(), Some("spotify".into()))]))
        );
        assert_eq!(matched(&matcher, 0, "fly away"), None);
    }

    #[test]
    fn a_typed_placeholder_that_does_not_parse_rejects_the_verb() {
        let config = fixtures(&["apps"]);
        let matcher = Matcher::with_clock(&config, wednesday_afternoon());
        assert_eq!(
            matched(&matcher, 0, "move firefox to workspace three"),
            Some((
                "move".into(),
                vec![
                    ("window".into(), Some("firefox".into())),
                    ("workspace".into(), Some("3".into()))
                ]
            ))
        );
        let result = matcher.first_match(0, "move firefox to workspace blue");
        assert_eq!(result.rejections.len(), 1);
        assert!(
            result.rejections[0].reason.contains("did not parse"),
            "{:?}",
            result.rejections
        );
    }

    #[test]
    fn a_toml_verb_with_a_broken_regex_says_why() {
        let mut config = fixtures(&["media"]);
        config.integrations[0].verbs.insert(
            0,
            schema::Verb {
                action: "broken".into(),
                pattern: "volume (up".into(),
                line: None,
                requires: None,
            },
        );
        let matcher = Matcher::new(&config);
        let result = matcher.first_match(0, "volume up");
        assert!(
            result.rejections[0].reason.starts_with("bad regex: "),
            "{:?}",
            result.rejections
        );
        assert!(matches!(result.outcome, Outcome::Matched(ref found) if found.action == "volume_up"));
    }

    #[test]
    fn yield_verbs_and_requires() {
        let config = fixtures(&["apps"]);
        let matcher = Matcher::new(&config);
        assert_eq!(
            matcher.first_match(0, "close my agents").outcome,
            Outcome::Yielded { verb: 0 }
        );
        // Firefox is not loaded, so the browser veto does not count and "open" takes the phrase.
        let result = matcher.first_match(0, "open youtube in firefox");
        assert_eq!(result.rejections[0].reason, "requires firefox");
        assert!(matches!(result.outcome, Outcome::Matched(ref found) if found.action == "open"));
    }

    #[test]
    fn mode_exits_compile_from_the_mode_object() {
        let config = fixtures(&["click"]);
        let matcher = Matcher::new(&config);
        assert_eq!(
            matched(&matcher, 0, "okay stop clicking now").map(|m| m.0),
            Some("stop_clicking".into())
        );
    }

    #[test]
    fn force_prefixes_need_words_after_them() {
        let mut config = fixtures(&["media"]);
        config.integrations[0].force_prefixes = vec!["Key-Bind".into()];
        let matcher = Matcher::new(&config);
        assert_eq!(matcher.forced("key bind super q"), Some((0, "super q".into())));
        assert_eq!(matcher.forced("key bind"), None);
        assert_eq!(matcher.forced("key binding x"), None);
    }

    #[test]
    fn toml_near_misses_read_the_ast() {
        let config = fixtures(&["media"]);
        let matcher = Matcher::new(&config);
        let misses = matcher.near_misses(0, "mute toggle");
        let actions: Vec<&str> = misses
            .iter()
            .map(|(verb, _)| config.integrations[0].verbs[*verb].action.as_str())
            .collect();
        assert_eq!(actions, ["toggle_mute"]);
        // "{number}( percent)?" glues a group to the placeholder, which near-miss.awk could not read either.
        assert!(matcher.near_misses(0, "up volume").is_empty());
    }
}
