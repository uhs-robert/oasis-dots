//! `voxcmd wake listen --pcm` against the Python listener's scores on the owner's recorded takes
//!
//! The takes and the goldens (written by the Python listener, since deleted) are not committed: the owner decides whether the recordings
//! are. They live in `.logs/voxcmd/voxcmd-wake-port/` of the main checkout, or in the directory named by
//! `VOXCMD_WAKE_PARITY_DIR` (a `recordings/` of `.s16` takes beside a `goldens/` of `.json`). With either absent the
//! test skips with a message. It asserts every frame score within 1e-4 and the triggers at all three levels, take
//! for take.
use std::path::{Path, PathBuf};
use std::process::Command;

const TOLERANCE: f64 = 1e-4;
const LEVELS: [&str; 3] = ["strict", "balanced", "relaxed"];
/// Scores before this frame are not compared. openWakeWord seeds the head's window with the embedding of random noise,
/// so the Python listener's own scores differ between two runs on one file at frames 9 to 14 (by up to 0.2); the Rust
/// scorer uses one fixed draw. From frame 15 on every real embedding has replaced the seed and the runs agree.
const SETTLED_FRAME: usize = 16;

fn parity_dir() -> Option<PathBuf> {
    if let Some(dir) = std::env::var_os("VOXCMD_WAKE_PARITY_DIR") {
        return Some(PathBuf::from(dir));
    }
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    let repo = manifest.parent()?.parent()?;
    // A worktree's `.git` is a file naming `<main>/.git/worktrees/<name>`; the logs are in the main checkout.
    let main = match std::fs::read_to_string(repo.join(".git")) {
        Ok(pointer) => {
            let git_dir = PathBuf::from(pointer.strip_prefix("gitdir: ")?.trim());
            git_dir.parent()?.parent()?.parent()?.to_path_buf()
        }
        Err(_) => repo.to_path_buf(),
    };
    Some(main.join(".logs/voxcmd/voxcmd-wake-port"))
}

fn feature_models_present() -> bool {
    let data_home = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap()).join(".local/share"));
    let dir = data_home.join("voxcmd-wake/models");
    dir.join("melspectrogram.onnx").exists() && dir.join("embedding_model.onnx").exists()
}

struct Listen {
    scores: Vec<f64>,
    triggers: Vec<usize>,
}

fn listen(take: &Path, level: &str, runtime: &Path) -> Listen {
    let mut command = Command::new(env!("CARGO_BIN_EXE_voxcmd"));
    for (key, _) in std::env::vars() {
        if key.starts_with("VOXCMD_") {
            command.env_remove(key);
        }
    }
    let output = command
        .args(["wake", "listen", "--pcm"])
        .arg(take)
        .env("VOXCMD_DRY_RUN", "1")
        .env("XDG_RUNTIME_DIR", runtime)
        .env("VOXCMD_VOICE_ENV_FILE", runtime.join("no-voice.env"))
        .env("VOXCMD_WAKE_SENSITIVITY", level)
        .output()
        .unwrap();
    assert_eq!(
        output.status.code(),
        Some(0),
        "{}: {}",
        take.display(),
        String::from_utf8_lossy(&output.stderr)
    );
    let mut result = Listen {
        scores: Vec::new(),
        triggers: Vec::new(),
    };
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        if let Some(rest) = line.strip_prefix("trigger ") {
            result.triggers.push(rest.split(' ').next().unwrap().parse().unwrap());
        } else {
            result.scores.push(line.split_once(' ').unwrap().1.parse().unwrap());
        }
    }
    result
}

#[test]
fn the_rust_listener_matches_the_python_scores_and_triggers_on_the_recorded_takes() {
    let Some(dir) = parity_dir() else {
        return eprintln!("skipped: no parity directory");
    };
    let (takes_dir, goldens_dir) = (dir.join("recordings"), dir.join("goldens"));
    if !takes_dir.is_dir() || !goldens_dir.is_dir() {
        return eprintln!(
            "skipped: the recorded takes and Python goldens are not in {} (not committed; set VOXCMD_WAKE_PARITY_DIR)",
            dir.display()
        );
    }
    if !feature_models_present() {
        return eprintln!("skipped: the feature models are not downloaded");
    }
    let mut takes: Vec<PathBuf> = std::fs::read_dir(&takes_dir)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "s16"))
        .collect();
    takes.sort();
    if takes.is_empty() {
        return eprintln!("skipped: {} holds no .s16 takes", takes_dir.display());
    }
    let runtime = tempfile::tempdir().unwrap();
    let mut worst = 0f64;
    for take in &takes {
        let name = take.file_stem().unwrap().to_string_lossy().to_string();
        let golden: serde_json::Value = serde_json::from_slice(
            &std::fs::read(goldens_dir.join(format!("{name}.json")))
                .unwrap_or_else(|error| panic!("{name} has no golden in {}: {error}", goldens_dir.display())),
        )
        .unwrap();
        let want: Vec<f64> = golden["scores"]
            .as_array()
            .unwrap()
            .iter()
            .map(|score| score.as_f64().unwrap())
            .collect();
        for level in LEVELS {
            let got = listen(take, level, runtime.path());
            assert_eq!(got.scores.len(), want.len(), "{name}: frame count");
            for (frame, (have, expected)) in got.scores.iter().zip(&want).enumerate().skip(SETTLED_FRAME) {
                let diff = (have - expected).abs();
                worst = worst.max(diff);
                assert!(
                    diff < TOLERANCE,
                    "{name} frame {frame} at {level}: {have} against {expected}"
                );
            }
            let want_triggers: Vec<usize> = golden["triggers"][level]
                .as_array()
                .unwrap()
                .iter()
                .map(|frame| frame.as_u64().unwrap() as usize)
                .collect();
            assert_eq!(got.triggers, want_triggers, "{name}: triggers at {level}");
        }
    }
    eprintln!("parity: {} takes, worst score difference {worst:.2e}", takes.len());
}
