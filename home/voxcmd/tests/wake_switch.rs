//! `wake on|off|toggle|status` against a stub systemctl, with a bash voxcmd-wake-switch beside it that must never run.
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::{Command, Output};

fn write_stub(dir: &Path, name: &str, script: &str) {
    let path = dir.join(name);
    std::fs::write(&path, script).unwrap();
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

struct Wake {
    root: tempfile::TempDir,
}

impl Wake {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        let bin = root.path().join("bin");
        std::fs::create_dir(&bin).unwrap();
        let calls = root.path().join("calls.log");
        write_stub(
            &bin,
            "systemctl",
            &format!(
                r#"#!/bin/sh
echo "systemctl $*" >> {calls}
state={state}
case "$*" in
"--user start --no-block voxcmd-wake.service") echo active > "$state" ;;
"--user stop voxcmd-wake.service") rm -f "$state" ;;
"--user is-active voxcmd-wake.service")
  if [ -e "$state" ]; then cat "$state"; else echo inactive; exit 3; fi ;;
esac
"#,
                calls = calls.display(),
                state = root.path().join("state").display()
            ),
        );
        write_stub(
            &bin,
            "notify-send",
            &format!("#!/bin/sh\necho \"notify-send $*\" >> {}\n", calls.display()),
        );
        // The tripwire: the bash sibling this subcommand replaced.
        write_stub(
            &bin,
            "voxcmd-wake-switch",
            &format!("#!/bin/sh\necho 'BASH-RAN voxcmd-wake-switch' >> {}\n", calls.display()),
        );
        Self { root }
    }

    fn voxcmd(&self, args: &[&str]) -> Output {
        Command::new(env!("CARGO_BIN_EXE_voxcmd"))
            .args(args)
            .env_clear()
            .env(
                "PATH",
                format!("{}:/usr/bin:/bin", self.root.path().join("bin").display()),
            )
            .output()
            .unwrap()
    }

    fn calls(&self) -> String {
        std::fs::read_to_string(self.root.path().join("calls.log")).unwrap_or_default()
    }
}

#[test]
fn the_switch_follows_the_unit_and_the_rust_binary_ran() {
    let wake = Wake::new();
    let status = wake.voxcmd(&["wake", "status"]);
    assert_eq!(status.status.code(), Some(1));
    assert_eq!(String::from_utf8_lossy(&status.stdout), "off\n");

    assert!(wake.voxcmd(&["wake", "on"]).status.success());
    assert!(
        wake.calls()
            .contains("systemctl --user start --no-block voxcmd-wake.service\n")
    );
    assert!(
        wake.calls()
            .contains("notify-send -a voxcmd --transient Wake word on Say \"Cortana\"\n")
    );
    let status = wake.voxcmd(&["wake", "status"]);
    assert!(status.status.success());
    assert_eq!(String::from_utf8_lossy(&status.stdout), "on\n");

    assert!(wake.voxcmd(&["wake", "on"]).status.success());
    assert_eq!(
        wake.calls().matches(" start ").count(),
        1,
        "a second `on` starts nothing"
    );

    assert!(wake.voxcmd(&["wake", "toggle"]).status.success());
    assert!(wake.calls().contains("systemctl --user stop voxcmd-wake.service\n"));
    assert!(wake.calls().contains("Wake word off Microphone released"));
    assert_eq!(wake.voxcmd(&["wake", "status"]).status.code(), Some(1));

    assert!(
        !wake.calls().contains("BASH-RAN"),
        "the bash sibling ran:\n{}",
        wake.calls()
    );
}

#[test]
fn a_stop_that_leaves_the_unit_running_fails_without_claiming_release() {
    let wake = Wake::new();
    // A systemctl whose stop does nothing: the unit stays active.
    write_stub(
        &wake.root.path().join("bin"),
        "systemctl",
        "#!/bin/sh\ncase \"$*\" in *is-active*) echo active ;; *stop*) exit 0 ;; esac\n",
    );
    let off = wake.voxcmd(&["wake", "off"]);
    assert_eq!(off.status.code(), Some(1));
    assert!(wake.calls().contains("may still be in use"));
    assert!(!wake.calls().contains("Microphone released"));
}
