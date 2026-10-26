//! The matcher, force prefixes and near misses against the committed `match-goldens.tsv`: what the shipped
//! `integrations/*.toml` made of 12,563 phrases when the file was last written. A change in any route shows as a
//! difference here; if it is wanted, the owner signs off a new file.
use super::matcher::{Matcher, Outcome};
use crate::config::Config;
use crate::config::intents::Intents;
use crate::config::schema;
use crate::text::normalize::Replacements;
use std::path::PathBuf;

/// Each shipped `integrations/<stem>.toml`, in file-name order as `Config::load` sorts, with the intents fixture.
fn config() -> Config {
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(".config/voxcmd/integrations");
    let mut integrations = Vec::new();
    for entry in std::fs::read_dir(&dir).expect("integrations dir").map(Result::unwrap) {
        let path = entry.path();
        // Symlinks are private integrations linked in from outside the repo (like sandbox.sh): not shipped, no goldens.
        if !entry.file_type().unwrap().is_file() || path.extension().is_none_or(|extension| extension != "toml") {
            continue;
        }
        integrations.push(schema::load_toml(&path).unwrap());
    }
    assert!(
        !integrations.is_empty(),
        "no shipped TOML integration in {}",
        dir.display()
    );
    integrations.sort_by(|a, b| a.file.file_name().cmp(&b.file.file_name()));
    Config {
        integrations,
        intents: Intents::load(&fixtures.join("match")),
        replacements: Replacements::default(),
    }
}

/// The golden line's three result columns.
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
fn shipped_toml_matches_the_goldens() {
    let goldens = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/match-goldens.tsv"))
        .expect("tests/fixtures/match-goldens.tsv is committed");
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
                mismatches.push(format!("{phrase:?} {column}:\n  golden {expected}\n  got    {got}"));
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
