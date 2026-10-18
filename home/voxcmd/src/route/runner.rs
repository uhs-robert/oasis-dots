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
use crate::config::Config;
use crate::config::schema::Format;
use crate::exit::CliError;
use crate::hooks::{Dispatch, LegacyHooks, ShellHooks};
use crate::log::log_no_match;
use crate::notify::{self, Desktop, Kind};
use crate::paths;
use crate::process;
use crate::text::wake_word::WAKE_WORD;
use std::collections::BTreeSet;

/// The most options an integration's own picker (numbered boxes on screen) takes; more go to the text picker.
const MAX_BOXED_OPTIONS: usize = 10;

pub struct Runner<'a> {
    pub router: &'a Router<'a>,
    pub rt: &'a Runtime<'a>,
}

impl Runner<'_> {
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
                eprintln!("voxcmd: help: not implemented yet (2.6)");
                return StepResult::new(StepOutcome::Cancelled).with_exit_code(1);
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

    /// The command and choices of an integration's own picker, when every option comes from one bash integration whose
    /// `pick_box` places each option on screen (click's numbered boxes); else none, and the text picker asks. A TOML
    /// integration has none until 2.5.
    fn integration_pick(&self, options: &[RouteOption], choices: &str) -> Option<(String, String)> {
        let files: BTreeSet<_> = options.iter().map(|option| &option.file).collect();
        if files.len() != 1 || options.len() > MAX_BOXED_OPTIONS {
            return None;
        }
        let integration = &self.rt.config.integrations[options[0].integration];
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
    let exit_code = route_phrase(&args.phrase.join(" "), Heard::Typed)?;
    if exit_code == 0 {
        Ok(())
    } else {
        Err(CliError::quiet("run"))
    }
}

/// A transcript a watcher heard, routed as `run` routes a phrase; the exit code `run` would have. `heard_private`: the
/// mode it was heard in keeps what is said out of the logs.
pub fn run_spoken(transcript: &str, heard_private: bool) -> i32 {
    route_phrase(transcript, Heard::Spoken { heard_private }).unwrap_or_else(|error| {
        eprintln!("{error}");
        1
    })
}

/// How the phrase arrived.
#[derive(Clone, Copy)]
enum Heard {
    Typed,
    Spoken { heard_private: bool },
}

fn route_phrase(phrase: &str, heard: Heard) -> Result<i32, CliError> {
    let config_dir = paths::config_dir();
    let config = Config::load(&config_dir).map_err(|message| CliError::usage("run", message))?;
    let stems = || config.integrations.iter().map(|integration| integration.stem.clone());
    let shell = ShellHooks::new(&config_dir, stems(), notify::dry_run());
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
        came_by_voice: matches!(heard, Heard::Spoken { .. }),
        heard_private: matches!(heard, Heard::Spoken { heard_private: true }),
        // A session's turns are the bash voxcmd's until voxcmd-port 2.4c.
        in_session_turn: false,
    };
    let runner = Runner {
        router: &router,
        rt: &runtime,
    };
    let split = sequence::split_phrase(&router, phrase);
    Ok(if split.steps.len() == 1 {
        runner.run_step(&split.steps[0], false, "").exit_code
    } else {
        runner.run_sequence(&split, &Pacing::from_env())
    })
}
