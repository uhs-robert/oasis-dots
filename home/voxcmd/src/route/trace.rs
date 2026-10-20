//! the `explain` record every stage of routing fills in, its text printout and its `--json` document
//!
//! The text starts with the lines the bash dry run printed (`transcript:`, `normalized:`, `result:`, `option N:`, ...),
//! which run-phrases.sh, bench.sh and owner-test-bar parse, then a blank line and the `why:` block. The JSON shapes
//! follow voxcmd-port 1.3 section 3.3 and are provisional until 3.2: additions are free, renames need the owner.
use super::router::Router;
use super::sequence;
use crate::cli::ExplainArgs;
use crate::click::driver::WindowSel;
use crate::click::explain::{self, ClickTrace, ExplainSink};
use crate::config::Config;
use crate::exit::CliError;
use crate::hooks::{Dispatch, HookRun, Hooks, LegacyHooks, NoHooks, ShellHooks};
use serde::Serialize;
use std::fmt::Write as _;
use std::path::PathBuf;

/// One `voxcmd explain --json` document.
#[derive(Debug, Serialize)]
pub struct Explain {
    /// As given on the command line.
    pub phrase: String,
    /// Set when "and then" split the phrase into steps.
    pub sequence: Option<SequenceTrace>,
    /// One per step; one for a plain phrase; none for a refused sequence.
    pub steps: Vec<StepTrace>,
    /// The click traces (`--window`), one per click the routing asked the screen about; empty when none was.
    pub click: Option<serde_json::Value>,
    /// The reply trace (`--reply`).
    pub reply: Option<crate::ask::reply::ReplyTrace>,
}

#[derive(Debug, Serialize)]
pub struct SequenceTrace {
    /// The steps the phrase split into; one past the limit when it split into more.
    pub steps: usize,
    pub refused: Option<String>,
    pub free_text_step: Option<usize>,
}

#[derive(Debug, Serialize)]
pub struct StepTrace {
    /// The step's raw text.
    pub transcript: String,
    /// The leading wake word that was stripped.
    pub wake_word: Option<String>,
    /// After normalizing, replacements and workspace ordinals; the retry's text when `corrected`.
    pub normalized: String,
    /// What the chosen action reads as the raw transcript: the step as spoken, or, after a correction retry, the
    /// normalized text before the retried part plus the raw words that became it. Hooks always see the step as spoken.
    pub raw_transcript: String,
    /// Which replacements.d lines fired: not recorded yet.
    pub replacements: Vec<serde_json::Value>,
    /// The text retried after a correction point, when the phrase as spoken left no strong option.
    pub corrected: Option<String>,
    /// The integration a force prefix chose.
    pub forced: Option<String>,
    /// The integration whose bar surface was open and took the phrase.
    pub surface: Option<String>,
    pub mode: Option<String>,
    pub rewritten: Option<String>,
    /// Every integration, in the order tried.
    pub integrations: Vec<IntegrationTrace>,
    /// Every hook run, in order, those of discarded passes (a retry that did not win) included.
    pub hooks: Vec<HookRun>,
    /// What the user would be offered, in order.
    pub options: Vec<OptionTrace>,
    pub decision: Decision,
    /// What the next step of a sequence would wait for.
    pub wait: Option<String>,
    /// Route time without the hooks and the target matching that follows them.
    pub millis: f64,
    /// Whether a sequence goes on past this step: it matched something, or was Voice Help outside a sequence.
    #[serde(skip)]
    pub ran: bool,
    /// The phrase was handled before any integration was tried; a live run acts on it without options.
    #[serde(skip)]
    pub builtin: Option<Builtin>,
    /// The integration (index) a force prefix or an open surface chose, for the no-match log.
    #[serde(skip)]
    pub forced_integration: Option<usize>,
}

/// What a phrase handled before any integration was tried is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Builtin {
    OnlyWakeWord,
    VoiceHelp,
    VoiceHelpInSequence,
    Discard,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RouteTier {
    Forced,
    Surface,
    Normal,
    #[allow(
        dead_code,
        reason = "the LLM hook is 2.6; the tier keeps its place in the JSON shape"
    )]
    Llm,
    Fallback,
}

