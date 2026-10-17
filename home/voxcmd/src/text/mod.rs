//! spoken text: normalizing a transcript, parsing numbers, positions, times and monitor words, the wake word
//!
//! Only `speech` has a CLI surface so far (`util speech`); the rest is library code the router uses from 2.2.
#[allow(dead_code, reason = "used by the router from 2.2")]
pub mod monitors;
#[allow(dead_code, reason = "used by the router from 2.2")]
pub mod normalize;
#[allow(
    dead_code,
    reason = "positions and ordinals are used by the router and monitors from 2.2"
)]
pub mod speech;
#[allow(dead_code, reason = "used by the router from 2.2")]
pub mod wake_word;

/// The bash functions this module replaces, run over a corpus once (tests/fixtures/gen-speech-goldens.sh) and compared
/// row by row. The CLI-visible half is tests/speech_goldens.rs.
#[cfg(test)]
mod goldens {
    use super::monitors::{self, Place};
    use super::normalize::{Replacements, apply_replacements, name_workspace_ordinals, normalize};
    use super::speech::{spoken_cardinal, spoken_ordinal, spoken_position};
    use super::wake_word::{WakeWords, correction_tails};
    use std::collections::HashMap;
    use std::path::PathBuf;

    fn unescape(field: &str) -> String {
        let mut out = String::new();
        let mut chars = field.chars();
        while let Some(c) = chars.next() {
            if c != '\\' {
                out.push(c);
                continue;
            }
            match chars.next() {
                Some('n') => out.push('\n'),
                Some('t') => out.push('\t'),
                Some('r') => out.push('\r'),
                Some(other) => out.push(other),
                None => out.push('\\'),
            }
        }
        out
    }

    /// Built once: compiling the wake regexes per row would dominate the test.
    struct Context {
        fixtures: PathBuf,
        replacements: Replacements,
        wake: HashMap<String, WakeWords>,
        places: HashMap<String, Vec<Place>>,
    }

    impl Context {
        fn new(fixtures: PathBuf) -> Self {
            let replacements = Replacements::load(&fixtures.join("speech/replacements.d"));
            Self {
                fixtures,
                replacements,
                wake: HashMap::new(),
                places: HashMap::new(),
            }
        }

        /// What the bash function printed (None: it failed, printing nothing).
        fn run(&mut self, operation: &str, input: &str, env: &str) -> Option<String> {
            let setting = |name: &str| env.split(' ').find_map(|pair| pair.strip_prefix(&format!("{name}=")));
            let aliases = setting("VOXCMD_WAKE_ALIASES").unwrap_or("kortana|cortona").to_string();
            let wake = self
                .wake
                .entry(aliases.clone())
                .or_insert_with(|| WakeWords::new(&aliases));
            match operation {
                "normalize" => Some(normalize(input)),
                "apply-replacements" => Some(apply_replacements(input, &self.replacements)),
                "workspace-ordinals" => Some(name_workspace_ordinals(input)),
                "correction-tails" => Some(correction_tails(input).join("|")),
                "leading-wake" => wake.split_leading(input),
                "trailing-wake" => wake
                    .split_trailing(input)
                    .map(|(before, rest)| format!("{before}|{rest}")),
                "heard-wake" => wake.heard(input, &self.replacements),
                "position" => spoken_position(input).map(|n| n.to_string()),
                "ordinal" => spoken_ordinal(input).map(|n| n.to_string()),
                "cardinal" => spoken_cardinal(input).map(|n| n.to_string()),
                "words-known" => monitors::words_known(input).then(String::new),
                "monitor-named" => {
                    let file = setting("PLACES")
                        .and_then(|path| path.strip_prefix('@'))
                        .expect("PLACES=@path");
                    let fixtures = &self.fixtures;
                    let places = self.places.entry(file.to_string()).or_insert_with(|| {
                        serde_json::from_str(&std::fs::read_to_string(fixtures.join(file)).unwrap()).unwrap()
                    });
                    Some(monitors::named(input, places).unwrap_or_else(|sentence| format!("error:{sentence}")))
                }
                other => panic!("unknown golden operation {other}"),
            }
        }
    }

    #[test]
    fn rust_matches_the_bash_goldens() {
        let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");
        let goldens = std::fs::read_to_string(fixtures.join("text-goldens.tsv")).expect("run gen-speech-goldens.sh");
        let mut context = Context::new(fixtures);
        let mut checked = 0;
        let mut mismatches = Vec::new();
        for line in goldens.lines() {
            let fields: Vec<&str> = line.splitn(5, '\t').collect();
            let [env, operation, input, status, expected] = fields[..] else {
                panic!("malformed golden row: {line:?}")
            };
            let (input, expected) = (unescape(input), unescape(expected));
            let got = context.run(operation, &input, env);
            let got_status = if got.is_some() { "0" } else { "1" };
            checked += 1;
            if got_status != status || got.as_deref().unwrap_or("") != expected {
                mismatches.push(format!(
                    "{operation} {input:?} [{env}]: bash exit {status} {expected:?}, rust {got:?}"
                ));
            }
        }
        assert!(checked > 1000, "only {checked} golden rows: was the corpus lost?");
        assert!(
            mismatches.is_empty(),
            "{} of {checked} rows differ:\n{}",
            mismatches.len(),
            mismatches[..mismatches.len().min(40)].join("\n")
        );
    }
}
