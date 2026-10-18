//! running a chosen option: ask first when it asks, run its action, say what happened (was `run_option`)
//!
//! An action is the integration's `run` string: TOML ones through the same `bash -c` wrapper hooks use, bash ones
//! through the bash voxcmd's `_legacy-hook run` (which sets the globals the real actions read). Unlike a hook an action
//! has no deadline; it leads a process group of its own, so Stop Voice (SIGTERM to voxcmd) ends it.
use crate::ask::Asker;
use crate::config::Config;
use crate::config::schema::{Format, Integration};
use crate::debug::debug;
use crate::hooks::{HookEnv, LegacyHooks, ShellHooks, tail_lines};
use crate::notify::{Kind, Notifier};
use crate::process::{self, Outcome};
use crate::route::resolve::RouteOption;
use crate::route::router::{option_label, toast_label};
use crate::text::normalize::normalize;
use std::process::Command;

/// Everything running a step needs from outside the phrase.
pub struct Runtime<'a> {
    pub config: &'a Config,
    pub shell: &'a ShellHooks,
    pub legacy: &'a LegacyHooks,
    pub asker: &'a dyn Asker,
    pub notifier: &'a dyn Notifier,
    /// The phrase was spoken: a watcher routes it, so a question it asks records the answer by voice too, and the
    /// watcher's discard flag (which Stop Voice sets) is its recording's as well as its sequence's.
    pub came_by_voice: bool,
    /// The mode the phrase was heard in is private (type mode): nothing of it goes to the no-match log.
    pub heard_private: bool,
    /// A voice session's turn: nobody is at the keyboard, so every picker listens.
    pub in_session_turn: bool,
}

impl Runtime<'_> {
    /// A question asked now records its spoken answer: the command was spoken, and Stop Voice has not discarded this
    /// turn since (an action already routing still finishes, but nothing it opens listens).
    pub fn reply_listen_wanted(&self) -> bool {
        self.came_by_voice && !crate::paths::discard_flag(std::process::id()).exists()
    }
}

/// How a step ended. A sequence goes on only past `Ran`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StepOutcome {
    Ran,
    NoMatch,
    /// A picker was closed.
    Cancelled,
    /// A confirm card was answered no.
    Declined,
    Failed,
    TimedOut,
    /// Stop Voice, or a phrase that throws the command away.
    Discarded,
}

#[derive(Debug)]
pub struct StepResult {
    pub outcome: StepOutcome,
    /// 0 for what the user decided (ran, cancelled, declined, discarded), 1 for the rest.
    pub exit_code: i32,
    /// What a failure names: the option's label, blank for a private one.
    pub label: String,
    /// What a failure reports: the tail of the action's output.
    pub detail: String,
    /// The option that ran, which the wait that follows reads.
    pub ran: Option<RouteOption>,
    /// The step's text as the option saw it: normalized, and as spoken. Set by the runner.
    pub phrase: String,
    pub raw_transcript: String,
}

impl StepResult {
    pub fn with_exit_code(self, exit_code: i32) -> Self {
        Self { exit_code, ..self }
    }

    pub fn new(outcome: StepOutcome) -> Self {
        let exit_code = match outcome {
            StepOutcome::Ran | StepOutcome::Cancelled | StepOutcome::Declined | StepOutcome::Discarded => 0,
            StepOutcome::NoMatch | StepOutcome::Failed | StepOutcome::TimedOut => 1,
        };
        Self {
            outcome,
            exit_code,
            label: String::new(),
            detail: String::new(),
            ran: None,
            phrase: String::new(),
            raw_transcript: String::new(),
        }
    }
}

/// The step's own text, which actions read.
#[derive(Clone, Copy)]
pub struct Spoken<'a> {
    /// Normalized, with replacements applied.
    pub phrase: &'a str,
    /// As spoken, or as shortened by a correction retry.
    pub raw_transcript: &'a str,
    /// The window focused before the step, for waits.
    pub active_before: &'a str,
    /// A sequence reports its steps' failures itself, in one toast.
    pub in_sequence: bool,
}

