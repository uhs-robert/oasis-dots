//! a phrase of several steps joined by "and then": splitting it, refusing what cannot run, and the dry-run walk (was
//! `split_phrase`, `sequence_refusal` and `dry_run_sequence`)
//!
//! The steps run one after another, each only once the one before has finished; here nothing runs, so the walk routes
//! each step as a sequence step and says what the next would wait for. Running them is 2.3.
use super::resolve::RouteOption;
use super::router::{Router, StepContext, needs_pick};
use super::trace::{Explain, SequenceTrace};
use crate::config::schema::Wait;
use regex::Regex;
use std::sync::LazyLock;

/// A phrase has at most this many steps; more is refused.
pub const MAX_STEPS: usize = 5;

/// "and then", or a comma before "then" (never a bare "then": "then" alone is ordinary speech). Matched in the raw
/// transcript, where the comma still is. The edges are one non-word character or the string's end.
pub static SEPARATOR: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?is)((?:^|[^\p{L}\p{N}])and\s+then|,\s*then)(?:[^\p{L}\p{N}]|$)").expect("fixed pattern")
});

/// The text without the whitespace and the `,;.` around it that the split leaves.
pub fn trim_step(text: &str) -> &str {
    text.trim_matches(|c: char| c.is_whitespace() || matches!(c, ',' | ';' | '.'))
}

/// The raw steps of a phrase, and the 1-based step that took the rest of the phrase as free text (a timer's "remind
/// me to ...", a calendar event's title, whose words may hold "and then").
pub struct Steps {
    pub steps: Vec<String>,
    pub free_text_step: Option<usize>,
}

/// Reading stops one step past `MAX_STEPS`, which is enough to refuse the phrase. A phrase with no "and then" is one
/// step, unchanged.
pub fn split_phrase(router: &Router, transcript: &str) -> Steps {
    let one = |transcript: &str| Steps {
        steps: vec![transcript.to_string()],
        free_text_step: None,
    };
    if !SEPARATOR.is_match(transcript) {
        return one(transcript);
    }
    let mut steps: Vec<String> = Vec::new();
    let mut free_text_step = None;
    let mut rest = match router.wake().after_leading_raw(transcript) {
        Some(after) if !trim_step(&after).is_empty() => trim_step(&after).to_string(),
        _ => transcript.to_string(),
    };
    loop {
        if steps.len() > MAX_STEPS {
            break;
        }
        let Some(found) = SEPARATOR.find(&rest) else {
            let last = trim_step(&rest);
            if !last.is_empty() {
                steps.push(last.to_string());
            }
            break;
        };
        let step = trim_step(&rest[..found.start()]).to_string();
        let after = rest[found.end()..].to_string();
        if trim_step(&after).is_empty() {
            if !step.is_empty() {
                steps.push(step);
            }
            break;
        }
        if !step.is_empty() && starts_free_text_action(router, &rest) {
            steps.push(trim_step(&rest).to_string());
            free_text_step = Some(steps.len());
            break;
        }
        if !step.is_empty() {
            steps.push(step);
        }
        rest = after;
    }
    if steps.is_empty() {
        return one(transcript);
    }
    Steps { steps, free_text_step }
}

/// Whether some integration's verb for one of its `free_text` actions takes the whole text.
fn starts_free_text_action(router: &Router, raw: &str) -> bool {
    let text = router.step_text(raw);
    matches_listed(router, &text, |action| action.free_text)
}

/// Whether some integration matches the whole text with a verb whose action is flagged by `listed`.
fn matches_listed(router: &Router, text: &str, listed: impl Fn(&crate::config::schema::Action) -> bool) -> bool {
    router
        .config()
        .integrations
        .iter()
        .enumerate()
        .any(|(index, integration)| {
            let among = |action: &str| integration.actions.get(action).is_some_and(&listed);
            matches!(
                router.matcher().first_match_among(index, text, among).outcome,
                super::matcher::Outcome::Matched(_)
            )
        })
}

/// Why the steps cannot run, none when they can. Checked before any runs.
pub fn refusal(router: &Router, steps: &[String]) -> Option<String> {
    let total = steps.len();
    if total > MAX_STEPS {
        return Some(format!("a phrase can have at most {MAX_STEPS} steps"));
    }
    for (index, step) in steps.iter().enumerate().take(total.saturating_sub(1)) {
        let text = router.step_text(step);
        if matches_listed(router, &text, |action| action.mode_switch || action.mode_entry) {
            return Some(format!(
                "a mode switch can only be the last step (step {} of {total})",
                index + 1
            ));
        }
    }
    None
}

/// The wait the dry run names after a step that ran: the condition its action declares, else the bar settling and a
/// moment for the app.
fn describe_wait(router: &Router, option: &RouteOption) -> String {
    let declared = router.config().integrations[option.integration]
        .actions
        .get(&option.action)
        .and_then(|action| action.wait.as_ref());
    match declared {
        Some(Wait::LegacyCondition(condition)) => condition.clone(),
        Some(Wait::Builtin(name)) => format!("the {name} wait"),
        Some(Wait::Hook(hook)) => format!("hook: {hook}"),
        None => {
            let settle = std::env::var("VOXCMD_APP_SETTLE_SECS")
                .ok()
                .filter(|secs| !secs.is_empty())
                .unwrap_or_else(|| "0.3".to_string());
            format!("no popup opening or closing and no click overlay, then {settle}s")
        }
    }
}

/// What the dry run says the step is followed by, once it ran.
fn wait_of(router: &Router, options: &[RouteOption], last: bool) -> String {
    if last {
        "nothing, it is the last step".to_string()
    } else if options.is_empty() {
        "nothing, the step does not match".to_string()
    } else if needs_pick(options) {
        "whatever the picked option waits for".to_string()
    } else {
        describe_wait(router, &options[0])
    }
}

/// The whole record for a phrase: one step, or the dry-run walk of a sequence.
pub fn explain_phrase(router: &Router, phrase: &str) -> Explain {
    let split = split_phrase(router, phrase);
    let mut explain = Explain {
        phrase: phrase.to_string(),
        sequence: None,
        steps: Vec::new(),
        click: None,
        reply: None,
    };
    if split.steps.len() == 1 {
        explain
            .steps
            .push(router.route_step(&split.steps[0], StepContext::default()));
        return explain;
    }
    let refused = refusal(router, &split.steps);
    explain.sequence = Some(SequenceTrace {
        steps: split.steps.len(),
        refused: refused.clone(),
        free_text_step: split.free_text_step,
    });
    if refused.is_some() {
        return explain;
    }
    let total = split.steps.len();
    for (index, raw) in split.steps.iter().enumerate() {
        let (mut step, options) = router.route_step_with_options(
            raw,
            StepContext {
                in_sequence: true,
                in_session_turn: false,
            },
        );
        let stop = !step.ran;
        if !stop {
            step.wait = Some(wait_of(router, &options, index + 1 == total));
        }
        explain.steps.push(step);
        if stop {
            break;
        }
    }
    explain
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trim_cuts_whitespace_and_separators_punctuation() {
        assert_eq!(trim_step(" , open firefox. ;"), "open firefox");
        assert_eq!(trim_step(""), "");
    }

    #[test]
    fn separator_needs_and_then_or_comma_then() {
        for (text, found) in [
            ("open firefox and then close it", true),
            ("open firefox, And Then close it", true),
            ("open firefox, then close it", true),
            ("open firefox then close it", false),
            ("band then", false),
            ("and then go", true),
            ("candy and thence", false),
        ] {
            assert_eq!(SEPARATOR.is_match(text), found, "{text}");
        }
    }
}
