//! the tract scorer against openWakeWord's own scores on a committed clip
//!
//! The clip is 1.5 s of silence then 2 s of noise (peak score 0.47, so the head's sigmoid is off the floor). The scores
//! come from openWakeWord on onnxruntime, with the head's initial window set to `init_features.f32` as the scorer's is.
//! The feature models are not tracked: without them in the cache the test says so and passes.
#![allow(dead_code)]

#[path = "../src/voice/wake/scorer.rs"]
mod scorer;

use scorer::{FRAME_SAMPLES, Scorer, TractScorer};
use std::path::{Path, PathBuf};

const TOLERANCE: f32 = 1e-4;

fn feature_dir() -> PathBuf {
    let data_home = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap()).join(".local/share"));
    data_home.join("voxcmd-wake/models")
}

fn clip() -> Vec<i16> {
    let bytes = std::fs::read(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/wake/silence_then_noise.s16"))
        .unwrap();
    bytes
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| i16::from_le_bytes(*pair))
        .collect()
}

fn expected() -> Vec<f32> {
    std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/wake/silence_then_noise.scores"))
        .unwrap()
        .lines()
        .map(|line| line.parse().unwrap())
        .collect()
}

fn load() -> Option<TractScorer> {
    let dir = feature_dir();
    let wake_model = Path::new(env!("CARGO_MANIFEST_DIR")).join(".local/share/voxcmd/cortana.onnx");
    if !dir.join("melspectrogram.onnx").exists() || !dir.join("embedding_model.onnx").exists() {
        eprintln!(
            "skipped: the feature models are not in {} (voxcmd wake listen --fetch-models)",
            dir.display()
        );
        return None;
    }
    Some(TractScorer::load(&dir, &wake_model).unwrap())
}

fn scores_of(scorer: &mut TractScorer, clip: &[i16]) -> Vec<f32> {
    clip.as_chunks::<FRAME_SAMPLES>()
        .0
        .iter()
        .map(|frame| scorer.score(frame))
        .collect()
}

#[test]
fn scores_match_openwakeword_within_1e_4() {
    let Some(mut scorer) = load() else { return };
    let scores = scores_of(&mut scorer, &clip());
    let expected = expected();
    assert_eq!(scores.len(), expected.len());
    for (frame, (got, want)) in scores.iter().zip(&expected).enumerate() {
        assert!((got - want).abs() < TOLERANCE, "frame {frame}: {got} against {want}");
    }
    assert!(
        scores.iter().cloned().fold(0.0, f32::max) > 0.3,
        "the clip no longer exercises the head"
    );
}

#[test]
fn the_first_five_frames_score_zero() {
    let Some(mut scorer) = load() else { return };
    let scores = scores_of(&mut scorer, &clip());
    assert!(scores[..5].iter().all(|score| *score == 0.0));
}

#[test]
fn a_reset_starts_over() {
    let Some(mut scorer) = load() else { return };
    let clip = clip();
    let first = scores_of(&mut scorer, &clip);
    scorer.reset();
    assert_eq!(scores_of(&mut scorer, &clip), first);
}
