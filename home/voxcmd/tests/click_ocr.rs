//! `voxcmd internal click-ocr` with real child processes: the strip lifecycle (forked children, cleanup on failure and
//! on a stop signal, ordering of the output). The sandbox suite (run.sh, "click-ocr") drives the same behaviour through the whole stack; the
//! cases here add the ones it cannot see, a stop signal and the environment and pipes of the children.
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

mod common;
use common::gone_within;

/// Stubs for hyprctl, grim, magick and tesseract on a PATH of their own, and a runtime dir. `tesseract` and `magick`
/// are given per test; every stub logs the pids it ran as to `$WORK/pids` (kept across exec).
struct Rig {
    root: tempfile::TempDir,
}

const HYPRCTL: &str = r#"#!/bin/sh
echo '{"at": [0, 0], "size": [100, 1500], "stableId": "1"}'
"#;

/// A capture of the window's own size, so the scale is 1 and 1500 rows are five strips.
const GRIM: &str = r#"#!/bin/sh
for out; do :; done
{ printf 'P6\n100 1500\n255\n'; head -c 450000 /dev/zero; } > "$out"
"#;

const MAGICK_LIGHT: &str = r#"#!/bin/sh
previous=
for arg; do
  [ "$previous" != -write ] || case "$arg" in info:-) echo "${MEAN:-1}" ;; *) : > "$arg" ;; esac
  previous=$arg
done
"#;

impl Rig {
    fn new(tesseract: &str) -> Self {
        let root = tempfile::tempdir().unwrap();
        for dir in ["bin", "runtime", "work"] {
            std::fs::create_dir_all(root.path().join(dir)).unwrap();
        }
        let rig = Self { root };
        rig.stub("hyprctl", HYPRCTL);
        rig.stub("grim", GRIM);
        rig.stub("magick", MAGICK_LIGHT);
        rig.stub("tesseract", tesseract);
        rig
    }

    fn stub(&self, name: &str, script: &str) {
        let path = self.root.path().join("bin").join(name);
        std::fs::write(&path, script).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
    }

    fn work(&self) -> PathBuf {
        self.root.path().join("work")
    }

    fn runtime(&self) -> PathBuf {
        self.root.path().join("runtime")
    }

