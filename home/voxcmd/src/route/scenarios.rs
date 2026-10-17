//! routing end to end over TOML fixtures and canned hook answers: the tiers, ties, retries, near misses, sequences, and
//! the snapshots of `explain --json` (tests/snapshots), where an agent sees a change of behaviour as a diff
use super::router::Router;
use super::sequence::explain_phrase;
use super::trace::{DecisionKind, Explain};
use crate::config::Config;
use crate::config::intents::Intents;
use crate::config::schema::{Integration, parse_toml};
use crate::hooks::{Candidate, HookRun, Hooks, Lookup};
use crate::text::normalize::Replacements;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// Integrations that only the scenarios need: a fallback catch-all with a force prefix, a bar surface and a free-text
/// action. Files are named as they would be in a config dir, so snapshots hold no machine paths.
const KEYBINDS: &str = r#"
name = "Keybinds"
fallback = true
force_prefixes = ["keybind", "key bind"]
verbs = [{ action = "run", match = '(run )?{target}' }]
[actions.run]
run = 'run_keybind "$VOXCMD_ID"'
candidates = 'list_binds'
silent = true
"#;

const OVERVIEW: &str = r#"
name = "Overview"
verbs = [{ action = "act", match = '(close|select) {number}' }]
[surface]
state_file = "overview.json"
[actions]
act = "overview_act"
"#;

const TIMERS: &str = r#"
name = "Timers"
verbs = [
  { action = "remind", match = 'remind me {target}' },
  { action = "timer", match = 'set a timer for {duration:duration}' },
]
[actions.remind]
run = 'remind "$VOXCMD_ARG_TARGET"'
free_text = true
[actions.timer]
run = 'timer "$VOXCMD_ARG_DURATION"'
wait_hook = 'timer_started'
"#;

const SEARCH: &str = r#"
name = "Search"
verbs = [{ action = "find", match = 'find {target}' }]
[actions.find]
run = 'show "$VOXCMD_ID"'
candidates = 'search_index'
no_match = "missing"
[actions.missing]
run = 'notify "nothing named $VOXCMD_ARG_TARGET"'
"#;

fn fixture_text(stem: &str) -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join(format!("tests/fixtures/integrations/{stem}.toml"));
    std::fs::read_to_string(path).expect("fixture")
}

fn integration(stem: &str, text: &str) -> Integration {
    parse_toml(&PathBuf::from(format!("integrations/{stem}.toml")), text).expect("fixture parses")
}

/// In file-name order, which is routing order.
fn config() -> Config {
    let from_files = |stem: &str| integration(stem, &fixture_text(stem));
    Config {
        integrations: vec![
            from_files("apps"),
            from_files("click"),
            integration("keybinds", KEYBINDS),
            from_files("media"),
            integration("overview", OVERVIEW),
            integration("search", SEARCH),
            integration("timers", TIMERS),
        ],
        intents: Intents::default(),
        replacements: Replacements::default(),
    }
}

/// What each hook says, by integration stem and action; a hook not listed prints nothing (its target is the id).
#[derive(Default)]
struct CannedHooks {
    lookups: HashMap<(&'static str, &'static str), Lookup>,
    open_surface: Option<&'static str>,
    /// The raw transcript each hook call was given.
    raw_seen: std::sync::Mutex<Vec<String>>,
}

impl CannedHooks {
    fn says(mut self, stem: &'static str, action: &'static str, candidates: &[(&str, &str, Option<&str>)]) -> Self {
        let list = candidates
            .iter()
            .map(|(id, label, match_text)| Candidate {
                id: (*id).into(),
                label: (*label).into(),
                match_text: match_text.map(str::to_string),
                weak: false,
            })
            .collect();
        self.lookups.insert((stem, action), Lookup::Candidates(list));
        self
    }

    fn yields(mut self, stem: &'static str, action: &'static str) -> Self {
        self.lookups.insert((stem, action), Lookup::Yield);
        self
    }

    fn surface(mut self, stem: &'static str) -> Self {
        self.open_surface = Some(stem);
        self
    }
}

