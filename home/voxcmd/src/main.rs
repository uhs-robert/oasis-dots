//! parses argv (cli), dispatches to the subcommand's module; no logic
mod actions;
mod ask;
mod bar;
mod cli;
mod click;
mod config;
mod debug;
mod exit;
mod hooks;
mod hypr;
mod log;
mod notify;
mod paths;
mod process;
mod route;
mod session;
mod text;
mod timer;
mod voice;

use clap::{CommandFactory, FromArgMatches};
use cli::{
    AskCommand, Cli, Command, IntegrationsCommand, InternalCommand, LogCommand, SessionCommand, TimerCommand,
    UtilCommand, WakeCommand,
};
use exit::CliError;
use std::io::Write;
use std::process::ExitCode;

/// The bash script's underscore entry points, which callers still run at the top level (`voxcmd _wake-confirm`):
/// each is routed to `internal`, whose subcommands take these spellings as aliases.
const LEGACY_INTERNAL: [&str; 5] = [
    "_watch",
    "_settle",
    "_cancel_owned_recording",
    "_wake-confirm",
    "_chain-stop",
];

fn main() -> ExitCode {
    let mut args: Vec<std::ffi::OsString> = std::env::args_os().collect();
    if args
        .get(1)
        .and_then(|arg| arg.to_str())
        .is_some_and(|arg| LEGACY_INTERNAL.contains(&arg))
    {
        args.insert(1, "internal".into());
    }
    let matches = Cli::command().version(version()).get_matches_from(args);
    let cli = Cli::from_arg_matches(&matches).unwrap_or_else(|error| error.exit());
    match dispatch(cli.command) {
        Ok(Some(output)) => {
            // A closed pipe (`| head`) is the reader's choice, not a failure.
            let _ = writeln!(std::io::stdout(), "{output}");
            ExitCode::SUCCESS
        }
        Ok(None) => ExitCode::SUCCESS,
        Err(error) => {
            if !error.message.is_empty() {
                eprintln!("{error}");
            }
            error.exit_code()
        }
    }
}

/// `0.1.0 (abc1234)`: the hash is `VOXCMD_GIT_HASH` at build time (`just voxcmd-build` sets it), absent in a plain build.
fn version() -> &'static str {
    let version = match option_env!("VOXCMD_GIT_HASH") {
        Some(hash) if !hash.is_empty() => format!("{} ({hash})", env!("CARGO_PKG_VERSION")),
        _ => env!("CARGO_PKG_VERSION").to_string(),
    };
    Box::leak(version.into_boxed_str())
}

/// Each arm either calls the handler in the module the CLI table names, or names the port item that adds it.
fn dispatch(command: Command) -> Result<Option<String>, CliError> {
    let later = |subcommand: &str, phase_item: &str| Err(CliError::not_implemented(subcommand, phase_item));
    match command {
        Command::Run(args) => route::runner::run(args).map(|()| None),
        Command::Explain(args) => route::trace::run(args).map(Some),
        Command::Reply(args) => ask::reply::run(args),
        Command::Listen { start_only } => voice::listen::run(start_only).map(|()| None),
        Command::Stop => voice::stop::run().map(|()| None),
        Command::Session(SessionCommand::End) => {
            session::run_end();
            Ok(None)
        }
        Command::Session(SessionCommand::Rapid) => route::runner::run(cli::PhraseArgs {
            phrase: vec!["rapid mode".to_string()],
        })
        .map(|()| None),
        Command::Ask(AskCommand::Pick {
            ask,
            label,
            choices_json,
            expansions_json,
        }) => ask::pick::run(ask.listen, &label, &choices_json, expansions_json.as_deref()),
        Command::Ask(AskCommand::Confirm { ask, verb, question }) => {
            ask::confirm::run(ask.listen, verb.as_deref(), &question).map(|()| None)
        }
        Command::Ask(AskCommand::Hints {
            ask,
            label,
            choices_json,
        }) => ask::hints::run(ask.listen, &label, &choices_json),
        Command::Wake(WakeCommand::Listen { .. }) => later("wake listen", "4.1"),
        Command::Wake(WakeCommand::On) => voice::wake_switch::run(voice::wake_switch::Switch::On),
        Command::Wake(WakeCommand::Off) => voice::wake_switch::run(voice::wake_switch::Switch::Off),
        Command::Wake(WakeCommand::Toggle) => voice::wake_switch::run(voice::wake_switch::Switch::Toggle),
        Command::Wake(WakeCommand::Status) => voice::wake_switch::run(voice::wake_switch::Switch::Status),
        Command::Integrations(IntegrationsCommand::List(_)) => later("integrations list", "2.6"),
        Command::Integrations(IntegrationsCommand::Check { .. }) => later("integrations check", "2.6"),
        Command::Integrations(IntegrationsCommand::Examples { .. }) => later("integrations examples", "2.6"),
        Command::Integrations(IntegrationsCommand::Schema) => later("integrations schema", "2.6"),
        Command::Help => later("help", "2.6"),
        Command::Log(LogCommand::Misses { json, count }) => log::misses(count, json.json),
        Command::Log(LogCommand::Errors { json, count }) => log::errors(count, json.json),
        Command::Timer(TimerCommand::Ring { summary, body }) => timer::ring(&summary, &body).map(|()| None),
        Command::Util(UtilCommand::Notify { level, title, body }) => notify::run(&level, &title, &body).map(|()| None),
        Command::Util(UtilCommand::Intents { name }) => config::intents::run(&name).map(Some),
        Command::Util(UtilCommand::WordMatch { ignore, target }) => {
            route::resolve::run_word_match(ignore.as_deref(), &target).map(Some)
        }
        Command::Util(UtilCommand::Speech(speech)) => text::speech::run(speech).map(Some),
        Command::Util(UtilCommand::VoiceEnv { key }) => config::voice_env::run(&key).map(Some),
        Command::Internal(InternalCommand::Watch(args)) => voice::watch::run(&args.args).map(|()| None),
        Command::Internal(InternalCommand::Settle(_)) => voice::settle::run().map(|()| None),
        Command::Internal(InternalCommand::CancelOwnedRecording(args)) => {
            ask::run_cancel_owned_recording(&args.args).map(|()| None)
        }
        Command::Internal(InternalCommand::WakeConfirm(args)) => voice::wake_confirm::run(&args.args),
        Command::Internal(InternalCommand::ChainStop(args)) => voice::chain_stop::run(&args.args).map(|()| None),
        Command::Internal(InternalCommand::Session(args)) => session::bridge::run(&args.args),
        Command::Internal(InternalCommand::ClickMatch(args)) => click::internal::click_match(&args),
        Command::Internal(InternalCommand::ClickOcr(args)) => click::internal::click_ocr(&args.args),
        Command::Internal(InternalCommand::ClickAt(args)) => click::internal::click_at(&args),
    }
}
