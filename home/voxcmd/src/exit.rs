//! the exit-code enum (E5) and the error type every subcommand returns
use std::fmt;
use std::process::ExitCode;

/// Exit codes are 0, 1 and 2 only. Never 3: a hook that calls `voxcmd ask` would pass it on as "yield".
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Exit {
    /// Nothing matched, did not parse, the action failed, or the user cancelled or declined.
    Failed = 1,
    /// Usage or unreadable configuration.
    Usage = 2,
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

    /// A subcommand whose handler lands in a later item of the port; `phase_item` names it ("2.2").
    pub fn not_implemented(subcommand: &str, phase_item: &str) -> Self {
        Self::failed(subcommand, format!("not implemented yet ({phase_item})"))
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn message_has_the_stderr_contract_shape() {
        let error = CliError::not_implemented("util notify", "2.3");
        assert_eq!(error.to_string(), "voxcmd: util notify: not implemented yet (2.3)");
        assert_eq!(error.exit, Exit::Failed);
    }
}
