//! `voxcmd wake listen --pcm` on the committed clip and on audio built from it, and exit 78 without a model
//!
//! No microphone and no `wake.json`: `--pcm` reads a file. There is no recorded "cortana" in the repo, so the triggers
//! come from the clip's one spike (frames 40 and 41 score 0.42 and 0.47 as the noise ends) with the threshold lowered
//! to 0.4 over 2 frames, which makes it a stand-in take. The cooldown cases join two of them.
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const CLIP_FRAMES: usize = 43;
const FRAME_SAMPLES: usize = 1280;
/// A take's spike triggers on frame 41 of the clip (0-based) at these settings.
const TRIGGER_FRAME: usize = 41;

fn manifest(path: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join(path)
}

fn feature_dir() -> Option<PathBuf> {
    let data_home = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap()).join(".local/share"));
    let dir = data_home.join("voxcmd-wake/models");
    (dir.join("melspectrogram.onnx").exists() && dir.join("embedding_model.onnx").exists()).then_some(dir)
}

struct Run {
    output: Output,
    runtime: tempfile::TempDir,
}

impl Run {
    fn lines(&self) -> Vec<String> {
        String::from_utf8_lossy(&self.output.stdout)
            .lines()
            .map(str::to_string)
            .collect()
    }

    fn triggers(&self) -> Vec<usize> {
        self.lines()
            .iter()
            .filter_map(|line| line.strip_prefix("trigger "))
            .map(|rest| rest.split(' ').next().unwrap().parse().unwrap())
            .collect()
    }
}

fn wake_listen(args: &[&str], env: &[(&str, &str)], model_dir: Option<&Path>) -> Run {
    let runtime = tempfile::tempdir().unwrap();
    let mut command = Command::new(env!("CARGO_BIN_EXE_voxcmd"));
    command.args(["wake", "listen"]).args(args);
    for (key, _) in std::env::vars() {
        if key.starts_with("VOXCMD_") {
            command.env_remove(key);
        }
    }
    command
        // The setup errors send a toast; dry run prints it to stderr instead of the owner's desktop.
        .env("VOXCMD_DRY_RUN", "1")
        .env("XDG_RUNTIME_DIR", runtime.path())
        .env("VOXCMD_VOICE_ENV_FILE", runtime.path().join("no-voice.env"))
        .envs(env.iter().copied());
    if let Some(dir) = model_dir {
        command.env("VOXCMD_WAKE_MODEL_DIR", dir);
    }
    Run {
        output: command.output().unwrap(),
        runtime,
    }
}

fn clip_samples() -> Vec<i16> {
    std::fs::read(manifest("tests/fixtures/wake/silence_then_noise.s16"))
        .unwrap()
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| i16::from_le_bytes(*pair))
        .collect()
}

fn write_pcm(dir: &Path, name: &str, samples: &[i16]) -> PathBuf {
    let path = dir.join(name);
    std::fs::write(
        &path,
        samples
            .iter()
            .flat_map(|sample| sample.to_le_bytes())
            .collect::<Vec<u8>>(),
    )
    .unwrap();
    path
}

/// The clip through its trigger, `gap_secs` of silence, then the clip again: two takes whose triggers are
/// `42 frames + gap` apart (3.36 s with a gap of 1.5 s, the least that gives the second spike a clean window).
fn two_takes(dir: &Path, gap_secs: f64) -> PathBuf {
    let clip = clip_samples();
    let mut samples = clip[..(TRIGGER_FRAME + 1) * FRAME_SAMPLES].to_vec();
    samples.extend(std::iter::repeat_n(0i16, (gap_secs * 16000.0) as usize));
    samples.extend_from_slice(&clip[24000..]);
    write_pcm(dir, "two_takes.s16", &samples)
}

#[test]
fn the_clip_prints_one_score_line_per_frame_and_exits_0_without_a_wake_json() {
    let Some(models) = feature_dir() else {
        return eprintln!("skipped: the feature models are not downloaded");
    };
    let run = wake_listen(
        &[
            "--pcm",
            manifest("tests/fixtures/wake/silence_then_noise.s16").to_str().unwrap(),
        ],
        &[],
        Some(&models),
    );
    assert_eq!(
        run.output.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&run.output.stderr)
    );
    let lines = run.lines();
    assert_eq!(lines.len(), CLIP_FRAMES, "{lines:?}");
    let expected: Vec<f32> = std::fs::read_to_string(manifest("tests/fixtures/wake/silence_then_noise.scores"))
        .unwrap()
        .lines()
        .map(|line| line.parse().unwrap())
        .collect();
    for (index, (line, want)) in lines.iter().zip(&expected).enumerate() {
        let (frame, score) = line.split_once(' ').unwrap();
        assert_eq!(frame.parse::<usize>().unwrap(), index);
        // The line has 4 decimals.
        assert!(
            (score.parse::<f32>().unwrap() - want).abs() < 1e-3,
            "{line} against {want}"
        );
    }
    assert!(run.triggers().is_empty(), "the default level fired on noise");
    assert!(!run.runtime.path().join("voxcmd/wake.json").exists());
}

