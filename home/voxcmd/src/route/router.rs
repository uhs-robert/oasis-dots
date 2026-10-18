//! one step of a phrase through the tiers: built-ins, wake word, forced integration, open surface, normal tier, fallback
//! tier, correction retry, near misses, and the decision (was `route_step` and `route_options`)
//!
//! Every stage appends to the `StepTrace` that `explain` prints. The LLM hook sits between the normal and the fallback
//! tier in bash; it is 2.6 here, so a phrase that reaches it goes straight on to the fallback tier. Nothing here acts:
//! running the chosen option is 2.3.
use super::matcher::{Arg, IntegrationMatch, Match, Matcher, Outcome};
use super::near_miss::NearMiss;
use super::pattern::PlaceholderType;
use super::resolve::{self, PendingMatch, Resolved, RouteOption, Texts};
use super::trace::{
    ArgValue, Builtin, Decision, DecisionKind, IntegrationOutcome, IntegrationTrace, NearMissTrace, OptionTrace,
    Rejection, RouteTier, StepTrace, VerbRef,
};
use crate::config::Config;
use crate::config::schema::{Format, Integration, Tier};
use crate::hooks::{HookRun, Hooks, Lookup, Memoized};
use crate::text::normalize::{apply_replacements, normalize};
use crate::text::wake_word::{WakeWords, correction_tails};
use regex::Regex;
use std::cell::Cell;
use std::collections::BTreeMap;
use std::sync::LazyLock;
use std::time::{Duration, Instant};

/// Phrases that open Voice Help before any integration is tried, so the keybinds fallback never takes them.
static HELP_PHRASES: LazyLock<Regex> =
    LazyLock::new(|| Regex::new("^(what can i say|voice help|show voice commands)$").expect("fixed pattern"));

/// Phrases that throw the command away silently, for a false start that still got recorded.
static DISCARD_PHRASES: LazyLock<Regex> =
    LazyLock::new(|| Regex::new("^(never ?mind|cancel|forget it|nothing)$").expect("fixed pattern"));

/// How many options a near-miss picker offers.
const NEAR_MISS_OPTIONS: usize = 10;

#[derive(Debug, Clone, Copy, Default)]
pub struct StepContext {
    /// Routing a step of "and then": no near miss, and Voice Help is no match.
    pub in_sequence: bool,
    /// Routing a voice session's turn (2.4): no near miss.
    pub in_session_turn: bool,
}

pub struct Router<'c> {
    config: &'c Config,
    matcher: Matcher<'c>,
    wake: WakeWords,
    hooks: Memoized<'c>,
    /// Time spent resolving matches (hooks, fzf) in the step being routed, left out of its `millis`.
    resolve_wall: Cell<Duration>,
}

/// The integrations one pass over the tiers tried, and what they offered.
struct Pass {
    /// The integration a force prefix chose, or the open surface that took the phrase.
    forced: Option<usize>,
    surface: bool,
    options: Vec<RouteOption>,
    /// By integration index; none for one not tried.
    traces: Vec<Option<IntegrationTrace>>,
    hooks: Vec<HookRun>,
}

impl Pass {
    fn new(integrations: usize) -> Self {
        Self {
            forced: None,
            surface: false,
            options: Vec::new(),
            traces: (0..integrations).map(|_| None).collect(),
            hooks: Vec::new(),
        }
    }
}

impl<'c> Router<'c> {
    pub fn new(config: &'c Config, hooks: &'c dyn Hooks) -> Self {
        Self {
            config,
            matcher: Matcher::new(config),
            wake: WakeWords::from_env(),
            hooks: Memoized::new(hooks),
            resolve_wall: Cell::new(Duration::ZERO),
        }
    }

