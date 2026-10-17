//! the `explain` printout; so far the match layer: which verb of which integration matches, or nearly matches
//!
//! The lines are not the bash dry run's: no `result:` or `option N:` line appears until 2.2b resolves matches into
//! options, so nothing that parses the dry run (run-phrases.sh, bench.sh, owner-test-bar) mistakes this for a route.
use super::matcher::{Matcher, Outcome};
use crate::cli::ExplainArgs;
use crate::config::Config;
use crate::config::schema::{Integration, Tier};
use crate::exit::CliError;
use crate::text::normalize::{apply_replacements, normalize};
use crate::text::wake_word::WakeWords;
use std::fmt::Write as _;

/// `voxcmd explain <phrase>`.
pub fn run(args: ExplainArgs) -> Result<String, CliError> {
    if args.json {
        return Err(CliError::not_implemented("explain --json", "2.2b"));
    }
    if args.window.is_some() {
        return Err(CliError::not_implemented("explain --window", "2.5"));
    }
    if args.reply {
        return Err(CliError::not_implemented("explain --reply", "2.4"));
    }
    let config = Config::load(&crate::paths::config_dir()).map_err(|message| CliError::usage("explain", message))?;
    let matcher = Matcher::new(&config);
    Ok(match_layer(
        &matcher,
        &config,
        &WakeWords::from_env(),
        &args.phrase.join(" "),
    ))
}

fn describe(integration: &Integration) -> String {
    let file = integration.file.file_name().unwrap_or_default().to_string_lossy();
    let fallback = if integration.tier == Tier::Fallback {
        " [fallback]"
    } else {
        ""
    };
    format!("{} ({file}){fallback}", integration.name)
}

/// "verb 3", or "verb 3 (line 12)" for a TOML verb, so the line can be opened.
fn verb_ref(integration: &Integration, verb: usize) -> String {
    match integration.verbs[verb].line {
        Some(line) => format!("verb {verb} (line {line})"),
        None => format!("verb {verb}"),
    }
}

fn match_layer(matcher: &Matcher, config: &Config, wake: &WakeWords, phrase: &str) -> String {
    let mut out = String::new();
    let mut text = apply_replacements(&normalize(phrase), &config.replacements);
    if let Some(rest) = wake.split_leading(&text) {
        text = rest;
    }
    let _ = writeln!(out, "transcript: {phrase}");
    let _ = writeln!(out, "normalized: {text}");
    let integrations = matcher.integrations();
    let forced = matcher.forced(&text);
    let (tried, text): (Vec<usize>, String) = match forced.clone() {
        Some((index, rest)) => {
            let _ = writeln!(out, "forced to: {}", describe(&integrations[index]));
            (vec![index], rest)
        }
        None => (
            matcher.tier(Tier::Normal).chain(matcher.tier(Tier::Fallback)).collect(),
            text,
        ),
    };
    let mut any_match = false;
    for &index in &tried {
        for verb in 0..integrations[index].verbs.len() {
            if let Err(error) = matcher.pattern(index, verb) {
                let at = verb_ref(&integrations[index], verb);
                let _ = writeln!(out, "bad pattern: {} {at}: {error}", describe(&integrations[index]));
            }
        }
        let found = matcher.first_match(index, &text);
        for rejection in &found.rejections {
            let _ = writeln!(
                out,
                "rejected: {} {}: {}",
                describe(&integrations[index]),
                verb_ref(&integrations[index], rejection.verb),
                rejection.reason
            );
        }
        match found.outcome {
            Outcome::Matched(matched) => {
                any_match = true;
                let args: String = matched
                    .args
                    .iter()
                    .map(|arg| format!(" {}={}", arg.name, arg.value.as_deref().unwrap_or("")))
                    .collect();
                let _ = writeln!(
                    out,
                    "match: {} {} action={}{args}",
                    describe(&integrations[index]),
                    verb_ref(&integrations[index], matched.verb),
                    matched.action
                );
            }
            Outcome::Yielded { verb } => {
                let at = verb_ref(&integrations[index], verb);
                let _ = writeln!(out, "yielded: {} {at}", describe(&integrations[index]));
            }
            Outcome::NoVerb => {}
        }
    }
    // As in routing: a phrase forced to one integration gets no near misses.
    if !any_match && forced.is_none() {
        for &index in &tried {
            for (verb, near) in matcher.near_misses(index, &text) {
                let action = &integrations[index].verbs[verb].action;
                let _ = writeln!(
                    out,
                    "near miss: {} {} action={action} target={} leftover={}",
                    describe(&integrations[index]),
                    verb_ref(&integrations[index], verb),
                    near.target,
                    near.leftover
                );
            }
        }
    }
    out.push_str("note: the match layer only; options, hooks and the decision come in 2.2b");
    out
}
