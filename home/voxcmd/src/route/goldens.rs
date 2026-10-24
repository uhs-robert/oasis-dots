//! The matcher, force prefixes and near misses against what the bash voxcmd and near-miss.awk made of the same phrases
//! (tests/fixtures/gen-match-goldens.sh), over the committed `_legacy-dump` of this checkout's integrations. A second run
//! swaps in the shipped `integrations/*.toml`, since the dump comes from the bash files and never sees a conversion.
use super::matcher::{Matcher, Outcome};
use crate::config::Config;
use crate::config::intents::Intents;
use crate::config::{legacy, schema};
use crate::text::normalize::Replacements;
use crate::text::speech::{Clock, parse_day};
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

/// The same config with each shipped `integrations/<stem>.toml` standing in for the dump's integration of that stem,
/// in file-name order as `Config::load` sorts. A converted file is held to the bash goldens of its stem.
fn config_with_shipped_toml() -> Config {
    let mut config = config();
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(".config/voxcmd/integrations");
    let mut shipped = 0;
    for entry in std::fs::read_dir(&dir).expect("integrations dir").map(Result::unwrap) {
        let path = entry.path();
        // Symlinks are private integrations linked in from outside the repo (like sandbox.sh): not shipped, no goldens.
        if !entry.file_type().unwrap().is_file() {
            continue;
        }
        if path.extension().is_none_or(|extension| extension != "toml") {
            continue;
        }
        let toml = schema::load_toml(&path).unwrap();
        let slot = config
            .integrations
            .iter_mut()
            .find(|integration| integration.stem == toml.stem)
            .unwrap_or_else(|| panic!("{} has no bash original in the dump", toml.stem));
        *slot = toml;
        shipped += 1;
    }
    assert!(shipped > 0, "no shipped TOML integration in {}", dir.display());
    config
        .integrations
        .sort_by(|a, b| a.file.file_name().cmp(&b.file.file_name()));
    config
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
    matches_the_goldens(&config(), &[]);
}

#[test]
fn shipped_toml_matches_the_bash_goldens() {
    matches_the_goldens(&config_with_shipped_toml(), TYPED_DAY_VERBS);
}

/// calendar's two `day` verbs, as `stem:verb:action=` prefixes of golden entries. In bash they matched any words and a
/// candidate hook declined the non-days afterwards; `{target:day}` does not match those, so the goldens hold match
/// entries these verbs rightly lack. Near misses skip typed verbs altogether, so every near entry of them is ignored.
const TYPED_DAY_VERBS: &[&str] = &["calendar:5:day=", "calendar:7:day="];

/// `column` without the golden entries of `ignored` verbs that Rust cannot have: all of a near column's, and a match
/// column's whose target is no day (a valid day must still match).
fn without_entries(column_name: &str, column: &str, ignored: &[&str]) -> String {
    let clock = Clock::from_env().expect("clock");
    column
        .split("; ")
        .filter(|entry| {
            let Some(prefix) = ignored.iter().find(|prefix| entry.starts_with(**prefix)) else {
                return true;
            };
            column_name == "match" && parse_day(&entry[prefix.len()..], &clock).is_some()
        })
        .collect::<Vec<_>>()
        .join("; ")
}

fn matches_the_goldens(config: &Config, ignored: &[&str]) {
    let goldens = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/match-goldens.tsv"))
        .expect("run gen-match-goldens.sh");
    let matcher = Matcher::new(config);
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
            if without_entries(column, expected, ignored) != without_entries(column, got, ignored) {
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