    pub fn config(&self) -> &'c Config {
        self.config
    }

    pub fn matcher(&self) -> &Matcher<'c> {
        &self.matcher
    }

    pub fn wake(&self) -> &WakeWords {
        &self.wake
    }

    /// The text of a step as the integrations see it: normalized, replaced, without a leading wake word.
    pub fn step_text(&self, transcript: &str) -> String {
        let text = apply_replacements(&normalize(transcript), &self.config.replacements);
        self.wake.split_leading(&text).unwrap_or(text)
    }

    /// The options a session turn's whole text names as mode switches: entering or leaving a mode (each integration's
    /// mode actions, bash `session_mode_options`), resolved as any match is.
    pub fn mode_options(&self, text: &str) -> Vec<RouteOption> {
        self.hooks.forget();
        let pending: Vec<PendingMatch> = (0..self.config.integrations.len())
            .filter_map(|index| match self.mode_action_match(index, text).outcome {
                Outcome::Matched(matched) => Some(PendingMatch::from_args(
                    index,
                    self.config,
                    &matched.action,
                    matched.args,
                )),
                _ => None,
            })
            .collect();
        let texts = Texts {
            phrase: text,
            raw_transcript: text,
        };
        self.resolve(&pending, texts)
            .into_iter()
            .flat_map(|resolved| resolved.options)
            .collect()
    }

    /// Whether some integration's mode action takes the whole text.
    pub fn is_mode_action(&self, text: &str) -> bool {
        (0..self.config.integrations.len())
            .any(|index| matches!(self.mode_action_match(index, text).outcome, Outcome::Matched(_)))
    }

    fn mode_action_match(&self, index: usize, text: &str) -> IntegrationMatch {
        let actions = &self.config.integrations[index].actions;
        self.matcher.first_match_among(index, text, |action| {
            actions.get(action).is_some_and(|action| action.mode_switch)
        })
    }

    /// Routes one step. The record says what a run would do; nothing is run.
    pub fn route_step(&self, transcript: &str, context: StepContext) -> StepTrace {
        self.route_step_with_options(transcript, context).0
    }

    /// `route_step`, and the options its decision is about, which a sequence reads the next wait from.
    pub fn route_step_with_options(&self, transcript: &str, context: StepContext) -> (StepTrace, Vec<RouteOption>) {
        let started = Instant::now();
        self.resolve_wall.set(Duration::ZERO);
        self.hooks.forget();
        let mut text = apply_replacements(&normalize(transcript), &self.config.replacements);
        let mut step = StepTrace {
            transcript: transcript.to_string(),
            wake_word: None,
            normalized: String::new(),
            replacements: Vec::new(),
            raw_transcript: transcript.to_string(),
            corrected: None,
            forced: None,
            surface: None,
            mode: None,
            rewritten: None,
            integrations: Vec::new(),
            hooks: Vec::new(),
            options: Vec::new(),
            decision: Decision {
                kind: DecisionKind::NoMatch,
                option: None,
                reason: String::new(),
                result: String::new(),
            },
            wait: None,
            millis: 0.0,
            ran: false,
            builtin: None,
            forced_integration: None,
        };
        if let Some(rest) = self.wake.split_leading(&text) {
            step.wake_word = Some(text[..text.len() - rest.len()].trim().to_string());
            text = rest;
            if text.is_empty() {
                step.normalized = text;
                return (
                    finish_builtin(
                        step,
                        DecisionKind::NoMatch,
                        false,
                        Builtin::OnlyWakeWord,
                        "no match, only the wake word",
                        "only the wake word was said",
                        started,
                    ),
                    Vec::new(),
                );
            }
        }
        step.normalized.clone_from(&text);
        if HELP_PHRASES.is_match(&text) {
            let finished = if context.in_sequence {
                finish_builtin(
                    step,
                    DecisionKind::NoMatch,
                    false,
                    Builtin::VoiceHelpInSequence,
                    "no match, Voice Help is not opened inside a sequence",
                    "a Voice Help phrase is no match inside a sequence",
                    started,
                )
            } else {
                finish_builtin(
                    step,
                    DecisionKind::Builtin,
                    true,
                    Builtin::VoiceHelp,
                    "built-in, opens Voice Help",
                    "a Voice Help phrase, handled before any integration",
                    started,
                )
            };
            return (finished, Vec::new());
        }
        if DISCARD_PHRASES.is_match(&text) {
            return (
                finish_builtin(
                    step,
                    DecisionKind::Builtin,
                    false,
                    Builtin::Discard,
                    "built-in, discarded",
                    "a discard phrase, handled before any integration",
                    started,
                ),
                Vec::new(),
            );
        }

        let mut pass = self.route_options(&text, transcript);
        let mut all_hooks = std::mem::take(&mut pass.hooks);
        if pass.options.iter().all(|option| option.weak)
            && let Some((retry_text, retry_raw, mut retry)) =
                self.retry_after_correction(&text, transcript, &mut all_hooks)
        {
            all_hooks.append(&mut retry.hooks);
            step.raw_transcript = retry_raw;
            step.corrected = Some(retry_text.clone());
            text = retry_text;
            step.normalized.clone_from(&text);
            pass = retry;
        }
        let forced_file = pass.forced.is_some();
        let mut near_misses = false;
        if pass.options.is_empty() && !forced_file && !context.in_sequence && !context.in_session_turn {
            near_misses = true;
            let (options, mut hooks) = self.near_miss_options(&text, transcript, &mut pass);
            all_hooks.append(&mut hooks);
            pass.options = options;
        }

        step.forced_integration = pass.forced;
        if let Some(index) = pass.forced {
            let name = self.config.integrations[index].file.clone();
            let shown = name.file_name().unwrap_or_default().to_string_lossy().into_owned();
            if pass.surface {
                step.surface = Some(shown);
            } else {
                step.forced = Some(shown);
            }
        }
        let untried = untried_reason(self.config, pass.forced, pass.surface);
        step.integrations = pass
            .traces
            .into_iter()
            .enumerate()
            .map(|(index, trace)| {
                trace.unwrap_or_else(|| {
                    let integration = &self.config.integrations[index];
                    IntegrationTrace {
                        name: integration.name.clone(),
                        file: integration.file.clone(),
                        tier: tier_of(integration.tier),
                        outcome: IntegrationOutcome::NotTried { reason: untried(index) },
                        rejected: Vec::new(),
                    }
                })
            })
            .collect();
        step.hooks = all_hooks;
        step.options = pass.options.iter().map(|option| self.option_trace(option)).collect();
        step.decision = decide(&pass.options, near_misses, &step);
        step.ran = !pass.options.is_empty();
        step.millis = elapsed_without_resolving(started, self.resolve_wall.get());
        (step, pass.options)
    }

    fn option_trace(&self, option: &RouteOption) -> OptionTrace {
        let env = match self.config.integrations[option.integration].format {
            Format::Bash => BTreeMap::from([
                ("id".to_string(), option.id.clone()),
                ("target".to_string(), option.target.clone()),
            ]),
            Format::Toml => {
                let mut env = resolve::arg_env(&option.args);
                env.insert("VOXCMD_ID".to_string(), option.id.clone());
                env
            }
        };
        let integration = &self.config.integrations[option.integration];
        OptionTrace {
            toast_label: toast_label(integration, option),
            integration: option.name.clone(),
            file: option.file.clone(),
            fallback: option.fallback,
            action: option.action.clone(),
            target: option.target.clone(),
            id: option.id.clone(),
            label: option.label.clone(),
            score: None,
            weak: option.weak,
            near_miss: option.near_miss,
            confirm: option.confirm.clone(),
            silent: option.silent,
            candidates: option.candidates,
            command: option.command.clone(),
            env,
        }
    }

    /// What a text routes to, in the order the tiers are tried: a forced integration alone, else the open surface
    /// when it takes the phrase, else the normal tier, then the fallback tier if that left nothing.
    fn route_options(&self, text: &str, raw: &str) -> Pass {
        let mut pass = Pass::new(self.config.integrations.len());
        if let Some((index, rest)) = self.matcher.forced(text) {
            pass.forced = Some(index);
            self.try_tier(&mut pass, &[index], &rest, RouteTier::Forced, raw);
            return pass;
        }
        if let Some(index) = self.open_surface() {
            let mut attempt = Pass::new(self.config.integrations.len());
            self.try_tier(&mut attempt, &[index], text, RouteTier::Surface, raw);
            if !attempt.options.is_empty() {
                attempt.forced = Some(index);
                attempt.surface = true;
                return attempt;
            }
            pass.hooks = attempt.hooks;
        }
        let normal: Vec<usize> = self.matcher.tier(Tier::Normal).collect();
        self.try_tier(&mut pass, &normal, text, RouteTier::Normal, raw);
        if pass.options.is_empty() {
            let fallback: Vec<usize> = self.matcher.tier(Tier::Fallback).collect();
            self.try_tier(&mut pass, &fallback, text, RouteTier::Fallback, raw);
        }
        pass
    }

    /// The first integration, in file order, whose bar surface is open. Asking the bar is a hook call, so its time
    /// is left out of the step's `millis` like any other.
    fn open_surface(&self) -> Option<usize> {
        let started = Instant::now();
        let open = self
            .config
            .integrations
            .iter()
            .position(|integration| integration.surface.is_some() && self.hooks.surface_open(integration));
        if self
            .config
            .integrations
            .iter()
            .any(|integration| integration.surface.is_some())
        {
            self.resolve_wall.set(self.resolve_wall.get() + started.elapsed());
        }
        open
    }

    /// Matches the text against each integration's verbs (the first match of each counts) and resolves the matches,
    /// adding their options in integration order.
    fn try_tier(&self, pass: &mut Pass, integrations: &[usize], text: &str, tier: RouteTier, raw: &str) {
        let mut pending = Vec::new();
        for &index in integrations {
            let found = self.matcher.first_match(index, text);
            let (trace, matched) = self.trace_match(index, tier, found);
            pass.traces[index] = Some(trace);
            if let Some(matched) = matched {
                pending.push(PendingMatch::from_args(
                    index,
                    self.config,
                    &matched.action,
                    matched.args,
                ));
            }
        }
        for (one, resolved) in pending.iter().zip(self.resolve(
            &pending,
            Texts {
                phrase: text,
                raw_transcript: raw,
            },
        )) {
            self.take(pass, one.integration, resolved);
        }
    }

    fn resolve(&self, pending: &[PendingMatch], texts: Texts) -> Vec<Resolved> {
        let started = Instant::now();
        let resolved = resolve::resolve_all(self.config, &self.hooks, pending, texts);
        if resolved.iter().any(|one| one.hook.is_some()) {
            self.resolve_wall.set(self.resolve_wall.get() + started.elapsed());
        }
        resolved
    }

    fn take(&self, pass: &mut Pass, integration: usize, resolved: Resolved) {
        if let Some(hook) = resolved.hook {
            if hook.lookup == Lookup::Yield
                && let Some(trace) = pass.traces[integration].as_mut()
            {
                trace.outcome = IntegrationOutcome::YieldedByHook {
                    action: hook.action.clone(),
                };
            }
            pass.hooks.push(hook);
        }
        pass.options.extend(resolved.options);
    }

    fn verb_ref(&self, integration: usize, verb: usize) -> VerbRef {
        let config = &self.config.integrations[integration];
        VerbRef {
            index: verb,
            line: config.verbs[verb].line,
            action: config.verbs[verb].action.clone(),
            pattern: config.verbs[verb].pattern.clone(),
            regex: self
                .matcher
                .pattern(integration, verb)
                .map(|pattern| pattern.regex.clone())
                .unwrap_or_default(),
        }
    }

    /// The arguments a TOML verb's near miss read from the phrase, so that its command gets its number as an exact match
    /// would. A legacy verb keeps none: the bash near miss passed only the target.
    fn near_miss_args(&self, index: usize, verb: usize, miss: &NearMiss) -> Vec<Arg> {
        if self.config.integrations[index].format == Format::Bash {
            return Vec::new();
        }
        let Ok(pattern) = self.matcher.pattern(index, verb) else {
            return Vec::new();
        };
        pattern
            .placeholders
            .iter()
            .map(|placeholder| {
                let words = match placeholder.kind {
                    PlaceholderType::Text if miss.target_placeholder.as_deref() == Some(placeholder.name.as_str()) => {
                        Some(miss.target.clone())
                    }
                    PlaceholderType::Number => miss
                        .numbers
                        .iter()
                        .find(|(name, _)| *name == placeholder.name)
                        .map(|(_, word)| word.clone()),
                    _ => None,
                };
                Arg {
                    name: placeholder.name.clone(),
                    kind: placeholder.kind,
                    value: words.clone(),
                    words,
                }
            })
            .collect()
    }

    fn trace_match(&self, index: usize, tier: RouteTier, found: IntegrationMatch) -> (IntegrationTrace, Option<Match>) {
        let integration = &self.config.integrations[index];
        let rejections: Vec<Rejection> = found
            .rejections
            .iter()
            .map(|rejection| Rejection {
                verb: self.verb_ref(index, rejection.verb),
                reason: rejection.reason.clone(),
            })
            .collect();
        let (outcome, rejected, matched) = match found.outcome {
            Outcome::Matched(matched) => {
                let args = matched
                    .args
                    .iter()
                    .map(|arg| {
                        (
                            arg.name.clone(),
                            ArgValue {
                                r#type: arg.kind.name().to_string(),
                                value: arg.value.clone(),
                                words: arg.words.clone(),
                            },
                        )
                    })
                    .collect();
                let verb = self.verb_ref(index, matched.verb);
                (IntegrationOutcome::Matched { verb, args }, rejections, Some(matched))
            }
            Outcome::Yielded { verb } => (
                IntegrationOutcome::YieldedByVerb {
                    verb: self.verb_ref(index, verb),
                },
                rejections,
                None,
            ),
            Outcome::NoVerb if !rejections.is_empty() => {
                (IntegrationOutcome::Rejected { verbs: rejections }, Vec::new(), None)
            }
            Outcome::NoVerb => (IntegrationOutcome::NoVerb { near_miss: None }, Vec::new(), None),
        };
        let trace = IntegrationTrace {
            name: integration.name.clone(),
            file: integration.file.clone(),
            tier,
            outcome,
            rejected,
        };
        (trace, matched)
    }

    /// When the text left no strong option, routes what follows the last correction point instead ("exit, exit
    /// overview" is "exit overview"), then earlier points. A retry counts only as one option that is not a weak match;
    /// otherwise routing goes on with what the text as spoken found. Behind a force prefix the correction is read in
    /// the rest of the phrase. The hooks of retries that did not win go to `discarded`.
    fn retry_after_correction(
        &self,
        text: &str,
        raw: &str,
        discarded: &mut Vec<HookRun>,
    ) -> Option<(String, String, Pass)> {
        let (lead, body) = match self.matcher.forced(text) {
            Some((_, rest)) => (text.strip_suffix(rest.as_str()).unwrap_or_default().to_string(), rest),
            None => (String::new(), text.to_string()),
        };
        for tail in correction_tails(&body) {
            let retried = format!("{lead}{tail}");
            // The hooks of every retry still read the whole phrase as spoken: bash rewrites `raw_transcript` only once a
            // retry is accepted, so only the accepted option's action sees the shortened one.
            let mut pass = self.route_options(&retried, raw);
            if pass.options.len() == 1 && !pass.options[0].weak {
                let retried_raw = format!("{lead}{}", self.raw_suffix_of(raw, &tail));
                return Some((retried, retried_raw, pass));
            }
            discarded.append(&mut pass.hooks);
        }
        None
    }

    /// The last words of the raw transcript that normalize (with replacements) to `tail`, or `tail` itself when none do,
    /// so that an action reading the raw transcript still sees its own punctuation.
    pub(super) fn raw_suffix_of(&self, raw: &str, tail: &str) -> String {
        let tokens: Vec<&str> = raw.split_whitespace().collect();
        (1..=tokens.len())
            .map(|size| tokens[tokens.len() - size..].join(" "))
            .find(|suffix| apply_replacements(&normalize(suffix), &self.config.replacements) == tail)
            .unwrap_or_else(|| tail.to_string())
    }

    /// The last tier, for a phrase nothing else could use: every verb whose words are all in the phrase, in any order,
    /// each resolved like a match and all weak so that the picker always asks. The ten with the fewest words left over
    /// come first; two verbs reading the same option offer it once. A target that named no candidate, so that the
    /// integration's `no_match` action took the option, offers nothing.
    fn near_miss_options(&self, text: &str, raw: &str, pass: &mut Pass) -> (Vec<RouteOption>, Vec<HookRun>) {
        let mut pending = Vec::new();
        for index in 0..self.config.integrations.len() {
            let misses = self.matcher.near_misses(index, text);
            if let Some((verb, best)) = misses.iter().min_by_key(|(_, miss)| miss.leftover)
                && let Some(IntegrationTrace {
                    outcome: outcome @ IntegrationOutcome::NoVerb { near_miss: None },
                    ..
                }) = pass.traces[index].as_mut()
            {
                *outcome = IntegrationOutcome::NoVerb {
                    near_miss: Some(NearMissTrace {
                        action: self.config.integrations[index].verbs[*verb].action.clone(),
                        leftover: best.leftover,
                    }),
                };
            }
            for (verb, miss) in misses {
                let action = &self.config.integrations[index].verbs[verb].action;
                let args = self.near_miss_args(index, verb, &miss);
                let mut one = PendingMatch::from_args(index, self.config, action, args);
                one.target = miss.target;
                one.has_target = miss.has_target;
                one.near_miss = Some(miss.leftover);
                pending.push(one);
            }
        }
        let mut options = Vec::new();
        let mut hooks = Vec::new();
        let resolved_all = self.resolve(
            &pending,
            Texts {
                phrase: text,
                raw_transcript: raw,
            },
        );
        for resolved in resolved_all {
            options.extend(
                resolved
                    .options
                    .into_iter()
                    .filter(|option| option.action == option.verb_action),
            );
            hooks.extend(resolved.hook);
        }
        for option in &mut options {
            option.weak = true;
        }
        (rank_near_misses(options), hooks)
    }
}