impl Hooks for CannedHooks {
    fn candidates(&self, integration: &Integration, action: &str, _target: &str, raw: &str) -> HookRun {
        self.raw_seen.lock().unwrap().push(raw.to_string());
        let mut run = HookRun::unhooked(integration, action, "canned");
        let key = self
            .lookups
            .iter()
            .find(|((stem, canned), _)| *stem == integration.stem && *canned == action);
        // The catch-all fallback offers nothing unless a scenario gives it binds, as an unbound phrase gets nothing.
        run.lookup = match key {
            Some((_, lookup)) => lookup.clone(),
            None if integration.stem == "keybinds" => Lookup::Candidates(Vec::new()),
            None => Lookup::Unhooked,
        };
        if let Lookup::Candidates(lines) = &run.lookup {
            run.lines.clone_from(lines);
        }
        run
    }

    fn surface_open(&self, integration: &Integration) -> bool {
        self.open_surface == Some(integration.stem.as_str())
    }
}

fn explain(phrase: &str, hooks: &CannedHooks) -> Explain {
    let config = config();
    let router = Router::new(&config, hooks);
    explain_phrase(&router, phrase)
}

/// The JSON document with its timings zeroed, which differ on every run.
fn stable_json(explain: &mut Explain) -> String {
    for step in &mut explain.steps {
        step.millis = 0.0;
        step.hooks.iter_mut().for_each(|hook| hook.millis = 0.0);
    }
    serde_json::to_string_pretty(explain).unwrap()
}

macro_rules! snapshot {
    ($name:literal, $phrase:expr, $hooks:expr) => {{
        let mut explain = explain($phrase, &$hooks);
        insta::with_settings!({ snapshot_path => "../../tests/snapshots" }, {
            insta::assert_snapshot!($name, stable_json(&mut explain));
        });
        explain
    }};
}

fn only_step(explain: &Explain) -> &super::trace::StepTrace {
    assert_eq!(explain.steps.len(), 1, "{}", explain.text());
    &explain.steps[0]
}

#[test]
fn a_plain_phrase_runs_the_first_integration_that_matches() {
    let explain = snapshot!("plain_phrase", "volume up by 10", CannedHooks::default());
    let step = only_step(&explain);
    assert_eq!(step.decision.kind, DecisionKind::Run);
    assert_eq!(step.options[0].action, "volume_up");
    assert_eq!(step.options[0].env["VOXCMD_ARG_NUMBER"], "10");
}

#[test]
fn a_force_prefix_gives_the_rest_of_the_phrase_to_one_integration() {
    let hooks = CannedHooks::default().says("keybinds", "run", &[("141", "Mute", None), ("142", "Unmute", None)]);
    let explain = snapshot!("forced_integration", "keybind mute", hooks);
    let step = only_step(&explain);
    assert_eq!(step.forced.as_deref(), Some("keybinds.toml"));
    assert_eq!(step.options[0].id, "141");
}

#[test]
fn an_open_surface_takes_the_phrase_before_the_tiers_and_gives_it_back_when_it_has_no_verb() {
    let explain = snapshot!("open_surface", "close 2", CannedHooks::default().surface("overview"));
    let step = only_step(&explain);
    assert_eq!(step.surface.as_deref(), Some("overview.toml"));
    assert_eq!(step.options[0].action, "act");
    let given_back = explain_phrase(
        &Router::new(&config(), &CannedHooks::default().surface("overview")),
        "volume up",
    );
    assert_eq!(only_step(&given_back).surface, None);
    assert_eq!(only_step(&given_back).options[0].action, "volume_up");
}

#[test]
fn a_self_correction_retries_after_the_last_correction_point() {
    let hooks = CannedHooks::default().says("media", "play_on", &[]);
    let explain = snapshot!("correction_retry", "play pause no wait next track", hooks);
    let step = only_step(&explain);
    assert_eq!(step.corrected.as_deref(), Some("next track"));
    assert_eq!(step.normalized, "next track");
    assert_eq!(step.options[0].action, "next");
    assert_eq!(step.raw_transcript, "next track");
}

#[test]
fn the_raw_suffix_keeps_the_punctuation_of_the_retried_words() {
    let hooks = CannedHooks::default().says("media", "play_on", &[]);
    let explain = explain("play pause, no wait, Next Track!", &hooks);
    let step = only_step(&explain);
    assert_eq!(step.corrected.as_deref(), Some("next track"));
    assert_eq!(step.raw_transcript, "Next Track!");
    let config = config();
    let router = Router::new(&config, &hooks);
    assert_eq!(router.raw_suffix_of("a b, c d", "c d"), "c d");
    assert_eq!(router.raw_suffix_of("a b, c d", "x"), "x");
}