#[test]
fn a_lowered_threshold_fires_on_the_spike_once() {
    let Some(models) = feature_dir() else {
        return eprintln!("skipped: the feature models are not downloaded");
    };
    let clip = manifest("tests/fixtures/wake/silence_then_noise.s16");
    let env = [("VOXCMD_WAKE_THRESHOLD", "0.4"), ("VOXCMD_WAKE_FRAMES", "2")];
    let run = wake_listen(&["--pcm", clip.to_str().unwrap()], &env, Some(&models));
    assert_eq!(run.triggers(), [TRIGGER_FRAME]);
    assert!(
        run.lines().iter().any(|line| line.starts_with("trigger 41 0.4677")),
        "{:?}",
        run.lines()
    );
}

#[test]
fn the_cooldown_swallows_a_second_take_inside_it_and_not_one_after_it() {
    let Some(models) = feature_dir() else {
        return eprintln!("skipped: the feature models are not downloaded");
    };
    let dir = tempfile::tempdir().unwrap();
    let file = two_takes(dir.path(), 1.5);
    let level = [("VOXCMD_WAKE_THRESHOLD", "0.4"), ("VOXCMD_WAKE_FRAMES", "2")];
    let triggers_with = |cooldown: &str| {
        let mut env = level.to_vec();
        env.push(("VOXCMD_WAKE_COOLDOWN_SECS", cooldown));
        wake_listen(&["--pcm", file.to_str().unwrap()], &env, Some(&models)).triggers()
    };
    // The takes' triggers are 42 frames, 3.36 s, apart.
    assert_eq!(
        triggers_with("5"),
        [TRIGGER_FRAME],
        "a second take 3.4 s later, inside a 5 s cooldown"
    );
    assert_eq!(
        triggers_with("3"),
        [TRIGGER_FRAME, TRIGGER_FRAME + 42],
        "after the default 3 s cooldown"
    );
}

#[test]
fn missing_models_and_a_bad_setting_exit_78() {
    let empty = tempfile::tempdir().unwrap();
    let run = wake_listen(&[], &[], Some(empty.path()));
    assert_eq!(run.output.status.code(), Some(78));
    assert!(
        String::from_utf8_lossy(&run.output.stderr).contains("melspectrogram.onnx is not in"),
        "{:?}",
        run.output
    );
    let pcm = write_pcm(empty.path(), "x.s16", &[0; FRAME_SAMPLES]);
    let run = wake_listen(&["--pcm", pcm.to_str().unwrap()], &[], Some(empty.path()));
    assert_eq!(run.output.status.code(), Some(78), "a --pcm run needs the models too");
    let run = wake_listen(&[], &[("VOXCMD_WAKE_SENSITIVITY", "loud")], Some(empty.path()));
    assert_eq!(run.output.status.code(), Some(78));
    assert!(String::from_utf8_lossy(&run.output.stderr).contains("VOXCMD_WAKE_SENSITIVITY must be"));
    let run = wake_listen(&[], &[("VOXCMD_WAKE_PAUSE_FOR_MIC", "yes")], Some(empty.path()));
    assert_eq!(run.output.status.code(), Some(78));
}

#[test]
fn check_says_what_is_missing_and_exits_1() {
    let empty = tempfile::tempdir().unwrap();
    let run = wake_listen(&["--check"], &[], Some(empty.path()));
    assert_eq!(run.output.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&run.output.stdout).contains("melspectrogram.onnx is not in"));
    if let Some(models) = feature_dir() {
        assert_eq!(
            wake_listen(&["--check"], &[], Some(&models)).output.status.code(),
            Some(0)
        );
    }
}

#[test]
fn a_missing_pcm_file_fails_with_exit_1() {
    let Some(models) = feature_dir() else {
        return eprintln!("skipped: the feature models are not downloaded");
    };
    let run = wake_listen(&["--pcm", "/nonexistent/take.s16"], &[], Some(&models));
    assert_eq!(run.output.status.code(), Some(1));
}