/// `sort_by(.leftover) | unique_by([.file, .action, .id]) | sort_by(.leftover) | .[:10]`: unique_by leaves the options
/// in key order, so options with equally many words left over end up ordered by file, action and id.
fn rank_near_misses(mut options: Vec<RouteOption>) -> Vec<RouteOption> {
    options.sort_by_key(|option| option.leftover);
    options.sort_by(|a, b| (&a.file, &a.action, &a.id).cmp(&(&b.file, &b.action, &b.id)));
    options.dedup_by(|b, a| (&a.file, &a.action, &a.id) == (&b.file, &b.action, &b.id));
    options.sort_by_key(|option| option.leftover);
    options.truncate(NEAR_MISS_OPTIONS);
    options
}

/// The label a toast or the picker shows for the option (`option_label`): the integration's name, then the action and
/// the candidate, or only the candidate when the action says nothing the integration's name does not. Without
/// `with_candidate` the candidate's label is left out, as a private integration's is (screen text must reach neither
/// the notification history nor the debug log).
pub fn option_label(integration: &Integration, option: &RouteOption, with_candidate: bool) -> String {
    let settings = &integration.settings;
    let label = if with_candidate { option.label.as_str() } else { "" };
    let omits_action = integration.actions.len() == 1 || !settings.action_labels;
    if omits_action && !label.is_empty() {
        return format!("{}: {label}", option.name);
    }
    let action = option.action.replace('_', " ");
    let candidate = if label.is_empty() || label == option.action {
        String::new()
    } else {
        format!(" {label}")
    };
    format!("{}: {action}{candidate}", option.name)
}