    fn command(&self, args: &[&str]) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_voxcmd"));
        command
            .args(["internal", "click-ocr"])
            .args(args)
            .env(
                "PATH",
                format!("{}:/usr/bin:/bin", self.root.path().join("bin").display()),
            )
            .env("XDG_RUNTIME_DIR", self.runtime())
            .env("WORK", self.work())
            .stdin(Stdio::null());
        command
    }

    fn pids(&self) -> Vec<i32> {
        std::fs::read_to_string(self.work().join("pids"))
            .unwrap_or_default()
            .split_whitespace()
            .filter_map(|pid| pid.parse().ok())
            .collect()
    }

    fn work_dirs(&self) -> Vec<String> {
        std::fs::read_dir(self.runtime())
            .unwrap()
            .filter_map(|entry| entry.ok()?.file_name().into_string().ok())
            .filter(|name| name.starts_with("voxcmd-click."))
            .collect()
    }

    fn wait_for_pids(&self, count: usize) {
        let deadline = Instant::now() + Duration::from_secs(10);
        while self.pids().len() < count {
            assert!(Instant::now() < deadline, "only {:?} started", self.pids());
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    fn assert_all_gone(&self) {
        for pid in self.pids() {
            assert!(
                gone_within(pid, Duration::from_secs(5)),
                "process {pid} outlived the run"
            );
        }
    }
}

#[test]
fn a_stop_signal_ends_every_strip_and_removes_the_work_directory() {
    // Each strip forks a child of its own first, so the group, not the strip alone, has to be ended.
    let rig = Rig::new("#!/bin/sh\nsleep 60 &\necho \"$$ $!\" >> \"$WORK/pids\"\nwait\n");
    let mut child = rig
        .command(&[])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    rig.wait_for_pids(10);
    assert_eq!(rig.work_dirs().len(), 1);
    // SAFETY: signals the child this test started.
    unsafe { libc::kill(child.id() as i32, libc::SIGTERM) };
    child.wait().unwrap();
    rig.assert_all_gone();
    assert_eq!(rig.work_dirs(), Vec::<String>::new());
}

#[test]
fn a_failed_strip_exits_1_saying_ocr_failed_with_no_strip_left_and_no_directory() {
    let rig = Rig::new(
        "#!/bin/sh\necho \"$$\" >> \"$WORK/pids\"\n\
         if mkdir \"$WORK/failed\" 2>/dev/null; then\n\
         \x20 # Fail only once the four siblings have their trap, or a TERM would find none to run.\n\
         \x20 while [ \"$(cat \"$WORK/trapped\" 2>/dev/null | wc -l)\" -lt 4 ]; do sleep 0.02; done\n\
         \x20 exit 1\n\
         fi\n\
         trap 'echo term >>\"$WORK/termed\"; exit 0' TERM\n\
         echo ready >> \"$WORK/trapped\"\nsleep 60 &\nwait\n",
    );
    let output = rig.command(&[]).output().unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(String::from_utf8_lossy(&output.stderr), "ocr failed\n");
    assert!(output.stdout.is_empty());
    rig.assert_all_gone();
    assert_eq!(rig.work_dirs(), Vec::<String>::new());
    // The siblings are asked to stop before they are killed: the trap only runs on a SIGTERM that arrives first.
    assert!(rig.work().join("termed").exists(), "no strip saw a SIGTERM");
}

#[test]
fn a_strip_that_succeeds_but_leaves_no_text_fails_the_run() {
    let rig = Rig::new("#!/bin/sh\nrm \"${1%.pgm}.tsv\"\n");
    let output = rig.command(&[]).output().unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(String::from_utf8_lossy(&output.stderr), "ocr failed\n");
    assert!(output.stdout.is_empty());
}

#[test]
fn a_dark_strip_that_fails_ends_the_negating_magick_in_its_pipe_too() {
    // Both stages of a strip are one group: tesseract fails at once, magick would run for a minute.
    let rig = Rig::new("#!/bin/sh\nexit 1\n");
    rig.stub(
        "magick",
        &format!(
            "{MAGICK_LIGHT}{}",
            "case \"$*\" in *-negate*) echo \"$$\" >> \"$WORK/pids\"; exec sleep 60 ;; esac\n"
        ),
    );
    let output = rig.command(&[]).env("MEAN", "0.1").output().unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(!rig.pids().is_empty(), "no strip was negated");
    rig.assert_all_gone();
}

#[test]
fn several_strips_get_one_thread_each_and_a_single_strip_all_of_them() {
    let log = "echo \"${OMP_THREAD_LIMIT:-unset}\" >> \"$WORK/omp\"\n";
    let rig = Rig::new(&format!("#!/bin/sh\n{log}"));
    assert!(rig.command(&[]).output().unwrap().status.success());
    let many = std::fs::read_to_string(rig.work().join("omp")).unwrap();
    assert_eq!(many.lines().collect::<Vec<_>>(), ["1"; 5]);

    rig.stub("hyprctl", &HYPRCTL.replace("1500", "150"));
    rig.stub("grim", &GRIM.replace("100 1500", "100 150").replace("450000", "45000"));
    std::fs::remove_file(rig.work().join("omp")).unwrap();
    assert!(rig.command(&[]).output().unwrap().status.success());
    assert_eq!(std::fs::read_to_string(rig.work().join("omp")).unwrap(), "unset\n");
}

#[test]
fn the_shot_is_gone_before_the_strips_are_read() {
    let rig = Rig::new("#!/bin/sh\nls \"$XDG_RUNTIME_DIR\"/voxcmd-click.*/ >> \"$WORK/listing\"\n");
    assert!(rig.command(&[]).output().unwrap().status.success());
    let listing = std::fs::read_to_string(rig.work().join("listing")).unwrap();
    assert!(!listing.contains("shot.ppm"), "{listing}");
    assert!(listing.contains("strip0.pgm"));
}

#[test]
fn the_streams_text_comes_in_strip_order_whichever_strip_finishes_first() {
    let rig = Rig::new("#!/bin/sh\nn=${1##*strip}\nn=${n%.pgm}\nsleep \"0.$((9 - n))\"\necho \"text-$n\"\n");
    let output = rig.command(&[]).output().unwrap();
    let lines: Vec<String> = String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(str::to_string)
        .collect();
    let order: Vec<&str> = lines
        .iter()
        .filter_map(|line| {
            line.strip_prefix("text-")
                .or(line.strip_prefix("#strip ").map(|rest| &rest[..1]))
        })
        .collect();
    assert_eq!(lines[0], "#window 0 0 100 1500 100 1500");
    assert_eq!(order, ["0", "0", "1", "1", "2", "2", "3", "3", "4", "4"]);
}

#[test]
fn click_target_is_written_before_the_strips_are_read() {
    let rig = Rig::new("#!/bin/sh\nls \"$XDG_RUNTIME_DIR/voxcmd/\" >> \"$WORK/listing\"\n");
    assert!(rig.command(&[]).output().unwrap().status.success());
    assert!(
        std::fs::read_to_string(rig.work().join("listing"))
            .unwrap()
            .contains("click-target")
    );
    let target: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(rig.runtime().join("voxcmd/click-target")).unwrap()).unwrap();
    assert_eq!(target["window"]["stableId"], "1");
}
