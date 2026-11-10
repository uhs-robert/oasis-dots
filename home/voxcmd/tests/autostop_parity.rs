//! `voxcmd internal autostop --pcm` against the Python detector's verdicts, traces and published thresholds
//!
//! `tests/fixtures/autostop-parity-goldens.json` holds what the Python script (since deleted) gave on the synthetic clips
//! of `autostop_audio` under each settings profile: its exit code, its debug-trace lines (stamp and pid dropped) and the
//! threshold file it published. The clips are built by the generator, nothing recorded is committed. A missing fixture
//! fails the test.
//!
//! Regenerating needs the Python script from before the port (`git show 5281ff1e3:home/voxcmd/.local/bin/voxcmd-autostop`):
//! `VOXCMD_AUTOSTOP_INPUTS_DIR=<dir> cargo test --test autostop_parity -- --ignored write_inputs` writes the clips, then run
//! the script on each with the profile's variables and `VOXCMD_AUTOSTOP_THRESHOLD_FILE` set, and keep the three results.
mod autostop_audio;
use autostop_audio::{CLIPS, PROFILES, pcm};
use serde_json::Value;
use std::path::Path;
use std::process::Command;

#[test]
#[ignore = "writes the clips the goldens were made from, for regenerating them"]
fn write_inputs() {
    let dir = std::env::var("VOXCMD_AUTOSTOP_INPUTS_DIR").expect("VOXCMD_AUTOSTOP_INPUTS_DIR names the directory");
    for (name, segments) in CLIPS {
        std::fs::write(Path::new(&dir).join(format!("{name}.s16")), pcm(segments)).unwrap();
    }
}

#[test]
fn rust_matches_the_python_detector_on_every_golden() {
    let goldens: Value = serde_json::from_str(
        &std::fs::read_to_string(
            Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/autostop-parity-goldens.json"),
        )
        .expect("the parity goldens are committed"),
    )
    .unwrap();
    let mut runs = 0;
    let mut mismatches = Vec::new();
    for (clip, segments) in CLIPS {
        let audio = tempfile::tempdir().unwrap();
        let file = audio.path().join("clip.s16");
        std::fs::write(&file, pcm(segments)).unwrap();
        for (profile, env) in PROFILES {
            let key = format!("{clip}@{profile}");
            let golden = goldens.get(&key).unwrap_or_else(|| panic!("no golden for {key}"));
            let run = tempfile::tempdir().unwrap();
            let config = tempfile::tempdir().unwrap();
            std::fs::create_dir(run.path().join("voxcmd")).unwrap();
            std::fs::write(run.path().join("voxcmd/debug.log"), "").unwrap();
            let threshold_file = run.path().join("threshold");
            let mut command = Command::new(env!("CARGO_BIN_EXE_voxcmd"));
            for (name, _) in std::env::vars() {
                if name.starts_with("VOXCMD_") {
                    command.env_remove(name);
                }
            }
            let output = command
                .args(["internal", "autostop", "--pcm"])
                .arg(&file)
                .env("XDG_RUNTIME_DIR", run.path())
                .env("VOXCMD_CONFIG_DIR", config.path())
                .env("VOXCMD_AUTOSTOP_THRESHOLD_FILE", &threshold_file)
                .envs(env.iter().copied())
                .output()
                .unwrap();
            let trace: Vec<String> = std::fs::read_to_string(run.path().join("voxcmd/debug.log"))
                .unwrap()
                .lines()
                .map(|line| line.split_once("] ").unwrap().1.to_string())
                .collect();
            let got = serde_json::json!({
                "exit": output.status.code().unwrap(),
                "trace": trace,
                "threshold": std::fs::read_to_string(&threshold_file).ok(),
            });
            if &got != golden {
                mismatches.push(format!("{key}\n  want {golden}\n  got  {got}"));
            }
            runs += 1;
        }
    }
    assert_eq!(
        goldens.as_object().unwrap().len(),
        runs,
        "a golden has no clip and profile"
    );
    assert!(
        mismatches.is_empty(),
        "{} of {runs} differ:\n{}",
        mismatches.len(),
        mismatches.join("\n")
    );
}
