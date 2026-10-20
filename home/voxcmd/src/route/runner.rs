//! one live step: route it, then decide between running the option, asking which, and reporting no match (the live
//! half of `route_step`)
//!
//! `Router` decides and never acts; this acts on its decision. A phrase of several steps is `sequence.rs`.
use super::resolve::RouteOption;
use super::router::{Router, StepContext, needs_pick, option_label};
use super::sequence;
use super::sequence_run::Pacing;
use super::trace::Builtin;
use crate::actions::{Runtime, Spoken, StepOutcome, StepResult, run_option};
use crate::ask::{AskWith, PickWith};
use crate::cli::PhraseArgs;
use crate::click::pick::boxed_choices;
use crate::config::Config;
use crate::config::schema::{Format, Picker};
use crate::exit::CliError;
use crate::hooks::{Dispatch, LegacyHooks, ShellHooks};
use crate::log::log_no_match;
use crate::notify::{Desktop, Kind};
use crate::paths;
use crate::process;
use crate::text::wake_word::WAKE_WORD;
use std::cell::RefCell;
use std::collections::BTreeSet;

/// What a `Picker::Hints` integration names as its pick command; `ask` knows it by this name.
const HINTS_COMMAND: &str = "voxcmd-hints";

/// The most options an integration's own picker (numbered boxes on screen) takes; more go to the text picker.
const MAX_BOXED_OPTIONS: usize = 10;

pub struct Runner<'a> {
    pub router: &'a Router<'a>,
    pub rt: &'a Runtime<'a>,
    /// The action of the last option that ran, which a session turn reads to tell what it did (bash
    /// `last_run_action`).
    last_run_action: RefCell<String>,
}

/// How a phrase routed: the exit code `run` gives, and how its last step ended.
#[derive(Debug, Clone, Copy)]
pub struct Routed {
    pub exit_code: i32,
    pub outcome: StepOutcome,
}

impl<'a> Runner<'a> {
    pub fn new(router: &'a Router<'a>, rt: &'a Runtime<'a>) -> Self {
        Self {
            router,
            rt,
            last_run_action: RefCell::default(),
        }
    }

    pub fn last_run_action(&self) -> String {
        self.last_run_action.borrow().clone()
    }

    pub fn forget_last_run_action(&self) {
        self.last_run_action.borrow_mut().clear();
    }

    /// Runs an option chosen outside routing (a mode switch a session turn names).
    pub fn run_option(&self, option: &RouteOption, said: &Spoken) -> StepResult {
        let result = run_option(self.rt, option, said);
        self.note_ran(&result);
        result
    }

    fn note_ran(&self, result: &StepResult) {
        if let Some(option) = &result.ran {
            self.last_run_action.borrow_mut().clone_from(&option.action);
        }
    }

    /// One spoken or typed phrase: one step, or the steps of "and then" in order.
    pub fn route(&self, phrase: &str) -> Routed {
        let split = sequence::split_phrase(self.router, phrase);
        if split.steps.len() == 1 {
            let result = self.route_step(&split.steps[0]);
            Routed {
                exit_code: result.exit_code,
                outcome: result.outcome,
            }
        } else {
            self.route_steps(&split)
        }
    }

    /// One step, as the whole of a phrase.
    pub fn route_step(&self, transcript: &str) -> StepResult {
        self.run_step(transcript, false, "")
    }

    /// The steps as one sequence, which may be refused before any runs.
    pub fn route_steps(&self, steps: &sequence::Steps) -> Routed {
        self.run_sequence(steps, &Pacing::from_env())
    }

    /// Routes the step and acts on it. In a sequence it sends no no-match toast and does not open Voice Help: the
    /// sequence reports the step it stopped at.
    pub fn run_step(&self, transcript: &str, in_sequence: bool, active_before: &str) -> StepResult {
        let (step, options) = self.router.route_step_with_options(
            transcript,
            StepContext {
                in_sequence,
                in_session_turn: self.rt.in_session_turn,
            },
        );
        match step.builtin {
            Some(Builtin::OnlyWakeWord) => {
                if !in_sequence {
                    self.rt
                        .notifier
                        .notify(Kind::Info, "voxcmd", &format!("Say a command after \"{WAKE_WORD}\""));
                }
                // Nothing was asked of it, so this is not a failure.
                return StepResult::new(StepOutcome::NoMatch).with_exit_code(0);
            }
            Some(Builtin::VoiceHelp) => {
                return StepResult::new(StepOutcome::Cancelled).with_exit_code(crate::help::run(self));
            }
            Some(Builtin::VoiceHelpInSequence) => return StepResult::new(StepOutcome::NoMatch),
            Some(Builtin::Discard) => return StepResult::new(StepOutcome::Discarded),
            None => {}
        }
        let integrations = &self.rt.config.integrations;
        if options.is_empty() {
            let private = step
                .forced_integration
                .is_some_and(|index| integrations[index].settings.private_labels);
            // Kept out, as the debug log keeps them out: a transcript heard in a private mode, and a session's turns,
            // which its mode may take as dictation.
            if !self.rt.heard_private && !self.rt.in_session_turn {
                log_no_match(&step.normalized, private);
            }
            if !in_sequence {
                self.rt
                    .notifier
                    .notify(Kind::NoMatch, "voxcmd: no match", &format!("\"{transcript}\""));
            }
            return StepResult::new(StepOutcome::NoMatch);
        }
        let said = Spoken {
            phrase: &step.normalized,
            raw_transcript: &step.raw_transcript,
            active_before,
            in_sequence,
        };
        // Stop Voice may have flagged the sequence while routing ran (a slow hook, the window query); bash looked only
        // at the top of the step, so this is stricter on purpose: nothing runs after the user said stop.
        if in_sequence && super::sequence_run::sequence_stopped() {
            return StepResult::new(StepOutcome::Discarded);
        }
        let mut result = if needs_pick(&options) {
            self.pick_and_run(&options, &said)
        } else {
            run_option(self.rt, &options[0], &said)
        };
        self.note_ran(&result);
        result.phrase.clone_from(&step.normalized);
        result.raw_transcript.clone_from(&step.raw_transcript);
        result
    }