/// `option_label` as notifications and logs may show it.
pub fn toast_label(integration: &Integration, option: &RouteOption) -> String {
    option_label(integration, option, !integration.settings.private_labels)
}

fn tier_of(tier: Tier) -> RouteTier {
    match tier {
        Tier::Normal => RouteTier::Normal,
        Tier::Fallback => RouteTier::Fallback,
    }
}

/// Why an integration the pass never reached was left out.
fn untried_reason(config: &Config, forced: Option<usize>, surface: bool) -> impl Fn(usize) -> String + '_ {
    move |index| match forced {
        Some(forced) if surface => format!("the open surface {} took the phrase", config.integrations[forced].name),
        Some(forced) => format!("forced to {}", config.integrations[forced].name),
        None if config.integrations[index].tier == Tier::Fallback => "the normal tier had options".to_string(),
        None => "not tried".to_string(),
    }
}

fn elapsed_without_resolving(started: Instant, resolving: Duration) -> f64 {
    started.elapsed().saturating_sub(resolving).as_secs_f64() * 1000.0
}

fn finish_builtin(
    mut step: StepTrace,
    kind: DecisionKind,
    ran: bool,
    builtin: Builtin,
    result: &str,
    reason: &str,
    started: Instant,
) -> StepTrace {
    step.decision = Decision {
        kind,
        option: None,
        reason: reason.to_string(),
        result: result.to_string(),
    };
    step.ran = ran;
    step.builtin = Some(builtin);
    step.millis = started.elapsed().as_secs_f64() * 1000.0;
    step
}

