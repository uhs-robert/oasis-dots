//! The matcher, force prefixes and near misses against what the bash voxcmd and near-miss.awk made of the same phrases
//! (tests/fixtures/gen-match-goldens.sh), over the committed `_legacy-dump` of this checkout's integrations.
use super::matcher::{Matcher, Outcome};
use crate::config::Config;
use crate::config::intents::Intents;
use crate::config::legacy;
use crate::text::normalize::Replacements;
use std::path::PathBuf;

fn config() -> Config {
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");
    let dump = std::fs::read_to_string(fixtures.join("legacy-dump.jsonl")).expect("run gen-match-goldens.sh");
    Config {
        integrations: legacy::parse_dump(&dump).unwrap(),
        intents: Intents::load(&fixtures.join("match")),
        replacements: Replacements::default(),
    }
}

/// The golden line's three result columns, as the generator writes them.
fn columns(matcher: &Matcher, phrase: &str) -> [String; 3] {
    let integrations = matcher.integrations();
    let forced = match matcher.forced(phrase) {
        Some((index, rest)) => format!("{} {rest}", integrations[index].stem),
        None => "-".to_string(),
    };
    let target = |words: Option<String>| format!("={}", words.unwrap_or_default());
    let mut matches = Vec::new();
    let mut near = Vec::new();
    for (index, integration) in integrations.iter().enumerate() {
        if let Outcome::Matched(found) = matcher.first_match(index, phrase).outcome {
            let target = found
                .args
                .into_iter()
                .next()
                .map(|arg| target(arg.words))
                .unwrap_or_default();
            matches.push(format!("{}:{}:{}{target}", integration.stem, found.verb, found.action));
        }
        for (verb, miss) in matcher.near_misses(index, phrase) {
            let action = &integration.verbs[verb].action;
            let target = if miss.has_target {
                format!("={}", miss.target)
            } else {
                String::new()
            };
            near.push(format!(
                "{}:{verb}:{action}{target}~{}",
                integration.stem, miss.leftover
            ));
        }
    }
    [forced, matches.join("; "), near.join("; ")]
}

#[test]
fn rust_matches_the_bash_goldens() {
    let goldens = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/match-goldens.tsv"))
        .expect("run gen-match-goldens.sh");
    let config = config();
    let matcher = Matcher::new(&config);
    let mut checked = 0;
    let mut mismatches = Vec::new();
    for line in goldens.lines() {
        let fields: Vec<&str> = line.split('\t').collect();
        let [phrase, forced, matches, near] = fields[..] else {
            panic!("malformed golden line: {line:?}")
        };
        checked += 1;
        let got = columns(&matcher, phrase);
        for (column, (expected, got)) in ["force", "match", "near"]
            .iter()
            .zip([forced, matches, near].iter().zip(&got))
        {
            if expected != got {
                mismatches.push(format!("{phrase:?} {column}:\n  bash {expected}\n  rust {got}"));
            }
        }
    }
    assert!(checked > 5000, "only {checked} golden phrases: was the corpus lost?");
    assert!(
        mismatches.is_empty(),
        "{} differences over {checked} phrases:\n{}",
        mismatches.len(),
        mismatches[..mismatches.len().min(30)].join("\n")
    );
}
