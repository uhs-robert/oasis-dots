//! parses argv (cli), dispatches to the subcommand's module; no logic
mod cli;
mod config;
mod exit;
mod hooks;
mod notify;
mod paths;
mod process;
mod route;
mod text;

use clap::{CommandFactory, FromArgMatches};
use cli::{
    AskCommand, Cli, Command, IntegrationsCommand, InternalCommand, LogCommand, TimerCommand, UtilCommand, WakeCommand,
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
            eprintln!("{error}");
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
        Command::Run(_) => later("run", "2.3"),
        Command::Explain(args) => route::trace::run(args).map(Some),
        Command::Reply(_) => later("reply", "2.4"),
        Command::Listen { .. } => later("listen", "2.4"),
        Command::Stop => later("stop", "2.4"),
        Command::Session(_) => later("session", "2.4"),
        Command::Ask(AskCommand::Pick { .. }) => later("ask pick", "2.4"),
        Command::Ask(AskCommand::Confirm { .. }) => later("ask confirm", "2.4"),
        Command::Ask(AskCommand::Hints { .. }) => later("ask hints", "2.4"),
        Command::Wake(WakeCommand::Listen { .. }) => later("wake listen", "4.1"),
        Command::Wake(_) => later("wake", "2.6"),
        Command::Integrations(IntegrationsCommand::List(_)) => later("integrations list", "2.6"),
        Command::Integrations(IntegrationsCommand::Check { .. }) => later("integrations check", "2.6"),
        Command::Integrations(IntegrationsCommand::Examples { .. }) => later("integrations examples", "2.6"),
        Command::Integrations(IntegrationsCommand::Schema) => later("integrations schema", "2.6"),
        Command::Help => later("help", "2.6"),
        Command::Log(LogCommand::Misses { .. }) => later("log misses", "2.6"),
        Command::Log(LogCommand::Errors { .. }) => later("log errors", "2.6"),
        Command::Timer(TimerCommand::Ring { .. }) => later("timer ring", "2.6"),
        Command::Util(UtilCommand::Notify { level, title, body }) => notify::run(&level, &title, &body).map(|()| None),
        Command::Util(UtilCommand::Intents { name }) => config::intents::run(&name).map(Some),
        Command::Util(UtilCommand::WordMatch { ignore, target }) => {
            route::resolve::run_word_match(ignore.as_deref(), &target).map(Some)
        }
        Command::Util(UtilCommand::Speech(speech)) => text::speech::run(speech).map(Some),
        Command::Util(UtilCommand::VoiceEnv { key }) => config::voice_env::run(&key).map(Some),
        Command::Internal(InternalCommand::Watch(_)) => later("internal watch", "2.4"),
        Command::Internal(InternalCommand::Settle(_)) => later("internal settle", "2.4"),
        Command::Internal(InternalCommand::CancelOwnedRecording(_)) => later("internal cancel-owned-recording", "2.4"),
        Command::Internal(InternalCommand::WakeConfirm(_)) => later("internal wake-confirm", "2.4"),
        Command::Internal(InternalCommand::ChainStop(_)) => later("internal chain-stop", "2.4"),
    }
}
