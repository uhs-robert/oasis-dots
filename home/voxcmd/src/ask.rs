//! asking the user a question during a run: confirm a risky action, pick between options (temporary, until 2.4's `ask`)
//!
//! Until `ask` is ported these run the bash `voxcmd-confirm` and `voxcmd-pick` that sit beside the bash voxcmd, or the
//! command in `VOXCMD_ASK_CMD` when it is set, called as `$VOXCMD_ASK_CMD <kind> <args>`: the seam the suites stub
//! the helpers through (1.3 section 3.6). Deleted when 2.4 lands.
use crate::paths;
use crate::process;
use std::path::PathBuf;
use std::process::Command;

/// Who shows the choices.
pub enum PickWith<'a> {
    /// The text picker.
    Picker,
    /// An integration's own picker (click's numbered boxes), by the command the integration names.
    Command(&'a str),
}

pub trait Asker: Sync {
    /// Whether the user said yes. `verb` is the question's first word, which a spoken answer starting with it confirms.
    fn confirm(&self, question: &str, verb: &str) -> bool;
    /// The index of the choice picked, none when the picker was cancelled. `choices` is the JSON `[{id, label}]`.
    fn pick(&self, with: &PickWith, label: &str, choices: &str) -> Option<usize>;
}

pub struct LegacyAsk {
    helper_dir: PathBuf,
    ask_cmd: Option<PathBuf>,
}

impl LegacyAsk {
    pub fn from_env() -> Self {
        Self::new(
            paths::legacy_bin().parent().map(PathBuf::from).unwrap_or_default(),
            std::env::var_os("VOXCMD_ASK_CMD")
                .filter(|cmd| !cmd.is_empty())
                .map(PathBuf::from),
        )
    }

    pub fn new(helper_dir: PathBuf, ask_cmd: Option<PathBuf>) -> Self {
        Self { helper_dir, ask_cmd }
    }

    /// The helper to run for a kind (`confirm`, `pick`, `hints`) and the arguments to give it.
    fn command(&self, kind: &str, helper: &std::path::Path, args: &[&str]) -> Command {
        match &self.ask_cmd {
            Some(ask_cmd) => {
                let mut command = Command::new(ask_cmd);
                command.arg(kind).args(args);
                command
            }
            None => {
                let mut command = Command::new(helper);
                command.args(args);
                command
            }
        }
    }

    /// Runs a helper to its end, its group listed so that Stop Voice reaches it; stderr is passed on.
    fn run(mut command: Command) -> Option<String> {
        let outcome = process::run_to_end(&mut command).ok()?;
        eprint!("{}", outcome.stderr);
        (outcome.code() == Some(0)).then_some(outcome.stdout)
    }
}

impl Asker for LegacyAsk {
    fn confirm(&self, question: &str, verb: &str) -> bool {
        let helper = self.helper_dir.join("voxcmd-confirm");
        Self::run(self.command("confirm", &helper, &["--verb", verb, question])).is_some()
    }

    fn pick(&self, with: &PickWith, label: &str, choices: &str) -> Option<usize> {
        let (kind, helper) = match with {
            PickWith::Picker => ("pick", self.helper_dir.join("voxcmd-pick")),
            PickWith::Command(path) => ("hints", PathBuf::from(path)),
        };
        let answer = Self::run(self.command(kind, &helper, &[label, choices]))?;
        answer.trim().parse().ok()
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    /// An executable file whose exec is known to work (see `settle_exec`); `VOXCMD_TEST_PROBE` makes it exit at once.
    pub(crate) fn script(dir: &std::path::Path, name: &str, body: &str) -> PathBuf {
        let temp = dir.join(format!(".{name}.tmp"));
        std::fs::write(
            &temp,
            format!("#!/bin/sh\n[ -z \"$VOXCMD_TEST_PROBE\" ] || exit 0\n{body}\n"),
        )
        .unwrap();
        std::fs::set_permissions(&temp, std::fs::Permissions::from_mode(0o755)).unwrap();
        let path = dir.join(name);
        std::fs::rename(&temp, &path).unwrap();
        settle_exec(&path);
        path
    }

    /// Runs the script once in probe mode until it execs: renaming does not help (the inode is the same), but a fork on
    /// another test thread that held the write fd lets go of it at its exec, so after this no later exec is ETXTBSY.
    fn settle_exec(path: &std::path::Path) {
        for _ in 0..500 {
            match std::process::Command::new(path).env("VOXCMD_TEST_PROBE", "1").status() {
                Err(error) if error.kind() == std::io::ErrorKind::ExecutableFileBusy => {
                    std::thread::sleep(std::time::Duration::from_millis(10));
                }
                _ => return,
            }
        }
    }

    #[test]
    fn the_seam_command_gets_the_kind_then_the_arguments() {
        let dir = tempfile::tempdir().unwrap();
        let log = dir.path().join("calls");
        let stub = script(
            dir.path(),
            "stub",
            &format!(
                "printf '%s|' \"$@\" >> '{}'; echo >> '{0}'; [ \"$1\" = confirm ] || echo 1",
                log.display()
            ),
        );
        let ask = LegacyAsk::new(PathBuf::from("/nonexistent"), Some(stub));
        assert!(ask.confirm("Close it?", "close"));
        assert_eq!(
            ask.pick(&PickWith::Picker, "Which command?", "[{\"id\":\"0\"}]"),
            Some(1)
        );
        assert_eq!(
            ask.pick(&PickWith::Command("voxcmd-hints"), "Which one?", "[]"),
            Some(1)
        );
        assert_eq!(
            std::fs::read_to_string(&log).unwrap(),
            "confirm|--verb|close|Close it?|\npick|Which command?|[{\"id\":\"0\"}]|\nhints|Which one?|[]|\n"
        );
    }

    #[test]
    fn without_the_seam_the_helpers_beside_the_bash_voxcmd_run() {
        let dir = tempfile::tempdir().unwrap();
        script(dir.path(), "voxcmd-confirm", "[ \"$3\" = 'Yes?' ]");
        script(dir.path(), "voxcmd-pick", "echo 2");
        let ask = LegacyAsk::new(dir.path().to_path_buf(), None);
        assert!(ask.confirm("Yes?", "yes"));
        assert!(!ask.confirm("No?", "no"));
        assert_eq!(ask.pick(&PickWith::Picker, "l", "[]"), Some(2));
    }

    #[test]
    fn a_cancelled_or_unreadable_pick_is_none() {
        let dir = tempfile::tempdir().unwrap();
        let cancel = script(dir.path(), "cancel", "exit 1");
        let junk = script(dir.path(), "junk", "echo banana");
        assert_eq!(
            LegacyAsk::new(PathBuf::new(), Some(cancel)).pick(&PickWith::Picker, "l", "[]"),
            None
        );
        assert_eq!(
            LegacyAsk::new(PathBuf::new(), Some(junk)).pick(&PickWith::Picker, "l", "[]"),
            None
        );
    }
}