    fn pick_and_run(&self, options: &[RouteOption], said: &Spoken) -> StepResult {
        let choices = choices_json(self.rt, options);
        let command;
        let listen_wanted = self.rt.reply_listen_wanted();
        // An integration's own picker (numbers on screen) is answered by voice whenever the command was, since the user
        // is looking at it. The text picker is when it asks only "this one?" (a single weak match), as a confirmation
        // is, or in a session turn, where nobody is at the keyboard.
        let (with, label, choices, listen) = match self.integration_pick(options, &choices) {
            Some((own_command, boxed)) => {
                command = own_command;
                (PickWith::Command(&command), "Which one?", boxed, listen_wanted)
            }
            None => {
                let listen = listen_wanted && (options.len() == 1 || self.rt.in_session_turn);
                (PickWith::Picker, "Which command?", choices, listen)
            }
        };
        match self.rt.asker.pick(&with, label, &choices, listen) {
            Some(index) if index < options.len() => run_option(self.rt, &options[index], said),
            _ => StepResult::new(StepOutcome::Cancelled),
        }
    }

    /// The command and choices of an integration's own picker, when every option comes from one integration whose
    /// options can be placed on screen (click's numbered boxes); else none, and the text picker asks. A built-in
    /// picker reads each id's box itself; a bash integration's `pick_box` is asked through the bridge.
    fn integration_pick(&self, options: &[RouteOption], choices: &str) -> Option<(String, String)> {
        let files: BTreeSet<_> = options.iter().map(|option| &option.file).collect();
        if files.len() != 1 || options.len() > MAX_BOXED_OPTIONS {
            return None;
        }
        let integration = &self.rt.config.integrations[options[0].integration];
        if integration.picker == Some(Picker::Hints) {
            let ids: Vec<&str> = options.iter().map(|option| option.id.as_str()).collect();
            return Some((HINTS_COMMAND.to_string(), boxed_choices(choices, &ids)?));
        }
        if integration.format != Format::Bash {
            return None;
        }
        let mut command = self.rt.legacy.call("pick-boxes", integration);
        command
            .arg(choices)
            .args(options.iter().map(|option| option.id.as_str()));
        let outcome = process::run_to_end(&mut command).ok()?;
        if outcome.code() != Some(0) {
            return None;
        }
        let (command_path, boxed) = outcome.stdout.split_once('\n')?;
        Some((command_path.to_string(), boxed.trim_end().to_string()))
    }
}

/// `[{"id": "<index>", "label": "<label>"}, ...]`: what the picker shows, answered with the index.
fn choices_json(rt: &Runtime, options: &[RouteOption]) -> String {
    let choices: Vec<_> = options
        .iter()
        .enumerate()
        .map(|(index, option)| {
            let integration = &rt.config.integrations[option.integration];
            serde_json::json!({"id": index.to_string(), "label": option_label(integration, option, true)})
        })
        .collect();
    serde_json::Value::Array(choices).to_string()
}

/// `voxcmd run <phrase>`: one step, or the steps of "and then" in order. Exit 0 when the user decided (it ran, or was
/// cancelled, declined or discarded), 1 when nothing matched, the action failed or no step of a sequence ran.
pub fn run(args: PhraseArgs) -> Result<(), CliError> {
    let phrase = args.phrase.join(" ");
    let exit_code = with_runner(&Heard::default(), |runner| runner.route(&phrase).exit_code)?;
    if exit_code == 0 {
        Ok(())
    } else {
        Err(CliError::quiet("run"))
    }
}

/// A transcript a watcher heard, routed as `run` routes a phrase; the exit code `run` would have.
pub fn run_spoken(transcript: &str, heard: &Heard) -> i32 {
    with_runner(heard, |runner| runner.route(transcript).exit_code).unwrap_or_else(|error| {
        eprintln!("{error}");
        1
    })
}

/// How a phrase arrived; the default is typed.
#[derive(Debug, Default)]
pub struct Heard {
    /// Spoken: a watcher routes it.
    pub by_voice: bool,
    /// The mode it was heard in keeps what is said out of the logs.
    pub private: bool,
    /// The session mode it was heard in (`session::mode_token`), as the watcher was told; bash `$heard_mode`.
    pub mode: String,
    /// A voice session's turn.
    pub in_session_turn: bool,
}

/// Loads the configuration and hands `act` a runner over it.
pub fn with_runner<R>(heard: &Heard, act: impl FnOnce(&Runner) -> R) -> Result<R, CliError> {
    let config_dir = paths::config_dir();
    let config = Config::load(&config_dir).map_err(|message| CliError::usage("run", message))?;
    let shell = ShellHooks::for_config_dir(&config_dir);
    let legacy = LegacyHooks::new(config_dir);
    let hooks = Dispatch::new(
        shell.clone(),
        Box::new(LegacyHooks::with_bin(paths::legacy_bin(), paths::config_dir())),
    );
    let router = Router::new(&config, &hooks);
    let asker = AskWith::from_env();
    let runtime = Runtime {
        config: &config,
        shell: &shell,
        legacy: &legacy,
        asker: &asker,
        notifier: &Desktop,
        came_by_voice: heard.by_voice,
        heard_private: heard.private,
        heard_mode: &heard.mode,
        in_session_turn: heard.in_session_turn,
    };
    Ok(act(&Runner::new(&router, &runtime)))
}
