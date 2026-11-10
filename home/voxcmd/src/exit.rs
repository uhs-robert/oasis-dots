//! the exit-code enum (E5) and the error type every subcommand returns
use std::fmt;
use std::process::ExitCode;

/// Exit codes are 0, 1 and 2, and 78 for `wake listen` alone. Never 3: a hook that calls `voxcmd ask` would pass it on
/// as "yield". The one exception is `internal autostop`, whose verdicts (0, 3, 4, 5, 1) are exit codes that `main`
/// returns without a `CliError`; no hook calls it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Exit {
    /// Nothing matched, did not parse, the action failed, or the user cancelled or declined.
    Failed = 1,
    /// Usage or unreadable configuration.
    Usage = 2,
    /// `wake listen` has no setup to run with (sysexits EX_CONFIG). The wake unit lists it in `RestartPreventExitStatus`,
    /// since restarting cannot install a model.
    Setup = 78,
}

/// What a handler returns when it did not succeed. `main` prints `voxcmd: <subcommand>: <message>` to stderr.
#[derive(Debug)]
pub struct CliError {
    pub exit: Exit,
    pub subcommand: String,
    pub message: String,
}

impl CliError {
    pub fn failed(subcommand: &str, message: impl Into<String>) -> Self {
        Self {
            exit: Exit::Failed,
            subcommand: subcommand.to_string(),
            message: message.into(),
        }
    }

    pub fn usage(subcommand: &str, message: impl Into<String>) -> Self {
        Self {
            exit: Exit::Usage,
            subcommand: subcommand.to_string(),
            message: message.into(),
        }
    }

    /// The listener cannot start for want of setup; see `Exit::Setup`.
    pub fn setup(subcommand: &str, message: impl Into<String>) -> Self {
        Self {
            exit: Exit::Setup,
            subcommand: subcommand.to_string(),
            message: message.into(),
        }
    }

    /// A failure that has said all there is to say (a toast, a log line): exit 1, nothing on stderr.
    pub fn quiet(subcommand: &str) -> Self {
        Self::failed(subcommand, "")
    }

    pub fn exit_code(&self) -> ExitCode {
        ExitCode::from(self.exit as u8)
    }
}

impl fmt::Display for CliError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "voxcmd: {}: {}", self.subcommand, self.message)
    }
}