#[test]
fn hooks_read_the_phrase_as_spoken_during_a_correction_retry() {
    let hooks = CannedHooks::default().says("media", "play_on", &[]);
    explain("play pause, no wait, Next Track!", &hooks);
    let seen = hooks.raw_seen.lock().unwrap();
    assert!(!seen.is_empty());
    assert!(
        seen.iter().all(|raw| raw == "play pause, no wait, Next Track!"),
        "{seen:?}"
    );
}

#[test]
fn a_phrase_with_its_words_in_the_wrong_order_offers_near_misses_through_the_picker() {
    let explain = snapshot!("near_miss", "mute toggle", CannedHooks::default());
    let step = only_step(&explain);
    assert_eq!(step.decision.kind, DecisionKind::Pick);
    assert!(step.options.iter().all(|option| option.near_miss && option.weak));
    assert_eq!(step.options[0].action, "toggle_mute");
}

#[test]
fn a_near_miss_carries_the_number_it_read() {
    let explain = explain("10 close", &CannedHooks::default());
    let step = only_step(&explain);
    let act = step
        .options
        .iter()
        .find(|option| option.action == "act")
        .unwrap_or_else(|| panic!("{}", explain.text()));
    assert_eq!(act.env["VOXCMD_ARG_NUMBER"], "10");
}

#[test]
fn a_yield_verb_is_not_offered_as_a_near_miss() {
    let mut config = config();
    config.integrations[0].verbs.push(crate::config::schema::Verb {
        action: "yield".into(),
        pattern: "open the calendar".into(),
        line: None,
        requires: None,
    });
    let hooks = CannedHooks::default();
    let explain = explain_phrase(&Router::new(&config, &hooks), "calendar open");
    assert!(
        explain
            .steps
            .iter()
            .flat_map(|step| &step.options)
            .all(|option| option.action != "yield"),
        "{}",
        explain.text()
    );
}

#[test]
fn a_sequence_routes_every_step_and_says_what_each_waits_for() {
    let explain = snapshot!("sequence", "next track and then volume up", CannedHooks::default());
    assert_eq!(explain.steps.len(), 2);
    assert_eq!(
        explain.steps[0].wait.as_deref(),
        Some("no popup opening or closing and no click overlay, then 0.3s")
    );
    assert_eq!(explain.steps[1].wait.as_deref(), Some("nothing, it is the last step"));
    assert!(explain.text().contains("step 2 of 2\ntranscript:  volume up\n"));
}

#[test]
fn a_mode_switch_anywhere_but_last_refuses_the_sequence() {
    let explain = snapshot!(
        "refused_sequence",
        "click mode and then next track",
        CannedHooks::default()
    );
    let sequence = explain.sequence.as_ref().unwrap();
    assert_eq!(
        sequence.refused.as_deref(),
        Some("a mode switch can only be the last step (step 1 of 2)")
    );
    assert!(explain.steps.is_empty());
    assert!(
        explain
            .text()
            .starts_with("sequence:    2 steps\nresult:      refused, a mode switch")
    );
    // Last, the same switch is allowed.
    assert!(
        explain_phrase(
            &Router::new(&config(), &CannedHooks::default()),
            "next track and then click mode"
        )
        .sequence
        .unwrap()
        .refused
        .is_none()
    );
}

#[test]
fn built_ins_are_handled_before_any_integration() {
    let explain = snapshot!("built_in", "never mind", CannedHooks::default());
    let step = only_step(&explain);
    assert_eq!(step.decision.kind, DecisionKind::Builtin);
    assert!(step.integrations.is_empty());
    let help = explain_phrase(&Router::new(&config(), &CannedHooks::default()), "what can i say");
    assert_eq!(only_step(&help).decision.result, "built-in, opens Voice Help");
    let help_in_a_sequence = explain_phrase(
        &Router::new(&config(), &CannedHooks::default()),
        "next track and then what can i say",
    );
    assert_eq!(
        help_in_a_sequence.steps[1].decision.result,
        "no match, Voice Help is not opened inside a sequence"
    );
}

#[test]
fn a_phrase_nothing_takes_is_no_match() {
    let explain = snapshot!("no_match", "bogus words", CannedHooks::default());
    let step = only_step(&explain);
    assert_eq!(step.decision.result, "no match");
    assert!(step.options.is_empty());
}