/// A single option runs unless it is a weak match, which the user picks like any ambiguity.
pub fn needs_pick(options: &[RouteOption]) -> bool {
    options.len() > 1 || options.iter().any(|option| option.weak)
}

fn decide(options: &[RouteOption], near_misses: bool, step: &StepTrace) -> Decision {
    let count = options.len();
    if count == 0 {
        let reason = if let Some(forced) = step.forced.as_ref().or(step.surface.as_ref()) {
            format!("forced to {forced}, and none of its verbs matched the rest")
        } else if near_misses {
            "no verb matched, and no verb nearly matched".to_string()
        } else {
            "no verb matched".to_string()
        };
        return Decision {
            kind: DecisionKind::NoMatch,
            option: None,
            reason,
            result: "no match".to_string(),
        };
    }
    let first = &options[0];
    if needs_pick(options) {
        let (reason, listens) = if count == 1 {
            (
                format!("{} {} is a weak match, so the picker asks", first.name, first.action),
                ", weak match, listens for the reply when spoken",
            )
        } else {
            (format!("{count} options, so the picker asks which"), "")
        };
        return Decision {
            kind: DecisionKind::Pick,
            option: None,
            reason,
            result: format!("ask with the picker ({count} options{listens})"),
        };
    }
    let (kind, how) = match &first.confirm {
        Some(why) => (DecisionKind::Confirm, format!("; it asks first ({why})")),
        None => (DecisionKind::Run, String::new()),
    };
    Decision {
        kind,
        option: Some(0),
        reason: format!("one option, not a weak match: {} {}{how}", first.name, first.action),
        result: "run".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn near_misses_rank_by_leftover_then_by_key() {
        let option = |file: &str, action: &str, id: &str, leftover: usize| RouteOption {
            integration: 0,
            name: String::new(),
            file: file.into(),
            fallback: false,
            action: action.into(),
            verb_action: action.into(),
            target: String::new(),
            args: Vec::new(),
            id: id.into(),
            label: String::new(),
            command: String::new(),
            weak: true,
            silent: false,
            confirm: None,
            candidates: 0,
            near_miss: true,
            leftover,
        };
        let ranked = rank_near_misses(vec![
            option("b.sh", "x", "1", 2),
            option("a.sh", "y", "1", 2),
            option("a.sh", "x", "1", 3),
            option("a.sh", "x", "1", 1),
            option("a.sh", "y", "1", 5),
        ]);
        let order: Vec<(&str, &str, usize)> = ranked
            .iter()
            .map(|o| (o.file.to_str().unwrap(), o.action.as_str(), o.leftover))
            .collect();
        // a.sh/x keeps its first (leftover 1); a.sh/y keeps leftover 2; ties order by key: a.sh before b.sh.
        assert_eq!(order, [("a.sh", "x", 1), ("a.sh", "y", 2), ("b.sh", "x", 2)]);
    }
}