/// The variables the bash voxcmd's `_legacy-hook run|wait` turn into the globals a bash action reads.
pub fn legacy_env(option: &RouteOption, said: &Spoken, confirmed: bool) -> [(&'static str, String); 5] {
    [
        ("VOXCMD_LEGACY_ID", option.id.clone()),
        ("VOXCMD_LEGACY_TARGET", option.target.clone()),
        ("VOXCMD_LEGACY_CONFIRMED", u8::from(confirmed).to_string()),
        ("VOXCMD_LEGACY_RAW_TRANSCRIPT", said.raw_transcript.to_string()),
        ("VOXCMD_LEGACY_ACTIVE_BEFORE", said.active_before.to_string()),
    ]
}

/// "Apps: close Slack window: Inbox" asks "Close Slack window: Inbox?". Its first word is the verb a spoken "close it"
/// answers yes with.
fn confirm_question(integration_name: &str, label: &str) -> String {
    let label = label.strip_prefix(&format!("{integration_name}: ")).unwrap_or(label);
    let mut chars = label.chars();
    let first: String = chars.next().map(|c| c.to_uppercase().collect()).unwrap_or_default();
    format!("{first}{}?", chars.as_str())
}

pub fn run_option(rt: &Runtime, option: &RouteOption, said: &Spoken) -> StepResult {
    let integration = &rt.config.integrations[option.integration];
    // The label an error toast and the debug log carry is the one without screen text for a private integration.
    let toast = toast_label(integration, option);
    let mut result = StepResult::new(StepOutcome::Failed);
    result.label.clone_from(&toast);
    if option.command.is_empty() {
        result.detail = "has no command".to_string();
        if !said.in_sequence {
            rt.notifier
                .notify(Kind::Error, "voxcmd error", &format!("{toast} has no command"));
        }
        return result;
    }
    let mut confirmed = false;
    if option.confirm.is_some() {
        let question = confirm_question(&integration.name, &option_label(integration, option, true));
        // Not logged with the flags: the verb is the question's first word, which for a private label is screen text.
        let verb = normalize(question.split(' ').next().unwrap_or_default());
        let listen = rt.reply_listen_wanted();
        debug(&format!(
            "confirm asks: {}{}",
            confirm_question(&integration.name, &toast),
            if listen { " (by voice)" } else { "" }
        ));
        if !rt.asker.confirm(&question, &verb, listen) {
            debug(&format!("confirm answered no: {toast} not run"));
            return StepResult {
                label: toast,
                ..StepResult::new(StepOutcome::Declined)
            };
        }
        debug(&format!("confirm answered yes: running {toast}"));
        confirmed = true;
    }
    let started = process::run_to_end(&mut action_command(rt, integration, option, said, confirmed));
    let output = match &started {
        Ok(outcome) => action_output(integration, outcome),
        Err(error) => error.to_string(),
    };
    if started.as_ref().is_ok_and(|outcome| outcome.code() == Some(0)) {
        result.outcome = StepOutcome::Ran;
        result.exit_code = 0;
        result.ran = Some(option.clone());
        // A silent action's own effect (a bar popup it opens) is the feedback, which a toast would only cover.
        if !option.silent {
            let label = option_label(integration, option, true);
            let last = output
                .lines()
                .next_back()
                .map(|line| format!(": {line}"))
                .unwrap_or_default();
            rt.notifier.notify(Kind::Info, "voxcmd", &format!("{label}{last}"));
        }
        return result;
    }
    result.detail = tail_lines(&output, 3).join("\n");
    let how = started.map_or_else(|_| "did not start".to_string(), |outcome| outcome.how_it_ended());
    debug(&format!(
        "action failed: {toast}: {how}{}",
        detail_suffix(integration, &result.detail)
    ));
    if !said.in_sequence {
        let body = if output.is_empty() {
            toast
        } else {
            format!("{toast}: {}", result.detail)
        };
        rt.notifier.notify(Kind::Error, "voxcmd failed", &body);
    }
    result
}

/// The output of a failed action in the debug log, unless the integration's labels are screen text.
fn detail_suffix(integration: &Integration, detail: &str) -> String {
    match detail.lines().next_back() {
        Some(line) if !integration.settings.private_labels => format!(": {line}"),
        _ => String::new(),
    }
}

/// What `$(...)` made of the action's output, without trailing newlines. A TOML action's wrapper already folded the
/// action body's stderr into its stdout, so stderr holds only the `.sh` library's own diagnostics: those go to the debug
/// log, not into the toast. The bash bridge (`_legacy-hook run`) has no such split, so both streams are the output.
fn action_output(integration: &Integration, outcome: &Outcome) -> String {
    let both;
    let text = match integration.format {
        Format::Toml => {
            if !outcome.stderr.is_empty() {
                debug(&format!(
                    "action {}: library stderr: {}",
                    integration.name,
                    outcome.stderr.trim_end_matches('\n')
                ));
            }
            &outcome.stdout
        }
        Format::Bash => {
            both = format!("{}{}", outcome.stdout, outcome.stderr);
            &both
        }
    };
    text.trim_end_matches('\n').to_string()
}

fn action_command(
    rt: &Runtime,
    integration: &Integration,
    option: &RouteOption,
    said: &Spoken,
    confirmed: bool,
) -> Command {
    match integration.format {
        Format::Toml => {
            let env = HookEnv {
                integration,
                action: &option.action,
                args: &option.args,
                phrase: said.phrase,
                raw_transcript: said.raw_transcript,
                id: Some(&option.id),
                label: Some(&option.label),
                confirmed,
                active_before: None,
                spoken: false,
            };
            rt.shell.command(&option.command, &env, true)
        }
        Format::Bash => {
            let mut command = rt.legacy.call("run", integration);
            command.arg(&option.action).envs(legacy_env(option, said, confirmed));
            command
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_confirm_question_drops_the_integration_prefix_and_capitalises() {
        assert_eq!(
            confirm_question("Apps", "Apps: close Slack window: Inbox"),
            "Close Slack window: Inbox?"
        );
        assert_eq!(confirm_question("Apps", "quit it"), "Quit it?");
        assert_eq!(confirm_question("Apps", ""), "?");
    }

    #[test]
    fn what_the_user_decided_exits_zero_and_the_rest_one() {
        use StepOutcome::*;
        for outcome in [Ran, Cancelled, Declined, Discarded] {
            assert_eq!(StepResult::new(outcome).exit_code, 0, "{outcome:?}");
        }
        for outcome in [NoMatch, Failed, TimedOut] {
            assert_eq!(StepResult::new(outcome).exit_code, 1, "{outcome:?}");
        }
        assert_eq!(StepResult::new(NoMatch).with_exit_code(0).exit_code, 0);
    }

    #[test]
    fn the_failure_detail_in_the_debug_log_is_left_out_for_private_labels() {
        let mut integration =
            crate::config::schema::parse_toml(std::path::Path::new("t.toml"), "verbs = []\n").unwrap();
        assert_eq!(detail_suffix(&integration, "a\nb"), ": b");
        assert_eq!(detail_suffix(&integration, ""), "");
        integration.settings.private_labels = true;
        assert_eq!(detail_suffix(&integration, "a\nb"), "");
    }
}