#[test]
fn two_integrations_with_options_make_a_picker() {
    let hooks = CannedHooks::default().says(
        "media",
        "play_on",
        &[("spotify.i1", "spotify", None), ("spotify.i2", "spotify", None)],
    );
    let explain = snapshot!("picker", "play spotify", hooks);
    let step = only_step(&explain);
    assert_eq!(step.decision.kind, DecisionKind::Pick);
    assert_eq!(step.decision.result, "ask with the picker (2 options)");
}

#[test]
fn a_label_matching_confirm_labels_asks_before_running() {
    let hooks = CannedHooks::default().says(
        "apps",
        "close",
        &[
            ("0x1", "Firefox window: Inbox", Some("firefox")),
            ("0x2", "Kitty window: sh", Some("kitty")),
        ],
    );
    let explain = snapshot!("confirm", "close the firefox window", hooks);
    let step = only_step(&explain);
    assert_eq!(step.decision.kind, DecisionKind::Confirm);
    assert_eq!(step.options.len(), 1);
    assert_eq!(step.options[0].confirm.as_deref(), Some("confirm_labels[0]"));
    assert_eq!(step.options[0].toast_label, "Apps: close Firefox window: Inbox");
}

#[test]
fn a_hook_that_yields_leaves_the_phrase_to_the_next_integration() {
    let hooks = CannedHooks::default()
        .yields("apps", "close")
        .says("keybinds", "run", &[("7", "Close Window", None)]);
    let explain = explain("close window", &hooks);
    let step = only_step(&explain);
    assert_eq!(step.options.len(), 1);
    assert_eq!(step.options[0].integration, "Keybinds");
    assert!(step.integrations.iter().any(|trace| matches!(
        &trace.outcome,
        super::trace::IntegrationOutcome::YieldedByHook { action } if action == "close"
    )));
}

#[test]
fn a_target_no_candidate_names_is_reported_by_the_no_match_action() {
    let hooks = CannedHooks::default().says("search", "find", &[("1", "Quarterly report", None)]);
    let explain = explain("find holiday photos", &hooks);
    let step = only_step(&explain);
    assert_eq!(step.options.len(), 1, "{}", explain.text());
    assert_eq!(step.options[0].action, "missing");
    assert_eq!(step.options[0].id, "");
    assert_eq!(step.options[0].label, "holiday photos");
    // A hook that printed `[]` is the same: nothing matches.
    let none = explain_phrase(
        &Router::new(&config(), &CannedHooks::default().says("search", "find", &[])),
        "find holiday photos",
    );
    assert_eq!(only_step(&none).options[0].action, "missing");
}

#[test]
fn the_wake_word_is_stripped_and_alone_it_is_no_match() {
    let hooks = CannedHooks::default();
    let stripped = explain("Cortana, next track", &hooks);
    let step = only_step(&stripped);
    assert_eq!(step.wake_word.as_deref(), Some("cortana"));
    assert_eq!(step.options[0].action, "next");
    let alone = explain("cortana", &hooks);
    assert_eq!(only_step(&alone).decision.result, "no match, only the wake word");
}

#[test]
fn a_free_text_action_takes_the_rest_of_the_phrase() {
    let explain = explain("remind me to call mom and then buy milk", &CannedHooks::default());
    assert_eq!(explain.steps.len(), 1);
    assert_eq!(explain.steps[0].options[0].target, "to call mom and then buy milk");
    assert!(explain.sequence.is_none());
    let split = explain_phrase(
        &Router::new(&config(), &CannedHooks::default()),
        "next track and then remind me to call mom and then buy milk",
    );
    assert_eq!(split.sequence.as_ref().unwrap().free_text_step, Some(2));
    assert!(
        split
            .text()
            .contains("note:        a free-text action takes the rest of the phrase")
    );
}

#[test]
fn more_than_five_steps_are_refused() {
    let phrase = "mute and then mute and then mute and then mute and then mute and then mute and then mute";
    let explain = explain(phrase, &CannedHooks::default());
    assert!(
        explain
            .text()
            .starts_with("sequence:    more than 5 steps\nresult:      refused, a phrase can have at most 5 steps\n")
    );
}

#[test]
fn a_sequence_stops_at_the_first_step_that_does_not_run() {
    let explain = explain("next track and then bogus words and then mute", &CannedHooks::default());
    assert_eq!(explain.steps.len(), 2);
    assert_eq!(explain.steps[1].decision.result, "no match");
    assert!(explain.text().contains("step 2 of 3\n"));
    assert!(!explain.text().contains("step 3 of 3"));
}