impl RouteTier {
    fn name(self) -> &'static str {
        match self {
            Self::Forced => "forced",
            Self::Surface => "surface",
            Self::Normal => "normal",
            Self::Llm => "llm",
            Self::Fallback => "fallback",
        }
    }
}

#[derive(Debug, Serialize)]
pub struct IntegrationTrace {
    pub name: String,
    pub file: PathBuf,
    pub tier: RouteTier,
    pub outcome: IntegrationOutcome,
    /// Verbs whose regex matched but did not count, before the one that did.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub rejected: Vec<Rejection>,
}

#[derive(Debug, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum IntegrationOutcome {
    Matched {
        verb: VerbRef,
        args: std::collections::BTreeMap<String, ArgValue>,
    },
    NoVerb {
        near_miss: Option<NearMissTrace>,
    },
    /// Verbs matched, and every one was rejected.
    Rejected {
        verbs: Vec<Rejection>,
    },
    YieldedByVerb {
        verb: VerbRef,
    },
    YieldedByHook {
        action: String,
    },
    NotTried {
        reason: String,
    },
}

#[derive(Debug, Clone, Serialize)]
pub struct VerbRef {
    pub index: usize,
    pub line: Option<usize>,
    pub action: String,
    pub pattern: String,
    pub regex: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct Rejection {
    pub verb: VerbRef,
    pub reason: String,
}

#[derive(Debug, Serialize)]
pub struct ArgValue {
    pub r#type: String,
    pub value: Option<String>,
    pub words: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct NearMissTrace {
    pub action: String,
    pub leftover: usize,
}

#[derive(Debug, Serialize)]
pub struct OptionTrace {
    pub integration: String,
    pub file: PathBuf,
    pub fallback: bool,
    pub action: String,
    pub target: String,
    pub id: String,
    pub label: String,
    /// What a toast or the picker shows for the option.
    pub toast_label: String,
    pub score: Option<f64>,
    pub weak: bool,
    pub near_miss: bool,
    /// Why it would ask first: `confirm = true`, or the `confirm_labels` entry its label matches.
    pub confirm: Option<String>,
    pub silent: bool,
    /// How many candidates the hook offered before the target narrowed them.
    pub candidates: usize,
    /// The action's `run` string.
    pub command: String,
    /// What the command can read: a TOML action's `VOXCMD_*` variables, a bash one's `id` and `target`.
    pub env: std::collections::BTreeMap<String, String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DecisionKind {
    Run,
    Confirm,
    Pick,
    NoMatch,
    Builtin,
}

#[derive(Debug, Serialize)]
pub struct Decision {
    pub kind: DecisionKind,
    /// Index into `options` for `run` and `confirm`.
    pub option: Option<usize>,
    /// One sentence: why this and not another outcome.
    pub reason: String,
    /// The text after `result:` in the dry-run lines.
    pub result: String,
}

// ---- text -----------------------------------------------------------------------------------------------------------

/// jq's `@sh` for a string: single-quoted, a quote inside as `'\''`.
fn shell_quote(text: &str) -> String {
    format!("'{}'", text.replace('\'', r"'\''"))
}

fn file_name(path: &std::path::Path) -> String {
    path.file_name().unwrap_or_default().to_string_lossy().into_owned()
}

/// The dry-run lines of one step (the bash `print_dry_run`).
fn step_lines(out: &mut String, step: &StepTrace) {
    let _ = writeln!(out, "transcript:  {}", step.transcript);
    let _ = writeln!(out, "normalized:  {}", step.normalized);
    if step.corrected.is_some() {
        out.push_str("corrected:   no match as spoken, retried after the last correction point\n");
    }
    if let Some(forced) = step.forced.as_ref().or(step.surface.as_ref()) {
        let _ = writeln!(out, "forced to:   {forced}");
    }
    let _ = writeln!(out, "result:      {}", step.decision.result);
    for (index, option) in step.options.iter().enumerate() {
        let fallback = if option.fallback { " [fallback]" } else { "" };
        let near = if option.near_miss { " [near miss]" } else { "" };
        let _ = writeln!(
            out,
            "option {}:    {} ({}){fallback}{near} action={} target={} id={} label={}",
            index + 1,
            option.integration,
            file_name(&option.file),
            option.action,
            shell_quote(&option.target),
            shell_quote(&option.id),
            shell_quote(&option.label)
        );
        let _ = writeln!(
            out,
            "             candidates offered: {}, weak: {}, confirm: {}, silent: {}",
            option.candidates,
            option.weak,
            option.confirm.is_some(),
            option.silent
        );
        let _ = writeln!(out, "             command: {}", option.command);
    }
}

fn verb_text(verb: &VerbRef) -> String {
    match verb.line {
        Some(line) => format!("verb {} (line {line})", verb.index),
        None => format!("verb {}", verb.index),
    }
}

/// The `why:` lines of one step: the decision, each integration that did more than find no verb, then the hooks.
fn why_lines(out: &mut String, step: &StepTrace, prefix: &str) {
    let _ = writeln!(out, "  {prefix}{}", step.decision.reason);
    for trace in &step.integrations {
        let who = format!("{} ({}, {})", trace.name, file_name(&trace.file), trace.tier.name());
        for rejection in &trace.rejected {
            let _ = writeln!(
                out,
                "    {who}: {} rejected: {}",
                verb_text(&rejection.verb),
                rejection.reason
            );
        }
        match &trace.outcome {
            IntegrationOutcome::Matched { verb, args } => {
                let args: String = args
                    .iter()
                    .map(|(name, arg)| format!(" {name}={}", arg.words.as_deref().unwrap_or("")))
                    .collect();
                let _ = writeln!(
                    out,
                    "    {who}: matched {} action={}{args}",
                    verb_text(verb),
                    verb.action
                );
            }
            IntegrationOutcome::YieldedByVerb { verb } => {
                let _ = writeln!(out, "    {who}: {} yields to other integrations", verb_text(verb));
            }
            IntegrationOutcome::Rejected { verbs } => {
                for rejection in verbs {
                    let _ = writeln!(
                        out,
                        "    {who}: {} rejected: {}",
                        verb_text(&rejection.verb),
                        rejection.reason
                    );
                }
            }
            IntegrationOutcome::NoVerb { near_miss: Some(near) } => {
                let _ = writeln!(
                    out,
                    "    {who}: near miss, action={} with {} word(s) left over",
                    near.action, near.leftover
                );
            }
            IntegrationOutcome::YieldedByHook { action } => {
                let _ = writeln!(out, "    {who}: the {action} hook yielded");
            }
            IntegrationOutcome::NoVerb { near_miss: None } | IntegrationOutcome::NotTried { .. } => {}
        }
    }
    for hook in &step.hooks {
        let timing = if hook.reused {
            "reused".to_string()
        } else {
            format!("{:.1} ms", hook.millis)
        };
        let _ = writeln!(
            out,
            "    hook {} {}: {} line(s) in {timing}",
            hook.integration,
            hook.action,
            hook.lines.len(),
        );
        if let Some(problem) = &hook.problem {
            let _ = writeln!(
                out,
                "      failed: {problem}; it offers nothing, and no_match is skipped"
            );
        }
        for line in &hook.stderr_tail {
            let _ = writeln!(out, "      stderr: {line}");
        }
    }
    let _ = writeln!(out, "    route time without hooks: {:.2} ms", step.millis);
}

impl Explain {
    pub fn text(&self) -> String {
        let mut out = String::new();
        if let Some(sequence) = &self.sequence {
            let count = if sequence.steps > sequence::MAX_STEPS {
                format!("more than {}", sequence::MAX_STEPS)
            } else {
                sequence.steps.to_string()
            };
            let _ = writeln!(out, "sequence:    {count} steps");
            if let Some(refusal) = &sequence.refused {
                let _ = writeln!(out, "result:      refused, {refusal}");
            }
        }
        // A sequence stopped at a step that did not run lists fewer steps than it has.
        let total = self
            .sequence
            .as_ref()
            .map_or(self.steps.len(), |sequence| sequence.steps);
        for (index, step) in self.steps.iter().enumerate() {
            if self.sequence.is_some() {
                let _ = writeln!(out, "step {} of {total}", index + 1);
            }
            step_lines(&mut out, step);
            if self.sequence.as_ref().and_then(|sequence| sequence.free_text_step) == Some(index + 1) {
                out.push_str("note:        a free-text action takes the rest of the phrase\n");
            }
            if let Some(wait) = &step.wait {
                let _ = writeln!(out, "waits for:   {wait}");
            }
        }
        out.push_str("\nwhy:\n");
        if let Some(refusal) = self.sequence.as_ref().and_then(|sequence| sequence.refused.as_ref()) {
            let _ = writeln!(out, "  refused before any step was routed: {refusal}");
        }
        for (index, step) in self.steps.iter().enumerate() {
            let prefix = if self.sequence.is_some() {
                format!("step {}: ", index + 1)
            } else {
                String::new()
            };
            why_lines(&mut out, step, &prefix);
        }
        out.truncate(out.trim_end().len());
        out
    }
}

/// The window `--window` names: `focused`, or a Hyprland stable id.
fn window_of(name: &str) -> Result<WindowSel, CliError> {
    match name {
        "" => Err(CliError::usage(
            "explain",
            "--window needs `focused` or a window's stable id",
        )),
        "focused" => Ok(WindowSel::Focused),
        id => Ok(WindowSel::StableId(id.to_string())),
    }
}

/// `voxcmd explain <phrase>`.
pub fn run(args: ExplainArgs) -> Result<String, CliError> {
    if args.reply {
        if args.window.is_some() {
            return Err(CliError::usage("explain", "--window and --reply cannot be combined"));
        }
        return crate::ask::reply::explain(&args.phrase.join(" "), args.json);
    }
    let window = args.window.as_deref().map(window_of).transpose()?;
    let config_dir = crate::paths::config_dir();
    let config = Config::load(&config_dir).map_err(|message| CliError::usage("explain", message))?;
    let sink = ExplainSink::default();
    // A dump given as a file turns every hook off, TOML ones too: the latency test routes phrases that reach TOML
    // hooks, and a bash start per hook would measure bash, not routing.
    let hooks: Box<dyn Hooks> = if crate::paths::legacy_dump_override().is_some() {
        Box::new(NoHooks)
    } else {
        // A dry run: a hook that toasts prints it to stderr instead.
        let shell = ShellHooks::new(
            &config_dir,
            config.integrations.iter().map(|integration| integration.stem.clone()),
            true,
        );
        let dispatch = Dispatch::new(shell, Box::new(LegacyHooks::new(config_dir)));
        match window {
            // The click section comes from the capture the routing makes, so there is one capture, not two.
            Some(window) => Box::new(dispatch.tracing(window, ExplainSink::clone(&sink))),
            None => Box::new(dispatch),
        }
    };
    let router = Router::new(&config, hooks.as_ref());
    let mut explain = sequence::explain_phrase(&router, &args.phrase.join(" "));
    let traces: Vec<ClickTrace> = std::mem::take(&mut *sink.lock().expect("no panic holds the lock"));
    if args.window.is_some() {
        explain.click = Some(serde_json::Value::Array(traces.iter().map(ClickTrace::json).collect()));
    }
    if args.json {
        serde_json::to_string_pretty(&explain).map_err(|error| CliError::failed("explain", error.to_string()))
    } else if args.window.is_some() {
        Ok(format!("{}\n\n{}", explain.text(), explain::sections_text(&traces)))
    } else {
        Ok(explain.text())
    }
}
